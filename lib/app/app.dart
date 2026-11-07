import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app_services.dart';
import 'app_tray.dart';
import '../core/background.dart';
import '../core/error_message.dart';
import '../core/network.dart';
import '../features/acquisition/resource_metadata.dart';
import '../domain/catalog.dart';
import '../domain/play_candidate.dart';
import '../features/appearance/appearance.dart';
import '../features/discovery/discovery_controller.dart';
import '../features/downloads/downloads_controller.dart';
import '../features/playback/playback.dart';
import '../features/playback/playback_coordinator.dart';
import '../features/playback/resource_search.dart';
import '../features/playback/resume_controller.dart';
import '../features/discovery/continue_range.dart';
import '../features/discovery/schedule_filter.dart';
import '../features/subscriptions/subscription_controller.dart';
import '../features/tracking/subject_controller.dart';
import '../features/tracking/tracking_controller.dart';
import '../features/update/app_update.dart';
import '../ui/acquisition/downloads_page.dart';
import '../ui/acquisition/resource_search_view.dart';
import '../ui/core/action_feedback.dart';
import '../ui/core/app_chrome.dart';
import '../ui/core/byte_units.dart';
import '../ui/core/cached_image.dart';
import '../ui/core/cover_colors.dart';
import '../ui/core/motion.dart';
import '../ui/core/page_widgets.dart';
import '../ui/core/pointer_lamp.dart';
import '../ui/core/subject_posters.dart';
import '../ui/core/theme.dart';
import '../ui/core/theme_reveal.dart';
import '../ui/discovery/calendar_page.dart';
import '../ui/discovery/home_page.dart';
import '../ui/discovery/search_page.dart';
import '../ui/player/player_page.dart';
import '../ui/settings/bittorrent_settings.dart';
import '../ui/settings/network_settings.dart';
import '../ui/settings/settings_page.dart';
import '../ui/settings/settings_sections.dart';
import '../ui/settings/storage_settings.dart';
import '../ui/settings/update_settings.dart';
import '../ui/sources/pikpak_account.dart';
import '../ui/sources/sources_page.dart';
import '../ui/subscriptions/subscription_dialogs.dart';
import '../ui/tracking/subject_page.dart';
import '../ui/tracking/tracking_page.dart';

class MelonApp extends StatefulWidget {
  const MelonApp({
    super.key,
    required this.window,
    required this.service,
    required this.preferences,
  });
  final Window window;
  final AppServices service;
  final SharedPreferences preferences;
  @override
  State<MelonApp> createState() => _MelonAppState();
}

