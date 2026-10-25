import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/danmaku.dart';
import 'danmaku_clock.dart';
import 'danmaku_layout.dart';
import '../../features/playback/playback.dart';

/// Clock times such as `12:34`, `1:02:03` and `02 ： 13`, `2.19`, or
/// `1分30(秒)`. A dotted time is not followed by a unit, which marks a
/// number such as a score or a price.
final _jumpTime = RegExp(
  r'(?<![\d:：.])(?:'
  r'(?:(\d{1,2})\s*[:：]\s*)?(\d{1,2})\s*[:：]\s*(\d{2})(?![\d:：])'
  r'|(\d{1,2})\.(\d{2})(?![\d.%％倍元块万亿分])'
  r'|(\d{1,3})\s*分\s*(\d{1,2})(?!\d))',
);

/// The first time [text] names inside the episode's [duration], in seconds.
/// Viewers post these for where an OP or ED ends.
double? danmakuJumpTarget(String text, Duration duration) {
  for (final match in _jumpTime.allMatches(text)) {
    final hours = int.parse(match[1] ?? '0');
    final minutes = int.parse(match[2] ?? match[4] ?? match[6]!);
    final seconds = int.parse(match[3] ?? match[5] ?? match[7]!);
    if (seconds >= 60 || (match[1] != null && minutes >= 60)) continue;
    final target = hours * 3600 + minutes * 60 + seconds;
    if (target > 0 && Duration(seconds: target) < duration) {
      return target.toDouble();
    }
  }
  return null;
}

class DanmakuLayer extends StatefulWidget {
  const DanmakuLayer({super.key, required this.playback, required this.onJump});
  final Playback playback;

  /// A comment naming a time was clicked; seek to [seconds].
  final ValueChanged<double> onJump;
  @override
  State<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends State<DanmakuLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  final clock = ValueNotifier<double>(0);
  final motion = DanmakuClock();
  final sprites = DanmakuSpriteCache();
  final layout = DanmakuLayout();
  Object? identity;
  bool frozen = false;

