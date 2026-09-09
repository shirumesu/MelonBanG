import 'package:flutter/material.dart';

Duration motionDuration(BuildContext context, [int milliseconds = 180]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

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
