import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../features/update/app_update.dart';
import '../ui/core/motion.dart';
import '../ui/core/theme.dart';

class AppTitleBar extends StatelessWidget {
  const AppTitleBar({
    super.key,
    required this.window,
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
  final Window window;

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
            Positioned.fill(
              child: DragToMoveArea(window: window, child: const SizedBox()),
            ),
            Row(
              children: [
                SizedBox(width: macOS ? 78 : Gap.sm),
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
                    onPressed: window.minimize,
                    icon: const Icon(Icons.remove, size: 16),
                  ),
                  _MaximizeButton(window: window),
                  IconButton(
                    tooltip: '关闭窗口',
                    onPressed: window.close,
                    icon: const Icon(Icons.close, size: 17),
                  ),
                  const SizedBox(width: Gap.xs),
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

/// Maximises or restores the window; its tooltip names what a click does.
class _MaximizeButton extends StatefulWidget {
  const _MaximizeButton({required this.window});
  final Window window;

  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton> {
  late bool maximized = widget.window.isMaximized;
  ListenerId? listener;

  @override
  void initState() {
    super.initState();
    listener = widget.window.addListener(windowEvent);
  }

  void windowEvent(WindowEvent event) {
    switch (event) {
      case WindowMaximizedEvent() ||
          WindowRestoredEvent() ||
          WindowResizedEvent():
        final now = widget.window.isMaximized;
        if (now != maximized && mounted) setState(() => maximized = now);
      default:
    }
  }

  @override
  void dispose() {
    if (listener case final id?) widget.window.removeListener(id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: maximized ? '还原' : '最大化',
    onPressed: () => widget.window.isMaximized
        ? widget.window.unmaximize()
        : widget.window.maximize(),
    icon: const Icon(Icons.crop_square, size: 15),
  );
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

  /// What each suggestion searches, in the order shown.
  List<String> get queries => [if (offersTag) '#$typed', ...options];

  /// The suggestion the arrow keys moved to; -1 leaves Enter to search the
  /// typed text.
  int highlight = -1;

  /// Closed with Esc; typing or ↓ opens the suggestions again.
  bool dismissed = false;
  late String _text = widget.controller.text;

  bool get open => suggestions.isShowing;

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
    final focused = widget.focusNode.hasFocus;
    if (widget.controller.text != _text || !focused) {
      _text = widget.controller.text;
      highlight = -1;
      dismissed = false;
    }
    final visible = focused && !dismissed && queries.isNotEmpty;
    if (!visible || highlight >= queries.length) highlight = -1;
    if (visible) {
      suggestions.show();
    } else {
      suggestions.hide();
    }
    setState(() {});
  }

  /// Moves the highlight by [step], through the typed text after the last
  /// suggestion; ↓ on closed suggestions opens them.
  void _move(int step) {
    if (!open) {
      dismissed = false;
      sync();
      return;
    }
    final slots = queries.length + 1;
    setState(() => highlight = (highlight + 1 + step + slots) % slots - 1);
  }

  void _dismiss() {
    dismissed = true;
    sync();
  }

  /// The arrow keys, Enter on a highlighted suggestion and Esc, only while
  /// they act on the suggestions; otherwise the field keeps its own keys,
  /// as it does for an input method choosing among its candidates.
  Map<ShortcutActivator, VoidCallback> get _keys {
    if (widget.controller.value.composing.isValid) return const {};
    return {
      if (open) ...{
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
      },
      if (open || (dismissed && queries.isNotEmpty))
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
      if (open && highlight >= 0) ...{
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            widget.onSearch(queries[highlight]),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            widget.onSearch(queries[highlight]),
      },
    };
  }

  Widget _suggestion({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final highlighted = index == highlight;
    return Builder(
      builder: (context) {
        // The highlighted row scrolls into view as the arrow keys reach it.
        if (highlighted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.findRenderObject()?.showOnScreen();
          });
        }
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          tileColor: highlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .08)
              : null,
          leading: Icon(icon, size: 18),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => widget.onSearch(queries[index]),
        );
      },
    );
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
                      // Drawn like the app's menus: a panel whose rows are
                      // inset by Gap.xs with controlBorderRadius corners.
                      shape: const RoundedRectangleBorder(
                        borderRadius: panelBorderRadius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 340),
                        child: ListView(
                          padding: const EdgeInsets.all(Gap.xs),
                          shrinkWrap: true,
                          children: [
                            if (offersTag)
                              _suggestion(
                                index: 0,
                                icon: Icons.sell_outlined,
                                label: '按标签搜索 #$typed',
                              ),
                            if (options.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  Gap.lg,
                                  0,
                                  Gap.xs,
                                  0,
                                ),
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
                            for (final (index, option) in options.indexed)
                              _suggestion(
                                index: index + (offersTag ? 1 : 0),
                                icon: option.startsWith('#')
                                    ? Icons.sell_outlined
                                    : Icons.history,
                                label: option,
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
          child: CallbackShortcuts(
            bindings: _keys,
            child: TextField(
              key: const PageStorageKey('catalogue-search-input'),
              controller: widget.controller,
              focusNode: widget.focusNode,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(fontSize: FontSize.body, height: 1.25),
              onSubmitted: (value) => widget.onSearch(value.trim()),
              decoration: InputDecoration(
                fillColor: scheme.surface,
                hintText: '搜索番剧或 #标签',
                contentPadding: const EdgeInsets.symmetric(horizontal: Gap.md),
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
                  padding: const EdgeInsets.only(right: Gap.sm),
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
                                  borderRadius: tightBorderRadius,
                                ),
                                child: Text(
                                  shortcut,
                                  style: TextStyle(
                                    fontSize: FontSize.caption,
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
      ),
    );
  }
}
