import 'package:flutter/material.dart';

import 'theme.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.dark,
    required this.route,
    required this.nickname,
    required this.onNavigate,
    required this.onOpenVideo,
  });
  final bool dark;
  final String route;
  final String nickname;
  final ValueChanged<String> onNavigate;
  final VoidCallback onOpenVideo;
  @override
  Widget build(BuildContext context) => Container(
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
        _navItem('home', '探索', Icons.explore_outlined),
        _navItem('tracking', '追番', Icons.favorite_border),
        _navItem('calendar', '放送日历', Icons.calendar_month_outlined),
        _navItem('downloads', '缓存', Icons.download_outlined),
        _navItem('player', '播放器', Icons.play_circle_outline),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: onOpenVideo,
          icon: const Icon(Icons.video_file_outlined, size: 18),
          label: const Text('打开视频'),
        ),
        const SizedBox(height: 12),
        _navItem('settings', '设置', Icons.settings_outlined),
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
                nickname,
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
  Widget _navItem(String target, String label, IconData icon) => Padding(
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
        onTap: () => onNavigate(target),
      ),
    ),
  );
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
  });
  final bool dark;
  final String route;
  final TextEditingController search;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onToggleTheme;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 18, 24, 14),
    child: Row(
      children: [
        if (['subject', 'resources', 'search'].contains(route))
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
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
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: '寻找想看的故事…',
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              suffixIcon: IconButton(
                onPressed: onSearch,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '切换主题',
          onPressed: onToggleTheme,
          icon: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
        ),
      ],
    ),
  );
}
