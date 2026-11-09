import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme.dart';

/// Where the mouse is in the window, for [PointerLamp]s: null while it is
/// outside or the last pointer was not a mouse. It also notifies, a frame
/// late, when the page scrolls under a resting pointer.
class LampPointer extends ChangeNotifier {
  LampPointer._();
  static final instance = LampPointer._();

  Offset? _position;
  Offset? get position => _position;

  bool _nudging = false;

  void _move(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      if (_position == null) return;
      _position = null;
    } else {
      _position = event.position;
    }
    notifyListeners();
  }

  void _leave() {
    if (_position == null) return;
    _position = null;
    notifyListeners();
  }

  /// After the layout a scroll causes, so panels measure where they now are.
  void _nudge() {
    if (_position == null || _nudging) return;
    _nudging = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _nudging = false;
      notifyListeners();
    });
  }
}

/// Feeds [LampPointer] from everything below it; one at the window's root.
class LampTracker extends StatelessWidget {
  const LampTracker({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lamp = LampPointer.instance;
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (_) {
        lamp._nudge();
        return false;
      },
      // Opaque, as nothing lies behind the root: a region that is not
      // reports no hit to its ancestors, and the tap region surface above
      // it then never learns of a tap, so text fields stopped losing focus
      // and popovers stopped closing on a click outside.
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.translucent,
        onHover: lamp._move,
        onExit: (_) => lamp._leave(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerMove: lamp._move,
          onPointerDown: lamp._move,
          child: child,
        ),
      ),
    );
  }
}

/// How close the pointer is to one panel, and where, in its coordinates.
class _Glow extends ChangeNotifier {
  Offset at = Offset.zero;
  double near = 0;

  void set(Offset at, double near) {
    if (near == 0 && this.near == 0) return;
    this.at = at;
    this.near = near;
    notifyListeners();
  }
}

/// The edge of [child] catches a little light where the pointer comes
/// near, from 240 px off to brightest inside, and its face a faint wash:
/// barely there, following the pointer at once without trailing it. The
/// light is [panelLamp]. Touch and pens show nothing.
class PointerLamp extends StatefulWidget {
  const PointerLamp({super.key, required this.child, required this.radius});
  final Widget child;
  final BorderRadius radius;

  @override
  State<PointerLamp> createState() => _PointerLampState();
}

class _PointerLampState extends State<PointerLamp> {
  final _glow = _Glow();

  @override
  void initState() {
    super.initState();
    LampPointer.instance.addListener(_track);
  }

  @override
  void dispose() {
    LampPointer.instance.removeListener(_track);
    _glow.dispose();
    super.dispose();
  }

  void _track() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final pointer = LampPointer.instance.position;
    // Panels of a page kept hidden behind another skip measuring.
    if (pointer == null ||
        !TickerMode.getValuesNotifier(context).value.enabled) {
      _glow.set(_glow.at, 0);
      return;
    }
    final at = box.globalToLocal(pointer);
    final size = box.size;
    final dx = math.max(math.max(-at.dx, 0.0), at.dx - size.width);
    final dy = math.max(math.max(-at.dy, 0.0), at.dy - size.height);
    final near = math.max(0.0, 1 - math.sqrt(dx * dx + dy * dy) / 240);
    _glow.set(at, near);
  }

  @override
  Widget build(BuildContext context) {
    final lamp = panelLamp(context);
    Widget layer(CustomPainter painter) => Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(child: CustomPaint(painter: painter)),
      ),
    );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        layer(_FacePainter(_glow, lamp.color, lamp.strength)),
        widget.child,
        layer(_EdgePainter(_glow, lamp.color, lamp.strength, widget.radius)),
      ],
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.glow, this.color, this.strength) : super(repaint: glow);
  final _Glow glow;
  final Color color;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (glow.near == 0) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: glow.near * strength * .06),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .7],
        ).createShader(Rect.fromCircle(center: glow.at, radius: 340)),
    );
  }

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.color != color || old.strength != strength;
}

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.glow, this.color, this.strength, this.radius)
    : super(repaint: glow);
  final _Glow glow;
  final Color color;
  final double strength;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (glow.near == 0) return;
    final rect = Offset.zero & size;
    canvas.drawRRect(
      radius.toRRect(rect.deflate(.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: glow.near * strength * .3),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .72],
        ).createShader(Rect.fromCircle(center: glow.at, radius: 200)),
    );
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.color != color || old.strength != strength || old.radius != radius;
}
