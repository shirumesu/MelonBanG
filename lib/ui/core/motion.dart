import 'package:flutter/material.dart';

Duration motionDuration(BuildContext context, [int milliseconds = 180]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

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
    builder: (context, value, child) => ClipRect(
      child: Align(
        alignment: alignment,
        widthFactor: axis == Axis.horizontal ? value : null,
        heightFactor: axis == Axis.vertical ? value : null,
        child: child,
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
