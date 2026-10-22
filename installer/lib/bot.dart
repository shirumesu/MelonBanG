import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// What the character is doing; each mode is a motion, not an expression.
enum BotMode { idle, morph, error, sleep, cheer, shrink, hop }

enum BotTone {
  mint(Color(0xff22b388)),
  coral(Color(0xffff6b81)),
  muted(Color(0xff8cbfae));

  const BotTone(this.colour);
  final Color colour;
}

/// MelonBanG's character, a rounded triangle with two eyes (after Grok's
/// avatars). It morphs between shapes, eases between modes and turns toward
/// the pointer.
class Bot extends StatefulWidget {
  const Bot({
    super.key,
    required this.mode,
    required this.pointer,
    this.tone = BotTone.mint,
    this.progress = 0,
    this.size = 200,
  });

  final BotMode mode;
  final BotTone tone;

  /// 0 to 1; shrinking follows it.
  final double progress;
  final double size;

  /// The pointer in global coordinates, null when it is outside the window.
  final ValueListenable<Offset?> pointer;

  @override
  State<Bot> createState() => _BotState();
}

// Drawing space: a 200 box, shape centre (100, 104), radius 62, standing on
// y 168.
const _centreX = 100.0, _centreY = 104.0, _radius = 62.0, _ground = 168.0;
const _samples = 96;

class _Shape {
  const _Shape(this.radius, this.turn, this.eye);
  final double Function(double angle) radius;
  final double turn;

  /// How far below the centre the eyes sit, in radii.
  final double eye;
}

double Function(double) _superformula(
  double m,
  double n1,
  double n2,
  double n3,
) =>
    (t) => math
        .pow(
          math.pow(math.cos(m * t / 4).abs(), n2) +
              math.pow(math.sin(m * t / 4).abs(), n3),
          -1 / n1,
        )
        .toDouble();

final _shapes = {
  'triangle': _Shape(_superformula(3, 3.6, 7, 7), math.pi / 2, 0.14),
  'circle': _Shape((_) => 1, 0, 0),
  'squircle': _Shape(_superformula(4, 4.2, 4.2, 4.2), 0.14, 0),
  'flower': _Shape((t) => 1 + 0.11 * math.cos(6 * t), 0, 0),
  'clover': _Shape((t) => 1 + 0.16 * math.cos(4 * t), math.pi / 4, 0),
  'pebble': _Shape(
    (t) => 1 + 0.07 * math.cos(2 * t) + 0.05 * math.cos(3 * t + 0.6),
    0,
    0,
  ),
};
const _cycle = ['triangle', 'circle', 'squircle', 'flower', 'clover', 'pebble'];

/// Every shape sampled at the same angles, centred on its bounds and
/// starting at its top, so blends between any two do not twist.
final _outlines = {
  for (final MapEntry(:key, :value) in _shapes.entries) key: _sample(value),
};

List<Offset> _sample(_Shape shape) {
  final radii = [
    for (var i = 0; i < _samples; i++) shape.radius(2 * math.pi * i / _samples),
  ];
  final top = radii.reduce(math.max);
  final points = [
    for (var i = 0; i < _samples; i++)
      Offset.fromDirection(
        2 * math.pi * i / _samples + shape.turn,
        radii[i] / top,
      ),
  ];
  final bounds = points
      .skip(1)
      .fold(
        Rect.fromPoints(points.first, points.first),
        (rect, point) => rect.expandToInclude(Rect.fromPoints(point, point)),
      );
  final centred = [for (final point in points) point - bounds.center];
  var start = 0;
  for (var i = 0; i < centred.length; i++) {
    if (centred[i].dx >= 0 && centred[i].direction < centred[start].direction) {
      start = i;
    }
  }
  return [...centred.skip(start), ...centred.take(start)];
}

