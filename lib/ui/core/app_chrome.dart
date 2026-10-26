import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/update/app_update.dart';
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
    this.update,
    this.onRestartToUpdate,
  });
  final String backLabel;

  final bool dark, sidebarVisible, immersive;
  final VoidCallback onToggleSidebar, onToggleTheme, onClearRecentSearches;
  final VoidCallback? onBack;
  final TextEditingController search;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearch;
  final List<String> recentSearches;

  /// Offers a restart while a downloaded update waits to be installed.
  final AppUpdate? update;
  final VoidCallback? onRestartToUpdate;

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
                    // Material's sidebar is on the right; mirror it for ours.
                    icon: Transform.flip(
                      flipX: true,
                      child: const Icon(Icons.view_sidebar_outlined, size: 18),
                    ),
                  ),
                  IconButton(
                    tooltip: backLabel,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, size: 18),
                  ),
                ],
                const Spacer(),
                if (!immersive && update != null)
                  ListenableBuilder(
                    listenable: update!,
                    builder: (context, _) => MotionReveal(
                      visible: update!.phase == UpdatePhase.ready,
                      axis: Axis.horizontal,
                      alignment: Alignment.centerRight,
                      milliseconds: 280,
                      child: Tooltip(
                        message: '新版本 ${update!.readyVersion} 已下载',
                        child: Padding(
                          padding: const EdgeInsets.only(right: Gap.xs),
                          child: FilledButton.tonalIcon(
                            onPressed: onRestartToUpdate,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.restart_alt, size: 16),
                            label: const Text('重启以更新'),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!immersive)
                  IconButton(
                    tooltip: '切换主题',
                    onPressed: onToggleTheme,
                    icon: _ThemeGlyph(dark: dark),
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

/// The theme switch's sun or moon, turning in as it replaces the other.
class _ThemeGlyph extends StatelessWidget {
  const _ThemeGlyph({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: motionDuration(context, 320),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: RotationTransition(
        turns: animation.drive(Tween(begin: -.25, end: 0)),
        child: ScaleTransition(
          scale: animation.drive(Tween(begin: .5, end: 1)),
          child: child,
        ),
      ),
    ),
    child: Icon(
      dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      key: ValueKey(dark),
      size: 18,
    ),
  );
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

  String get typed => widget.controller.text.trim();

  List<String> get options {
    final text = typed.toLowerCase();
    return widget.recent
        .where((item) => text.isEmpty || item.toLowerCase().contains(text))
        .toList();
  }

  /// Typed text can also be searched as a tag, written `#text`.
  bool get offersTag => typed.isNotEmpty && !typed.startsWith('#');

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
    if (identical(oldWidget.recent, widget.recent)) return;
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
    final visible =
        widget.focusNode.hasFocus && (offersTag || options.isNotEmpty);
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
                child: MotionAppear(
                  offset: -4,
                  milliseconds: 180,
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
                            if (offersTag)
                              ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: const Icon(
                                  Icons.sell_outlined,
                                  size: 18,
                                ),
                                title: Text('按标签搜索 #$typed', maxLines: 1),
                                onTap: () => widget.onSearch('#$typed'),
                              ),
                            if (options.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                                child: Row(
                                  children: [
                                    Text(
                                      '最近搜索',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
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
                                leading: Icon(
                                  option.startsWith('#')
                                      ? Icons.sell_outlined
                                      : Icons.history,
                                  size: 18,
                                ),
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
              hintText: '搜索番剧或 #标签',
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
                child: MotionSwap(
                  value: focused,
                  alignment: Alignment.centerRight,
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
      ),
    );
  }
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.route,
    required this.nickname,
    required this.onNavigate,
    this.watchingCount = 0,
    this.downloadCount = 0,
    this.username,
    this.avatarUrl,
    this.selectedRoute,
    this.sourcesWarning = false,
  });
  final String route, nickname;
  final String? username, avatarUrl;
  final String? selectedRoute;
  final int watchingCount, downloadCount;
  final bool sourcesWarning;
  final ValueChanged<String> onNavigate;

  /// The entry standing for the current page; detail pages reached from
  /// 探索 keep it selected.
  String? get _selected {
    final active = selectedRoute ?? route;
    if (const ['subject', 'calendar', 'search', 'resources'].contains(active)) {
      return 'home';
    }
    return const [
          'home',
          'tracking',
          'downloads',
          'sources',
          'settings',
        ].contains(active)
        ? active
        : null;
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(gradient: sidebarSurface(context)),
    padding: const EdgeInsets.fromLTRB(12, Gap.md, 12, Gap.md),
    // One highlight glides between entries instead of each lighting up.
    child: MotionSelection<String>(
      selected: _selected,
      highlight: sidebarHighlight(context),
      builder: (context, keyOf) => Column(
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
                    label: 'MelonBanG，返回探索首页',
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.sm),
                      child: Image.asset(
                        'assets/images/logotype.png',
                        width: 150,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _nav(context, keyOf, 'home', '探索', Icons.explore_outlined),
          _nav(
            context,
            keyOf,
            'tracking',
            '追番',
            Icons.favorite_border,
            watchingCount > 0 ? '$watchingCount' : null,
          ),
          _nav(
            context,
            keyOf,
            'downloads',
            '缓存',
            Icons.download_outlined,
            downloadCount > 0 ? '$downloadCount' : null,
          ),
          const Spacer(),
          _nav(
            context,
            keyOf,
            'sources',
            '数据源',
            Icons.hub_outlined,
            sourcesWarning ? '●' : null,
          ),
          _nav(context, keyOf, 'settings', '设置', Icons.settings_outlined),
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
                            username == null ? '点击登录' : '@$username',
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
    ),
  );
  Widget _nav(
    BuildContext context,
    Key Function(String) keyOf,
    String target,
    String label,
    IconData icon, [
    String? count,
  ]) {
    final selected = _selected == target;
    final accent = accentOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: SidebarTile(
        key: keyOf(target),
        label: label,
        icon: icon,
        selected: selected,
        onTap: () => onNavigate(target),
        trailing: count == null
            ? null
            : MotionSwap(
                value: count,
                scale: .6,
                child: AnimatedDefaultTextStyle(
                  duration: motionDuration(context, 200),
                  style: appFont.copyWith(
                    fontSize: 11,
                    color: selected
                        ? accent.onNavigation
                        : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                  child: Text(count),
                ),
              ),
      ),
    );
  }
}

/// The highlight a [MotionSelection] glides under the selected
/// [SidebarTile].
Widget sidebarHighlight(BuildContext context) => DecoratedBox(
  decoration: BoxDecoration(
    borderRadius: controlBorderRadius,
    gradient: accentOf(context).navigation,
  ),
);

/// An entry of the main sidebar or the settings contents column, drawn over
/// a [sidebarHighlight] when selected.
class SidebarTile extends StatelessWidget {
  const SidebarTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.trailing,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      dense: true,
      selected: selected,
      selectedColor: accentOf(context).onNavigation,
      iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      titleTextStyle: Theme.of(context).textTheme.titleSmall,
      selectedTileColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: controlBorderRadius),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(icon, size: 20),
      title: Text(label),
      trailing: trailing,
      onTap: onTap,
    ),
  );
}
