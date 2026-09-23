import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/json.dart';
import 'motion.dart';
import 'page_widgets.dart';
import 'account_avatar.dart';
import 'theme.dart';

const routeTitles = {
  'home': '探索',
  'tracking': '追番',
  'calendar': '新番时间表',
  'downloads': '缓存',
  'settings': '设置',
  'player': '播放器',
  'subject': '番剧详情',
  'search': '搜索番剧',
  'resources': '查找资源',
};

class AppTitleBar extends StatelessWidget {
  const AppTitleBar({
    super.key,
    required this.route,
    required this.dark,
    required this.sidebarVisible,
    required this.onToggleSidebar,
    required this.onToggleTheme,
    this.onBack,
    this.backLabel = '返回',
    this.immersive = false,
  });
  final String route, backLabel;
  final bool dark, sidebarVisible, immersive;
  final VoidCallback onToggleSidebar, onToggleTheme;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Row(
      children: [
        if (Theme.of(context).platform == TargetPlatform.macOS)
          const SizedBox(width: 78)
        else
          const SizedBox(width: 8),
        if (!immersive) ...[
          IconButton(
            tooltip: route == 'settings'
                ? '设置分类始终显示'
                : sidebarVisible
                ? '收起侧栏'
                : '展开侧栏',
            onPressed: route == 'settings' ? null : onToggleSidebar,
            icon: const Icon(Icons.view_sidebar_outlined, size: 18),
          ),
          IconButton(
            tooltip: backLabel,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
          ),
        ],
        Expanded(
          child: DragToMoveArea(
            child: Container(
              height: 40,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'melonbang',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: '  /  ${routeTitles[route] ?? ''}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
        if (!immersive)
          IconButton(
            tooltip: '切换主题',
            onPressed: onToggleTheme,
            icon: Icon(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 18,
            ),
          ),
        if (Theme.of(context).platform != TargetPlatform.macOS) ...[
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
    this.watchingCount = 0,
    this.downloadCount = 0,
    this.username,
    this.avatarUrl,
    this.selectedRoute,
  });
  final bool dark;
  final String route, nickname;
  final String? username, avatarUrl;
  final String? selectedRoute;
  final int watchingCount, downloadCount;
  final ValueChanged<String> onNavigate;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(gradient: sidebarSurface(context)),
    padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Tooltip(
            message: '返回探索首页',
            child: Material(
              color: Colors.transparent,
              borderRadius: controlBorderRadius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('brand-home'),
                onTap: () => onNavigate('home'),
                child: Semantics(
                  button: true,
                  label: 'melonbang，返回探索首页',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xff6fd9b1), mint],
                            ),
                            borderRadius: controlBorderRadius,
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 0, 8),
          child: Text(
            '浏览',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        if (route == 'player')
          _nav(context, 'player', '播放器', Icons.play_circle_outline),
        _nav(context, 'settings', '设置', Icons.settings_outlined),
        const SizedBox(height: 10),
        Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: posterBorderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onNavigate('settings'),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  AccountAvatar(url: avatarUrl, name: nickname, size: 36),
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
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
    final activeRoute = selectedRoute ?? route;
    final selected =
        activeRoute == target ||
        (target == 'home' &&
            [
              'subject',
              'calendar',
              'search',
              'resources',
            ].contains(activeRoute));
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: AnimatedContainer(
        duration: motionDuration(context, 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: controlBorderRadius,
          gradient: selected ? navigationGradient : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            dense: true,
            selected: selected,
            selectedColor: const Color(0xff08321f),
            iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
            titleTextStyle: Theme.of(context).textTheme.titleSmall,
            selectedTileColor: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: controlBorderRadius,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(icon, size: 20),
            title: Text(label),
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
    required this.route,
    required this.search,
    required this.onSearch,
    this.sync = const {},
    this.collectionCount = 0,
    this.searchFocusNode,
  });
  final String route;
  final TextEditingController search;
  final FocusNode? searchFocusNode;
  final VoidCallback onSearch;
  final Json sync;
  final int collectionCount;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(26, 16, 26, 12),
    child: LayoutBuilder(
      builder: (context, size) => Row(
        children: [
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
                    child: Text(switch (route) {
                      'home' => 'Bangumi 收藏与放送动态',
                      'tracking' => '我的动画收藏 · 共 $collectionCount 部',
                      _ => '下载与本地缓存',
                    }, style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          if (route != 'player')
            SizedBox(
              width: size.maxWidth < 800 ? 205 : 280,
              height: 40,
              child: TextField(
                key: const PageStorageKey('catalogue-search-input'),
                controller: search,
                focusNode: searchFocusNode,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 13, height: 1.25),
                onSubmitted: (_) => onSearch(),
                decoration: InputDecoration(
                  fillColor: Theme.of(context).colorScheme.surface,
                  hintText: '搜索番剧名称…',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 19),
                  suffixIcon: IconButton(
                    tooltip: '搜索番剧',
                    onPressed: onSearch,
                    icon: const Icon(Icons.arrow_forward, size: 16),
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
        ],
      ),
    ),
  );
}
