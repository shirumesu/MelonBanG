import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app_services.dart';
import 'ui/acquisition/download_dialogs.dart';
import 'ui/acquisition/downloads_page.dart';
import 'ui/acquisition/resources_page.dart';
import 'data/resource_metadata.dart';
import 'ui/core/action_feedback.dart';
import 'ui/core/app_chrome.dart';
import 'ui/core/motion.dart';
import 'ui/core/page_widgets.dart';
import 'ui/core/theme.dart';
import 'ui/core/subject_posters.dart';
import 'ui/discovery/discovery_pages.dart';
import 'ui/player/playback.dart';
import 'ui/player/player_page.dart';
import 'ui/settings/bittorrent_settings.dart';
import 'ui/settings/settings_page.dart';
import 'ui/settings/storage_settings.dart';
import 'ui/tracking/subject_page.dart';
import 'ui/tracking/tracking_page.dart';

class MelonApp extends StatefulWidget {
  const MelonApp({
    super.key,
    required this.service,
    required this.preferences,
    this.initialMedia,
  });
  final AppServices service;
  final SharedPreferences preferences;
  final String? initialMedia;
  @override
  State<MelonApp> createState() => _MelonAppState();
}

class _MelonAppState extends State<MelonApp> with WindowListener {
  final messages = GlobalKey<ScaffoldMessengerState>();
  final navigation = GlobalKey<NavigatorState>();
  final playerPageKey = GlobalKey();
  final search = TextEditingController();
  final resourceSearch = TextEditingController();
  final searchFocus = FocusNode(debugLabel: 'Catalogue search');
  final pageStorage = PageStorageBucket();
  final List<_PageLocation> history = [];
  String selectedSection = 'home';
  String? searchError;
  String resultQuery = '';
  List<String>? resourceQueryNames;
  String resourceQueryEpisode = '';
  late final Playback playback;
  final subscriptions = <StreamSubscription<dynamic>>[];
  String route = 'home', collectionFilter = 'watching';
  bool dark = false, ready = false, busy = false, fullScreen = false;
  String? error;
  bool trendingLoading = true;
  bool todayLoading = true;
  String? todayError;
  String? todayDate;
  bool closing = false, sidebarVisible = true, windowFullScreen = false;
  bool accountBusy = false;
  final homeFeedback = ActionFeedback();
  final syncFeedback = ActionFeedback();
  Json? account, subject, playerSubject, subjectResume;
  Set<int>? cachedEpisodeIds;
  List<Json> resumable = [];
  int? mediaSubjectId;
  int _mediaRequest = 0, _trackingRefreshRequest = 0;
  List<Json> trending = [],
      today = [],
      calendar = [],
      collection = [],
      results = [],
      candidates = [],
      providers = [];
  Json downloads = {}, sync = {};
  int? resourceEpisode;
  int _navigation = 0;
  int? _subjectRequest;
  int _personalRequest = 0, _resourceRequest = 0, _playbackRequest = 0;
  Future<void> _playbackOperations = Future.value();
  Future<void> _fullScreenOperations = Future.value();
  Completer<void>? _fullScreenTransition;

  @override
  void initState() {
    super.initState();
    dark = widget.preferences.getBool('dark') ?? false;
    playback = Playback(widget.service, widget.preferences);
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
    unawaited(boot());
  }

