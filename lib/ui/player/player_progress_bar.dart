import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/theme.dart';
import 'player_theme.dart';

/// Thin seek bar that thickens on hover and shows the time under the pointer.
/// [marks] are small dots, such as where the OP ends; hovering one names it.
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onDragStart,
    required this.onDragChanged,
    required this.onDragEnd,
    this.marks = const [],
  });
  final double position, duration, buffered;
  final List<({double at, String label})> marks;
  final ValueChanged<double> onDragStart, onDragChanged, onDragEnd;

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  double? hoverX;
  bool dragging = false;

  double valueAt(double x, double width) =>
      (x / width).clamp(0.0, 1.0) * widget.duration;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final enabled = widget.duration > 0;
      final active = enabled && (hoverX != null || dragging);
      final marks = enabled
          ? [
              for (final mark in widget.marks)
                if (mark.at > 0 && mark.at < widget.duration) mark,
            ]
          : const <({double at, String label})>[];
      // Hovering near a mark names it and shows its exact time.
      final hovered = hoverX == null || dragging
          ? null
          : marks
                .where(
                  (mark) =>
                      (mark.at / widget.duration * width - hoverX!).abs() <= 6,
                )
                .firstOrNull;
      final bubbleX = hovered != null
          ? hovered.at / widget.duration * width
          : hoverX ?? (widget.position / widget.duration) * width;
      final bubbleWidth = hovered == null ? 56.0 : 112.0;
      return Semantics(
        slider: true,
        label: '播放进度',
        value: formatTime(widget.position),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onHover: (event) => setState(() => hoverX = event.localPosition.dx),
          onExit: (_) => setState(() => hoverX = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: enabled
                ? (details) {
                    final value =
                        hovered?.at ?? valueAt(details.localPosition.dx, width);
                    widget.onDragStart(value);
                    widget.onDragEnd(value);
                  }
                : null,
            onHorizontalDragStart: enabled
                ? (details) {
                    setState(() => dragging = true);
                    widget.onDragStart(
                      valueAt(details.localPosition.dx, width),
                    );
                  }
                : null,
            onHorizontalDragUpdate: enabled
                ? (details) {
                    setState(() => hoverX = details.localPosition.dx);
                    widget.onDragChanged(
                      valueAt(details.localPosition.dx, width),
                    );
                  }
                : null,
            onHorizontalDragEnd: enabled
                ? (_) {
                    setState(() => dragging = false);
                    widget.onDragEnd(widget.position);
                  }
                : null,
            child: SizedBox(
              height: 22,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: active ? 1 : 0),
                      duration: motionDuration(context, 120),
                      builder: (_, emphasis, _) => CustomPaint(
                        painter: _ProgressPainter(
                          played: enabled
                              ? widget.position / widget.duration
                              : 0,
                          buffered: enabled
                              ? widget.buffered / widget.duration
                              : 0,
                          hover: hoverX == null ? null : hoverX! / width,
                          marks: [
                            for (final mark in marks) mark.at / widget.duration,
                          ],
                          emphasis: emphasis,
                        ),
                      ),
                    ),
                  ),
                  if (active)
                    Positioned(
                      left: (bubbleX - bubbleWidth / 2).clamp(
                        0,
                        width - bubbleWidth,
                      ),
                      bottom: 24,
                      width: bubbleWidth,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        decoration: const BoxDecoration(
                          color: overlaySurface,
                          borderRadius: badgeBorderRadius,
                        ),
                        child: Text.rich(
                          TextSpan(
                            text: formatTime(
                              hovered?.at ?? valueAt(bubbleX, width),
                            ),
                            children: [
                              if (hovered != null)
                                TextSpan(
                                  text: '  ${hovered.label}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({
    required this.played,
    required this.buffered,
    required this.hover,
    required this.marks,
    required this.emphasis,
  });
  final double played, buffered, emphasis;
  final double? hover;
  final List<double> marks;

  @override
  void paint(Canvas canvas, Size size) {
    final height = 3 + 2 * emphasis;
    final top = (size.height - height) / 2;
    final radius = Radius.circular(height / 2);
    RRect bar(double fraction) => RRect.fromLTRBR(
      0,
      top,
      size.width * fraction.clamp(0.0, 1.0),
      top + height,
      radius,
    );
    canvas
      ..drawRRect(bar(1), Paint()..color = Colors.white24)
      ..drawRRect(bar(buffered), Paint()..color = Colors.white38);
    if (hover case final hover? when hover > played) {
      canvas.drawRRect(bar(hover), Paint()..color = Colors.white30);
    }
    canvas.drawRRect(bar(played), Paint()..color = Colors.white);
    final dot = 3 + emphasis;
    for (final mark in marks) {
      final center = Offset(size.width * mark, size.height / 2);
      canvas
        ..drawCircle(center, dot + 1.5, Paint()..color = Colors.black54)
        ..drawCircle(center, dot, Paint()..color = Colors.white);
    }
    if (emphasis > 0) {
      canvas.drawCircle(
        Offset(size.width * played.clamp(0.0, 1.0), size.height / 2),
        6.5 * emphasis,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.hover != hover ||
      old.emphasis != emphasis ||
      !_sameMarks(old.marks, marks);

  static bool _sameMarks(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

String formatTime(double seconds) {
  final total = seconds.isFinite ? seconds.floor().clamp(0, 1 << 40) : 0;
  final hours = total ~/ 3600;
  final minutes = (total % 3600 ~/ 60).toString().padLeft(2, '0');
  final rest = (total % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$rest' : '$minutes:$rest';
}