/// The window: navigation, history, title bar, sidebar and full screen. Page
/// state and requests belong to the feature controllers.
class _MelonAppState extends State<MelonApp>
    with WidgetsBindingObserver
    implements PlaybackShell {
  final messages = GlobalKey<ScaffoldMessengerState>();
  final navigation = GlobalKey<NavigatorState>();
  final playerPageKey = GlobalKey<PlayerPageState>();

  /// The player's side panel; null until the player picks a default.
  final playerPanel = ValueNotifier<bool?>(null);
  final search = TextEditingController();
  final searchFocus = FocusNode(debugLabel: 'Catalogue search');
  final pageStorage = PageStorageBucket();

  /// Sidebar pages shown so far, kept so coming back to one does not build
  /// it again.
  final kept = <String>{};
  final List<_PageLocation> history = [];
  final subscriptions = <StreamSubscription<dynamic>>[];
  final homeFeedback = ActionFeedback();
  String route = 'home', selectedSection = 'home';
  bool ready = false, fullScreen = false;
  bool closing = false, sidebarVisible = true, windowFullScreen = false;

  /// Theme mode, theme colour and cover colouring.
  late final appearance = Appearance(widget.preferences);

  /// Which shows the home page's 继续观看 lists.
  late final continueRange = ContinuePreference(widget.preferences);
  late final scheduleFilter = SchedulePreference(widget.preferences);

  /// Set when the window's close quits rather than going to the background.
  bool quitting = false;

  /// While the first close asks whether to stay in the background.
  bool askingClose = false;

  /// Set once everything is shut down and the window may close for good.
  bool exiting = false;
  ListenerId? windowListener;

  /// The tray icon while there are subscriptions.
  AppTray? tray;
  bool? keptAwake;
  CoverColors? covers;

  /// The cover the theme colour is taken from, and that colour once read.
  String? coverSeedUrl;
  Color? coverSeed;

  /// Set when quitting to uninstall, which skips a waiting update.
  bool uninstalling = false;

  bool get dark => appearance.dark(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  /// Relaunch once the prepared update has been swapped in on exit.
  bool restartForUpdate = false;

  /// Set when quitting to start again after a failed startup.
  bool relaunching = false;
  String? startError;

  /// Set on a first launch until the download location is confirmed.
  Completer<void>? storageSetup;
  List<String> recentSearches = [];
  Listenable? _controllers;
  Future<void> _fullScreenOperations = Future.value();
  Completer<void>? _fullScreenTransition;

  /// The player starts with the sidebar collapsed so the video gets the width;
  /// toggling it there does not change the other pages.
  bool playerSidebarVisible = false;

  Window get window => widget.window;
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
  bool get loading =>
      ready &&
      switch (route) {
        'subject' => subjects.loading,
        'search' => discovery.searching,
        'resources' => resources.busy,
        _ => false,
      };

  /// Whether the title-bar progress shows: a subject only until its detail
  /// is shown, after which its sections show what they still load; never
  /// for resources, whose page shows each site's progress.
  bool get busy =>
      loading &&
      route != 'resources' &&
      (route != 'subject' || subjects.waiting);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appearance.addListener(servicesChanged);
    continueRange.addListener(servicesChanged);
    unawaited(appearance.refreshSystemAccent());
    recentSearches = widget.preferences.getStringList('recentSearches') ?? [];
    windowListener = window.addListener(windowEvent);
    Background.listen(
      onQuit: quit,
      onOpenSubject: (_) {
        showWindow();
        navigate('downloads');
      },
    );
    unawaited(boot());
  }

  Future<void> boot() async {
    try {
      if (await (await service.locate())?.fresh ?? false) {
        setState(() => storageSetup = Completer());
        await storageSetup!.future;
        if (!mounted || closing) return;
        setState(() => storageSetup = null);
      }
      await service.start();
      if (!mounted || closing) return;
      covers = CoverColors(service.cache);
      coordinator.shell = this;
      _controllers = Listenable.merge([
        coordinator,
        service.sources,
        service.downloadsAvailable,
        discovery,
        personal,
        subjects,
        resources,
        service.subscriptions,
      ])..addListener(servicesChanged);
      downloads.availability.addListener(availabilityChanged);
      service.subscriptions.onCached = (subscription, episode) => unawaited(
        Background.notify(
          '${subscription.title} ${episode?.label ?? '新一话'}已缓存',
          subscription.ledger[episode?.id]?.title ?? '',
          subjectId: subscription.subjectId,
        ),
      );
      service.subscriptions.onEnded = (subscription, reason) => unawaited(
        Background.notify(
          '${subscription.title} 已取消订阅',
          '$reason；已缓存的文件都还在',
          subjectId: subscription.subjectId,
        ),
      );
      service.subscriptions.addListener(syncTray);
      downloads.active.addListener(syncTray);
      subscriptions.add(
        service.tracking.changes.stream.listen((_) {
          if (!mounted) return;
          unawaited(perform(personal.refresh));
          unawaited(perform(refreshPlaybackAvailability));
        }),
      );
      setState(() => ready = true);
      syncTray();
      unawaited(perform(pullProgress));
      if (service.update.autoCheck) unawaited(perform(service.update.check));
      await Future.wait([
        discovery.loadHome().then((issue) {
          // An empty feed names its failure on the home page itself.
          if (issue != null && discovery.homeShowsStale) showError(issue);
        }),
        personal.refresh(),
        refreshPlaybackAvailability(),
      ]);
      unawaited(discovery.loadCalendar());
    } catch (e) {
      // Once the window works, a failed first load is an ordinary error.
      if (ready) {
        showError(e);
      } else if (mounted) {
        setState(() => startError = errorMessage(e));
      }
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

  Future<void> refreshHome() {
    unawaited(perform(pullProgress));
    return homeFeedback.run(() => discovery.loadHome(refresh: true));
  }

  /// Pulls the Bangumi collection and the episode progress of recently
  /// played subjects; the tracking changes refresh the pages. A failure
  /// keeps the saved progress and shows on the tracking page.
  Future<void> pullProgress() async {
    await personal.pull();
    await resume.pull().catchError((Object _) {});
  }

  Future<void> refreshPlaybackAvailability() => resume.refresh(subjects.id);

  _PageLocation get location => _PageLocation(
    route: route,
    accountId: personal.userId,
    section: selectedSection,
    subject: subjects.subject,
    query: search.text,
    search: discovery.search,
    resources: resources.state,
    pending: loading,
  );

  void rememberLocation() {
    history.add(location);
    // Each location keeps its page's results; older steps are dropped.
    if (history.length > 50) history.removeAt(0);
  }

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
    // A player left while it was still preparing has nothing to return to.
    while (history.lastOrNull?.route == 'player' && playback.uri == null) {
      history.removeLast();
    }
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
    // Filters change in place; a new keyword or tag is another page.
    'search' => 'search:${discovery.search.query.text}',
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
  void showError(Object e) =>
      showMessage(messages.currentState, errorMessage(e));

  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } on RequestCancelled {
      return;
    } catch (e) {
      showError(e);
    }
  }

  /// Opens [item]'s detail page; unless [remember] is false, back returns
  /// to the current page.
  Future<void> openSubject(Subject item, {bool remember = true}) async {
    if (item.id <= 0) {
      showError('这部番暂时没有详情');
      return;
    }
    leavePlayer();
    if (remember && (route != 'subject' || subjects.id != item.id)) {
      rememberLocation();
    }
    nextNavigation();
    setState(() => route = 'subject');
    final opening = subjects.open(item);
    unawaited(perform(refreshPlaybackAvailability));
    if (discovery.calendar.isEmpty) unawaited(discovery.loadCalendar());
    await perform(() => opening);
  }

  /// The player's detail entry: back to the detail page the player was
  /// opened from, otherwise to a new one; back from it skips the stopped
  /// player.
  void openPlayerSubject(Subject item) {
    final previous = history.lastOrNull;
    if (previous?.route == 'subject' && previous?.subject?.id == item.id) {
      goBack();
      return;
    }
    unawaited(openSubject(item, remember: false));
  }

  @override
  bool get showingPlayer => route == 'player';

  @override
  void enterPlayer() {
    if (route != 'player') rememberLocation();
    nextNavigation();
    setState(() => route = 'player');
  }

  /// Detach the video texture before disposing its native rendering context.
  /// A hidden window draws no frames, and has no texture on screen.
  @override
  Future<void> videoDetached() async {
    if (!window.isVisible) return;
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
  }

  /// A playing player searches in its own sheet instead of leaving for the
  /// resources page.
  @override
  Future<void> openResources(Subject subject, Episode episode) async {
    final player = playerPageKey.currentState;
    if (route == 'player' &&
        player != null &&
        coordinator.preparing == null &&
        playback.uri != null) {
      player.findResources(episode);
    } else {
      findResources(subject, episode: episode);
    }
  }

  @override
  Future<PlayCandidate?> chooseCandidate(Subject item, Episode episode) async {
    final target = navigation.currentState?.overlay?.context;
    if (target == null) return null;
    final search = service.newResourceSearch()..open(item, episode: episode);
    try {
      return await showMelonDialog<PlayCandidate>(
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

  /// Searches typed text, where `#百合` searches the tag 百合. On the search
  /// page the filters stay, so empty text searches by them alone; elsewhere
  /// it lists every anime.
  Future<void> searchSubjects({String? query}) async {
    final typed = SubjectQuery.parse(query ?? search.text);
    await searchCatalogue(
      route == 'search'
          ? discovery.search.query.copyWith(
              keyword: typed.keyword,
              tag: typed.tag,
            )
          : typed,
    );
  }

  /// Opens the search page for [query].
  Future<void> searchCatalogue(SubjectQuery query) async {
    if (!ready) return;
    search.text = query.text;
    searchFocus.unfocus();
    if (query.text.isNotEmpty) rememberSearch(query.text);
    leavePlayer();
    if (route != 'search') rememberLocation();
    nextNavigation();
    setState(() => route = 'search');
    await discovery.searchSubjects(query);
  }

  /// Changes the filters or order of the search page in place.
  Future<void> refineSearch(SubjectQuery query) {
    search.text = query.text;
    return discovery.searchSubjects(query);
  }

  /// The settings section [openSettings] shows first.
  String? settingsSection;

  void openSettings(String section) {
    settingsSection = section;
    // Settings scroll to the section when they open.
    if (route != 'settings') kept.remove('settings');
    navigate('settings');
  }

  void navigate(String target) {
    if (target != 'settings') settingsSection = null;
    if (target == route) return;
    leavePlayer();
    rememberLocation();
    nextNavigation();
    setState(() {
      route = target;
      if (_sections.contains(target)) {
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
        unawaited(perform(pullProgress));
        // Continue watching times the next episodes by the schedule.
        if (discovery.calendar.isEmpty) {
          unawaited(discovery.loadCalendar());
        }
      case 'tracking':
        unawaited(personal.pull());
        unawaited(discovery.loadCalendar());
      case 'calendar':
        unawaited(discovery.loadCalendar());
    }
  }

  /// Brings the window back from the background or the Dock.
  void showWindow() {
    if (window.isMinimized) window.restore();
    window
      ..show()
      ..focus();
  }

  /// Keeps the tray icon, and macOS awake enough for the timers, while
  /// there are subscriptions.
  void syncTray() {
    if (!ready || closing) return;
    final subscriptions = service.subscriptions;
    final active = subscriptions.active;
    if (keptAwake != active) {
      keptAwake = active;
      unawaited(Background.keepAwake(active).catchError((Object _) {}));
    }
    if (subscriptions.subscriptions.isEmpty) {
      tray?.hide();
      return;
    }
    final icon = tray ??= AppTray(
      onOpen: showWindow,
      onCheck: subscriptions.checkNow,
      onQuit: quit,
    );
    icon.show(
      subscribed: subscriptions.subscriptions.length,
      caching: downloads.active.value,
    );
  }

  /// Quits for good: from the tray, Command-Q, settings, an update or
  /// uninstalling, past staying in the background.
  void quit() {
    quitting = true;
    closeWindow();
  }

  /// The window's close requests, focus and full screen.
  void windowEvent(WindowEvent event) {
    switch (event) {
      case WindowCloseRequestedEvent(:final request):
        // The title bar's close, Alt-F4 and our own close button all go
        // through [closeWindow]; only its final close passes.
        if (exiting) return;
        request.cancel();
        closeWindow();
      case WindowFocusedEvent():
        // System colours and proxy settings can change while the app runs.
        unawaited(appearance.refreshSystemAccent());
        unawaited(service.proxy.refreshSystem());
      case WindowEnteredFullScreenEvent():
        fullScreenChanged(true);
      case WindowExitedFullScreenEvent():
        fullScreenChanged(false);
      default:
    }
  }

  /// Closing the window while subscriptions run keeps the app going in
  /// the background, once asked; otherwise, or when [quitting], it quits.
  void closeWindow() async {
    if (closing || askingClose) return;
    if (!quitting && ready && service.subscriptions.active) {
      final preferences = service.subscriptions.preferences;
      var action = preferences.closeAction;
      if (action == null) {
        final target = navigation.currentState?.overlay?.context;
        if (target == null) return;
        askingClose = true;
        try {
          action = await askCloseAction(
            target,
            shows: service.subscriptions.subscriptions.length,
          );
        } finally {
          askingClose = false;
        }
        if (action == null) return;
        await preferences.setCloseAction(action);
      }
      if (action == CloseAction.background) {
        await toBackground();
        return;
      }
    }
    setState(() => closing = true);
    await videoDetached();
    try {
      if (ready) await coordinator.close();
    } finally {
      try {
        await service.close();
        if (ready && !uninstalling) {
          await service.update.applyOnExit(restart: restartForUpdate);
        }
      } finally {
        if (relaunching) await relaunchAfterExit();
        tray?.hide();
        exiting = true;
        if (Platform.isMacOS) {
          // The macOS runner stays open without windows; it quits itself.
          await Background.quit().catchError((Object _) {});
        } else {
          // Closing continues the runner's own WM_CLOSE on Windows, which
          // destroys its view before leaving the message loop.
          window.close();
        }
      }
    }
  }

  /// Hides the window, or minimizes it on Linux, whose desktops may have no
  /// tray to come back from; the player stops and lets go of its video.
  Future<void> toBackground() async {
    if (route == 'player') goBack();
    if (fullScreen) await setFullScreen(false);
    if (Platform.isLinux) {
      window.minimize();
    } else {
      window.hide();
    }
  }

  void restartToUpdate() {
    restartForUpdate = true;
    quit();
  }

  /// Quits and opens the app again, since partly started services cannot be
  /// started a second time in this process.
  void relaunch() {
    relaunching = true;
    quit();
  }

  /// Hidden to the tray or minimized, the app gives way to whatever the user
  /// does now, unless a video still plays on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Background.yieldResources(
      state == AppLifecycleState.hidden && !(ready && playback.playing),
    );
  }

  @override
  void didChangePlatformBrightness() {
    if (appearance.mode == ThemeChoice.system) setState(() {});
  }

  /// The cover the current page takes its colour from, while that is on.
  String? get themeCover {
    if (!ready || !appearance.coverColor) return null;
    return switch (route) {
      'subject' => subjects.subject?.coverUrl,
      // Kept while the player loads the subject between sessions.
      'player' =>
        coordinator.subject?.coverUrl ??
            coordinator.preparing?.coverUrl ??
            coverSeedUrl,
      _ => null,
    };
  }

  /// The theme colour: the page's cover colour once read, else the chosen
  /// one.
  Color get themeAccent {
    final cover = themeCover;
    if (cover != coverSeedUrl) {
      coverSeedUrl = cover;
      // The previous cover's colour stays until the new one is read, so
      // moving between subjects changes colour once.
      if (cover == null) coverSeed = null;
      if (cover != null) {
        unawaited(
          covers!.seed(cover).then((value) {
            if (mounted && coverSeedUrl == cover) {
              setState(() => coverSeed = value);
            }
          }),
        );
      }
    }
    return cover != null && coverSeed != null ? coverSeed! : appearance.seed;
  }

  Future<void> uninstallApp(bool wipe) async {
    try {
      await service.uninstall.start(wipe: wipe);
    } catch (e) {
      showError('无法开始卸载：${errorMessage(e)}');
      return;
    }
    uninstalling = true;
    quit();
  }

  void fullScreenChanged(bool value) {
    if (mounted) setState(() => fullScreen = value);
    _fullScreenTransition?.complete();
    _fullScreenTransition = null;
  }

  Future<void> setFullScreen(bool value) {
    return _fullScreenOperations = _fullScreenOperations.then(
      (_) => perform(() async {
        if (!mounted || closing) return;
        if (window.isFullScreen != value) {
          // AppKit updates its style mask before the fullscreen animation ends.
          // Wait for its completion event before allowing a reverse transition.
          final transition = Platform.isMacOS ? Completer<void>() : null;
          _fullScreenTransition = transition;
          try {
            window.isFullScreen = value;
            await transition?.future.timeout(const Duration(seconds: 5));
          } finally {
            _fullScreenTransition = null;
          }
        }
        // Windows can resize to fullscreen without emitting enter/leave events.
        final actual = window.isFullScreen;
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
      service.subscriptions.removeListener(syncTray);
      downloads.active.removeListener(syncTray);
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
    playerPanel.dispose();
    continueRange.dispose();
    scheduleFilter.dispose();
    tray?.hide();
    search.dispose();
    searchFocus.dispose();
    appearance.removeListener(servicesChanged);
    continueRange.removeListener(servicesChanged);
    appearance.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (windowListener case final listener?) window.removeListener(listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (closing) {
      return const MaterialApp(home: Scaffold(body: SizedBox.shrink()));
    }
    final theme = appTheme(dark, accent: themeAccent);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Melonbang',
      // A reveal replaces the fades between themes.
      themeAnimationDuration: instantTheme
          ? Duration.zero
          : kThemeAnimationDuration,
      builder: (context, child) => LampTracker(
        child: ThemeReveal(
          key: themeReveal,
          child: ByteUnitsScope(
            units: appearance.byteUnits,
            child: ready
                ? ContentCacheScope(
                    cache: service.cache,
                    child: SubjectCoverScope(
                      covers: service.catalog,
                      child: child!,
                    ),
                  )
                : child!,
          ),
        ),
      ),
      scaffoldMessengerKey: messages,
      navigatorKey: navigation,
      theme: theme,
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
        // The mouse's back button goes back like the title-bar action.
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons & kBackMouseButton != 0 && history.isNotEmpty) {
              goBack();
            }
          },
          child: Builder(
            // One animated theme for the whole window: switching it fades
            // between light and dark.
            builder: (context) => AnimatedTheme(
              data: theme,
              duration: instantTheme
                  ? Duration.zero
                  : motionDuration(context, 300),
              curve: Curves.easeInOut,
              child: Scaffold(
                body: Column(
                  children: [
                    if (!fullScreen)
                      AppTitleBar(
                        window: window,
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
                        onToggleTheme: revealTheme,
                        search: search,
                        searchFocusNode: searchFocus,
                        onSearch: (query) => searchSubjects(query: query),
                        recentSearches: recentSearches,
                        onClearRecentSearches: clearRecentSearches,
                        update: ready ? service.update : null,
                        onRestartToUpdate: restartToUpdate,
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
                                MotionReveal(
                                  visible: busy && !fullScreen,
                                  child: const LinearProgressIndicator(
                                    minHeight: 2,
                                  ),
                                ),
                                Expanded(
                                  child: PageStorage(
                                    bucket: pageStorage,
                                    child: pages(),
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
      ),
    );
  }

  Widget sidebar() {
    Widget build(int count) {
      final account = ready ? personal.profile : null;
      return AppSidebar(
        route: route,
        selectedRoute: selectedSection,
        sourcesWarning: ready && service.sources.warning,
        nickname: account?.nickname ?? '未登录',
        username: account?.username,
        avatarUrl: account?.avatarUrl,
        accountIssue: account == null
            ? null
            : personal.sessionExpired
            ? '登录已过期'
            : personal.needsAuthorization
            ? '钥匙串未授权，暂停同步'
            : personal.credentialsUnsaved
            ? '登录没能保存到钥匙串'
            : null,
        watchingCount: ready ? personal.watching.length : 0,
        attentionCount: ready ? service.subscriptions.attention : 0,
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

  Future<void> playDownload(String id, String? fileId) {
    final task = downloads.snapshot.value.task(id);
    return coordinator.play(
      () => service.library.fromDownload(id, fileId: fileId),
      title: task?.title ?? '缓存视频',
      coverUrl: task?.coverUrl,
      downloadId: id,
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
    onPlayFile: playDownload,
    onFullScreenChanged: setFullScreen,
    panelOpen: playerPanel,
    community: service.community,
    source: coordinator.activeCandidate,
    remembered: playback.settings.rememberSource
        ? coordinator.remembered
        : null,
    onForgetSource: () => perform(coordinator.forgetSource),
    failure: coordinator.failure,
    onRetryFailure: coordinator.retryFailure,
    onMarkEpisode: coordinator.markEpisode,
    onOpenSubject: openPlayerSubject,
    subject: coordinator.subject,
    preparing: coordinator.preparing,
    onRetryPreparing: coordinator.retryPreparing,
    onChoosePreparing: coordinator.choosePreparing,
    onEpisode: coordinator.playEpisode,
    onPlayCandidate: (candidate, episode) =>
        coordinator.playCandidate(candidate, coordinator.subject!, episode),
    onOpenResources: openResourcePage,
  );

  void setDark(bool value) => unawaited(
    appearance.setMode(value ? ThemeChoice.dark : ThemeChoice.light),
  );

  final themeReveal = GlobalKey<ThemeRevealState>();

  /// While the title bar's switch opens the new theme from the pointer.
  bool instantTheme = false;

  /// The title bar's switch: the other theme spreads out from the pointer.
  void revealTheme() {
    final reveal = themeReveal.currentState;
    final next = dark ? ThemeChoice.light : ThemeChoice.dark;
    if (reveal == null) return unawaited(appearance.setMode(next));
    unawaited(
      reveal
          .run(() {
            setState(() => instantTheme = true);
            return appearance.setMode(next);
          })
          .whenComplete(() {
            if (mounted) setState(() => instantTheme = false);
          }),
    );
  }

  List<SettingsSection> settingsSections() => [
    accountSection(
      personal: personal,
      onAccountAction: () => perform(personal.toggleAccount),
      onCancelSignIn: () => perform(personal.cancelSignIn),
      onUnlock: () => perform(personal.unlock),
      onSaveCredentials: () => perform(personal.saveCredentials),
    ),
    appearanceSection(appearance, continueRange),
    playbackSection(playback.settings),
    danmakuSection(playback.danmaku.preferences),
    sourcesSection(
      playback.settings,
      cachedGroups: () => [
        for (final task in service.downloads.snapshot().tasks)
          ...task.releaseGroups,
      ],
    ),
    subscriptionSection(service.subscriptions.preferences, playback.settings),
    downloadsSection(
      available: service.downloadsAvailable,
      issue: service.downloadIssue,
      settings: service.bt.settings,
      onSave: service.bt.saveSettings,
    ),
    networkSection(proxy: service.proxy, connectivity: service.connectivity),
    storageSection(
      readCacheSize: service.cache.size,
      onClearCache: () async {
        await service.cache.clear();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      },
      onExit: quit,
      storage: service.storage,
      dataDirectory: service.dataDirectory!,
      mediaDirectory: service.bt.directory,
    ),
    shortcutsSection(),
    aboutSection(
      update: service.update,
      onRestart: restartToUpdate,
      uninstall: service.uninstall,
      onUninstall: uninstallApp,
    ),
  ];

  /// [content] once cache tasks are restored, until then their state.
  Widget restoredDownloads(Widget Function() content) => ListenableBuilder(
    listenable: Listenable.merge([
      service.downloadsAvailable,
      service.downloadIssue,
    ]),
    builder: (context, _) {
      if (service.downloadsAvailable.value) return content();
      return switch (service.downloadIssue.value) {
        null => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在恢复缓存任务…'),
            ],
          ),
        ),
        final issue => Padding(
          padding: const EdgeInsets.all(pageGutter),
          child: EmptyState(text: '缓存任务恢复失败', detail: issue),
        ),
      };
    },
  );

  /// The kept sidebar pages, the current one shown, over any other page.
  Widget pages() {
    if (_sections.contains(route)) kept.add(route);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final section in kept)
          _KeptPage(
            key: PageStorageKey(section),
            shown: route == section,
            builder: () => page(section),
          ),
        if (route == 'player')
          player()
        else if (!_sections.contains(route))
          PageEntrance(key: PageStorageKey(pageIdentity), child: page(route)),
      ],
    );
  }

  Widget page(String target) {
    if (storageSetup case final setup?) {
      return StorageSetup(storage: service.storage!, onDone: setup.complete);
    }
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
          : EmptyState(
              text: '应用服务未能启动',
              detail: startError,
              action: relaunch,
              actionLabel: '重新启动',
            );
    }
    switch (target) {
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
          range: continueRange.value,
          subscriptions: {
            for (final subscription
                in service.subscriptions.subscriptions.values)
              subscription.subjectId: switch (service.subscriptions.issueOf(
                subscription,
              )) {
                final issue? => (
                  lateEpisode: issue.episode?.id,
                  late: issue.late,
                ),
                null => (lateEpisode: null, late: null),
              },
          },
          onPlayEpisode: (subject, episode) => unawaited(
            coordinator.prepare(
              subject,
              episode,
              () => coordinator.selectEpisode(subject, episode),
            ),
          ),
        );
      case 'search':
        return SearchPage(
          discovery: discovery,
          onOpenSubject: openSubject,
          onQuery: refineSearch,
        );
      case 'calendar':
        return CalendarPage(
          calendar: discovery.calendar,
          loading: discovery.calendarLoading,
          error: discovery.calendarError,
          onOpenSubject: openSubject,
          onRetry: discovery.loadCalendar,
          filter: scheduleFilter,
        );
      case 'tracking':
        return TrackingPage(
          personal: personal,
          resume: resume,
          airing: {
            for (final day in discovery.calendar)
              for (final item in day.items) item.id,
          },
          onOpenSubject: openSubject,
          onAccountAction: () => perform(personal.toggleAccount),
          onUnlock: () => perform(personal.unlock),
          onSaveCredentials: () => perform(personal.saveCredentials),
          onExplore: focusSearch,
        );
      case 'subject':
        return SubjectPage(
          subjects: subjects,
          coverTint: themeCover != null && coverSeed != null,
          personal: personal,
          resume: resume,
          airings: [
            for (final day in discovery.calendar)
              for (final item in day.items)
                if (item.id == subjects.id) ?item.airingAt,
          ],
          community: service.community,
          catalog: service.catalog,
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
          onOpenEpisode: (episode) => unawaited(
            perform(() => coordinator.openEpisode(subjects.subject!, episode)),
          ),
          onOpenSubject: openSubject,
          onSearch: searchCatalogue,
          onError: showError,
          subscribeButton: (subject) => SubscribeButton(
            controller: service.subscriptions,
            subject: subject,
            preferredGroups: () => playback.settings.preferredGroups,
            onError: showError,
            markWatching: personal.profile == null
                ? MarkWatching.unavailable
                : personal.needsAuthorization || personal.sessionExpired
                ? MarkWatching.paused
                : MarkWatching.available,
          ),
        );
      case 'resources':
        final subject = resources.state.subject;
        return ResourceSearchView(
          key: ValueKey(
            'resources:${subject?.id}:${resources.state.episode?.id}',
          ),
          search: resources,
          onOpenDownloads: () => navigate('downloads'),
          onPlay: (candidate, episode) => coordinator.prepare(
            subject!,
            episode,
            () => coordinator.playCandidate(candidate, subject, episode),
          ),
        );
      case 'downloads':
        return restoredDownloads(
          () => DownloadsPage(
            downloads: downloads,
            onExplore: () => navigate('home'),
            onError: showError,
            onPlay: playDownload,
            subjectOf: (id) async =>
                await service.catalog.cached(id) ??
                await service.catalog.subject(id, forPlayback: true),
            onPlaySubject: coordinator.continueCache,
            hasProgress: (id) async =>
                await service.library.lastPlayed(id) != null,
            subscriptions: service.subscriptions,
            preferredGroups: () => playback.settings.preferredGroups,
            onOpenSubject: (id) => unawaited(
              perform(
                () async => openSubject(
                  await service.catalog.cached(id) ?? Subject(id: id),
                ),
              ),
            ),
          ),
        );
      case 'sources':
        final pikpak = service.pikpakTransfer;
        Future<void> changeAccount(Future<void> Function() change) async {
          await change();
          if (mounted) setState(() {});
        }

        return SourcesPage(
          registry: service.sources,
          danmaku: service.danmaku,
          connectivity: service.connectivity,
          pikpakAccount: PikPakAccount(
            account: pikpak.accountName,
            needsAuthorization: pikpak.needsAuthorization,
            verificationUrl: pikpak.verificationUrl,
            onUnlock: () => changeAccount(pikpak.unlock),
            onLogin: (username, password) =>
                changeAccount(() => pikpak.signIn(username, password)),
            onLogout: () => changeAccount(pikpak.signOut),
          ),
          onPlay: (stream) => coordinator.play(
            () async => service.library.online(stream),
            title: '在线视频',
          ),
          onOpenUpdates: () => openSettings('about'),
        );
      case 'settings':
        return SettingsPage(
          sections: settingsSections(),
          initial: settingsSection,
        );
      default:
        return const EmptyState(text: '打开一部喜欢的作品');
    }
  }
}

/// The pages the sidebar leads to.
const _sections = ['home', 'tracking', 'downloads', 'sources', 'settings'];

/// A sidebar page kept once shown. Hidden, it keeps what it last built,
/// stops its animations and takes no focus; shown again, it rises in.
class _KeptPage extends StatefulWidget {
  const _KeptPage({
    required super.key,
    required this.shown,
    required this.builder,
  });
  final bool shown;
  final Widget Function() builder;

  @override
  State<_KeptPage> createState() => _KeptPageState();
}

class _KeptPageState extends State<_KeptPage> {
  Widget? page;

  @override
  Widget build(BuildContext context) {
    if (widget.shown || page == null) page = widget.builder();
    return Visibility(
      visible: widget.shown,
      maintainState: true,
      child: ExcludeFocus(
        excluding: !widget.shown,
        // Shown again, a kept page is already laid out and appears at once,
        // as a sidebar switch does in native apps; fading it in from dim
        // read as a stall.
        child: PageEntrance(child: page!),
      ),
    );
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
