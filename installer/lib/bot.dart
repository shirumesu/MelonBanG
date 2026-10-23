import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// What the character is doing; each mode is a motion, not an expression.
enum BotMode { idle, spin, error, pause, cheer, shrink, hop }

enum BotTone {
  mint(Color(0xff22b388)),
  coral(Color(0xffff6b81)),
  muted(Color(0xff8cbfae));

  const BotTone(this.colour);
  final Color colour;
}

/// MelonBanG's mark as a character: the melon ring around the play arrow
/// (assets/brand/icon-bare.svg). It eases between modes and turns toward
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

// Drawing space: a 200 box, ring centre (100, 104), outer radius 64,
// standing on y 168. Proportions follow the 1024 icon, where the ring's
// outer radius is 268.
const _centreX = 100.0, _centreY = 104.0, _radius = 64.0, _ground = 168.0;
const _k = _radius / 268;
const _hole = 186 * _k, _flesh = _hole + 11 * _k;
const _arrowHeight = 268 * _k, _arrowWidth = 232 * _k;

const _coral = Color(0xffff6b81), _coralLight = Color(0xffff8e9e);
const _coralDark = Color(0xffde4d66), _fleshColour = Color(0xffeef9e6);
const _deep = Color(0xff0f5c46);

/// Dashes on the ring, as start and end angles in degrees.
const _dashes = [(252, 262), (270, 281), (289, 299), (148, 158), (166, 176)];

double _rad(double degrees) => degrees * math.pi / 180;

/// Three lumps between [from] and [to] degrees under a sine envelope, as
/// on the icon's lower right.
double _lumps(double angle, double from, double to, double height) {
  if (angle < from || angle > to) return 0;
  final u = (angle - from) / (to - from);
  final envelope = math.pow(math.sin(math.pi * u), 1.5);
  return height *
      envelope *
      (0.45 + 0.55 * (0.5 - 0.5 * math.cos(2 * math.pi * 3 * u)));
}

Path _polar(double Function(double angle) radius) {
  final path = Path();
  for (var a = 0; a < 360; a += 3) {
    final point =
        Offset(_centreX, _centreY) +
        Offset.fromDirection(_rad(a.toDouble()), radius(a.toDouble()));
    a == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
  }
  return path..close();
}

final _ringOuter = _polar((a) => _radius + _lumps(a, 8, 92, 15 * _k));
final _fleshEdge = _polar((a) => _flesh + _lumps(a, 22, 92, 9 * _k));

/// The play arrow, a chevron with a notched back, centred on its area at
/// the origin; corners rounded by quadratic curves.
final Path _arrow = () {
  const notch = 0.22;
  final points = [
    const Offset(0, -_arrowHeight / 2),
    const Offset(_arrowWidth, 0),
    const Offset(0, _arrowHeight / 2),
    const Offset(notch * _arrowWidth, 0),
  ];
  // The centroid of the two triangles either side of the notch-tip line.
  final centroid = (2 * _arrowWidth + notch * _arrowWidth) / 3;
  final shifted = [for (final p in points) p - Offset(centroid - 6 * _k, 0)];
  const radii = [
    _arrowHeight * 0.19,
    _arrowHeight * 0.25,
    _arrowHeight * 0.19,
    _arrowHeight * 0.14,
  ];
  final path = Path();
  for (var i = 0; i < 4; i++) {
    final p = shifted[i], a = shifted[(i + 3) % 4], b = shifted[(i + 1) % 4];
    final start = p + (a - p) / (a - p).distance * radii[i];
    final end = p + (b - p) / (b - p).distance * radii[i];
    i == 0 ? path.moveTo(start.dx, start.dy) : path.lineTo(start.dx, start.dy);
    path.quadraticBezierTo(p.dx, p.dy, end.dx, end.dy);
  }
  return path..close();
}();

