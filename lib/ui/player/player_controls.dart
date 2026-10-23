import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/theme.dart';
import '../../features/playback/playback.dart';
import 'danmaku_composer.dart';
import 'player_menus.dart';
import 'player_popovers.dart';
import 'player_progress_bar.dart';

/// Horizontal room before the play glyph and after the fullscreen glyph inside
/// their buttons, so the glyphs line up with the title and the timeline.
const _leadingInset = 15.0, _trailingInset = 11.0;

/// Bottom transport bar: progress on top, playback on the left, danmaku in
/// the middle, viewing options on the right. Everything sits on a gradient
/// over the video and stays white: the mint accent belongs to the light
/// panels.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.playback,
    required this.fullScreen,
    required this.dragging,
    required this.onDragStart,
    required this.onDragChanged,
    required this.onDragEnd,
    required this.onReveal,
    required this.onFullscreen,
    required this.onWindowFullScreen,
    required this.windowFullScreen,
    required this.danmakuMenuOpen,
    required this.onDanmakuMenu,
    required this.onPopupChanged,
    required this.onFeedback,
    required this.onStepFrame,
    required this.danmakuMenu,
    required this.danmakuDraft,
    required this.danmakuInput,
    required this.onDanmakuInputDone,
    required this.danmakuHint,
    this.danmakuMenuFocus,
    this.onNext,
  });
  final Playback playback;
  final bool fullScreen, windowFullScreen, danmakuMenuOpen;
  final VoidCallback onDanmakuMenu;
  final FocusNode? danmakuMenuFocus;

  /// The danmaku settings shown above their button while
  /// [danmakuMenuOpen], given how far they have faded in.
  final Widget Function(double visibility) danmakuMenu;

  /// The comment being written and its field.
  final TextEditingController danmakuDraft;
  final FocusNode danmakuInput;

  /// Gives the keys back to the video after sending or leaving the field.
  final VoidCallback onDanmakuInputDone;

  /// The comment field's empty line.
  final String danmakuHint;
  final ValueChanged<bool> onPopupChanged;
  final VoidCallback onWindowFullScreen;
  final double? dragging;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragChanged;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onReveal;
  final VoidCallback onFullscreen;
  final ValueChanged<String> onFeedback;
  final ValueChanged<bool> onStepFrame;
  final VoidCallback? onNext;
  Player get player => playback.player;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => playback.cancelAutoplay(),
    child: _transport(context),
  );

  List<({double at, String label})> get _marks => [
    if (playback.openingEnding?.opening case final opening?)
      (at: opening.end, label: 'OP 结束'),
    if (playback.openingEnding?.ending case final ending?)
      (at: ending.start, label: 'ED 开始'),
  ];

  Widget _transport(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(0, 56, 0, Gap.sm),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Color(0x99000000), Color(0xcc000000)],
        stops: [0, .55, 1],
      ),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: StreamBuilder<Duration>(
        stream: player.stream.position,
        initialData: player.state.position,
        builder: (context, position) {
          final duration = player.state.duration.inMilliseconds / 1000;
          final current = position.data!.inMilliseconds / 1000;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: pageGutter),
                child: StreamBuilder<Duration>(
                  stream: player.stream.buffer,
                  initialData: player.state.buffer,
                  builder: (_, buffer) => PlayerProgressBar(
                    position: dragging ?? current,
                    duration: duration,
                    buffered: buffer.data!.inMilliseconds / 1000,
                    marks: _marks,
                    onDragStart: onDragStart,
                    onDragChanged: onDragChanged,
                    onDragEnd: onDragEnd,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  pageGutter - _leadingInset,
                  0,
                  pageGutter - _trailingInset,
                  0,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 680;
                    final left = _left(current, duration);
                    final right = _right(context);
                    final danmaku = _danmaku();
                    return IconButtonTheme(
                      data: IconButtonThemeData(
                        style: ButtonStyle(
                          foregroundColor: const WidgetStatePropertyAll(
                            Colors.white,
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? Colors.white.withValues(alpha: .14)
                                : null,
                          ),
                          overlayColor: const WidgetStatePropertyAll(
                            Colors.white12,
                          ),
                          minimumSize: const WidgetStatePropertyAll(
                            Size(36, 36),
                          ),
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.all(6),
                          ),
                          iconSize: const WidgetStatePropertyAll(22),
                        ),
                      ),
                      child: wide
                          ? Row(
                              children: [
                                left,
                                const SizedBox(width: Gap.lg),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) => Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        ...danmaku,
                                        if (playback.danmaku.sendable &&
                                            constraints.maxWidth >=
                                                DanmakuComposer.minWidth + 80)
                                          Flexible(
                                            child: DanmakuComposer(
                                              playback: playback,
                                              draft: danmakuDraft,
                                              focusNode: danmakuInput,
                                              onPopupChanged: onPopupChanged,
                                              onFeedback: onFeedback,
                                              onDone: onDanmakuInputDone,
                                              hint: danmakuHint,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: Gap.lg),
                                right,
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                left,
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      ...danmaku,
                                      const SizedBox(width: Gap.lg),
                                      right,
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _left(double current, double duration) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: player.state.playing,
        builder: (_, playing) => IconButton(
          tooltip: playing.data == true ? '暂停 (Space)' : '播放 (Space)',
          iconSize: 28,
          onPressed: () {
            unawaited(playback.playOrPause());
            onReveal();
          },
          icon: Icon(
            playing.data == true
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
          ),
        ),
      ),
      IconButton(
        tooltip: '上一帧 (,)',
        onPressed: () => onStepFrame(false),
        icon: const PlayerGlyph(PlayerGlyphKind.previousFrame),
      ),
      IconButton(
        tooltip: '下一帧 (.)',
        onPressed: () => onStepFrame(true),
        icon: const PlayerGlyph(PlayerGlyphKind.nextFrame),
      ),
      if (onNext != null)
        IconButton(
          tooltip: '下一话',
          onPressed: onNext,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      PlayerVolumeControl(
        playback: playback,
        onFeedback: onFeedback,
        onPopupChanged: onPopupChanged,
      ),
      const SizedBox(width: Gap.sm),
      Text(
        '${formatTime(dragging ?? current)} / ${formatTime(duration)}',
        style: const TextStyle(
          fontSize: 12,
          color: Colors.white70,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );

  /// The danmaku switch and its settings, which open above the button.
  List<Widget> _danmaku() => [
    IconButton(
      tooltip: playback.danmakuEnabled ? '关闭弹幕 (D)' : '开启弹幕 (D)',
      onPressed: () {
        playback.toggleDanmaku();
        onFeedback(playback.danmakuEnabled ? '弹幕已开启' : '弹幕已关闭');
        onReveal();
      },
      icon: PlayerGlyph(
        playback.danmakuEnabled
            ? PlayerGlyphKind.danmaku
            : PlayerGlyphKind.danmakuOff,
      ),
    ),
    AnchoredPanel(
      open: danmakuMenuOpen,
      panel: danmakuMenu,
      child: IconButton(
        focusNode: danmakuMenuFocus,
        tooltip: '弹幕设置',
        isSelected: danmakuMenuOpen,
        onPressed: onDanmakuMenu,
        icon: const PlayerGlyph(PlayerGlyphKind.danmakuSettings),
      ),
    ),
  ];

  Widget _right(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SuperResolutionMenu(playback: playback, onPopupChanged: onPopupChanged),
      SpeedMenu(
        player: player,
        onPopupChanged: onPopupChanged,
        onFeedback: onFeedback,
      ),
      SubtitleMenu(playback: playback, onPopupChanged: onPopupChanged),
      IconButton(
        tooltip: windowFullScreen ? '退出窗口全屏' : '窗口全屏',
        onPressed: onWindowFullScreen,
        icon: Icon(
          windowFullScreen
              ? Icons.close_fullscreen_rounded
              : Icons.open_in_full_rounded,
          size: 18,
        ),
      ),
      IconButton(
        tooltip: fullScreen ? '退出全屏 (F)' : '全屏 (F)',
        onPressed: onFullscreen,
        icon: Icon(
          fullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          size: 24,
        ),
      ),
    ],
  );
}

enum PlayerGlyphKind {
  danmaku,
  danmakuOff,
  danmakuSettings,
  previousFrame,
  nextFrame,
}

/// Player icons Material lacks: the danmaku box (struck through when off,
/// with a cog for its settings) and the frame steps, a chevron with a dot.
class PlayerGlyph extends StatelessWidget {
  const PlayerGlyph(this.kind, {super.key});
  final PlayerGlyphKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 22;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GlyphPainter(kind, theme.color ?? Colors.white),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color);
  final PlayerGlyphKind kind;
  final Color color;

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
        canvas.drawCircle(const Offset(18, 17), 2.2, stroke);
        line(18, 13.3, 18, 14.6);
        line(18, 19.4, 18, 20.7);
        line(14.3, 17, 15.6, 17);
        line(20.4, 17, 21.7, 17);
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
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind || old.color != color;
}
