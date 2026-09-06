import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'playback.dart';
import 'player_page.dart';
import 'service.dart';

const mint = Color(0xff22b388);
const collectionLabels = {
  'watching': '在看',
  'wish': '想看',
  'completed': '看过',
  'on_hold': '搁置',
  'dropped': '抛弃',
};

class MelonApp extends StatefulWidget {
  const MelonApp({
    super.key,
    required this.service,
    required this.preferences,
    this.initialMedia,
  });
  final Service service;
  final SharedPreferences preferences;
  final String? initialMedia;
  @override
  State<MelonApp> createState() => _MelonAppState();
}

class _MelonAppState extends State<MelonApp> with WindowListener {
  final messages = GlobalKey<ScaffoldMessengerState>();
  final navigation = GlobalKey<NavigatorState>();
  final search = TextEditingController();
  late final Playback playback;
  StreamSubscription<Json>? subscription;
  String route = 'home', collectionFilter = 'watching';
  bool dark = false, ready = false, busy = false, fullScreen = false;
  String? error;
  bool trendingLoading = true;
  bool closing = false;
  Json? account, subject;
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

  @override
  void initState() {
    super.initState();
    dark = widget.preferences.getBool('dark') ?? false;
    playback = Playback(widget.service, widget.preferences);
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
    subscription = widget.service.events.stream.listen((event) {
      if (!mounted) return;
      switch (event['event']) {
        case 'openExternal':
          unawaited(
            launchUrl(
              Uri.parse('${event['data']}'),
              mode: LaunchMode.externalApplication,
            ),
          );
        case 'downloads':
          setState(() => downloads = object(event['data']));
        case 'playback':
          playback.accept(object(event['data']));
        case 'serviceError':
          setState(() {
            error = '${event['data']}';
            ready = false;
          });
      }
    });
    unawaited(boot());
  }

