import 'dart:math' as math;

import 'package:flutter/material.dart';

Duration motionDuration(BuildContext context, [int milliseconds = 180]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// Unfolds its child along [axis] while fading it in; folded away, the child
/// leaves the tree.
class MotionReveal extends StatelessWidget {
  const MotionReveal({
    super.key,
    required this.visible,
    required this.child,
    this.axis = Axis.vertical,
    this.alignment = Alignment.topLeft,
    this.milliseconds = 220,
  });

  final bool visible;
  final Widget child;
  final Axis axis;
  final AlignmentGeometry alignment;
  final int milliseconds;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: visible ? 1 : 0, end: visible ? 1 : 0),
    duration: motionDuration(context, milliseconds),
    curve: Curves.easeInOutCubic,
    child: IgnorePointer(
      ignoring: !visible,
      child: ExcludeFocus(
        excluding: !visible,
        child: ExcludeSemantics(excluding: !visible, child: child),
      ),
    ),
    builder: (context, value, child) => value == 0 && !visible
        ? const SizedBox.shrink()
        : ClipRect(
            child: Align(
              alignment: alignment,
              widthFactor: axis == Axis.horizontal ? value : null,
              heightFactor: axis == Axis.vertical ? value : null,
              child: Opacity(opacity: value, child: child),
            ),
          ),
  );
}

class PageEntrance extends StatelessWidget {
  const PageEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motionDuration(context),
      curve: Curves.easeOut,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: .4 + .6 * value,
        child: Transform.translate(
          offset: Offset(0, 4 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

/// Fades its child in once, rising [offset] pixels into place, when it is
/// first built. [delay] keeps brief states, such as a short buffering, from
/// flashing.
class MotionAppear extends StatelessWidget {
  const MotionAppear({
    super.key,
    required this.child,
    this.offset = 6,
    this.milliseconds = 220,
    this.delay = 0,
  });
  final Widget child;
  final double offset;
  final int milliseconds, delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final total = milliseconds + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, offset * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

/// Cross-fades to a new child whenever [value] changes, the incoming one
/// growing from [scale] like one symbol replacing another.
class MotionSwap extends StatelessWidget {
  const MotionSwap({
    super.key,
    required this.value,
    required this.child,
    this.scale = .8,
    this.milliseconds = 180,
    this.alignment = Alignment.center,
  });
  final Object? value;
  final Widget child;
  final double scale;
  final int milliseconds;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: motionDuration(context, milliseconds),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: scale == 1
          ? child
          : ScaleTransition(
              scale: animation.drive(Tween(begin: scale, end: 1)),
              child: child,
            ),
    ),
    layoutBuilder: (current, previous) =>
        Stack(alignment: alignment, children: [...previous, ?current]),
    child: KeyedSubtree(key: ValueKey(value), child: child),
  );
}

/// Glides to each new [value] instead of jumping, e.g. a progress bar.
/// [from] animates the first value in too, once per page: such a bar needs a
/// [PageStorageKey], so one scrolled out of view and back does not replay.
class MotionValue extends StatefulWidget {
  const MotionValue({
    super.key,
    required this.value,
    required this.builder,
    this.from,
    this.milliseconds = 320,
  }) : assert(from == null || key is PageStorageKey);
  final double value;
  final double? from;
  final int milliseconds;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<MotionValue> createState() => _MotionValueState();
}

class _MotionValueState extends State<MotionValue> {
  late final double? _from = _introduce();

  double? _introduce() {
    if (widget.from == null) return null;
    final storage = PageStorage.of(context);
    if (storage.readState(context) == true) return null;
    storage.writeState(context, true);
    return widget.from;
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: _from, end: widget.value),
    duration: motionDuration(context, widget.milliseconds),
    curve: Curves.easeOutCubic,
    builder: (context, value, _) => widget.builder(context, value),
  );
}

/// One [highlight] behind the selected child that slides from item to item.
/// [builder] marks each selectable child with `key: keyOf(value)`; the
/// highlight follows that child's bounds and fades out when nothing is
/// selected.
class MotionSelection<T> extends StatefulWidget {
  const MotionSelection({
    super.key,
    required this.selected,
    required this.highlight,
    required this.builder,
  });
  final T? selected;
  final Widget highlight;
  final Widget Function(BuildContext context, Key Function(T value) keyOf)
  builder;

  @override
  State<MotionSelection<T>> createState() => _MotionSelectionState<T>();
}

class _MotionSelectionState<T> extends State<MotionSelection<T>> {
  final _keys = <T, GlobalKey>{};
  Rect? _rect;
  T? _measured;
  bool _slide = false;

