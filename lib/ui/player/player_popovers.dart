import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/theme.dart';
import 'player_theme.dart';

/// A control whose popover rises above it while the pointer rests on either,
/// and closes shortly after leaving both. Clicking the control toggles it as
/// well, for the keyboard; a click elsewhere closes it.
class HoverPopover extends StatefulWidget {
  const HoverPopover({
    super.key,
    required this.onPopupChanged,
    required this.anchor,
    required this.popover,
    this.onPointerSignal,
  });
  final ValueChanged<bool> onPopupChanged;
  final Widget Function(HoverPopoverState popover) anchor, popover;
  final void Function(PointerSignalEvent)? onPointerSignal;

  @override
  State<HoverPopover> createState() => HoverPopoverState();
}

class HoverPopoverState extends State<HoverPopover>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  late final _fade = AnimationController(vsync: this);
  Timer? _timer;
  bool open = false;
  bool _overAnchor = false, _overPopover = false, _held = false;

  @override
  void dispose() {
    _timer?.cancel();
    _fade.dispose();
    // A popover still open would keep the controls from ever hiding.
    if (open) {
      final changed = widget.onPopupChanged;
      scheduleMicrotask(() => changed(false));
    }
    super.dispose();
  }

  void _show() {
    _timer?.cancel();
    if (open) return;
    setState(() => open = true);
    _portal.show();
    _fade.duration = motionDuration(context, 140);
    _fade.forward();
    widget.onPopupChanged(true);
  }

  void close() {
    _timer?.cancel();
    // The popover's region disappears without an exit event.
    _overPopover = _held = false;
    if (!open) return;
    setState(() => open = false);
    widget.onPopupChanged(false);
    _fade.reverse().whenComplete(() {
      if (mounted && !open) _portal.hide();
    });
  }

  void toggle() => open ? close() : _show();

  /// Keeps the popover open while a slider in it is dragged past its edge.
  void hold(bool value) {
    _held = value;
    _update();
  }

  /// Opens after a short rest so sweeping across the bar does not flash
  /// every popover on the way.
  void _update() {
    _timer?.cancel();
    final wanted = _overAnchor || _overPopover || _held;
    if (wanted == open) return;
    _timer = Timer(
      Duration(milliseconds: wanted ? 90 : 180),
      () => wanted ? _show() : close(),
    );
  }

  @override
  Widget build(BuildContext context) => TapRegion(
    groupId: this,
    onTapOutside: (_) => close(),
    child: Listener(
      onPointerSignal: widget.onPointerSignal,
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder: (context, info) => CustomSingleChildLayout(
          delegate: _AboveAnchor(
            MatrixUtils.transformRect(
              info.childPaintTransform,
              Offset.zero & info.childSize,
            ),
          ),
          child: _popover(),
        ),
        child: MouseRegion(
          onEnter: (_) {
            _overAnchor = true;
            _update();
          },
          onExit: (_) {
            _overAnchor = false;
            _update();
          },
          child: widget.anchor(this),
        ),
      ),
    ),
  );

  // Fading out, it no longer catches the pointer, which would reopen it.
  Widget _popover() => TapRegion(
    groupId: this,
    child: IgnorePointer(
      ignoring: !open,
      child: Listener(
        onPointerSignal: widget.onPointerSignal,
        child: MouseRegion(
          hitTestBehavior: HitTestBehavior.opaque,
          onEnter: (_) {
            _overPopover = true;
            _update();
          },
          onExit: (_) {
            _overPopover = false;
            _update();
          },
          child: Padding(
            // Bridges the gap to the control so the pointer never falls between.
            padding: const EdgeInsets.only(bottom: 6),
            child: AnimatedBuilder(
              animation: _fade,
              builder: (context, child) {
                final value = Curves.easeOutCubic.transform(_fade.value);
                return Transform.translate(
                  offset: Offset(0, 4 * (1 - value)),
                  child: OverlayGlass(visibility: value, child: child!),
                );
              },
              child: Theme(data: overlayTheme, child: widget.popover(this)),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A panel held open above its control by the page, such as the danmaku
/// settings; unlike [HoverPopover] it stays until closed.
class AnchoredPanel extends StatefulWidget {
  const AnchoredPanel({
    super.key,
    required this.open,
    required this.panel,
    required this.child,
  });
  final bool open;
  final Widget Function(double visibility) panel;
  final Widget child;

  @override
  State<AnchoredPanel> createState() => _AnchoredPanelState();
}

class _AnchoredPanelState extends State<AnchoredPanel>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  late final _fade = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      _fade.value = 1;
      _portal.show();
    }
  }

  @override
  void didUpdateWidget(AnchoredPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    _fade.duration = motionDuration(context);
    if (widget.open) {
      // The transport builds this inside a LayoutBuilder, and the overlay
      // cannot change during layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.open) return;
        _portal.show();
        _fade.forward();
      });
    } else {
      _fade.reverse().whenComplete(() {
        if (mounted && !widget.open) _portal.hide();
      });
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
    controller: _portal,
    overlayChildBuilder: (context, info) => CustomSingleChildLayout(
      delegate: _AboveAnchor(
        MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: IgnorePointer(
          ignoring: !widget.open,
          child: AnimatedBuilder(
            animation: _fade,
            builder: (context, _) {
              final value = Curves.easeOutCubic.transform(_fade.value);
              // The glass fades itself: an Opacity around its backdrop blur
              // would blur nothing on some renderers.
              return Transform.translate(
                offset: Offset(0, 5 * (1 - value)),
                child: Transform.scale(
                  scale: .98 + .02 * value,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(width: 312, child: widget.panel(value)),
                ),
              );
            },
          ),
        ),
      ),
    ),
    child: widget.child,
  );
}

/// Centres the popover above its control, kept inside the window.
class _AboveAnchor extends SingleChildLayoutDelegate {
  _AboveAnchor(this.anchor);
  final Rect anchor;
  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.max(0, constraints.maxWidth - 2 * _margin),
          math.max(0, anchor.top - _margin),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (anchor.center.dx - childSize.width / 2).clamp(
      _margin,
      math.max(_margin, size.width - childSize.width - _margin),
    ),
    anchor.top - childSize.height,
  );

  @override
  bool shouldRelayout(_AboveAnchor old) => old.anchor != anchor;
}

typedef PopoverChoice = ({String label, bool selected, VoidCallback onPressed});

/// The choices in a popover; the current one is filled white like the
/// segmented choices in the danmaku settings. Choosing closes the popover.
class ChoiceList extends StatelessWidget {
  const ChoiceList({super.key, required this.items, required this.popover});
  final List<PopoverChoice> items;
  final HoverPopoverState popover;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 76, maxWidth: 220),
    child: IntrinsicWidth(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              Material(
                color: item.selected ? Colors.white : Colors.transparent,
                borderRadius: badgeBorderRadius,
                child: InkWell(
                  borderRadius: badgeBorderRadius,
                  overlayColor: WidgetStatePropertyAll(
                    (item.selected ? overlayInk : Colors.white).withValues(
                      alpha: .1,
                    ),
                  ),
                  onTap: () {
                    item.onPressed();
                    popover.close();
                  },
                  child: Container(
                    height: 30,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: item.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: item.selected ? overlayInk : Colors.white,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A compact segmented choice for the dark popover.
class OverlayChoice extends StatelessWidget {
  const OverlayChoice({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final int value;
  final List<String> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: badgeBorderRadius,
    ),
    child: Row(
      children: [
        for (final (index, option) in options.indexed)
          Expanded(
            child: Material(
              color: index == value ? Colors.white : Colors.transparent,
              borderRadius: badgeBorderRadius,
              child: InkWell(
                borderRadius: badgeBorderRadius,
                onTap: () => onChanged(index),
                child: Center(
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: 12,
                      color: index == value ? overlayInk : Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