  Future<void> boot() async {
    try {
      await widget.service.start();
      if (!mounted || closing) return;
      subscriptions.add(
        widget.service.downloads.changes.stream.listen((value) {
          if (!mounted) return;
          String availability(Json snapshot) => objects(snapshot['tasks'])
              .map(
                (task) =>
                    '${task['id']}:${task['status']}:${number(task['progress']) >= 1}',
              )
              .join('|');
          final changed = availability(downloads) != availability(value);
          setState(() => downloads = value);
          if (changed && ready && ['home', 'subject'].contains(route)) {
            unawaited(perform(refreshPlaybackAvailability));
          }
        }),
      );
      subscriptions.add(
        widget.service.library.changes.stream.listen(playback.accept),
      );
      subscriptions.add(
        widget.service.tracking.changes.stream.listen((_) {
          if (mounted) unawaited(perform(refreshPersonal));
        }),
      );
      downloads = widget.service.downloads.snapshot();
      setState(() => ready = true);
      if (widget.initialMedia != null) {
        await openVideo(widget.initialMedia);
      }
      if (!mounted || closing) return;
      await Future.wait([
        loadHome().then((issue) {
          if (issue != null) showError(issue);
        }),
        refreshPersonal(),
        refreshPlaybackAvailability(),
      ]);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (widget.initialMedia != null &&
        mounted &&
        !closing &&
        playback.uri == null) {
      await openVideo(widget.initialMedia);
    }
  }

  Future<String?> loadHome({bool refresh = false}) async {
    if (!mounted) return null;
    setState(() {
      trendingLoading = true;
      todayLoading = true;
      error = null;
      todayError = null;
      if (todayDate != null &&
          todayDate != widget.service.catalog.scheduleDate) {
        today = [];
      }
    });
    void showTrending(List<Json> value) {
      if (mounted && !_dataEqual(trending, value)) {
        setState(() => trending = value);
      }
    }

    void showToday(Json value) {
      if (mounted &&
          (todayDate != value['date'] || !_dataEqual(today, value['items']))) {
        setState(() {
          today = objects(value['items']);
          todayDate = value['date'] as String?;
        });
      }
    }

    var trendingFailed = false, todayFailed = false;
    await Future.wait([
      widget.service.catalog
          .trending(refresh: refresh, limit: 8, onCached: showTrending)
          .then(showTrending)
          .catchError((Object e) {
            trendingFailed = true;
            if (mounted) setState(() => error = e.toString());
          })
          .whenComplete(() {
            if (mounted) setState(() => trendingLoading = false);
          }),
      widget.service.catalog
          .today(refresh: refresh, onCached: showToday)
          .then(showToday)
          .catchError((Object e) {
            todayFailed = true;
            if (mounted) setState(() => todayError = e.toString());
          })
          .whenComplete(() {
            if (mounted) setState(() => todayLoading = false);
          }),
    ]);
    if (trendingFailed && todayFailed) return '刷新失败，仍显示上次内容。';
    if (trendingFailed) return '今日放送已更新，本季热度刷新失败。';
    if (todayFailed) return '本季热度已更新，今日放送刷新失败。';
    return null;
  }

  Future<void> refreshHome() => homeFeedback.run(() => loadHome(refresh: true));

  Future<void> syncCollection() => syncFeedback.run(() async {
    final user = widget.service.account.userId;
    if (widget.service.account.session == null) return '登录 Bangumi 后可同步收藏。';
    try {
      await widget.service.tracking.refresh();
      await refreshPersonal();
      if (user != widget.service.account.userId) return '账号已切换，请重新同步。';
      final status = await widget.service.tracking.syncState();
      final pending = number(status['pendingMutationCount']).toInt();
      if (pending > 0) return '已拉取收藏，仍有 $pending 项修改待上传。';
      if (status['lastSyncError'] != null) return '部分修改未能同步，请重试。';
      return null;
    } catch (_) {
      return '同步失败，本地收藏已保留。';
    }
  });

  _PageLocation get location => _PageLocation(
    route: route,
    accountId: widget.service.account.userId,
    section: selectedSection,
    subject: subject,
    resourceEpisode: resourceEpisode,
    resourceQuery: resourceSearch.text,
    query: search.text,
    results: results,
    candidates: candidates,
    providers: providers,
    searchError: searchError,
    resultQuery: resultQuery,
    pending: busy || (route == 'subject' && _subjectRequest == _navigation),
    resourceQueryNames: resourceQueryNames,
    resourceQueryEpisode: resourceQueryEpisode,
  );

  void rememberLocation() => history.add(location);

  void leavePlayer() {
    if (route != 'player') return;
    _playbackRequest++;
    if (fullScreen) unawaited(setFullScreen(false));
    windowFullScreen = false;
    _playbackOperations = _playbackOperations.then(
      (_) => perform(() async {
        await playback.player.pause();
        await playback.saveProgress();
        await refreshPlaybackAvailability();
      }),
    );
  }

  void goBack() {
    leavePlayer();
    if (history.isEmpty) {
      navigate('home');
      return;
    }
    final previous = history.removeLast();
    _navigation++;
    setState(() {
      route = previous.route;
      selectedSection = previous.section;
      subject = previous.subject;
      resourceEpisode = previous.resourceEpisode;
      resourceSearch.text = previous.resourceQuery;
      search.text = previous.query;
      results = previous.results;
      candidates = previous.candidates;
      providers = previous.providers;
      searchError = previous.searchError;
      resultQuery = previous.resultQuery;
      resourceQueryNames = previous.resourceQueryNames;
      resourceQueryEpisode = previous.resourceQueryEpisode;
      busy = false;
    });
    if (ready && ['home', 'subject'].contains(route)) {
      unawaited(perform(refreshPlaybackAvailability));
    }
    if (previous.pending ||
        (route == 'subject' &&
            previous.accountId != widget.service.account.userId)) {
      switch (route) {
        case 'subject':
          if (subject != null) unawaited(openSubject(subject!));
        case 'search':
          unawaited(searchSubjects(query: previous.resultQuery));
        case 'resources':
          unawaited(
            searchResources(
              names: resourceQueryNames,
              episodeKeyword: resourceQueryEpisode,
            ),
          );
      }
    }
  }

  String get pageIdentity => switch (route) {
    'subject' => 'subject:${subject?['subjectId']}',
    'resources' => 'resources:${subject?['subjectId']}:$resourceEpisode',
    'search' => 'search:$resultQuery',
    _ => route,
  };

  void focusSearch() {
    if (fullScreen) unawaited(setFullScreen(false));
    final needsNavigation = route == 'player' || route == 'settings';
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

  Future<void> refreshPersonal() async {
    final ticket = ++_personalRequest;
    final userId = widget.service.account.userId;
    final values = await Future.wait<dynamic>([
      Future.value(widget.service.account.session),
      widget.service.tracking.collection(),
      widget.service.tracking.syncState(),
    ]);
    if (mounted &&
        ticket == _personalRequest &&
        userId == widget.service.account.userId) {
      setState(() {
        account = values[0] == null ? null : object(values[0]);
        collection = objects(values[1]);
        sync = object(values[2]);
      });
    }
  }

  void showError(Object e) => messages.currentState?.showSnackBar(
    SnackBar(
      content: Text(e.toString().replaceFirst('Bad state: ', '')),
      behavior: SnackBarBehavior.floating,
    ),
  );
  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      showError(e);
    }
  }

