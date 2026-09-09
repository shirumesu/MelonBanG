import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app_services.dart';
import 'ui/acquisition/download_dialogs.dart';
import 'ui/acquisition/downloads_page.dart';
import 'ui/acquisition/resources_page.dart';
import 'ui/core/action_feedback.dart';
import 'ui/core/app_chrome.dart';
import 'ui/core/motion.dart';
import 'ui/core/page_widgets.dart';
import 'ui/core/theme.dart';
import 'ui/discovery/discovery_pages.dart';
import 'ui/player/playback.dart';
import 'ui/player/player_page.dart';
import 'ui/settings/connection_settings.dart';
import 'ui/settings/settings_page.dart';
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
  final search = TextEditingController();
  final resourceSearch = TextEditingController();
  late final Playback playback;
  final subscriptions = <StreamSubscription<dynamic>>[];
  String route = 'home', collectionFilter = 'watching';
  bool dark = false, ready = false, busy = false, fullScreen = false;
  String? error;
  bool trendingLoading = true;
  bool closing = false, sidebarVisible = true;
  final homeFeedback = ActionFeedback();
  final syncFeedback = ActionFeedback();
  Json? account, subject, playerSubject;
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
  int _personalRequest = 0, _resourceRequest = 0, _playbackRequest = 0;
  Future<void> _playbackOperations = Future.value();

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
          if (mounted) setState(() => downloads = value);
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
      error = null;
    });
    var trendingFailed = false, todayFailed = false;
    await Future.wait([
      widget.service.catalog
          .trending(refresh: refresh)
          .then((value) {
            if (mounted) setState(() => trending = objects(value));
          })
          .catchError((Object e) {
            trendingFailed = true;
            if (mounted) setState(() => error = e.toString());
          }),
      widget.service.catalog
          .today(refresh: refresh)
          .then((value) {
            if (mounted) {
              setState(() => today = objects(object(value)['items']));
            }
          })
          .catchError((Object _) {
            todayFailed = true;
          }),
    ]);
    if (mounted) setState(() => trendingLoading = false);
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

  void goBack() =>
      navigate(route == 'resources' && subject != null ? 'subject' : 'home');

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
    final ticket = ++_navigation;
    setState(() {
      route = 'subject';
      subject = item;
      busy = true;
    });
    try {
      final detail = object(await widget.service.tracking.subject(id as int));
      if (mounted && ticket == _navigation) setState(() => subject = detail);
    } catch (e) {
      showError(e);
    } finally {
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
    final subjectId = playerSubject?['subjectId'] as int?;
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
        if (mounted &&
            ticket == _playbackRequest &&
            sessionId == playback.session?['id']) {
          setState(() => playerSubject = detail);
        }
      }),
    );
  }

  Future<void> updateTracking(Json mutation) async {
    final subjectId = mutation['subjectId'] as int;
    final ticket = _navigation;
    await perform(() async {
      if (mutation['kind'] == 'subjectCollection') {
        await widget.service.tracking.setCollection(
          mutation['subjectId'] as int,
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
      await refreshPersonal();
      final detail = await widget.service.tracking.subject(subjectId);
      if (mounted &&
          ticket == _navigation &&
          route == 'subject' &&
          subject?['subjectId'] == subjectId) {
        setState(() => subject = detail);
      }
    });
  }

  Future<void> findResources({Json? episode}) async {
    resourceEpisode = episode?['episodeId'] as int?;
    resourceSearch.text = '${subject?['name'] ?? titleOf(subject ?? {})}';
    _navigation++;
    setState(() {
      route = 'resources';
      candidates = [];
      providers = [];
    });
    await searchResources();
  }

  Future<void> searchResources() async {
    if (resourceSearch.text.trim().isEmpty || subject == null) return;
    final ticket = ++_resourceRequest;
    final navigation = _navigation;
    final subjectId = subject!['subjectId'] as int;
    final episodeId = resourceEpisode;
    final keyword = resourceSearch.text.trim();
    setState(() => busy = true);
    await perform(() async {
      final data = object(
        await widget.service.sources.search(
          subjectId,
          keyword,
          episodeId: episodeId,
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

  Future<void> searchSubjects() async {
    if (!ready || search.text.trim().isEmpty) return;
    final ticket = ++_navigation;
    setState(() {
      route = 'search';
      busy = true;
      results = [];
    });
    await perform(() async {
      final value = await widget.service.catalog.search(search.text.trim());
      if (mounted && ticket == _navigation) {
        setState(() => results = objects(value));
      }
    });
    if (mounted && ticket == _navigation) setState(() => busy = false);
  }

  void navigate(String target) {
    _navigation++;
    setState(() {
      route = target;
      busy = false;
    });
    if (ready && target == 'calendar' && calendar.isEmpty) {
      unawaited(
        perform(() async {
          final value = await widget.service.catalog.calendar();
          if (mounted) setState(() => calendar = objects(value));
        }),
      );
    }
  }

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
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => fullScreen = false);
  }

  Future<void> setFullScreen(bool value) async {
    await perform(() async {
      await windowManager.setFullScreen(value);
      // Windows can resize to fullscreen without emitting enter/leave events.
      final actual = await windowManager.isFullScreen();
      if (mounted && !closing) setState(() => fullScreen = actual);
    });
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
      scaffoldMessengerKey: messages,
      navigatorKey: navigation,
      theme: appTheme(dark),
      home: Scaffold(
        body: Column(
          children: [
            if (!fullScreen)
              AppTitleBar(
                route: route,
                dark: dark,
                sidebarVisible: sidebarVisible,
                onBack: route == 'home' ? null : goBack,
                onToggleSidebar: () =>
                    setState(() => sidebarVisible = !sidebarVisible),
                onToggleTheme: () => setDark(!dark),
              ),
            Expanded(
              child: Row(
                children: [
                  if (!fullScreen && route != 'settings' && sidebarVisible)
                    SizedBox(
                      width: 236,
                      child: AppSidebar(
                        dark: dark,
                        route: route,
                        nickname: '${account?['nickname'] ?? '尚未登录'}',
                        username: account?['username'] as String?,
                        watchingCount: collection
                            .where((item) => item['status'] == 'watching')
                            .length,
                        downloadCount: objects(downloads['tasks'])
                            .where(
                              (task) => [
                                'metadata',
                                'downloading',
                                'ready',
                              ].contains(task['status']),
                            )
                            .length,
                        onNavigate: navigate,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        if (!fullScreen && route != 'settings')
                          AppHeader(
                            route: route,
                            search: search,
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
                                  playback: playback,
                                  service: widget.service,
                                  onOpen: () => openVideo(),
                                  onError: showError,
                                  onBack: goBack,
                                  fullScreen: fullScreen,
                                  onFullScreenChanged: setFullScreen,
                                  subject: playerSubject,
                                  onEpisode: playEpisode,
                                )
                              : PageEntrance(
                                  key: ValueKey(route),
                                  child: page(),
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
    );
  }

  void setDark(bool value) {
    setState(() => dark = value);
    unawaited(widget.preferences.setBool('dark', value));
  }

  Widget page() {
    if (!ready) {
      return error == null
          ? const Center(child: CircularProgressIndicator())
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
          watching: collection
              .where((item) => item['status'] == 'watching')
              .toList(),
          trendingLoading: trendingLoading,
          error: error,
          onExplore: () => navigate('tracking'),
          feedback: homeFeedback,
          onCalendar: () => navigate('calendar'),
          onRefresh: refreshHome,
          onOpenSubject: openSubject,
        );
      case 'search':
        return SearchPage(
          results: results,
          busy: busy,
          onOpenSubject: openSubject,
        );
      case 'calendar':
        return CalendarPage(
          calendar: calendar,
          onOpenSubject: openSubject,
          onRetry: () {
            navigate('home');
            navigate('calendar');
          },
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
        );
      case 'subject':
        final item = subject;
        return SubjectPage(
          subject: item,
          onUpdateTracking: updateTracking,
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
          onSearch: searchResources,
          onDownload: (candidate) => perform(() async {
            await widget.service.sources.enqueue('${candidate['candidateId']}');
            navigate('downloads');
          }),
        );
      case 'downloads':
        return DownloadsPage(
          downloads: downloads,
          onAddMagnet: addMagnet,
          onAddTorrent: addTorrent,
          onOpenVideo: () => openVideo(),
          onExplore: () => navigate('home'),
          onRemove: confirmRemoval,
          onTogglePause: (task) => perform(() async {
            if (['paused', 'failed'].contains(task['status'])) {
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
          showSidebar: sidebarVisible,
          onBack: () => navigate('home'),
          account: account,
          sync: sync,
          dark: dark,
          dataDirectory: widget.service.dataDirectory,
          connectionSettings: ConnectionSettings(services: widget.service),
          onThemeChanged: setDark,
          onOpenVideo: () => openVideo(),
          onCancelSignIn: () => perform(() async {
            await widget.service.account.cancelSignIn();
          }),
          onAccountAction: () => perform(() async {
            if (account == null) {
              await widget.service.account.signIn();
              await widget.service.tracking.refresh();
            } else {
              await widget.service.account.signOut();
            }
            await refreshPersonal();
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
