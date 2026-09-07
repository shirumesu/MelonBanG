import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/json.dart';
import 'page_widgets.dart';
import 'theme.dart';

const routeTitles = {
  'home': '探索',
  'tracking': '追番',
  'calendar': '新番时间表',
  'downloads': '缓存',
  'settings': '设置',
  'player': '正在播放',
  'subject': '番剧详情',
  'search': '搜索番剧',
  'resources': '查找资源',
};

class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key, required this.route});
  final String route;
  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    decoration: BoxDecoration(
      color: softSurface(context),
      border: Border(bottom: BorderSide(color: lineColor(context))),
    ),
    child: Row(
      children: [
        Expanded(
          child: DragToMoveArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                children: [
                  const Icon(Icons.spa_rounded, size: 18, color: mint),
                  const SizedBox(width: 9),
                  const Text(
                    'melonbang',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .4,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '— ${routeTitles[route] ?? ''}',
                    style: TextStyle(fontSize: 11, color: mutedColor(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '最小化',
          onPressed: windowManager.minimize,
          icon: const Icon(Icons.remove, size: 16),
        ),
        IconButton(
          tooltip: '最大化 / 还原',
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          icon: const Icon(Icons.crop_square, size: 15),
        ),
        IconButton(
          tooltip: '关闭窗口',
          onPressed: windowManager.close,
          icon: const Icon(Icons.close, size: 17),
        ),
        const SizedBox(width: 5),
      ],
    ),
  );
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.dark,
    required this.route,
    required this.nickname,
    required this.onNavigate,
    required this.onOpenVideo,
    this.watchingCount = 0,
    this.downloadCount = 0,
    this.username,
  });
  final bool dark;
  final String route, nickname;
  final String? username;
  final int watchingCount, downloadCount;
  final ValueChanged<String> onNavigate;
  final VoidCallback onOpenVideo;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: surfaceColor(context).withValues(alpha: dark ? .65 : .8),
      border: Border(right: BorderSide(color: lineColor(context))),
    ),
    padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 0, 24),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xff6fd9b1), mint],
                  ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: mint.withValues(alpha: .25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.spa_rounded,
                  color: Color(0xff08321f),
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'melonbang',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'ANIME TRACKER',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.6,
                        color: mutedColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 0, 8),
          child: Text(
            '浏览',
            style: TextStyle(
              fontSize: 10,
              color: mutedColor(context),
              letterSpacing: 1.4,
            ),
          ),
        ),
        _nav(context, 'home', '探索', Icons.explore_outlined),
        _nav(context, 'tracking', '追番', Icons.favorite_border, watchingCount),
        _nav(
          context,
          'downloads',
          '缓存',
          Icons.download_outlined,
          downloadCount,
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onOpenVideo,
          icon: const Icon(Icons.video_file_outlined, size: 17),
          label: const Text('打开视频'),
        ),
        if (route == 'player')
          _nav(context, 'player', '播放器', Icons.play_circle_outline),
        _nav(context, 'settings', '设置', Icons.settings_outlined),
        const SizedBox(height: 10),
        InkWell(
          onTap: () => onNavigate('settings'),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: surfaceColor(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: lineColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [grape, sky]),
                  ),
                  child: Text(
                    nickname.isEmpty ? 'M' : nickname.characters.first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        username == null ? '本地追番记录' : '@$username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: mutedColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget _nav(
    BuildContext context,
    String target,
    String label,
    IconData icon, [
    int? count,
  ]) {
    final selected =
        route == target ||
        (target == 'home' &&
            ['subject', 'calendar', 'search', 'resources'].contains(route));
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xff43c99f), Color(0xff6fd9b1)],
                )
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: mint.withValues(alpha: .2),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(
              icon,
              size: 20,
              color: selected ? const Color(0xff08321f) : mutedColor(context),
            ),
            title: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xff08321f) : null,
              ),
            ),
            trailing: count == null
                ? null
                : Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      color: selected ? const Color(0xff08321f) : mint,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
            onTap: () => onNavigate(target),
          ),
        ),
      ),
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.dark,
    required this.route,
    required this.search,
    required this.onBack,
    required this.onSearch,
    required this.onToggleTheme,
    this.sync = const {},
    this.collectionCount = 0,
  });
  final bool dark;
  final String route;
  final TextEditingController search;
  final VoidCallback onBack, onSearch, onToggleTheme;
  final Json sync;
  final int collectionCount;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(26, 16, 26, 12),
    child: LayoutBuilder(
      builder: (context, size) => Row(
        children: [
          if ([
            'subject',
            'resources',
            'search',
            'calendar',
          ].contains(route)) ...[
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 20),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  routeTitles[route] ?? '',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (['home', 'tracking', 'downloads'].contains(route))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      switch (route) {
                        'home' => 'Bangumi 收藏与放送动态',
                        'tracking' => '我的动画收藏 · 已缓存 $collectionCount 部',
                        _ => '下载与本地缓存',
                      },
                      style: TextStyle(
                        fontSize: 12,
                        color: mutedColor(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (route != 'player')
            SizedBox(
              width: size.maxWidth < 800 ? 205 : 280,
              height: 43,
              child: TextField(
                controller: search,
                onSubmitted: (_) => onSearch(),
                decoration: InputDecoration(
                  hintText: '搜索番剧名称…',
                  prefixIcon: const Icon(Icons.search, size: 19),
                  suffixIcon: IconButton(
                    tooltip: '搜索番剧',
                    onPressed: onSearch,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(99)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(99),
                    borderSide: BorderSide(color: lineColor(context)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(99)),
                    borderSide: BorderSide(color: mint),
                  ),
                ),
              ),
            ),
          if (size.maxWidth > 800 && ['home', 'tracking'].contains(route)) ...[
            const SizedBox(width: 14),
            MelonBadge(
              sync['lastSyncError'] != null
                  ? '同步待重试'
                  : number(sync['pendingMutationCount']) > 0
                  ? '${sync['pendingMutationCount']} 项待同步'
                  : sync['lastSyncedAt'] != null
                  ? '已同步'
                  : '本地记录',
              color: sync['lastSyncError'] == null ? mint : gold,
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            tooltip: '切换主题',
            onPressed: onToggleTheme,
            icon: Icon(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 20,
            ),
          ),
        ],
      ),
    ),
  );
}
