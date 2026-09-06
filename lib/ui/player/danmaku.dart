import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app_services.dart';
import 'playback.dart';

class DanmakuLayer extends StatefulWidget {
  const DanmakuLayer({super.key, required this.playback});
  final Playback playback;
  @override
  State<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends State<DanmakuLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  final clock = ValueNotifier<double>(0);
  @override
  void initState() {
    super.initState();
    ticker = createTicker((_) {
      clock.value = widget.playback.player.state.position.inMilliseconds / 1000;
    })..start();
  }

  @override
  void dispose() {
    ticker.dispose();
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ClipRect(
      child: CustomPaint(
        painter: DanmakuPainter(widget.playback, clock),
        size: Size.infinite,
      ),
    ),
  );
}

int firstVisibleComment(List<Json> comments, double after) {
  var low = 0;
  var high = comments.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (number(comments[middle]['timeSeconds']) < after) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

class DanmakuPainter extends CustomPainter {
  DanmakuPainter(this.playback, this.clock) : super(repaint: clock);
  final Playback playback;
  final ValueNotifier<double> clock;
  @override
  void paint(Canvas canvas, Size size) {
    if (!playback.danmakuEnabled || size.isEmpty) return;
    final comments = playback.comments;
    const lifetime = 8.0;
    final lanes = math.max(
      1,
      (size.height * playback.danmakuArea / (playback.danmakuSize + 10))
          .floor(),
    );
    final occupied = <String, double>{};
    var drawn = 0;
    for (
      var index = firstVisibleComment(comments, clock.value - lifetime);
      index < comments.length && drawn < 100;
      index++
    ) {
      final item = comments[index];
      final age = clock.value - number(item['timeSeconds']);
      if (age < 0) break;
      final text = '${item['text'] ?? ''}';
      if (text.isEmpty) continue;
      final mode = '${item['mode'] ?? 'scroll'}';
      final lane = index % lanes;
      final colorValue =
          int.tryParse(
            '${item['color'] ?? '#ffffff'}'.replaceFirst('#', ''),
            radix: 16,
          ) ??
          0xffffff;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: playback.danmakuSize,
            fontWeight: FontWeight.w600,
            color: Color(0xff000000 | colorValue)
                .withValues(alpha: playback.danmakuOpacity),
            shadows: const [
              Shadow(blurRadius: 3, color: Colors.black, offset: Offset(1, 1)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final x = mode == 'scroll'
          ? size.width - (size.width + painter.width) * age / lifetime
          : (size.width - painter.width) / 2;
      final y = mode == 'bottom'
          ? size.height - 75 - (lane + 1) * (playback.danmakuSize + 10)
          : 16.0 + lane * (playback.danmakuSize + 10);
      final key = '$mode:$lane';
      if (occupied.containsKey(key) && x < occupied[key]! + 20) continue;
      occupied[key] = x + painter.width;
      painter.paint(canvas, Offset(x, y));
      drawn++;
    }
  }

  @override
  bool shouldRepaint(covariant DanmakuPainter oldDelegate) => true;
}
