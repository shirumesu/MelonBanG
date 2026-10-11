import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app_services.dart';
import '../core/network.dart';
import '../features/acquisition/resource_metadata.dart';
import '../domain/catalog.dart';
import '../domain/play_candidate.dart';
import '../features/discovery/discovery_controller.dart';
import '../features/downloads/downloads_controller.dart';
import '../features/playback/playback.dart';
import '../features/playback/playback_coordinator.dart';
import '../features/playback/resource_search.dart';
import '../features/playback/resume_controller.dart';
import '../features/tracking/subject_controller.dart';
import '../features/tracking/tracking_controller.dart';
import '../integrations/transfer/pikpak.dart';
import '../ui/acquisition/downloads_page.dart';
import '../ui/acquisition/resource_search_view.dart';
import '../ui/core/action_feedback.dart';
import '../ui/core/app_chrome.dart';
import '../ui/core/cached_image.dart';
import '../ui/core/motion.dart';
import '../ui/core/page_widgets.dart';
import '../ui/core/subject_posters.dart';
import '../ui/core/theme.dart';
import '../ui/discovery/discovery_pages.dart';
import '../ui/player/player_page.dart';
import '../ui/settings/bittorrent_settings.dart';
import '../ui/settings/cache_settings.dart';
import '../ui/settings/settings_page.dart';
import '../ui/settings/storage_settings.dart';
import '../ui/sources/sources_page.dart';
import '../ui/tracking/subject_page.dart';
import '../ui/tracking/tracking_page.dart';

class MelonApp extends StatefulWidget {
  const MelonApp({super.key, required this.service, required this.preferences});
  final AppServices service;
  final SharedPreferences preferences;
  @override
  State<MelonApp> createState() => _MelonAppState();
}