  Future<void> openSubject(Json item) async {
    final id = item['subjectId'];
    if (id == null) {
      showError('该日程尚未关联番剧条目。');
      return;
    }
    leavePlayer();
    if (route != 'subject' || subject?['subjectId'] != id) rememberLocation();
    final ticket = ++_navigation;
    _subjectRequest = ticket;
    setState(() {
      route = 'subject';
      subject = item;
      subjectResume = null;
      cachedEpisodeIds = null;
      mediaSubjectId = null;
      busy = true;
    });
    try {
      unawaited(perform(refreshPlaybackAvailability));
      final detail = await widget.service.tracking.subject(
        id as int,
        onAvailable: (value) {
          if (mounted && ticket == _navigation) {
            setState(() {
              subject = value;
              busy = false;
            });
          }
        },
      );
      if (mounted && ticket == _navigation) setState(() => subject = detail);
    } catch (e) {
      if (mounted && ticket == _navigation) showError(e);
    } finally {
      if (_subjectRequest == ticket) _subjectRequest = null;
      if (mounted && ticket == _navigation) setState(() => busy = false);
    }
  }

  Future<void> openVideo([String? path, Json? episode]) async {
    final subjectId = episode == null ? null : subject?['subjectId'] as int?;
    final selected = path ?? (await selectVideo())?.path;
    if (selected == null || !mounted) return;
    await queuePlayback(() async {
      await playback.openLocal(
        selected,
        subjectId: subjectId,
        episodeId: episode?['episodeId'] as int?,
      );
    });
  }