  /// Comments sent since the last frame.
  final sent = <DanmakuComment>[];
  late final StreamSubscription<DanmakuComment> sending;
  @override
  void initState() {
    super.initState();
    sending = widget.playback.danmaku.sent.listen(sent.add);
    clock.value =
        widget.playback.player.state.position.inMicroseconds /
        Duration.microsecondsPerSecond;
    ticker = createTicker((elapsed) {
      final playback = widget.playback;
      final state = playback.player.state;
      final nextIdentity = (
        playback,
        playback.session?.id,
        playback.uri,
        playback.opening,
        playback.danmakuRevision,
      );
      if (playback.frameStepping) {
        frozen = true;
        return;
      }
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
        reset: identity != nextIdentity || frozen,
      );
      identity = nextIdentity;
      frozen = false;
    });
    widget.playback.danmaku.preferences.addListener(_toggle);
    _toggle();
  }

  /// Hidden comments request no frames; shown again, the clock rebases.
  void _toggle() {
    final enabled = widget.playback.danmaku.preferences.enabled;
    if (enabled == ticker.isActive) return;
    if (enabled) {
      frozen = true;
      ticker.start();
    } else {
      ticker.stop();
    }
  }

  @override
  void dispose() {
    widget.playback.danmaku.preferences.removeListener(_toggle);
    unawaited(sending.cancel());
    ticker.dispose();
    sprites.clear();
    clock.dispose();
    super.dispose();
  }

  /// Where the comment pressed jumps to, until the tap completes.
  double? pressed;

  /// Where each comment text jumps to, for the episode's current length.
  final targets = <String, double?>{};
  Duration targetsDuration = Duration.zero;

  double? jumpTarget(String text) {
    final duration = widget.playback.player.state.duration;
    if (duration != targetsDuration) {
      targets.clear();
      targetsDuration = duration;
    }
    return targets.putIfAbsent(text, () => danmakuJumpTarget(text, duration));
  }

  double? targetAt(Offset position) {
    final item = layout.hit(
      position,
      clock.value,
      (item) => jumpTarget(item.text) != null,
    );
    return item == null ? null : jumpTarget(item.text);
  }

  // Only comments naming a time take pointers; elsewhere taps reach the
  // video beneath.
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    hitTestBehavior: HitTestBehavior.deferToChild,
    child: GestureDetector(
      onTapDown: (details) => pressed = targetAt(details.localPosition),
      onTap: () {
        if (pressed case final seconds?) widget.onJump(seconds);
        pressed = null;
      },
      onTapCancel: () => pressed = null,
      child: RepaintBoundary(
        child: ClipRect(
          child: CustomPaint(
            painter: DanmakuPainter(
              widget.playback,
              clock,
              sprites,
              layout,
              sent,
              MediaQuery.devicePixelRatioOf(context),
              targetAt,
              jumpTarget,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    ),
  );
}

class DanmakuPainter extends CustomPainter {
  DanmakuPainter(
    this.playback,
    this.clock,
    this.sprites,
    this.layout,
    this.sent,
    this.ratio,
    this.targetAt,
    this.jumpTarget,
  ) : super(repaint: Listenable.merge([clock, playback.danmaku.preferences]));
  final Playback playback;
  final ValueNotifier<double> clock;
  final DanmakuSpriteCache sprites;
  final DanmakuLayout layout;

  /// Sent comments waiting to enter; taken by the next frame.
  final List<DanmakuComment> sent;

  /// Physical pixels per logical pixel, the resolution sprites render at.
  final double ratio;

  /// The time a comment at a position jumps to.
  final double? Function(Offset) targetAt;

  /// The time a comment's text jumps to.
  final double? Function(String) jumpTarget;

  @override
  bool hitTest(Offset position) => targetAt(position) != null;

  @override
  void paint(Canvas canvas, Size size) {
    final preferences = playback.danmaku.preferences;
    if (!preferences.enabled || size.isEmpty) {
      layout.clear();
      sprites.clear();
      sent.clear();
      return;
    }
    sprites.beginFrame();
    final visible = layout.update(
      comments: playback.danmaku.visible,
      revision: playback.danmaku.revision,
      sent: sent,
      time: clock.value,
      viewport: size,
      fontSize: preferences.size,
      area: preferences.area,
      density: preferences.density,
      speed: preferences.speedFactor,
      overlap: preferences.overlap,
      shield: preferences.shield,
      measure: (item) => _sprite(item).size,
    );
    sent.clear();
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..color = Colors.white.withValues(alpha: preferences.opacity);
    double snap(double value) => (value * ratio).roundToDouble() / ratio;
    for (final entry in visible) {
      final bounds = entry.boundsAt(clock.value, size.width);
      if (entry.item.own) {
        // The viewer's own comment is framed, as players mark one just sent.
        canvas.drawRRect(
          RRect.fromRectAndRadius(bounds.inflate(3), const Radius.circular(4)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white.withValues(alpha: preferences.opacity),
        );
      }
      final image = _sprite(entry.item).image;
      // Resting edges sit on whole device pixels to stay sharp; a scrolling
      // comment keeps its fraction, which sampling turns into even motion.
      final left = bounds.left - DanmakuSpriteCache.padding;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(
          entry.scrolling ? left : snap(left),
          snap(bounds.top - DanmakuSpriteCache.padding),
          image.width / ratio,
          image.height / ratio,
        ),
        paint,
      );
    }
    sprites.endFrame();
  }

  DanmakuSprite _sprite(DanmakuComment item) {
    final preferences = playback.danmaku.preferences;
    return sprites.obtain(
      item.text,
      item.color,
      preferences.size,
      stroke: preferences.stroke,
      underline: jumpTarget(item.text) != null,
      ratio: ratio,
    );
  }

  @override
  bool shouldRepaint(covariant DanmakuPainter oldDelegate) => true;
}

/// A comment measured when it is considered and rendered once when it is
/// first drawn; frames then only draw its image.
class DanmakuSprite {
  DanmakuSprite(
    this.text,
    this.color,
    this.fontSize, {
    required this.stroke,
    required this.underline,
    required this.ratio,
  }) {
    final fill = _layout(TextStyle(color: Color(0xff000000 | color)));
    _fill = fill;
    size = fill.size;
  }
  final String text;
  final int color;
  final double fontSize;
  final bool stroke;

  /// Marks a comment that jumps to the time it names when clicked.
  final bool underline;
  final double ratio;
  TextPainter? _fill;
  ui.Image? _image;

  /// The text's own extent in logical pixels, without [DanmakuSpriteCache.padding].
  late final Size size;

  ui.Image get image => _image ??= _render();

  TextPainter _layout(TextStyle style) => TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(fontSize: fontSize, fontWeight: FontWeight.w600),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  ui.Image _render() {
    final fill = _fill!;
    final outline = stroke
        ? _layout(
            TextStyle(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = Colors.black,
            ),
          )
        : null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    const origin = Offset(
      DanmakuSpriteCache.padding,
      DanmakuSpriteCache.padding,
    );
    outline?.paint(canvas, origin);
    fill.paint(canvas, origin);
    if (underline) {
      // Drawn as one line: Latin and CJK text come from different fallback
      // fonts, whose own underlines sit at different heights.
      final thickness = fontSize / 16;
      final line = Rect.fromLTWH(
        0,
        fill.computeDistanceToActualBaseline(TextBaseline.alphabetic) +
            fontSize * .12,
        size.width,
        thickness,
      ).shift(origin);
      if (stroke) {
        canvas.drawRect(line.inflate(1), Paint()..color = Colors.black);
      }
      canvas.drawRect(line, Paint()..color = Color(0xff000000 | color));
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      ((size.width + DanmakuSpriteCache.padding * 2) * ratio).ceil(),
      ((size.height + DanmakuSpriteCache.padding * 2) * ratio).ceil(),
    );
    picture.dispose();
    outline?.dispose();
    fill.dispose();
    _fill = null;
    return image;
  }

  void dispose() {
    _fill?.dispose();
    _image?.dispose();
  }
}

/// Renders each comment to an image and keeps only the active window, as
/// Animeko and DanmakuFlameMaster do: drawing text with an outline every frame
/// costs raster time per glyph and snaps glyphs to the pixel grid, both of
/// which show as uneven scrolling.
class DanmakuSpriteCache {
  /// Room for the outline, which strokes 1 px outside the glyphs.
  static const padding = 1.0;
  final _sprites = <(String, int, double, bool, bool, double), DanmakuSprite>{};
  final _used = <(String, int, double, bool, bool, double)>{};

  void beginFrame() => _used.clear();

  DanmakuSprite obtain(
    String text,
    int color,
    double size, {
    required bool stroke,
    required bool underline,
    required double ratio,
  }) {
    final key = (text, color, size, stroke, underline, ratio);
    _used.add(key);
    return _sprites.putIfAbsent(
      key,
      () => DanmakuSprite(
        text,
        color,
        size,
        stroke: stroke,
        underline: underline,
        ratio: ratio,
      ),
    );
  }

  void endFrame() {
    _sprites.removeWhere((key, sprite) {
      if (_used.contains(key)) return false;
      sprite.dispose();
      return true;
    });
  }

  void clear() {
    for (final sprite in _sprites.values) {
      sprite.dispose();
    }
    _sprites.clear();
    _used.clear();
  }
}
