import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/motion.dart';

enum PlayerGlyphKind {
  danmaku,
  danmakuOff,
  danmakuSettings,
  previousFrame,
  nextFrame,
  settings,
}

/// Player icons Material lacks: the danmaku box (struck through when off,
/// with a cog for its settings), the frame steps (a chevron with a dot) and
/// a solid six-tooth cog, plainer and smaller than Material's settings.
class PlayerGlyph extends StatelessWidget {
  const PlayerGlyph(this.kind, {super.key});
  final PlayerGlyphKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    if (kind != PlayerGlyphKind.danmakuSettings) {
      return SizedBox.square(
        dimension: theme.size,
        child: CustomPaint(painter: _GlyphPainter(kind, theme.color!)),
      );
    }
    // Only the small cog turns, a quarter turn to its next spoke, as
    // [IconGesture.turn] does for the whole settings cog.
    final hover = IconHover.of(context);
    return SizedBox.square(
      dimension: theme.size,
      child: AnimatedBuilder(
        animation: hover,
        builder: (context, _) => CustomPaint(
          painter: _GlyphPainter(
            kind,
            theme.color!,
            turn: Curves.easeInOutCubic.transform(hover.value) * math.pi / 2,
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color, {this.turn = 0});
  final PlayerGlyphKind kind;
  final Color color;

  /// The small cog's angle in radians, in the danmaku settings glyph.
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24-unit grid like Material icons.
    canvas.scale(size.width / 24);
    final off = kind == PlayerGlyphKind.danmakuOff;
    final stroke = Paint()
      // The struck-out box fades so the slash reads first.
      ..color = off ? color.withValues(alpha: color.a * .55) : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), stroke);
    switch (kind) {
      case PlayerGlyphKind.danmaku || PlayerGlyphKind.danmakuOff:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 5, 21, 19, const Radius.circular(3)),
          stroke,
        );
        line(7, 10, 12, 10);
        line(15, 10, 17, 10);
        line(7, 14, 15, 14);
        if (off) {
          stroke.color = color;
          line(4, 21, 20, 3);
        }
      case PlayerGlyphKind.danmakuSettings:
        canvas.drawPath(
          Path()
            ..moveTo(12.5, 19)
            ..lineTo(6, 19)
            ..arcToPoint(const Offset(3, 16), radius: const Radius.circular(3))
            ..lineTo(3, 8)
            ..arcToPoint(const Offset(6, 5), radius: const Radius.circular(3))
            ..lineTo(18, 5)
            ..arcToPoint(const Offset(21, 8), radius: const Radius.circular(3))
            ..lineTo(21, 11),
          stroke,
        );
        line(7, 10, 13, 10);
        line(7, 14, 10, 14);
        canvas.translate(18, 17);
        canvas.rotate(turn);
        canvas.drawCircle(Offset.zero, 2.2, stroke);
        line(0, -3.7, 0, -2.4);
        line(0, 2.4, 0, 3.7);
        line(-3.7, 0, -2.4, 0);
        line(2.4, 0, 3.7, 0);
      case PlayerGlyphKind.previousFrame:
        stroke.strokeWidth = 2.2;
        canvas.drawPath(
          Path()
            ..moveTo(12, 6)
            ..lineTo(6, 12)
            ..lineTo(12, 18),
          stroke,
        );
        canvas.drawCircle(const Offset(17, 12), 1.7, fill);
      case PlayerGlyphKind.nextFrame:
        stroke.strokeWidth = 2.2;
        canvas.drawPath(
          Path()
            ..moveTo(12, 6)
            ..lineTo(18, 12)
            ..lineTo(12, 18),
          stroke,
        );
        canvas.drawCircle(const Offset(7, 12), 1.7, fill);
      case PlayerGlyphKind.settings:
        canvas.translate(12, 12);
        canvas.drawPath(_cog, fill);
    }
  }

  /// Six teeth around a ring, centred on the origin.
  static final _cog = () {
    var cog = Path()
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: 6.4));
    for (var i = 0; i < 6; i++) {
      final tooth = Path()
        ..addRRect(
          RRect.fromLTRBR(-1.9, -8.6, 1.9, -4, const Radius.circular(1)),
        );
      cog = Path.combine(
        PathOperation.union,
        cog,
        tooth.transform(Matrix4.rotationZ(i * math.pi / 3).storage),
      );
    }
    return Path.combine(
      PathOperation.difference,
      cog,
      Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 2.6)),
    );
  }();

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind || old.color != color || old.turn != turn;
}
