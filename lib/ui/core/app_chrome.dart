import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'motion.dart';
import 'account_avatar.dart';
import 'theme.dart';

class AppTitleBar extends StatelessWidget {
  const AppTitleBar({
    super.key,
    required this.dark,
    required this.sidebarVisible,
    required this.onToggleSidebar,
    required this.onToggleTheme,
    required this.search,
    required this.searchFocusNode,
    required this.onSearch,
    required this.recentSearches,
    required this.onClearRecentSearches,
    this.onBack,
    this.backLabel = '返回',
    this.immersive = false,
  });
  final String backLabel;
  final bool dark, sidebarVisible, immersive;
  final VoidCallback onToggleSidebar, onToggleTheme, onClearRecentSearches;
  final VoidCallback? onBack;
  final TextEditingController search;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearch;
  final List<String> recentSearches;

  @override
  Widget build(BuildContext context) {
    final macOS = Theme.of(context).platform == TargetPlatform.macOS;
    return Container(
      height: titleBarHeight,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            const Positioned.fill(child: DragToMoveArea(child: SizedBox())),
            Row(
              children: [
                SizedBox(width: macOS ? 78 : 8),
                if (!immersive) ...[
                  IconButton(
                    tooltip: sidebarVisible ? '收起侧栏' : '展开侧栏',
                    onPressed: onToggleSidebar,
                    icon: const Icon(Icons.view_sidebar_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: backLabel,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, size: 18),
                  ),
                ],
                const Spacer(),
                if (!immersive)
                  IconButton(
                    tooltip: '切换主题',
                    onPressed: onToggleTheme,
                    icon: Icon(
                      dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      size: 18,
                    ),
                  ),
                if (!macOS) ...[
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
            if (!immersive)
              Center(
                child: SizedBox(
                  // Both sides reserve room for the toolbar buttons.
                  width: math.min(420, constraints.maxWidth - 2 * 190),
                  height: 32,
                  child: _CatalogueSearch(
                    controller: search,
                    focusNode: searchFocusNode,
                    onSearch: onSearch,
                    recent: recentSearches,
                    onClearRecent: onClearRecentSearches,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogueSearch extends StatefulWidget {
  const _CatalogueSearch({
    required this.controller,
    required this.focusNode,
    required this.onSearch,
    required this.recent,
    required this.onClearRecent,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSearch;
  final List<String> recent;
  final VoidCallback onClearRecent;

  @override
  State<_CatalogueSearch> createState() => _CatalogueSearchState();
}

class _CatalogueSearchState extends State<_CatalogueSearch> {
  final suggestions = OverlayPortalController();
  final anchor = LayerLink();

  List<String> get options {
    final text = widget.controller.text.trim().toLowerCase();
    return widget.recent
        .where((item) => text.isEmpty || item.toLowerCase().contains(text))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(sync);
    widget.controller.addListener(sync);
  }

  @override
  void didUpdateWidget(_CatalogueSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recent searches change during a build; the overlay updates afterwards.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sync();
    });
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(sync);
    widget.controller.removeListener(sync);
    super.dispose();
  }

  void sync() {
    final visible = widget.focusNode.hasFocus && options.isNotEmpty;
    if (visible) {
      suggestions.show();
    } else {
      suggestions.hide();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shortcut = Theme.of(context).platform == TargetPlatform.macOS
        ? '⌘ F'
        : 'Ctrl F';
    final focused = widget.focusNode.hasFocus;
    return LayoutBuilder(
      builder: (context, constraints) => CompositedTransformTarget(
        link: anchor,
        child: OverlayPortal(
          controller: suggestions,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: anchor,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: TextFieldTapRegion(
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Material(
                    color: scheme.surface,
                    elevation: 3,
                    shadowColor: Theme.of(context).popupMenuTheme.shadowColor,
                    shape: const RoundedRectangleBorder(
                      borderRadius: controlBorderRadius,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                        shrinkWrap: true,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                            child: Row(
                              children: [
                                Text(
                                  '最近搜索',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: widget.onClearRecent,
                                  child: const Text('清除'),
                                ),
                              ],
                            ),
                          ),
                          for (final option in options)
                            ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: const Icon(Icons.history, size: 18),
                              title: Text(option, maxLines: 1),
                              onTap: () => widget.onSearch(option),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: TextField(
            key: const PageStorageKey('catalogue-search-input'),
            controller: widget.controller,
            focusNode: widget.focusNode,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 13, height: 1.25),
            onSubmitted: (value) => widget.onSearch(value.trim()),
            decoration: InputDecoration(
              fillColor: scheme.surface,
              hintText: '搜索番剧',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: controlBorderRadius,
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 34,
                minHeight: 32,
              ),
              suffixIconConstraints: const BoxConstraints(minHeight: 32),
              prefixIcon: const Icon(Icons.search, size: 17),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: focused
                    ? IconButton(
                        tooltip: '搜索番剧',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            widget.onSearch(widget.controller.text.trim()),
                        icon: const Icon(Icons.arrow_forward, size: 16),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(5),
                              ),
                            ),
                            child: Text(
                              shortcut,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant,
                              ),
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
    padding: const EdgeInsets.fromLTRB(12, Gap.md, 12, Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.lg),
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
                    padding: const EdgeInsets.all(Gap.sm),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xff6fd9b1), mint],
                            ),
                            borderRadius: BorderRadius.all(Radius.circular(9)),
                          ),
                          child: const Icon(
                            Icons.spa_rounded,
                            color: Color(0xff08321f),
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'melonbang',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
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
        _nav(context, 'home', '探索', Icons.explore_outlined),
        _nav(
          context,
          'tracking',
          '追番',
          Icons.favorite_border,
          watchingCount > 0 ? '$watchingCount' : null,
        ),
        _nav(
          context,
          'downloads',
          '缓存',
          Icons.download_outlined,
          downloadCount > 0 ? '$downloadCount 下载中' : null,
        ),
        const Spacer(),
        _nav(context, 'settings', '设置', Icons.settings_outlined),
        const SizedBox(height: Gap.sm),
        Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: posterBorderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onNavigate('settings'),
            child: Padding(
              padding: const EdgeInsets.all(Gap.sm),
              child: Row(
                children: [
                  AccountAvatar(url: avatarUrl, name: nickname, size: 32),
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
    String? count,
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
      padding: const EdgeInsets.only(bottom: Gap.xs),
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
                    count,
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