double _ease(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;

class _Pose {
  _Pose({
    required this.points,
    required this.eye,
    required this.colour,
    this.dx = 0,
    this.dy = 0,
    this.sx = 1,
    this.sy = 1,
    this.turn = 0,
    this.scale = 1,
    this.eyeHeight = 1,
    this.eyeShift = 0,
  });

  List<Offset> points;
  double eye, dx, dy, sx, sy, turn, scale, eyeHeight, eyeShift;
  Color colour;
}

/// The pose [mode] asks for [t] seconds into the mode and [life] seconds
/// after the character first appeared.
_Pose _target(
  BotMode mode,
  double t,
  double life,
  double progress,
  Color colour,
) {
  var a = 'triangle', b = 'triangle';
  var k = 0.0;
  var dx = 0.0, dy = 0.0, sx = 1.0, sy = 1.0, turn = 0.0, scale = 1.0;
  var eyeHeight = 1.0, eyeShift = 0.0;
  final breathe = math.sin(t * math.pi * 2 / 3);
  switch (mode) {
    case BotMode.idle || BotMode.hop || BotMode.cheer:
      sy = 1 + 0.025 * breathe;
      sx = 1 - 0.015 * breathe;
      if ((t + 1.2) % 3.6 < 0.14) eyeHeight = 0.12;
      final glance = math.sin(t * math.pi * 2 / 7);
      eyeShift = glance > 0.6 ? 5 : (glance < -0.6 ? -4 : 0);
      final hops = mode == BotMode.cheer ? 0.7 : 0.6;
      if (mode != BotMode.idle && t < hops * 2) {
        final f = (t % hops) / hops;
        final lift = math.sin(math.pi * f);
        final cheer = mode == BotMode.cheer;
        dy = (cheer ? -34 : -16) * lift;
        sy =
            1 +
            (cheer ? 0.08 : 0.05) * lift -
            (cheer ? 0.14 : 0.1) * math.pow(1 - lift, 6).toDouble();
        sx = 2 - sy;
        if (cheer && t < hops) turn = 360 * _ease(f);
      }
    case BotMode.morph || BotMode.shrink:
      final morph = mode == BotMode.morph;
      final segment = morph ? 0.9 : 1.4;
      final i = (t / segment).floor();
      a = _cycle[i % _cycle.length];
      b = _cycle[(i + 1) % _cycle.length];
      k = _ease(((t % segment) / (segment * 0.65)).clamp(0.0, 1.0));
      turn = (t * (morph ? 40 : 18)) % 360;
      if (morph) {
        dy = -10 * math.sin(math.pi * (t % segment) / segment);
      } else {
        scale = 1 - 0.5 * progress;
      }
    case BotMode.error:
      dx = t < 0.6 ? 9 * math.sin(t * 48) * (1 - t / 0.6) : 0;
      sy = 1 + 0.02 * breathe;
      sx = 1 - 0.02 * breathe;
      eyeHeight = 0.5;
    case BotMode.sleep:
      final slow = math.sin(t * math.pi * 2 / 4.2);
      sy = 1 + 0.035 * slow;
      sx = 1 - 0.02 * slow;
      eyeHeight = 0.12;
  }
  // Pops in when it first appears.
  if (life < 1.2) scale *= 1 - math.exp(-7 * life) * math.cos(11 * life);
  final from = _outlines[a]!, to = _outlines[b]!;
  return _Pose(
    points: [
      for (var j = 0; j < _samples; j++) Offset.lerp(from[j], to[j], k)!,
    ],
    eye: _shapes[a]!.eye + (_shapes[b]!.eye - _shapes[a]!.eye) * k,
    colour: colour,
    dx: dx,
    dy: dy,
    sx: sx,
    sy: sy,
    turn: turn,
    scale: scale,
    eyeHeight: eyeHeight,
    eyeShift: eyeShift,
  );
}

double _mix(double a, double b, double k) => a + (b - a) * k;

class _BotState extends State<Bot> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _now = Duration.zero, _last = Duration.zero, _modeAt = Duration.zero;
  late _Pose _pose;
  Offset _look = Offset.zero;
  bool _still = false;

  double _seconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerSecond;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _still && _ticker.isActive) return;
    _still = still;
    _pose = _target(
      widget.mode,
      0.6,
      still ? 5 : 0,
      widget.progress,
      widget.tone.colour,
    );
    if (still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(Bot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != oldWidget.mode) _modeAt = _now;
    if (_still) {
      _pose = _target(widget.mode, 0.6, 5, widget.progress, widget.tone.colour);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    _now = now;
    final dt = math.min(0.05, _seconds(now - _last));
    _last = now;
    final goal = _target(
      widget.mode,
      _seconds(now - _modeAt),
      _seconds(now),
      widget.progress,
      widget.tone.colour,
    );
    // Shape and colour ease toward the goal, so mode changes blend.
    final a = 1 - math.exp(-dt * 12);
    final pose = _pose;
    pose.points = [
      for (var j = 0; j < _samples; j++)
        Offset.lerp(pose.points[j], goal.points[j], a)!,
    ];
    pose.colour = Color.lerp(pose.colour, goal.colour, a)!;
    pose.eye = _mix(pose.eye, goal.eye, a);
    pose.eyeHeight = goal.eyeHeight < 0.2 || pose.eyeHeight < 0.2
        ? goal.eyeHeight
        : _mix(pose.eyeHeight, goal.eyeHeight, a);
    pose.eyeShift = _mix(pose.eyeShift, goal.eyeShift, 1 - math.exp(-dt * 18));
    pose.scale = goal.scale < pose.scale * 0.98 || widget.mode == BotMode.shrink
        ? _mix(pose.scale, goal.scale, a)
        : goal.scale;
    pose
      ..dx = goal.dx
      ..dy = goal.dy
      ..sx = goal.sx
      ..sy = goal.sy
      ..turn = goal.turn;

    // Turns toward the pointer, saturating about 320 px away.
    var aim = Offset.zero;
    final pointer = widget.pointer.value;
    final box = context.findRenderObject() as RenderBox?;
    if (pointer != null &&
        box != null &&
        box.hasSize &&
        widget.mode != BotMode.sleep &&
        widget.mode != BotMode.shrink) {
      final centre = box.localToGlobal(
        Offset(box.size.width / 2, box.size.height * 0.52),
      );
      aim = (pointer - centre) / 320;
      if (aim.distance > 1) aim /= aim.distance;
    }
    _look = Offset.lerp(_look, aim, 1 - math.exp(-dt * 8))!;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 1 / 520)
        ..rotateY(_look.dx * 22 * math.pi / 180)
        ..rotateX(-_look.dy * 16 * math.pi / 180),
      child: CustomPaint(painter: _BotPainter(_pose, _look)),
    ),
  );
}

