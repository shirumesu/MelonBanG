import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/overlay_glass.dart';
import '../core/theme.dart';

/// Jumps past the OP or ED the file's chapters mark.
class SkipButton extends StatelessWidget {
  const SkipButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _GlassCard(
    onTap: onPressed,
    children: [
      // As tall as the countdown's buttons.
      const SizedBox(height: 30),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: FontSize.body,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(width: Gap.xs),
      const Icon(
        Icons.keyboard_double_arrow_right_rounded,
        size: 18,
        color: Colors.white,
      ),
    ],
  );
}

/// Something about to happen on its own, such as skipping the OP: a ring
/// running down its seconds, what it is with a detail under it, and buttons
/// to call it off or do it at once.
class CountdownCard extends StatelessWidget {
  const CountdownCard({
    super.key,
    required this.title,
    required this.detail,
    required this.seconds,
    required this.remaining,
    required this.confirm,
    required this.onConfirm,
    required this.onCancel,
    this.ease = 300,
  });

  final String title, detail, confirm;
  final int seconds;

  /// The part of the countdown left, from 1 to 0.
  final double remaining;

  /// Milliseconds the ring takes to reach a new [remaining].
  final int ease;
  final VoidCallback onConfirm, onCancel;

  @override
  Widget build(BuildContext context) {
    const tabular = [FontFeature.tabularFigures()];
    return _GlassCard(
      children: [
        SizedBox.square(
          dimension: 34,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: remaining),
            duration: motionDuration(context, ease),
            builder: (context, value, child) =>
                CustomPaint(painter: _CountdownRing(value), child: child),
            child: Center(
              child: Text(
                '$seconds',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: FontSize.body,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Gap.md),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: FontSize.body,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: const TextStyle(
                color: overlayMuted,
                fontSize: FontSize.small,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
        const SizedBox(width: Gap.xl),
        TextButton(
          style: overlayTextButtonStyle(),
          onPressed: onCancel,
          child: const Text('取消'),
        ),
        const SizedBox(width: Gap.xs),
        TextButton(
          style: overlayTextButtonStyle(primary: true),
          onPressed: onConfirm,
          child: Text(confirm),
        ),
      ],
    );
  }
}

/// The frosted row the corner's timed controls share; [onTap] makes the
/// whole card a button.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.children, this.onTap});
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.xs, Gap.xs),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
    return OverlayGlass(
      borderRadius: panelBorderRadius,
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

/// A faint track with the part of the countdown left drawn over it from the
/// top, clockwise.
class _CountdownRing extends CustomPainter {
  _CountdownRing(this.remaining);
  final double remaining;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(rect, stroke..color = Colors.white12);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * remaining,
      false,
      stroke..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CountdownRing old) => old.remaining != remaining;
}