  Future<void> startPlayback(Future<Json> Function() load) async {
    await queuePlayback(() async {
      await playback.saveProgress();
      await playback.open(await load());
    });
  }

  Future<void> queuePlayback(Future<void> Function() open) {
    final ticket = ++_playbackRequest;
    final operation = _playbackOperations.then((_) async {
      if (!mounted || closing || ticket != _playbackRequest) return;
      await perform(() async {
        await open();
        showPlayback(ticket);
      });
    });
    _playbackOperations = operation.catchError((Object _) {});
    return operation;
  }

  void playEpisode(Json episode) {
    final subjectId = playback.session?['subjectId'] as int?;
    if (subjectId == null) return;
    unawaited(
      startPlayback(
        () => widget.service.library.episode(
          subjectId,
          episode['episodeId'] as int,
        ),
      ),
    );
  }

  void showPlayback(int ticket) {
    if (!mounted || closing || ticket != _playbackRequest) return;
    final sessionId = playback.session?['id'];
    final subjectId = playback.session?['subjectId'] as int?;
    if (route != 'player') rememberLocation();
    _navigation++;
    setState(() {
      route = 'player';
      busy = false;
      playerSubject = null;
    });
    if (subjectId == null || !ready) return;
    unawaited(
      perform(() async {
        final detail = await widget.service.tracking.subject(subjectId);
        if (mounted && sessionId == playback.session?['id']) {
          setState(() => playerSubject = detail);
        }
      }),
    );
  }

  Future<void> updateTracking(Json mutation) =>
      perform(() => saveTracking(mutation));

  Future<void> saveTracking(Json mutation) async {
    final subjectId = mutation['subjectId'] as int;
    final ticket = _navigation;
    final accountId = widget.service.account.userId;
    if (mutation['kind'] == 'subjectCollection') {
      await widget.service.tracking.setCollection(
        subjectId,
        status: mutation['status'] == null
            ? null
            : CollectionStatus.parse('${mutation['status']}'),
        score: mutation['score'] as int?,
      );
    } else {
      await widget.service.tracking.setEpisode(
        subjectId,
        mutation['episodeId'] as int,
        EpisodeStatus.parse('${mutation['status']}'),
      );
    }
    final refreshTicket = ++_trackingRefreshRequest;
    bool isCurrent() =>
        mounted &&
        ticket == _navigation &&
        route == 'subject' &&
        subject?['subjectId'] == subjectId &&
        accountId == widget.service.account.userId &&
        refreshTicket == _trackingRefreshRequest;
    if (isCurrent()) {
      setState(() {
        subject = {
          ...subject!,
          if (mutation['kind'] == 'subjectCollection')
            'collection': {
              ...object(subject!['collection']),
              if (mutation['status'] != null) 'status': mutation['status'],
              if (mutation['score'] != null) 'score': mutation['score'],
            }
          else
            'episodes': [
              for (final episode in objects(subject!['episodes']))
                if (episode['episodeId'] == mutation['episodeId'])
                  {...episode, 'status': mutation['status']}
                else
                  episode,
            ],
        };
      });
    }
    // Reflect committed local changes immediately; refresh has its own failure path.
    unawaited(
      perform(() async {
        await refreshPersonal();
        final detail = await widget.service.tracking.subject(subjectId);
        if (isCurrent()) setState(() => subject = detail);
      }),
    );
  }