class _BotPainter extends CustomPainter {
  _BotPainter(this.pose, this.look);
  final _Pose pose;
  final Offset look;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 200);
    canvas
      ..translate(100 + pose.dx, _ground + pose.dy)
      ..translate(0, _centreY - _ground)
      ..rotate(pose.turn * math.pi / 180)
      ..translate(0, _ground - _centreY)
      ..scale(pose.scale * pose.sx, pose.scale * pose.sy)
      ..translate(-100, -_ground);

    final points = [
      for (final point in pose.points)
        Offset(_centreX + point.dx * _radius, _centreY + point.dy * _radius),
    ];
    // A closed Catmull-Rom curve through the samples.
    final outline = Path()..moveTo(points.first.dx, points.first.dy);
    final n = points.length;
    for (var i = 0; i < n; i++) {
      final p0 = points[(i - 1 + n) % n], p1 = points[i];
      final p2 = points[(i + 1) % n], p3 = points[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      outline.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    canvas.drawPath(outline..close(), Paint()..color = pose.colour);

    final width = _radius * 0.28;
    final height = math.max(_radius * 0.44 * pose.eyeHeight, width * 0.42);
    final y = _centreY + pose.eye * _radius + look.dy * 7;
    final white = Paint()..color = const Color(0xffffffff);
    for (final side in const [-1, 1]) {
      final x =
          _centreX +
          _radius * (0.16 + side * 0.19) +
          pose.eyeShift +
          look.dx * 9;
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(8 * math.pi / 180)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: width, height: height),
            Radius.circular(math.min(width, height) / 2),
          ),
          white,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_BotPainter oldDelegate) => true;
}