  Key _keyOf(T value) => _keys.putIfAbsent(value, GlobalKey.new);

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final target =
        _keys[widget.selected]?.currentContext?.findRenderObject()
            as RenderBox?;
    if (box == null || target == null || !target.attached) return;
    final rect = target.localToGlobal(Offset.zero, ancestor: box) & target.size;
    if (rect == _rect && widget.selected == _measured) return;
    setState(() {
      // Only a move to another child slides; a resize follows at once.
      _slide =
          _rect != null && _measured != null && _measured != widget.selected;
      _measured = widget.selected;
      _rect = rect;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      final rect = _rect;
      return Stack(
        fit: StackFit.passthrough,
        children: [
          if (rect != null)
            AnimatedPositioned.fromRect(
              rect: rect,
              duration: _slide ? motionDuration(context, 280) : Duration.zero,
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: widget.selected == null ? 0 : 1,
                  duration: motionDuration(context, 160),
                  child: widget.highlight,
                ),
              ),
            ),
          widget.builder(context, _keyOf),
        ],
      );
    },
  );
}

/// An expand arrow that turns over while [open].
class ExpandChevron extends StatelessWidget {
  const ExpandChevron({super.key, required this.open, this.size, this.color});
  final bool open;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: open ? .5 : 0,
    duration: motionDuration(context, 240),
    curve: Curves.easeOutCubic,
    child: Icon(Icons.expand_more_rounded, size: size, color: color),
  );
}

/// How an icon answers the pointer arriving: [turn] advances a six-tooth cog
/// by one tooth, [back] and [forward] nudge toward where the button leads,
/// [swell] grows briefly outward. Each ends where it began.
enum IconGesture { turn, back, forward, swell }

/// Plays the [GestureIcon] inside [child] each time the pointer enters it, so
/// the whole button, not just its glyph, starts the motion.
class IconHover extends StatefulWidget {
  const IconHover({super.key, required this.child});
  final Widget child;

  /// Runs from 0 to 1 once per entry.
  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_IconHoverScope>()!.animation;

  @override
  State<IconHover> createState() => _IconHoverState();
}

class _IconHoverState extends State<IconHover>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    opaque: false,
    onEnter: (_) {
      final duration = motionDuration(context, 420);
      // A pass over the button mid-motion lets the motion finish.
      if (duration == Duration.zero || _controller.isAnimating) return;
      _controller.duration = duration;
      _controller.forward(from: 0);
    },
    child: _IconHoverScope(animation: _controller, child: widget.child),
  );
}

class _IconHoverScope extends InheritedWidget {
  const _IconHoverScope({required this.animation, required super.child});
  final Animation<double> animation;

  @override
  bool updateShouldNotify(_IconHoverScope old) => false;
}

/// An icon that moves by [gesture] when its [IconHover] is entered.
class GestureIcon extends StatelessWidget {
  const GestureIcon(this.gesture, {super.key, required this.child});
  final IconGesture gesture;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: IconHover.of(context),
    child: child,
    builder: (context, child) {
      final t = IconHover.of(context).value;
      // Out and back for the nudges and the swell.
      final bump = math.sin(math.pi * Curves.easeOutCubic.transform(t));
      return switch (gesture) {
        IconGesture.turn => Transform.rotate(
          angle: Curves.easeInOutCubic.transform(t) * math.pi / 3,
          child: child,
        ),
        IconGesture.back => Transform.translate(
          offset: Offset(-2.5 * bump, 0),
          child: child,
        ),
        IconGesture.forward => Transform.translate(
          offset: Offset(2.5 * bump, 0),
          child: child,
        ),
        IconGesture.swell => Transform.scale(
          scale: 1 + .12 * bump,
          child: child,
        ),
      };
    },
  );
}

/// Breathes gently while content loads.
class MotionPulse extends StatefulWidget {
  const MotionPulse({super.key, required this.child});
  final Widget child;

  @override
  State<MotionPulse> createState() => _MotionPulseState();
}

class _MotionPulseState extends State<MotionPulse>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _controller
        .drive(CurveTween(curve: Curves.easeInOut))
        .drive(Tween(begin: .5, end: 1)),
    child: widget.child,
  );
}

/// An image's [frameBuilder] body: the picture fades in over [placeholder]
/// once decoded, and shows at once when it was already in memory. Until then
/// the placeholder keeps the pointer, so its tooltip and tap handling apply.
class ImageFadeIn extends StatelessWidget {
  const ImageFadeIn({
    super.key,
    required this.frame,
    required this.synchronous,
    required this.placeholder,
    required this.child,
  });
  final int? frame;
  final bool synchronous;
  final Widget placeholder, child;

  @override
  Widget build(BuildContext context) {
    if (synchronous) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeSemantics(excluding: frame != null, child: placeholder),
        IgnorePointer(
          ignoring: frame == null,
          child: AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: motionDuration(context, 240),
            curve: Curves.easeOut,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// [showDialog] whose dialog settles in from slightly smaller as it fades.
Future<T?> showMelonDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  animationStyle: AnimationStyle(
    duration: motionDuration(context, 220),
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  ),
  builder: (context) => _DialogMotion(child: builder(context)),
);

class _DialogMotion extends StatelessWidget {
  const _DialogMotion({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: ModalRoute.of(context)!.animation!
        .drive(CurveTween(curve: Curves.easeOutCubic))
        .drive(Tween(begin: .95, end: 1)),
    child: child,
  );
}