  Future<void> refreshPlaybackAvailability() async {
    final ticket = ++_mediaRequest;
    final id = subject?['subjectId'] as int?;
    final recent = await widget.service.library.recent();
    final resume =
        recent.where((item) => item['subjectId'] == id).firstOrNull ??
        (id == null
            ? null
            : (await widget.service.library.recent(
                limit: 1,
                forSubject: id,
              )).firstOrNull);
    final playable = id == null
        ? null
        : await widget.service.library.playableEpisodes(id);
    if (!mounted || ticket != _mediaRequest) return;
    setState(() {
      resumable = recent;
      mediaSubjectId = id;
      cachedEpisodeIds = playable;
      subjectResume = resume;
    });
  }

  Future<void> findResources({Json? episode}) async {
    if (route != 'resources') rememberLocation();
    resourceEpisode = episode?['episodeId'] as int?;
    final episodeKeyword = resourceEpisodeKeyword(episode);
    final formId = ResourcesPage.formStorageId(
      subject?['subjectId'] as int?,
      resourceEpisode,
    );
    final savedForm = pageStorage.readState(context, identifier: formId);
    pageStorage.writeState(context, {
      ...?savedForm as Map?,
      'episode': episodeKeyword,
    }, identifier: formId);
    resourceSearch.text = titleOf(subject ?? {});
    _navigation++;
    setState(() {
      route = 'resources';
      candidates = [];
      providers = [];
    });
    await searchResources(episodeKeyword: episodeKeyword);
  }

  Future<void> searchResources({
    List<String>? names,
    String episodeKeyword = '',
  }) async {
    if (subject == null) return;
    final searchNames = names ?? resourceNames(subject!);
    if (resourceSearch.text.trim().isEmpty && searchNames.isEmpty) return;
    final ticket = ++_resourceRequest;
    final navigation = _navigation;
    final subjectId = subject!['subjectId'] as int;
    final episodeId = resourceEpisode;
    final keyword = resourceSearch.text.trim();
    setState(() {
      busy = true;
      resourceQueryNames = searchNames;
      resourceQueryEpisode = episodeKeyword;
      candidates = [];
      providers = [];
    });
    await perform(() async {
      final data = object(
        await widget.service.sources.search(
          subjectId,
          keyword,
          episodeId: episodeId,
          alternativeNames: searchNames,
          episodeKeyword: episodeKeyword,
          coverUrl: subject!['coverUrl'] as String?,
          isCurrent: () =>
              mounted &&
              ticket == _resourceRequest &&
              navigation == _navigation,
          onUpdate: (data) {
            if (mounted &&
                ticket == _resourceRequest &&
                navigation == _navigation) {
              setState(() {
                candidates = objects(data['candidates']);
                providers = objects(data['providers']);
              });
            }
          },
        ),
      );
      if (mounted && ticket == _resourceRequest && navigation == _navigation) {
        setState(() {
          candidates = objects(data['candidates']);
          providers = objects(data['providers']);
        });
      }
    });
    if (mounted && ticket == _resourceRequest && navigation == _navigation) {
      setState(() => busy = false);
    }
  }

  Future<void> searchSubjects({String? query}) async {
    final requestedQuery = query ?? search.text.trim();
    if (!ready || requestedQuery.isEmpty) return;
    if (route != 'search') rememberLocation();
    final ticket = ++_navigation;
    setState(() {
      route = 'search';
      busy = true;
      results = [];
      searchError = null;
      resultQuery = requestedQuery;
    });
    try {
      final value = await widget.service.catalog.search(
        resultQuery,
        onCached: (value) {
          if (mounted && ticket == _navigation && !_dataEqual(results, value)) {
            setState(() => results = value);
          }
        },
      );
      if (mounted && ticket == _navigation && !_dataEqual(results, value)) {
        setState(() => results = value);
      }
    } catch (_) {
      if (mounted && ticket == _navigation) {
        setState(() => searchError = '搜索暂时失败，请重试。');
      }
    }
    if (mounted && ticket == _navigation) setState(() => busy = false);
  }