/// The window: navigation, history, title bar, sidebar and full screen. Page
/// state and requests belong to the feature controllers.
class _MelonAppState extends State<MelonApp>
    with WindowListener
    implements PlaybackShell {
  final messages = GlobalKey<ScaffoldMessengerState>();
  final navigation = GlobalKey<NavigatorState>();
  final playerPageKey = GlobalKey();
  final search = TextEditingController();
  final searchFocus = FocusNode(debugLabel: 'Catalogue search');
  final pageStorage = PageStorageBucket();
  final List<_PageLocation> history = [];
  final subscriptions = <StreamSubscription<dynamic>>[];
  final homeFeedback = ActionFeedback();
  final syncFeedback = ActionFeedback();
  String route = 'home', selectedSection = 'home';
  bool dark = false, ready = false, fullScreen = false;
  bool closing = false, sidebarVisible = true, windowFullScreen = false;
  String? startError;
  List<String> recentSearches = [];
  Listenable? _controllers;
  Future<void> _fullScreenOperations = Future.value();
  Completer<void>? _fullScreenTransition;

  /// The player starts with the sidebar collapsed so the video gets the width;
  /// toggling it there does not change the other pages.
  bool playerSidebarVisible = false;

  /// "关灯" in the light theme darkens only the player; remembered across runs.
  bool playerLightsOff = false;

  AppServices get service => widget.service;
  Playback get playback => service.playback;
  PlaybackCoordinator get coordinator => service.coordinator;
  DiscoveryController get discovery => service.discovery;
  TrackingController get personal => service.personal;
  SubjectController get subjects => service.subjects;
  ResourceSearchController get resources => service.resources;
  DownloadsController get downloads => service.downloadList;
  ResumeController get resume => service.resume;

  bool get showSidebar =>
      route == 'player' ? playerSidebarVisible : sidebarVisible;

  /// Whether the current page is still loading.
  bool get busy =>
      ready &&
      switch (route) {
        'subject' => subjects.loading,
        'search' => discovery.searching,
        'resources' => resources.busy,
        _ => false,
      };

  void setPlayerLights(bool off) {
    setState(() => playerLightsOff = off);
    unawaited(widget.preferences.setBool('player-lights-off', off));
  }

  @override
  void initState() {
    super.initState();
    dark = widget.preferences.getBool('dark') ?? false;
    playerLightsOff = widget.preferences.getBool('player-lights-off') ?? false;
    recentSearches = widget.preferences.getStringList('recentSearches') ?? [];
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
    unawaited(boot());
  }

  Future<void> boot() async {
    try {
      await service.start();
      if (!mounted || closing) return;
      coordinator.shell = this;
      _controllers = Listenable.merge([
        coordinator,
        service.sources,
        service.downloadsAvailable,
        discovery,
        personal,
        subjects,
        resources,
      ])..addListener(servicesChanged);
      downloads.availability.addListener(availabilityChanged);
      subscriptions.add(
        service.tracking.changes.stream.listen((_) {
          if (mounted) unawaited(perform(personal.refresh));
        }),
      );
      setState(() => ready = true);
      await Future.wait([
        discovery.loadHome().then((issue) {
          if (issue != null) showError(issue);
        }),
        personal.refresh(),
        refreshPlaybackAvailability(),
      ]);
    } catch (e) {
      if (mounted) setState(() => startError = e.toString());
    }
  }

  void servicesChanged() {
    if (mounted && !closing) setState(() {});
  }

  void availabilityChanged() {
    if (mounted && ready && ['home', 'subject'].contains(route)) {
      unawaited(perform(refreshPlaybackAvailability));
    }
  }

  Future<void> refreshHome() =>
      homeFeedback.run(() => discovery.loadHome(refresh: true));

  Future<void> syncCollection() => syncFeedback.run(personal.synchronize);

  Future<void> refreshPlaybackAvailability() => resume.refresh(subjects.id);

  _PageLocation get location => _PageLocation(
    route: route,
    accountId: personal.userId,
    section: selectedSection,
    subject: subjects.subject,
    query: search.text,
    search: discovery.search,
    resources: resources.state,
    pending: busy,
  );

  void rememberLocation() => history.add(location);

  /// Stops requests that belong to the page being left.
  void nextNavigation() {
    resources.cancel();
    discovery.cancelSearch();
    subjects.cancel();
  }

  void leavePlayer() {
    // Navigation can happen before startup has created the coordinator.
    if (ready) coordinator.leave();
    if (route != 'player') return;
    if (fullScreen) unawaited(setFullScreen(false));
    windowFullScreen = false;
    coordinator.stop(refreshPlaybackAvailability);
  }

  void goBack() {
    final leavingPlayer = route == 'player';
    leavePlayer();
    if (history.isEmpty) {
      navigate('home');
      return;
    }
    final previous = history.removeLast();
    nextNavigation();
    final switched = previous.accountId != personal.userId;
    final subject = switched
        ? previous.subject?.copyWith(
            clearCollection: true,
            episodes: [
              for (final episode in previous.subject!.episodes)
                episode.withStatus(EpisodeStatus.unwatched),
            ],
          )
        : previous.subject;
    setState(() {
      route = previous.route;
      selectedSection = previous.section;
      search.text = previous.query;
    });
    subjects.show(subject);
    discovery.restoreSearch(
      previous.search,
      reload: previous.pending && route == 'search',
    );
    resources.restore(previous.resources);
    if (ready && ['home', 'subject'].contains(route)) {
      unawaited(perform(refreshPlaybackAvailability));
    }
    if (route == 'subject' &&
        subject != null &&
        (previous.pending || switched)) {
      unawaited(openSubject(subject));
    } else if (route == 'subject' && leavingPlayer) {
      unawaited(perform(subjects.reload));
    } else if (route == 'resources' && previous.pending) {
      unawaited(perform(() => resources.search(previous.resources.terms!)));
    }
  }

  String get pageIdentity => switch (route) {
    'subject' => 'subject:${subjects.id}',
    'resources' =>
      'resources:${resources.state.subject?.id}:${resources.state.episode?.id}',
    'search' => 'search:${discovery.search.query}',
    _ => route,
  };

  void focusSearch() {
    if (fullScreen) unawaited(setFullScreen(false));
    // The title-bar search is hidden only while the player fills the window.
    final needsNavigation = route == 'player' && windowFullScreen;
    void focus() {
      if (!mounted) return;
      searchFocus.requestFocus();
      search.selection = TextSelection(
        baseOffset: 0,
        extentOffset: search.text.length,
      );
    }

    if (needsNavigation) {
      navigate('home');
      WidgetsBinding.instance.addPostFrameCallback((_) => focus());
    } else {
      focus();
    }
  }

  @override
  void showError(Object e) => messages.currentState?.showSnackBar(
    SnackBar(
      content: Text(e.toString().replaceFirst('Bad state: ', '')),
      behavior: SnackBarBehavior.floating,
    ),
  );

  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } on RequestCancelled {
      return;
    } catch (e) {
      showError(e);
    }
  }

  Future<void> openSubject(Subject item) async {
    if (item.id <= 0) {
      showError('这部番暂时没有详情');
      return;
    }
    leavePlayer();
    if (route != 'subject' || subjects.id != item.id) rememberLocation();
    nextNavigation();
    setState(() => route = 'subject');
    final opening = subjects.open(item);
    unawaited(perform(refreshPlaybackAvailability));
    await perform(() => opening);
  }

  @override
  bool get showingPlayer => route == 'player';

  @override
  void enterPlayer() {
    if (route != 'player') rememberLocation();
    nextNavigation();
    setState(() => route = 'player');
  }

  @override
  Future<void> openResources(Subject subject, Episode episode) async =>
      findResources(subject, episode: episode);

  @override
  Future<PlayCandidate?> chooseCandidate(Subject item, Episode episode) async {
    final target = navigation.currentState?.overlay?.context;
    if (target == null) return null;
    final search = service.newResourceSearch()..open(item, episode: episode);
    try {
      return await showDialog<PlayCandidate>(
        context: target,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 960,
            height: 620,
            child: PageStorage(
              bucket: pageStorage,
              child: KeyedSubtree(
                key: const PageStorageKey('resource-dialog'),
                child: ResourceSearchView(
                  search: search,
                  onPlay: (candidate, _) async =>
                      Navigator.pop(context, candidate),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        openResourcePage(search);
                      },
                      child: const Text('在页面中打开'),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      // The closing dialog still listens until its route is gone.
      search.cancel();
    }
  }

  /// Opens the resources page for [subject], or one of its chapters, seeded
  /// with the catalogue title and chapter number; the page then searches.
  void findResources(Subject? subject, {Episode? episode}) {
    leavePlayer();
    if (route != 'resources') rememberLocation();
    final formId = ResourceSearchView.formStorageId(subject?.id, episode?.id);
    final savedForm = pageStorage.readState(context, identifier: formId);
    pageStorage.writeState(context, {
      ...?savedForm as Map?,
      'keyword': subject?.title ?? '未命名',
      'episode': resourceEpisodeKeyword(episode),
    }, identifier: formId);
    nextNavigation();
    resources.open(subject, episode: episode);
    setState(() => route = 'resources');
  }

  /// Continues [search] from the resource sheet or picker on the page.
  void openResourcePage(ResourceSearchController search) {
    final state = search.state;
    final pending = search.busy;
    leavePlayer();
    if (route != 'resources') rememberLocation();
    nextNavigation();
    resources.restore(state);
    setState(() => route = 'resources');
    if (pending) unawaited(perform(() => resources.search(state.terms!)));
  }

  /// Plays a cached file that has no chapter to associate.
  Future<void> playCachedFile(PlayCandidate candidate) {
    final DownloadTarget(:downloadId, :fileId) =
        candidate.target as DownloadTarget;
    return coordinator.play(
      () => service.library.fromDownload(downloadId, fileId: fileId),
    );
  }

  void rememberSearch(String query) {
    setState(() {
      recentSearches = [
        query,
        ...recentSearches.where((item) => item != query),
      ].take(8).toList();
    });
    unawaited(
      widget.preferences.setStringList('recentSearches', recentSearches),
    );
  }

  void clearRecentSearches() {
    setState(() => recentSearches = []);
    unawaited(widget.preferences.remove('recentSearches'));
  }

  Future<void> searchSubjects({String? query}) async {
    final requestedQuery = query ?? search.text.trim();
    if (!ready || requestedQuery.isEmpty) return;
    search.text = requestedQuery;
    searchFocus.unfocus();
    rememberSearch(requestedQuery);
    leavePlayer();
    if (route != 'search') rememberLocation();
    nextNavigation();
    setState(() => route = 'search');
    await discovery.searchSubjects(requestedQuery);
  }

  void navigate(String target) {
    if (target == route) return;
    leavePlayer();
    rememberLocation();
    nextNavigation();
    setState(() {
      route = target;
      if ([
        'home',
        'tracking',
        'downloads',
        'sources',
        'settings',
      ].contains(target)) {
        selectedSection = target;
      } else if (target == 'calendar') {
        selectedSection = 'home';
      }
    });
    if (!ready) return;
    switch (target) {
      case 'home':
        unawaited(discovery.loadHome());
        unawaited(perform(refreshPlaybackAvailability));
      case 'tracking':
        unawaited(perform(personal.pull));
      case 'calendar':
        unawaited(perform(discovery.loadCalendar));
      case 'sources':
        unawaited(service.sources.refreshRules().catchError((Object _) {}));
    }
  }

  @override
  void onWindowClose() async {
    if (closing) return;
    setState(() => closing = true);
    // Detach the video texture before disposing its native rendering context.
    await WidgetsBinding.instance.endOfFrame;
    try {
      if (ready) await coordinator.close();
    } finally {
      try {
        await service.close();
      } finally {
        // Use WM_CLOSE so the runner destroys its view before leaving the message
        // loop. windowManager.destroy posts WM_QUIT directly on Windows.
        await windowManager.setPreventClose(false);
        await windowManager.close();
      }
    }
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => fullScreen = true);
    _fullScreenTransition?.complete();
    _fullScreenTransition = null;
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => fullScreen = false);
    _fullScreenTransition?.complete();
    _fullScreenTransition = null;
  }

  Future<void> setFullScreen(bool value) {
    return _fullScreenOperations = _fullScreenOperations.then(
      (_) => perform(() async {
        if (!mounted || closing) return;
        if (await windowManager.isFullScreen() != value) {
          // AppKit updates its style mask before the fullscreen animation ends.
          // Wait for its completion event before allowing a reverse transition.
          final transition = Platform.isMacOS ? Completer<void>() : null;
          _fullScreenTransition = transition;
          try {
            await windowManager.setFullScreen(value);
            await transition?.future.timeout(const Duration(seconds: 5));
          } finally {
            _fullScreenTransition = null;
          }
        }
        // Windows can resize to fullscreen without emitting enter/leave events.
        final actual = await windowManager.isFullScreen();
        if (mounted && !closing) setState(() => fullScreen = actual);
      }),
    );
  }

  Future<void> setWindowFullScreen(bool value) async {
    if (fullScreen) {
      await setFullScreen(false);
      if (fullScreen) return;
    }
    if (mounted) setState(() => windowFullScreen = value);
  }

  @override
  void dispose() {
    closing = true;
    if (ready) {
      _controllers?.removeListener(servicesChanged);
      downloads.availability.removeListener(availabilityChanged);
    }
    unawaited(
      (ready ? coordinator.close() : Future<void>.value()).whenComplete(
        service.close,
      ),
    );
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    homeFeedback.dispose();
    syncFeedback.dispose();
    search.dispose();
    searchFocus.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (closing) {
      return const MaterialApp(home: Scaffold(body: SizedBox.shrink()));
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Melonbang',
      builder: (context, child) => ready
          ? ContentCacheScope(
              cache: service.cache,
              child: SubjectCoverScope(covers: service.catalog, child: child!),
            )
          : child!,
      scaffoldMessengerKey: messages,
      navigatorKey: navigation,
      theme: appTheme(dark),
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              focusSearch,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              focusSearch,
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
              goBack,
          const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
              goBack,
        },
        child: Builder(
          // One animated theme for the whole window: entering the player or
          // switching its lights fades between light and dark.
          builder: (context) => AnimatedTheme(
            data: appTheme(dark || (route == 'player' && playerLightsOff)),
            duration: motionDuration(context, 300),
            curve: Curves.easeInOut,
            child: Scaffold(
              body: Column(
                children: [
                  if (!fullScreen)
                    AppTitleBar(
                      immersive: route == 'player' && windowFullScreen,
                      dark: dark,
                      sidebarVisible: showSidebar,
                      onBack: history.isEmpty ? null : goBack,
                      backLabel: '返回',
                      onToggleSidebar: () => setState(() {
                        if (route == 'player') {
                          playerSidebarVisible = !playerSidebarVisible;
                        } else {
                          sidebarVisible = !sidebarVisible;
                        }
                      }),
                      onToggleTheme: () => setDark(!dark),
                      search: search,
                      searchFocusNode: searchFocus,
                      onSearch: (query) => searchSubjects(query: query),
                      recentSearches: recentSearches,
                      onClearRecentSearches: clearRecentSearches,
                    ),
                  Expanded(
                    child: Row(
                      children: [
                        if (!fullScreen &&
                            !(route == 'player' && windowFullScreen))
                          MotionReveal(
                            visible: showSidebar,
                            axis: Axis.horizontal,
                            child: SizedBox(
                              width: sidebarWidth,
                              child: sidebar(),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            children: [
                              if (busy && !fullScreen)
                                const LinearProgressIndicator(minHeight: 2),
                              Expanded(
                                child: PageStorage(
                                  bucket: pageStorage,
                                  child: route == 'player'
                                      ? player()
                                      : PageEntrance(
                                          key: PageStorageKey(pageIdentity),
                                          child: page(),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget sidebar() {
    Widget build(int count) {
      final account = ready ? personal.profile : null;
      return AppSidebar(
        dark: dark,
        route: route,
        selectedRoute: selectedSection,
        sourcesWarning: ready && service.sources.warning,
        nickname: account?.nickname ?? '未登录',
        username: account?.username,
        avatarUrl: account?.avatarUrl,
        watchingCount: ready ? personal.watching.length : 0,
        downloadCount: count,
        onNavigate: navigate,
      );
    }

    if (!ready) return build(0);
    return ValueListenableBuilder<int>(
      valueListenable: downloads.active,
      builder: (context, count, _) => build(count),
    );
  }

  Widget player() => PlayerPage(
    key: playerPageKey,
    playback: playback,
    newResourceSearch: service.newResourceSearch,
    onError: showError,
    onBack: goBack,
    fullScreen: fullScreen,
    windowFullScreen: windowFullScreen,
    onWindowFullScreenChanged: setWindowFullScreen,
    downloads: downloads,
    onPlayFile: (id, fileId) => coordinator.play(
      () => service.library.fromDownload(id, fileId: fileId),
    ),
    onFullScreenChanged: setFullScreen,
    lightsOff: dark ? null : playerLightsOff,
    onLightsChanged: setPlayerLights,
    subject: coordinator.subject,
    preparing: coordinator.preparing,
    onRetryPreparing: coordinator.retryPreparing,
    onChoosePreparing: coordinator.choosePreparing,
    onEpisode: coordinator.playEpisode,
    onPlayCandidate: (candidate, episode) => episode == null
        ? playCachedFile(candidate)
        : coordinator.playCandidate(candidate, coordinator.subject!, episode),
    onOpenResources: openResourcePage,
  );

  void setDark(bool value) {
    setState(() => dark = value);
    unawaited(widget.preferences.setBool('dark', value));
  }

  Widget downloadsSection(Widget Function() content) => ListenableBuilder(
    listenable: Listenable.merge([
      service.downloadsAvailable,
      service.downloadIssue,
    ]),
    builder: (context, _) {
      if (service.downloadsAvailable.value) return content();
      final issue = service.downloadIssue.value;
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: issue == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在恢复缓存任务…'),
                  ],
                )
              : Text('缓存任务恢复失败：$issue'),
        ),
      );
    },
  );

  Widget page() {
    if (!ready) {
      return startError == null
          ? Center(
              child: ValueListenableBuilder<String>(
                valueListenable: service.startupStatus,
                builder: (context, status, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(status),
                  ],
                ),
              ),
            )
          : EmptyState(text: '应用服务未能启动', detail: startError);
    }
    switch (route) {
      case 'home':
        return HomePage(
          discovery: discovery,
          personal: personal,
          resume: resume,
          onOpenTracking: () => navigate('tracking'),
          onExplore: focusSearch,
          feedback: homeFeedback,
          onCalendar: () => navigate('calendar'),
          onRefresh: refreshHome,
          onOpenSubject: openSubject,
        );
      case 'search':
        return SearchPage(discovery: discovery, onOpenSubject: openSubject);
      case 'calendar':
        return CalendarPage(
          calendar: discovery.calendar,
          loading: discovery.calendarLoading,
          error: discovery.calendarError,
          onOpenSubject: openSubject,
          onRetry: () => perform(discovery.loadCalendar),
        );
      case 'tracking':
        return TrackingPage(
          personal: personal,
          onOpenSubject: openSubject,
          feedback: syncFeedback,
          onSignIn: () => navigate('settings'),
          onSync: syncCollection,
          onExplore: focusSearch,
        );
      case 'subject':
        return SubjectPage(
          subjects: subjects,
          personal: personal,
          resume: resume,
          community: service.community,
          onFindResources: (episode) {
            final item = subjects.subject;
            if (episode == null) {
              findResources(item);
            } else if (item != null) {
              unawaited(coordinator.chooseSource(item, episode));
            }
          },
          onPlayEpisode: (episode) {
            final item = subjects.subject!;
            unawaited(
              coordinator.prepare(
                item,
                episode,
                () => coordinator.selectEpisode(item, episode),
              ),
            );
          },
          onOpenSubject: openSubject,
          onError: showError,
        );
      case 'resources':
        final subject = resources.state.subject;
        return ResourceSearchView(
          key: ValueKey(
            'resources:${subject?.id}:${resources.state.episode?.id}',
          ),
          search: resources,
          onPlay: (candidate, episode) => episode == null
              ? playCachedFile(candidate)
              : coordinator.prepare(
                  subject!,
                  episode,
                  () => coordinator.playCandidate(candidate, subject, episode),
                ),
        );
      case 'downloads':
        return downloadsSection(
          () => DownloadsPage(
            downloads: downloads,
            onExplore: () => navigate('home'),
            onError: showError,
            onPlay: (id, fileId) => coordinator.play(
              () => service.library.fromDownload(id, fileId: fileId),
            ),
          ),
        );
      case 'sources':
        return SourcesPage(
          registry: service.sources,
          onProbePikPak: () => service.sources.probe(
            'pikpak',
            url: PikPakTransfer.driveUrl,
            external: service.pikpakTransfer.checkAccess,
          ),
          onPlay: (stream) =>
              coordinator.play(() async => service.library.online(stream)),
        );
      case 'settings':
        final pikpak = service.pikpakTransfer;
        Future<void> changeAccount(Future<void> Function() change) async {
          await change();
          if (mounted) setState(() {});
        }

        return SettingsPage(
          playback: playback,
          personal: personal,
          dark: dark,
          dataDirectory: service.dataDirectory,
          cacheSettings: downloadsSection(
            () => CacheSettings(
              defaultMethod: downloads.defaultMethod,
              onMethodChanged: downloads.saveCacheMethod,
              account: pikpak.accountName,
              needsAuthorization: pikpak.needsAuthorization,
              verificationUrl: pikpak.verificationUrl,
              onUnlock: () => changeAccount(pikpak.unlock),
              onLogin: (username, password) =>
                  changeAccount(() => pikpak.signIn(username, password)),
              onLogout: () => changeAccount(pikpak.signOut),
            ),
          ),
          storageSettings: StorageSettings(
            readCacheSize: service.cache.size,
            onClearCache: () async {
              await service.cache.clear();
              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();
            },
            onExit: () => windowManager.close(),
            storage: service.storage,
            dataDirectory: service.dataDirectory!,
            mediaDirectory: service.bt.directory,
          ),
          onSync: () => perform(() async {
            final syncing = syncCollection();
            setState(() {});
            await syncing;
            if (mounted) setState(() {});
            if (syncFeedback.issue != null) {
              throw StateError(syncFeedback.issue!);
            }
          }),
          syncBusy: syncFeedback.busy,
          bitTorrentSettings: downloadsSection(
            () => BitTorrentSettingsPanel(
              settings: service.bt.settings,
              onSave: service.bt.saveSettings,
            ),
          ),
          onThemeChanged: setDark,
          onCancelSignIn: () => perform(personal.cancelSignIn),
          onAccountAction: () => perform(personal.toggleAccount),
        );
      default:
        return const EmptyState(text: '打开一部喜欢的作品');
    }
  }
}

/// A page to return to, with what it showed.
class _PageLocation {
  const _PageLocation({
    required this.route,
    required this.accountId,
    required this.section,
    required this.subject,
    required this.query,
    required this.search,
    required this.resources,
    required this.pending,
  });
  final String route, accountId, section, query;
  final Subject? subject;
  final SearchResults search;
  final ResourceSearchState resources;

  /// Still loading when left; loaded again on return.
  final bool pending;
}