double _ease(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;

class _Pose {
  _Pose(this.colour);

  Color colour;
  double dx = 0, dy = 0, sx = 1, sy = 1, turn = 0, scale = 1;

  /// How far the dashes have travelled round the ring, in degrees, and
  /// how fast they travel in degrees per second.
  double spin = 0, spinSpeed = 0;

  /// 0 for the play arrow, 1 for pause bars.
  double pause = 0;

  /// The arrow's forward push and its scale.
  double nudge = 0, pulse = 1;

  /// The share of the ring still drawn, unwinding clockwise.
  double sweep = 1;
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
  final pose = _Pose(colour);
  final breathe = math.sin(t * math.pi * 2 / 3);
  switch (mode) {
    case BotMode.idle || BotMode.hop || BotMode.cheer:
      pose
        ..sy = 1 + 0.02 * breathe
        ..sx = 1 - 0.012 * breathe;
      // Every few seconds the arrow pushes forward, like pressing play.
      final beat = (t + 1.2) % 3.6;
      if (beat < 0.5) pose.nudge = 5 * math.sin(math.pi * beat / 0.5);
      final hops = mode == BotMode.cheer ? 0.7 : 0.6;
      if (mode != BotMode.idle && t < hops * 2) {
        final f = (t % hops) / hops;
        final lift = math.sin(math.pi * f);
        final cheer = mode == BotMode.cheer;
        pose
          ..dy = (cheer ? -34 : -16) * lift
          ..sy =
              1 +
              (cheer ? 0.08 : 0.05) * lift -
              (cheer ? 0.14 : 0.1) * math.pow(1 - lift, 6).toDouble()
          ..nudge = (cheer ? 8 : 4) * lift;
        pose.sx = 2 - pose.sy;
        if (cheer && t < hops) pose.turn = 360 * _ease(f);
      }
    case BotMode.spin:
      pose
        ..spinSpeed = 150
        ..dy = -6 * math.sin(t * math.pi * 2 / 1.8)
        ..pulse = 1 + 0.06 * math.sin(t * math.pi * 2 / 0.9);
    case BotMode.error:
      pose
        ..dx = t < 0.6 ? 9 * math.sin(t * 48) * (1 - t / 0.6) : 0
        ..sy = 1 + 0.02 * breathe
        ..sx = 1 - 0.02 * breathe;
    case BotMode.pause:
      final slow = math.sin(t * math.pi * 2 / 4.2);
      pose
        ..sy = 1 + 0.03 * slow
        ..sx = 1 - 0.018 * slow
        ..pause = 1;
    case BotMode.shrink:
      pose
        ..spinSpeed = 40
        ..scale = 1 - 0.5 * progress
        ..sweep = 1 - progress;
  }
  // Pops in when it first appears.
  if (life < 1.2) pose.scale *= 1 - math.exp(-7 * life) * math.cos(11 * life);
  return pose;
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
    // Colour, pause and sweep ease toward the goal, so mode changes blend.
    final a = 1 - math.exp(-dt * 12);
    final pose = _pose;
    pose.colour = Color.lerp(pose.colour, goal.colour, a)!;
    pose.pause = _mix(pose.pause, goal.pause, 1 - math.exp(-dt * 9));
    pose.sweep = _mix(pose.sweep, goal.sweep, a);
    pose.pulse = _mix(pose.pulse, goal.pulse, a);
    pose.scale = goal.scale < pose.scale * 0.98 || widget.mode == BotMode.shrink
        ? _mix(pose.scale, goal.scale, a)
        : goal.scale;
    pose.spinSpeed = _mix(pose.spinSpeed, goal.spinSpeed, a);
    pose.spin = (pose.spin + pose.spinSpeed * dt) % 360;
    pose
      ..dx = goal.dx
      ..dy = goal.dy
      ..sx = goal.sx
      ..sy = goal.sy
      ..turn = goal.turn
      ..nudge = goal.nudge;

    // Turns toward the pointer, saturating about 320 px away.
    var aim = Offset.zero;
    final pointer = widget.pointer.value;
    final box = context.findRenderObject() as RenderBox?;
    if (pointer != null &&
        box != null &&
        box.hasSize &&
        widget.mode != BotMode.pause &&
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

    const centre = Offset(_centreX, _centreY);
    final colour = pose.colour;
    final ringBounds = Rect.fromCircle(center: centre, radius: _radius);

    // The ring unwinds clockwise from the top while shrinking.
    canvas.save();
    if (pose.sweep < 0.999) {
      canvas.clipPath(
        Path()
          ..moveTo(_centreX, _centreY)
          ..arcTo(
            ringBounds.inflate(12),
            -math.pi / 2,
            2 * math.pi * pose.sweep.clamp(0.0, 1.0),
            false,
          )
          ..close(),
      );
    }
    canvas
      ..drawPath(
        _ringOuter.shift(Offset(0, 16 * _k)),
        Paint()
          ..color = _deep.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20 * _k),
      )
      ..drawPath(
        _ringOuter,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(const Color(0xffffffff), colour, 0.32)!,
              Color.lerp(const Color(0xffffffff), colour, 0.65)!,
              colour,
            ],
            stops: const [0, 0.45, 1],
          ).createShader(ringBounds),
      )
      ..drawPath(
        _ringOuter,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * _k
          ..color = Color.lerp(colour, _deep, 0.25)!.withValues(alpha: 0.35),
      )
      ..drawPath(_fleshEdge, Paint()..color = _fleshColour);

    final mid = (_radius + _flesh) / 2;
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12 * _k
      ..color = Color.lerp(colour, _deep, 0.25)!.withValues(alpha: 0.38);
    final dashBounds = Rect.fromCircle(center: centre, radius: mid + 4 * _k);
    for (final (from, to) in _dashes) {
      canvas.drawArc(
        dashBounds,
        _rad(from + pose.spin),
        _rad((to - from).toDouble()),
        false,
        dash,
      );
    }
    // The gloss stays where the light is.
    final gloss = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x99ffffff);
    final glossBounds = Rect.fromCircle(
      center: centre - look * 2,
      radius: mid + 2 * _k,
    );
    canvas
      ..drawArc(
        glossBounds,
        _rad(196),
        _rad(42),
        false,
        gloss..strokeWidth = 17 * _k,
      )
      ..drawArc(
        glossBounds,
        _rad(182),
        _rad(4),
        false,
        gloss..strokeWidth = 12 * _k,
      )
      ..restore();

    canvas.drawCircle(
      centre,
      _hole,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.16, -0.24),
          radius: 0.7,
          colors: [Color(0xffffffff), Color(0xfff6fcf8)],
        ).createShader(Rect.fromCircle(center: centre, radius: _hole)),
    );

    // The arrow sits in front of the ring, so it follows the pointer more.
    final arrowCentre = centre + look * 5 + Offset(pose.nudge, 0);
    final play = 1 - _ease(pose.pause.clamp(0.0, 1.0));
    final pause = 1 - play;
    if (play > 0.01) {
      canvas
        ..save()
        ..translate(arrowCentre.dx, arrowCentre.dy)
        ..scale(pose.pulse * play)
        ..drawPath(
          _arrow.shift(Offset(4 * _k, 10 * _k)),
          Paint()
            ..color = const Color(0x38b23a52)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9 * _k),
        )
        ..drawPath(
          _arrow.shift(Offset(7 * _k, 9 * _k)),
          Paint()..color = _coralDark,
        )
        ..drawPath(
          _arrow,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_coralLight, _coral],
              stops: [0, 0.6],
            ).createShader(_arrow.getBounds()),
        )
        ..restore();
    }
    if (pause > 0.01) {
      final bar = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: _arrowHeight * 0.22,
          height: _arrowHeight * 0.82,
        ),
        Radius.circular(_arrowHeight * 0.11),
      );
      canvas
        ..save()
        ..translate(arrowCentre.dx, arrowCentre.dy)
        ..scale(pause);
      for (final side in const [-1, 1]) {
        final shifted = bar.shift(Offset(side * _arrowHeight * 0.2, 0));
        canvas
          ..drawRRect(
            shifted.shift(Offset(7 * _k, 9 * _k)),
            Paint()..color = _coralDark,
          )
          ..drawRRect(shifted, Paint()..color = _coral);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BotPainter oldDelegate) => true;
}