  void navigate(String target) {
    if (target == route) return;
    leavePlayer();
    rememberLocation();
    _navigation++;
    setState(() {
      route = target;
      if (['home', 'tracking', 'downloads'].contains(target)) {
        selectedSection = target;
      } else if (target == 'calendar') {
        selectedSection = 'home';
      }
      busy = false;
    });
    if (ready && target == 'home') {
      unawaited(loadHome());
      unawaited(perform(refreshPlaybackAvailability));
    }
    if (ready &&
        target == 'tracking' &&
        widget.service.account.session != null &&
        !widget.service.account.needsAuthorization) {
      unawaited(perform(widget.service.tracking.refresh));
    }
    if (ready && target == 'calendar') {
      unawaited(loadCalendar());
    }
  }

  Future<void> loadCalendar() => perform(() async {
    final value = await widget.service.catalog.calendar(
      onCached: (value) {
        if (mounted && !_dataEqual(calendar, value)) {
          setState(() => calendar = value);
        }
      },
    );
    if (mounted && !_dataEqual(calendar, value)) {
      setState(() => calendar = value);
    }
  });

  @override
  void onWindowClose() async {
    if (closing) return;
    setState(() => closing = true);
    // Detach the video texture before disposing its native rendering context.
    await WidgetsBinding.instance.endOfFrame;
    try {
      await _playbackOperations;
      await playback.close();
    } finally {
      try {
        await widget.service.close();
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
    unawaited(
      _playbackOperations
          .then((_) => playback.close())
          .whenComplete(widget.service.close),
    );
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    homeFeedback.dispose();
    syncFeedback.dispose();
    search.dispose();
    searchFocus.dispose();
    resourceSearch.dispose();
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
          ? SubjectCoverScope(catalog: widget.service.catalog, child: child!)
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
        child: Scaffold(
          body: Column(
            children: [
              if (!fullScreen)
                AppTitleBar(
                  route: route,
                  immersive: route == 'player' && windowFullScreen,
                  dark: dark,
                  sidebarVisible: sidebarVisible,
                  onBack: history.isEmpty ? null : goBack,
                  backLabel: '返回',
                  onToggleSidebar: () =>
                      setState(() => sidebarVisible = !sidebarVisible),
                  onToggleTheme: () => setDark(!dark),
                ),
              Expanded(
                child: Row(
                  children: [
                    if (!fullScreen &&
                        !(route == 'player' && windowFullScreen) &&
                        route != 'settings')
                      MotionReveal(
                        visible: sidebarVisible,
                        axis: Axis.horizontal,
                        child: SizedBox(
                          width: 236,
                          child: AppSidebar(
                            dark: dark,
                            route: route,
                            selectedRoute: selectedSection,
                            nickname: '${account?['nickname'] ?? '尚未登录'}',
                            username: account?['username'] as String?,
                            avatarUrl: account?['avatarUrl'] as String?,
                            watchingCount: collection
                                .where((item) => item['status'] == 'watching')
                                .length,
                            downloadCount: objects(downloads['tasks'])
                                .where(
                                  (task) =>
                                      [
                                        'metadata',
                                        'downloading',
                                        'ready',
                                        'queued',
                                        'checking',
                                      ].contains(task['status']) &&
                                      number(task['progress']) < 1,
                                )
                                .length,
                            onNavigate: navigate,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          if (!fullScreen &&
                              route != 'settings' &&
                              route != 'player')
                            AppHeader(
                              route: route,
                              search: search,
                              searchFocusNode: searchFocus,
                              onSearch: searchSubjects,
                              sync: sync,
                              collectionCount: collection.length,
                            ),
                          if (!ready && error != null && !fullScreen)
                            MaterialBanner(
                              content: Text(error!),
                              actions: [
                                TextButton(
                                  onPressed: () => openVideo(),
                                  child: const Text('打开本地视频'),
                                ),
                              ],
                            ),
                          if (busy && !fullScreen)
                            const LinearProgressIndicator(minHeight: 2),
                          Expanded(
                            child: route == 'player'
                                ? PlayerPage(
                                    key: playerPageKey,
                                    playback: playback,
                                    service: widget.service,
                                    onError: showError,
                                    onBack: goBack,
                                    fullScreen: fullScreen,
                                    windowFullScreen: windowFullScreen,
                                    onWindowFullScreenChanged:
                                        setWindowFullScreen,
                                    downloads: downloads,
                                    onPlayFile: (id, fileId) => startPlayback(
                                      () => widget.service.library.fromDownload(
                                        id,
                                        fileId: fileId,
                                      ),
                                    ),
                                    onFullScreenChanged: setFullScreen,
                                    subject: playerSubject,
                                    onEpisode: playEpisode,
                                  )
                                : PageStorage(
                                    bucket: pageStorage,
                                    child: PageEntrance(
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
    );
  }

  void setDark(bool value) {
    setState(() => dark = value);
    unawaited(widget.preferences.setBool('dark', value));
  }

  Widget page() {
    if (!ready) {
      return error == null
          ? Center(
              child: ValueListenableBuilder<String>(
                valueListenable: widget.service.startupStatus,
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
              detail: error,
              action: () => openVideo(),
              actionLabel: '打开本地视频',
            );
    }
    switch (route) {
      case 'home':
        return HomePage(
          dark: dark,
          today: today,
          trending: trending,
          resumable: resumable,
          onResume: (item) => startPlayback(
            () => widget.service.library.episode(
              item['subjectId'] as int,
              item['episodeId'] as int,
            ),
          ),
          watching: collection
              .where((item) => item['status'] == 'watching')
              .toList(),
          trendingLoading: trendingLoading,
          todayLoading: todayLoading,
          todayError: todayError,
          error: error,
          onExplore: focusSearch,
          feedback: homeFeedback,
          onCalendar: () => navigate('calendar'),
          onRefresh: refreshHome,
          onOpenSubject: openSubject,
        );
      case 'search':
        return SearchPage(
          results: results,
          busy: busy,
          error: searchError,
          onRetry: searchSubjects,
          onOpenSubject: openSubject,
        );
      case 'calendar':
        return CalendarPage(
          calendar: calendar,
          onOpenSubject: openSubject,
          onRetry: loadCalendar,
        );
      case 'tracking':
        return TrackingPage(
          collection: collection,
          collectionFilter: collectionFilter,
          sync: sync,
          onFilterChanged: (value) => setState(() => collectionFilter = value),
          onOpenSubject: openSubject,
          feedback: syncFeedback,
          signedIn: account != null,
          onSignIn: () => navigate('settings'),
          onSync: syncCollection,
          onExplore: focusSearch,
        );
      case 'subject':
        final item = subject;
        return SubjectPage(
          subject: item,
          loading: busy,
          onUpdateTracking: updateTracking,
          onSaveTracking: saveTracking,
          resume: mediaSubjectId == item?['subjectId'] ? subjectResume : null,
          cachedEpisodeIds: mediaSubjectId == item?['subjectId']
              ? cachedEpisodeIds
              : null,
          onFindResources: (episode) => findResources(episode: episode),
          onOpenEpisode: (episode) => openVideo(null, episode),
          onPlayEpisode: (episode) => startPlayback(
            () => widget.service.library.episode(
              item!['subjectId'] as int,
              episode['episodeId'] as int,
            ),
          ),
          onOpenSubject: openSubject,
        );
      case 'resources':
        return ResourcesPage(
          subject: subject,
          resourceSearch: resourceSearch,
          resourceEpisode: resourceEpisode,
          providers: providers,
          candidates: candidates,
          busy: busy,
          key: ValueKey('resources:${subject?["subjectId"]}:$resourceEpisode'),
          onSearch: (names, episode) =>
              searchResources(names: names, episodeKeyword: episode),
          onDownload: (candidate) async {
            await widget.service.sources.enqueue('${candidate['candidateId']}');
          },
        );
      case 'downloads':
        return DownloadsPage(
          downloads: downloads,
          onAddMagnet: addMagnet,
          onAddTorrent: addTorrent,
          onOpenVideo: () => openVideo(),
          onExplore: () => navigate('home'),
          onRemove: confirmRemoval,
          onStopSeeding: (task) => perform(
            () => widget.service.downloads.stopSeeding('${task['id']}'),
          ),
          onTogglePause: (task) => perform(() async {
            if (['paused', 'failed', 'completed'].contains(task['status'])) {
              await widget.service.downloads.resume('${task['id']}');
            } else {
              await widget.service.downloads.pause('${task['id']}');
            }
          }),
          onPlay: (id, fileId) => startPlayback(
            () => widget.service.library.fromDownload(id, fileId: fileId),
          ),
        );
      case 'settings':
        return SettingsPage(
          onBack: goBack,
          account: account,
          sync: sync,
          needsAuthorization: widget.service.account.needsAuthorization,
          accountBusy: accountBusy,
          dark: dark,
          dataDirectory: widget.service.dataDirectory,
          storageSettings: StorageSettings(
            onExit: () => windowManager.close(),
            storage: widget.service.storage,
            dataDirectory: widget.service.dataDirectory!,
            mediaDirectory: widget.service.downloads.directory,
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
          bitTorrentSettings: BitTorrentSettingsPanel(
            downloads: widget.service.downloads,
          ),
          onThemeChanged: setDark,
          onCancelSignIn: () => perform(() async {
            await widget.service.account.cancelSignIn();
          }),
          onAccountAction: () => perform(() async {
            if (accountBusy) return;
            setState(() => accountBusy = true);
            try {
              if (widget.service.account.session == null ||
                  widget.service.account.needsAuthorization) {
                await widget.service.account.signIn();
                await refreshPersonal();
                await widget.service.tracking.refresh();
              } else {
                await widget.service.account.signOut();
              }
            } finally {
              // A network failure must not hide a successfully restored login.
              if (mounted) setState(() => accountBusy = false);
              await refreshPersonal();
            }
          }),
        );
      default:
        return const EmptyState(text: '打开一部喜欢的作品');
    }
  }

  Future<void> addMagnet() async {
    final context = navigation.currentState?.overlay?.context;
    if (context == null) return;
    final uri = await showDialog<String>(
      context: context,
      builder: (_) => const AddMagnetDialog(),
    );
    if (uri != null && uri.trim().isNotEmpty) {
      await perform(() async {
        await widget.service.downloads.addMagnet(uri.trim());
      });
    }
  }

  Future<void> addTorrent() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Torrent', extensions: ['torrent']),
      ],
    );
    if (file != null) {
      await perform(() async {
        await widget.service.downloads.addTorrent(
          await file.readAsBytes(),
          file.name,
        );
      });
    }
  }

  Future<void> confirmRemoval(Json task) async {
    final context = navigation.currentState?.overlay?.context;
    if (context == null) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (_) => RemoveDownloadDialog(title: '${task['title']}'),
    );
    if (remove == true) {
      await perform(() async {
        await widget.service.downloads.remove('${task['id']}');
      });
    }
  }
}

class _PageLocation {
  const _PageLocation({
    required this.route,
    required this.accountId,
    required this.section,
    required this.subject,
    required this.resourceEpisode,
    required this.resourceQuery,
    required this.query,
    required this.results,
    required this.candidates,
    required this.providers,
    required this.searchError,
    required this.resultQuery,
    required this.pending,
    required this.resourceQueryNames,
    required this.resourceQueryEpisode,
  });
  final String route, accountId, section, resourceQuery, query, resultQuery;
  final bool pending;
  final List<String>? resourceQueryNames;
  final String resourceQueryEpisode;
  final Json? subject;
  final int? resourceEpisode;
  final List<Json> results, candidates, providers;
  final String? searchError;
}

Future<XFile?> selectVideo() => openFile(
  acceptedTypeGroups: [
    const XTypeGroup(
      label: 'Video',
      extensions: [
        'mkv',
        'mp4',
        'webm',
        'avi',
        'mov',
        'm4v',
        'ts',
        'm2ts',
        'flv',
        'wmv',
      ],
    ),
  ],
);

bool _dataEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_dataEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _dataEqual(a[key], b[key]));
  }
  return a == b;
}
