import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app_services.dart';
import 'danmaku_clock.dart';
import 'danmaku_layout.dart';
import 'playback.dart';

export 'danmaku_layout.dart' show firstVisibleComment;

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
  final motion = DanmakuClock();
  final textCache = DanmakuTextCache();
  final layout = DanmakuLayout();
  Object? identity;
  @override
  void initState() {
    super.initState();
    clock.value =
        widget.playback.player.state.position.inMicroseconds /
        Duration.microsecondsPerSecond;
    ticker = createTicker((elapsed) {
      final playback = widget.playback;
      final state = playback.player.state;
      final nextIdentity = (
        playback,
        playback.session?['id'],
        playback.uri,
        playback.opening,
      );
      if (identity != nextIdentity) layout.clear();
      clock.value = motion.sample(
        elapsed: elapsed,
        position: state.position,
        running:
            state.playing &&
            !state.buffering &&
            !state.completed &&
            !playback.opening,
        rate: state.rate,
        reset: identity != nextIdentity,
      );
      identity = nextIdentity;
    })..start();
  }

  @override
  void dispose() {
    ticker.dispose();
    textCache.clear();
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: ClipRect(
        child: CustomPaint(
          painter: DanmakuPainter(widget.playback, clock, textCache, layout),
          size: Size.infinite,
        ),
      ),
    ),
  );
}

class DanmakuPainter extends CustomPainter {
  DanmakuPainter(this.playback, this.clock, this.textCache, this.layout)
    : super(repaint: clock);
  final Playback playback;
  final ValueNotifier<double> clock;
  final DanmakuTextCache textCache;
  final DanmakuLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    if (!playback.danmakuEnabled || size.isEmpty) {
      layout.clear();
      textCache.clear();
      return;
    }
    textCache.beginFrame();
    final visible = layout.update(
      comments: playback.comments,
      time: clock.value,
      viewport: size,
      fontSize: playback.danmakuSize,
      area: playback.danmakuArea,
      measure: (item) => _text(item).size,
    );
    for (final entry in visible) {
      _text(entry.item)
          .paint(canvas, entry.boundsAt(clock.value, size.width).topLeft);
    }
    textCache.endFrame();
  }

  TextPainter _text(Json item) {
    final colorValue =
        int.tryParse(
          '${item['color'] ?? '#ffffff'}'.replaceFirst('#', ''),
          radix: 16,
        ) ??
        0xffffff;
    return textCache.obtain(
      '${item['text'] ?? ''}',
      Color(0xff000000 | colorValue).withValues(alpha: playback.danmakuOpacity),
      playback.danmakuSize,
    );
  }

  @override
  bool shouldRepaint(covariant DanmakuPainter oldDelegate) => true;
}

/// Keeps layout work out of animation frames and retains only the active window.
class DanmakuTextCache {
  final _painters = <(String, Color, double), TextPainter>{};
  final _used = <(String, Color, double)>{};

  void beginFrame() => _used.clear();

  TextPainter obtain(String text, Color color, double size) {
    final key = (text, color, size);
    _used.add(key);
    return _painters.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w600,
            color: color,
            shadows: const [
              Shadow(blurRadius: 3, color: Colors.black, offset: Offset(1, 1)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(),
    );
  }

  void endFrame() {
    _painters.removeWhere((key, painter) {
      if (_used.contains(key)) return false;
      painter.dispose();
      return true;
    });
  }

  void clear() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
    _used.clear();
  }
}