  Future<void> boot() async {
    try {
      await widget.service.start();
      if (!mounted) return;
      setState(() => ready = true);
      if (widget.initialMedia != null) {
        await openVideo(widget.initialMedia);
      }
      await Future.wait([
        loadHome(),
        refreshPersonal(),
        widget.service.call('download.list').then((value) {
          if (mounted) setState(() => downloads = object(value));
        }),
      ]);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (widget.initialMedia != null && mounted && playback.uri == null) {
      await openVideo(widget.initialMedia);
    }
  }

  Future<void> loadHome() async {
    if (mounted) {
      setState(() {
        trendingLoading = true;
        error = null;
      });
    }
    await Future.wait([
      widget.service
          .call('bangumi.getTrendingCurrent')
          .then((value) {
            if (mounted) {
              setState(() {
                trending = objects(value);
                trendingLoading = false;
              });
            }
          })
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                error = e.toString();
                trendingLoading = false;
              });
            }
          }),
      widget.service
          .call('bangumi.getTodaySchedule')
          .then((value) {
            if (mounted) {
              setState(() => today = objects(object(value)['items']));
            }
          })
          .catchError((Object e) {
            showError(e);
          }),
    ]);
  }

  Future<void> refreshPersonal() async {
    final values = await Future.wait([
      widget.service.call('bangumi.getSession'),
      widget.service.call('bangumi.listCollection'),
      widget.service.call('bangumi.getSyncState'),
    ]);
    if (mounted) {
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
      final detail = object(
        await widget.service.call('bangumi.getSubject', [id]),
      );
      if (mounted && ticket == _navigation) setState(() => subject = detail);
    } catch (e) {
      showError(e);
    } finally {
      if (mounted && ticket == _navigation) setState(() => busy = false);
    }
  }

  Future<void> openVideo([String? path, Json? episode]) async {
    final selected = path ?? (await selectVideo())?.path;
    if (selected == null) return;
    await perform(() async {
      await playback.openLocal(
        selected,
        subjectId: episode == null ? null : subject?['subjectId'] as int?,
        episodeId: episode?['episodeId'] as int?,
      );
      if (mounted) setState(() => route = 'player');
    });
  }

  Future<void> startPlayback(String method, Json input) async {
    await perform(() async {
      await playback.saveProgress();
      await playback.open(object(await widget.service.call(method, [input])));
      if (mounted) setState(() => route = 'player');
    });
  }

  Future<void> updateTracking(Json mutation) async {
    await perform(() async {
      await widget.service.call('bangumi.updateTracking', [mutation]);
      await refreshPersonal();
      if (subject != null) await openSubject(subject!);
    });
  }

  Future<void> findResources({Json? episode}) async {
    resourceEpisode = episode?['episodeId'] as int?;
    search.text = '${subject?['name'] ?? titleOf(subject ?? {})}';
    setState(() {
      route = 'resources';
      candidates = [];
      providers = [];
    });
    await searchResources();
  }

  Future<void> searchResources() async {
    if (search.text.trim().isEmpty || subject == null) return;
    setState(() => busy = true);
    await perform(() async {
      final data = object(
        await widget.service.call('source.search', [
          {
            'subjectId': subject!['subjectId'],
            'episodeId': ?resourceEpisode,
            'keyword': search.text.trim(),
          },
        ]),
      );
      if (mounted) {
        setState(() {
          candidates = objects(data['candidates']);
          providers = objects(data['providers']);
        });
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> searchSubjects() async {
    if (search.text.trim().isEmpty) return;
    final ticket = ++_navigation;
    setState(() {
      route = 'search';
      busy = true;
      results = [];
    });
    await perform(() async {
      final value = await widget.service.call('bangumi.searchSubjects', [
        search.text.trim(),
      ]);
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
    if (target == 'calendar' && calendar.isEmpty) {
      unawaited(
        perform(() async {
          final value = await widget.service.call('bangumi.getCalendar');
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
    await playback.close();
    await widget.service.close();
    // Use WM_CLOSE so the runner destroys its view before leaving the message
    // loop. windowManager.destroy posts WM_QUIT directly on Windows.
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => fullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => fullScreen = false);
  }

  @override
  void dispose() {
    unawaited(playback.close());
    unawaited(widget.service.close());
    subscription?.cancel();
    search.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (closing) {
      return const MaterialApp(home: Scaffold(body: SizedBox.shrink()));
    }
    final scheme = ColorScheme.fromSeed(
      seedColor: mint,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Melonbang',
      scaffoldMessengerKey: messages,
      navigatorKey: navigation,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme.copyWith(primary: mint),
        scaffoldBackgroundColor: dark
            ? const Color(0xff172322)
            : const Color(0xffeef3f1),
        fontFamily: 'Microsoft YaHei UI',
        cardTheme: CardThemeData(
          elevation: 0,
          color: dark ? const Color(0xff21312e) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: dark ? const Color(0xff21312e) : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: Scaffold(
        body: Row(
          children: [
            if (!fullScreen) SizedBox(width: 202, child: sidebar()),
            Expanded(
              child: Column(
                children: [
                  if (!fullScreen) header(),
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
                            onBack: () => navigate('home'),
                            fullScreen: fullScreen,
                            subject: subject,
                            onEpisode: (ep) =>
                                startPlayback('playback.startEpisode', {
                                  'subjectId': subject!['subjectId'],
                                  'episodeId': ep['episodeId'],
                                }),
                          )
                        : page(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget sidebar() => Container(
    decoration: BoxDecoration(
      color: dark ? const Color(0xff1b2926) : const Color(0xfff8fcfa),
      border: Border(right: BorderSide(color: mint.withValues(alpha: .12))),
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: mint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.spa_rounded, color: Colors.white),
            ),
            const SizedBox(width: 9),
            const Text(
              'melonbang',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24, horizontal: 8),
          child: Text(
            '你的追番时光',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        navItem('home', '探索', Icons.explore_outlined),
        navItem('tracking', '追番', Icons.favorite_border),
        navItem('calendar', '放送日历', Icons.calendar_month_outlined),
        navItem('downloads', '缓存', Icons.download_outlined),
        navItem('player', '播放器', Icons.play_circle_outline),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => openVideo(),
          icon: const Icon(Icons.video_file_outlined, size: 18),
          label: const Text('打开视频'),
        ),
        const SizedBox(height: 12),
        navItem('settings', '设置', Icons.settings_outlined),
        const Divider(height: 28),
        Row(
          children: [
            CircleAvatar(
              backgroundColor: mint.withValues(alpha: .15),
              child: const Icon(Icons.person_outline, color: mint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${account?['nickname'] ?? '尚未登录'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    ),
  );
  Widget navItem(String target, String label, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: route == target ? mint.withValues(alpha: .22) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: route == target ? mint : null),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: route == target ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        onTap: () => navigate(target),
      ),
    ),
  );
  Widget header() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 18, 24, 14),
    child: Row(
      children: [
        if (['subject', 'resources', 'search'].contains(route))
          IconButton(
            onPressed: () => navigate('home'),
            icon: const Icon(Icons.arrow_back),
          ),
        Text(
          {
                'home': '探索',
                'tracking': '我的追番',
                'calendar': '放送日历',
                'downloads': '缓存管理',
                'settings': '设置',
                'player': '正在播放',
                'subject': '番剧详情',
                'search': '搜索番剧',
                'resources': '查找资源',
              }[route] ??
              '',
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        SizedBox(
          width: 280,
          height: 42,
          child: TextField(
            controller: search,
            onSubmitted: (_) => searchSubjects(),
            decoration: InputDecoration(
              hintText: '寻找想看的故事…',
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              suffixIcon: IconButton(
                onPressed: searchSubjects,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '切换主题',
          onPressed: () {
            setState(() => dark = !dark);
            unawaited(widget.preferences.setBool('dark', dark));
          },
          icon: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
        ),
      ],
    ),
  );
  Widget page() {
    switch (route) {
      case 'home':
        return scroll([
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: dark
                    ? [const Color(0xff244c40), const Color(0xff263946)]
                    : [const Color(0xffc8f0df), const Color(0xffe3eefb)],
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '好故事，慢慢看。',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text('发现新番，记录每一话，也给喜欢的故事留个位置。'),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => openVideo(),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('打开视频'),
                ),
              ],
            ),
          ),
          sectionTitle(
            '今日放送',
            trailing: TextButton(
              onPressed: () => navigate('calendar'),
              child: const Text('查看日历 →'),
            ),
          ),
          posters(today, horizontal: true),
          sectionTitle(
            '当季热门',
            trailing: IconButton(
              tooltip: '刷新',
              onPressed: () => perform(loadHome),
              icon: const Icon(Icons.refresh),
            ),
          ),
          if (trendingLoading && trending.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null && trending.isEmpty)
            empty('暂时无法加载番剧', detail: error, action: () => perform(loadHome))
          else
            posters(trending),
        ]);
      case 'search':
        return scroll([
          sectionTitle('搜索结果 · ${results.length}'),
          if (results.isEmpty && !busy)
            empty('没有找到匹配的番剧')
          else
            posters(results),
        ]);
      case 'tracking':
        return scroll([
          Wrap(
            spacing: 8,
            children: collectionLabels.entries
                .map(
                  (entry) => ChoiceChip(
                    label: Text(
                      '${entry.value} ${collection.where((item) => object(item['collection'])['status'] == entry.key).length}',
                    ),
                    selected: collectionFilter == entry.key,
                    onSelected: (_) =>
                        setState(() => collectionFilter = entry.key),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          if (number(sync['pendingMutationCount']) > 0)
            Text('${sync['pendingMutationCount']} 项修改等待同步'),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => perform(() async {
                await widget.service.call('bangumi.refreshCollection');
                await refreshPersonal();
              }),
              icon: const Icon(Icons.sync),
              label: const Text('同步收藏'),
            ),
          ),
          if (account == null)
            empty(
              '登录 Bangumi，开始记录追番',
              action: () => navigate('settings'),
              actionLabel: '前往登录',
            )
          else
            posters(
              collection
                  .where(
                    (item) =>
                        object(item['collection'])['status'] ==
                        collectionFilter,
                  )
                  .toList(),
            ),
        ]);
      case 'calendar':
        return scroll([
          for (final day in calendar) ...[
            sectionTitle('${object(day['weekday'])['cn'] ?? ''}'),
            posters(objects(day['items']), horizontal: true),
          ],
          if (calendar.isEmpty)
            empty(
              '日历尚未加载',
              action: () {
                navigate('home');
                navigate('calendar');
              },
            ),
        ]);
      case 'subject':
        return subjectPage();
      case 'resources':
        return resourcesPage();
      case 'downloads':
        return downloadsPage();
      case 'settings':
        return settingsPage();
      default:
        return empty('打开一部喜欢的作品');
    }
  }

  Widget scroll(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 10, 28, 28),
    children: children,
  );
  Widget sectionTitle(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 16),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
  Widget empty(
    String text, {
    String? detail,
    VoidCallback? action,
    String actionLabel = '重试',
  }) => Padding(
    padding: const EdgeInsets.all(40),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.local_florist_outlined, size: 42, color: mint),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(fontSize: 17)),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(detail, textAlign: TextAlign.center),
            ),
          if (action != null)
            TextButton(onPressed: action, child: Text(actionLabel)),
        ],
      ),
    ),
  );
  Widget posters(List<Json> items, {bool horizontal = false}) {
    if (items.isEmpty) return empty(ready ? '这里还没有番剧' : '正在准备…');
    if (horizontal) {
      return SizedBox(
        height: 252,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (_, i) => SizedBox(width: 145, child: poster(items[i])),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (constraints.maxWidth / 170).floor().clamp(2, 8),
          crossAxisSpacing: 18,
          mainAxisSpacing: 18,
          childAspectRatio: .61,
        ),
        itemBuilder: (_, index) => poster(items[index]),
      ),
    );
  }

  Widget poster(Json item) => InkWell(
    onTap: () => openSubject(item),
    borderRadius: BorderRadius.circular(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: cover(item['coverUrl']),
                ),
              ),
              if (item['score'] != null)
                Positioned(
                  right: 7,
                  bottom: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .7),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '★ ${item['score']}',
                      style: const TextStyle(
                        color: Color(0xffffcf6b),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          titleOf(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          item['episodeTotal'] == null
              ? '${item['platform'] ?? '动画'}'
              : '全 ${item['episodeTotal']} 话',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    ),
  );
  Widget cover(dynamic url) => url is String && url.startsWith('http')
      ? Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => cover(null),
        )
      : Container(
          color: mint.withValues(alpha: .12),
          child: const Center(
            child: Icon(Icons.movie_outlined, color: mint, size: 36),
          ),
        );

  Widget subjectPage() {
    final item = subject ?? {};
    final episodes = objects(item['episodes']);
    return scroll([
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 175,
                height: 246,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: cover(item['coverUrl']),
                ),
              ),
              const SizedBox(width: 26),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleOf(item),
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${item['name'] ?? ''}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${item['airDate'] ?? ''}   ${item['platform'] ?? ''}   ${item['episodeTotal'] ?? '—'} 话   ★ ${item['score'] ?? '—'}',
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: collectionLabels.entries
                          .map(
                            (entry) => ChoiceChip(
                              label: Text(entry.value),
                              selected:
                                  object(item['collection'])['status'] ==
                                  entry.key,
                              onSelected: (_) => updateTracking({
                                'kind': 'subjectCollection',
                                'subjectId': item['subjectId'],
                                'status': entry.key,
                              }),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: () => findResources(),
                          icon: const Icon(Icons.search),
                          label: const Text('查找资源'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'https://bgm.tv/subject/${item['subjectId']}',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Bangumi'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      sectionTitle('故事简介'),
      SelectableText('${item['summary'] ?? '暂无简介'}'),
      if (objects(item['tags']).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: objects(item['tags'])
                .take(16)
                .map((tag) => Chip(label: Text('${tag['name']}')))
                .toList(),
          ),
        ),
      sectionTitle('章节 · ${episodes.length}'),
      for (final episode in episodes)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: episode['status'] == 'watched'
                  ? mint
                  : mint.withValues(alpha: .12),
              child: Text('${episode['sort']}'),
            ),
            title: Text(titleOf(episode)),
            subtitle: Text(episode['status'] == 'watched' ? '已看' : '未看'),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: '标记已看 / 未看',
                  icon: Icon(
                    episode['status'] == 'watched'
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                  ),
                  onPressed: () => updateTracking({
                    'kind': 'episodeCollection',
                    'episodeId': episode['episodeId'],
                    'status': episode['status'] == 'watched'
                        ? 'unwatched'
                        : 'watched',
                  }),
                ),
                IconButton(
                  tooltip: '打开本地文件并关联此话',
                  onPressed: () => openVideo(null, episode),
                  icon: const Icon(Icons.folder_open),
                ),
                IconButton(
                  tooltip: '搜索此话资源',
                  onPressed: () => findResources(episode: episode),
                  icon: const Icon(Icons.download_outlined),
                ),
                IconButton(
                  tooltip: '播放已缓存视频',
                  onPressed: () => startPlayback('playback.startEpisode', {
                    'subjectId': item['subjectId'],
                    'episodeId': episode['episodeId'],
                  }),
                  icon: const Icon(Icons.play_arrow),
                ),
              ],
            ),
          ),
        ),
      if (objects(item['infoBox']).isNotEmpty) ...[
        sectionTitle('作品信息'),
        for (final row in objects(item['infoBox']))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text('${row['key']}：${row['value']}'),
          ),
      ],
      if (objects(item['relatedSubjects']).isNotEmpty) ...[
        sectionTitle('关联作品'),
        posters(objects(item['relatedSubjects']), horizontal: true),
      ],
    ]);
  }

  Widget resourcesPage() => scroll([
    sectionTitle(titleOf(subject ?? {})),
    Row(
      children: [
        Expanded(
          child: TextField(
            controller: search,
            onSubmitted: (_) => searchResources(),
            decoration: const InputDecoration(labelText: '资源关键词'),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(onPressed: searchResources, child: const Text('搜索')),
      ],
    ),
    const SizedBox(height: 12),
    if (resourceEpisode != null) Text('下载将关联到所选章节 · $resourceEpisode'),
    for (final provider in providers)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '${provider['providerName']} · ${provider['message'] ?? '${provider['resultCount']} 条资源'}',
          style: TextStyle(
            color: provider['status'] == 'error' ? Colors.orange : Colors.grey,
          ),
        ),
      ),
    const SizedBox(height: 12),
    for (final candidate in candidates)
      Card(
        child: ListTile(
          title: Text('${candidate['title']}'),
          subtitle: Text(
            '${candidate['providerName']} · ${candidate['publishedAt'] ?? ''}',
          ),
          trailing: IconButton(
            tooltip: '下载',
            icon: const Icon(Icons.download),
            onPressed: () => perform(() async {
              await widget.service.call('source.enqueue', [
                {
                  'candidateId': candidate['candidateId'],
                  'episodeId': ?resourceEpisode,
                },
              ]);
              navigate('downloads');
            }),
          ),
        ),
      ),
    if (candidates.isEmpty && !busy) empty('没有找到资源，试试原名或其他关键词'),
  ]);
  Widget downloadsPage() => scroll([
    sectionTitle(
      '下载与本地缓存',
      trailing: Row(
        children: [
          TextButton.icon(
            onPressed: addMagnet,
            icon: const Icon(Icons.add_link),
            label: const Text('磁力链接'),
          ),
          TextButton.icon(
            onPressed: addTorrent,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('种子文件'),
          ),
        ],
      ),
    ),
    for (final task in objects(
      downloads['tasks'],
    ).where((task) => task['status'] != 'removed'))
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${task['title']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: number(task['progress']).clamp(0, 1),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${task['status']} · ${(number(task['progress']) * 100).toStringAsFixed(1)}% · ${(number(task['downloadSpeedBytesPerSecond']) / 1048576).toStringAsFixed(1)} MB/s · ${task['peerCount']} peers',
                    ),
                  ),
                  IconButton(
                    tooltip: '暂停 / 继续',
                    onPressed: () => perform(() async {
                      await widget.service.call(
                        ['paused', 'failed'].contains(task['status'])
                            ? 'download.resume'
                            : 'download.pause',
                        [task['id']],
                      );
                    }),
                    icon: Icon(
                      ['paused', 'failed'].contains(task['status'])
                          ? Icons.play_arrow
                          : Icons.pause,
                    ),
                  ),
                  IconButton(
                    tooltip: '播放',
                    onPressed: ['ready', 'completed'].contains(task['status'])
                        ? () => startPlayback('playback.startFromDownload', {
                            'downloadId': task['id'],
                          })
                        : null,
                    icon: const Icon(Icons.play_circle_outline),
                  ),
                  IconButton(
                    tooltip: '移除任务与缓存',
                    onPressed: () => confirmRemoval(task),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              if (task['errorMessage'] != null)
                Text(
                  '${task['errorMessage']}',
                  style: const TextStyle(color: Colors.orange),
                ),
              for (final file in objects(downloads['files']).where(
                (file) =>
                    file['downloadId'] == task['id'] &&
                    file['mediaKind'] == 'video',
              ))
                ListTile(
                  dense: true,
                  title: Text('${file['name']}'),
                  trailing: IconButton(
                    tooltip: '播放此文件',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: number(file['progress']) >= 1
                        ? () => startPlayback('playback.startFromDownload', {
                            'downloadId': task['id'],
                            'fileId': file['id'],
                          })
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    if (objects(downloads['tasks'])
        .where((task) => task['status'] != 'removed')
        .isEmpty)
      empty(
        '缓存好喜欢的故事，随时开始观看',
        action: () => navigate('home'),
        actionLabel: '去探索',
      ),
  ]);
  Future<void> addMagnet() async {
    final uri = await textDialog('添加磁力链接', 'magnet:?xt=urn:btih:…');
    if (uri != null && uri.trim().isNotEmpty) {
      await perform(() async {
        await widget.service.call('download.create', [
          {'kind': 'magnet', 'uri': uri.trim()},
        ]);
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
        await widget.service.call('download.create', [
          {
            'kind': 'torrentFile',
            'name': file.name,
            'bytes': await file.readAsBytes(),
          },
        ]);
      });
    }
  }

  Future<void> confirmRemoval(Json task) async {
    final context = navigation.currentState?.overlay?.context;
    if (context == null) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除缓存？'),
        content: Text('将移除下载任务及缓存文件：${task['title']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (remove == true) {
      await perform(() async {
        await widget.service.call('download.remove', [task['id']]);
      });
    }
  }

  Future<String?> textDialog(String title, String hint) async {
    var draft = '';
    final context = navigation.currentState?.overlay?.context;
    if (context == null) return null;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: TextField(
            onChanged: (value) => draft = value,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return value;
  }

  Widget settingsPage() => scroll([
    sectionTitle('账户'),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account == null
                  ? '连接 Bangumi，同步你的追番记录。'
                  : '已登录 · ${account!['nickname']}',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: ready
                      ? () => perform(() async {
                          await widget.service.call(
                            account == null
                                ? 'bangumi.signIn'
                                : 'bangumi.signOut',
                          );
                          await refreshPersonal();
                        })
                      : null,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: Text(account == null ? '登录 Bangumi' : '退出登录'),
                ),
                TextButton(
                  onPressed: () => perform(() async {
                    await widget.service.call('bangumi.cancelSignIn');
                  }),
                  child: const Text('取消登录'),
                ),
              ],
            ),
            if (sync['lastSyncError'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${sync['lastSyncError']}',
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
    ),
    sectionTitle('外观'),
    Card(
      child: SwitchListTile(
        title: const Text('深色主题'),
        value: dark,
        onChanged: (value) {
          setState(() => dark = value);
          unawaited(widget.preferences.setBool('dark', value));
        },
      ),
    ),
    sectionTitle('本地播放'),
    Card(
      child: ListTile(
        leading: const Icon(Icons.video_file_outlined, color: mint),
        title: const Text('从本地文件开始观看'),
        subtitle: const Text('选择视频，或将视频文件路径作为启动参数。'),
        trailing: FilledButton(
          onPressed: () => openVideo(),
          child: const Text('打开'),
        ),
      ),
    ),
    sectionTitle('应用数据'),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('追番数据和播放进度保存在应用数据目录，独立于安装目录。'),
            const SizedBox(height: 8),
            SelectableText(widget.service.dataDirectory ?? '正在准备…'),
          ],
        ),
      ),
    ),
  ]);
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
