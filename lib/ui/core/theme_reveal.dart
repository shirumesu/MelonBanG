import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'motion.dart';
import 'pointer_lamp.dart';

/// Lets a theme switch spread from where it was asked for: the window as it
/// was stays on top while a circle of the new theme opens out from the
/// pointer to the far corner. One at the window's root.
class ThemeReveal extends StatefulWidget {
  const ThemeReveal({super.key, required this.child});
  final Widget child;

  @override
  State<ThemeReveal> createState() => ThemeRevealState();
}

class ThemeRevealState extends State<ThemeReveal>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final _progress = AnimationController(vsync: this);
  late final _eased = CurvedAnimation(
    parent: _progress,
    curve: const Cubic(.22, 1, .36, 1),
  );
  ui.Image? _old;
  Offset _center = Offset.zero;

  @override
  void dispose() {
    _eased.dispose();
    // A reveal under way disposes its own picture.
    _progress.dispose();
    super.dispose();
  }

  /// Runs [change], which switches the theme at once rather than fading it
  /// (the circle is the transition), behind a picture of the window, then opens the new theme from the pointer (or the window's
  /// top-right corner, where the title bar's switch is, without one). With
  /// reduced motion it just runs [change].
  Future<void> run(Future<void> Function() change) async {
    final duration = motionDuration(context, 560);
    if (duration == Duration.zero || _old != null) return change();
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted) return change();
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return change();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final ui.Image image;
    try {
      image = await boundary.toImage(pixelRatio: ratio);
    } catch (_) {
      return change();
    }
    if (!mounted) {
      image.dispose();
      return change();
    }
    final size = boundary.size;
    final pointer = LampPointer.instance.position;
    setState(() {
      _old = image;
      _center = pointer != null
          ? boundary.globalToLocal(pointer)
          : Offset(size.width - 60, 22);
    });
    try {
      await change();
      if (!mounted) return;
      _progress.duration = duration;
      await _progress.forward(from: 0);
    } finally {
      if (mounted) {
        setState(() => _old = null);
        // Once the frame without it is drawn.
        SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());
      } else {
        image.dispose();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (old != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _OldWindow(old, _center, _eased)),
            ),
          ),
      ],
    );
  }
}

/// The window before the switch, with a hole the new theme shows through.
class _OldWindow extends CustomPainter {
  _OldWindow(this.image, this.center, this.progress) : super(repaint: progress);
  final ui.Image image;
  final Offset center;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final far = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ].map((corner) => (corner - center).distance).reduce(math.max);
    final hole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect)
      ..addOval(Rect.fromCircle(center: center, radius: far * progress.value));
    canvas
      ..save()
      ..clipPath(hole)
      ..drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.none,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_OldWindow old) =>
      old.image != image || old.center != center;
}
