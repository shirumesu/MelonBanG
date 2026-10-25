import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/motion.dart';
import '../core/theme.dart';
import '../../features/playback/playback.dart';
import 'danmaku_composer.dart';
import 'player_menus.dart';
import 'player_popovers.dart';
import 'player_progress_bar.dart';
import 'player_settings.dart';

/// Video widths below which the transport shrinks its buttons, then drops
/// the less used ones, then the frame steps; see [PlayerControls._buttons].
const _fullWidth = 720.0, _trimmedWidth = 620.0, _bareWidth = 520.0;

/// Room before a glyph that starts [margin] units into Material's 24-unit
/// grid, drawn at [size] in the middle of a button [side] wide.
double _inset(double side, double size, double margin) =>
    (side - size) / 2 + margin * size / 24;

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
    this.onPrevious,
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

  /// Shown together, each disabled at its end of the episodes.
  final VoidCallback? onPrevious, onNext;
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: pageGutter),
            child: StreamBuilder<Duration>(
              stream: player.stream.buffer,
              initialData: player.state.buffer,
              builder: (_, buffer) => _position(
                (current, duration) => PlayerProgressBar(
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
          ),
          const SizedBox(height: 2),
          LayoutBuilder(
            builder: (context, constraints) => _buttons(constraints.maxWidth),
          ),
        ],
      ),
    ),
  );

  /// Rebuilds [builder] as the playhead moves, in seconds.
  Widget _position(Widget Function(double current, double duration) builder) =>
      StreamBuilder<Duration>(
        stream: player.stream.position,
        initialData: player.state.position,
        builder: (_, position) => builder(
          position.data!.inMilliseconds / 1000,
          player.state.duration.inMilliseconds / 1000,
        ),
      );

  /// The button row for a video [width] wide. Below [_fullWidth] the buttons
  /// shrink; below [_trimmedWidth] volume (still on ↑↓), subtitles and window
  /// fullscreen leave; below [_bareWidth] the frame steps (still on , and .)
  /// leave too.
  Widget _buttons(double width) {
    final compact = width < _fullWidth;
    final trimmed = width < _trimmedWidth;
    final bare = width < _bareWidth;
    final side = compact ? 32.0 : 36.0;
    final padding = compact ? 4.0 : 6.0;
    final icon = compact ? 20.0 : 22.0;
    final play = compact ? 26.0 : 28.0;
    final fullscreenIcon = compact ? 22.0 : 24.0;
    final gap = compact ? Gap.sm : Gap.lg;
    final episodes = onPrevious != null || onNext != null;
    // Line the first and last glyphs up with the title and the timeline.
    final leading = episodes
        ? _inset(side, icon, 6)
        : _inset(math.max(side, play + padding * 2), play, 8);
    final trailing = _inset(
      math.max(side, fullscreenIcon + padding * 2),
      fullscreenIcon,
      5,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        pageGutter - leading,
        0,
        pageGutter - trailing,
        0,
      ),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? Colors.white38
                  : Colors.white,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white.withValues(alpha: .14)
                  : null,
            ),
            overlayColor: const WidgetStatePropertyAll(Colors.white12),
            minimumSize: WidgetStatePropertyAll(Size.square(side)),
            padding: WidgetStatePropertyAll(EdgeInsets.all(padding)),
            iconSize: WidgetStatePropertyAll(icon),
          ),
        ),
        child: Row(
          children: [
            _left(
              episodes: episodes,
              play: play,
              volume: !trimmed,
              frames: !bare,
            ),
            SizedBox(width: gap),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ..._danmaku(),
                    if (playback.danmaku.sendable &&
                        constraints.maxWidth >= DanmakuComposer.minWidth + 80)
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
            SizedBox(width: gap),
            _right(
              compact: compact,
              trimmed: trimmed,
              fullscreenIcon: fullscreenIcon,
            ),
          ],
        ),
      ),
    );
  }

  Widget _left({
    required bool episodes,
    required double play,
    required bool volume,
    required bool frames,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (episodes)
        IconButton(
          tooltip: '上一话',
          onPressed: onPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
      StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: player.state.playing,
        builder: (_, playing) => IconButton(
          tooltip: playing.data == true ? '暂停 (Space)' : '播放 (Space)',
          iconSize: play,
          onPressed: () {
            unawaited(playback.playOrPause());
            onReveal();
          },
          icon: MotionSwap(
            value: playing.data == true,
            scale: .6,
            child: Icon(
              playing.data == true
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
          ),
        ),
      ),
      if (episodes)
        IconButton(
          tooltip: '下一话',
          onPressed: onNext,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      if (frames) ...[
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
      ],
      if (volume)
        PlayerVolumeControl(
          playback: playback,
          onFeedback: onFeedback,
          onPopupChanged: onPopupChanged,
        ),
      const SizedBox(width: Gap.sm),
      _position(
        (current, duration) => Text(
          '${formatTime(dragging ?? current)} / ${formatTime(duration)}',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
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
      icon: MotionSwap(
        value: playback.danmakuEnabled,
        child: PlayerGlyph(
          playback.danmakuEnabled
              ? PlayerGlyphKind.danmaku
              : PlayerGlyphKind.danmakuOff,
        ),
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

  Widget _right({
    required bool compact,
    required bool trimmed,
    required double fullscreenIcon,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PlaybackMenu(playback: playback, onPopupChanged: onPopupChanged),
      SuperResolutionMenu(
        playback: playback,
        onPopupChanged: onPopupChanged,
        compact: compact,
      ),
      SpeedMenu(
        player: player,
        onPopupChanged: onPopupChanged,
        onFeedback: onFeedback,
      ),
      if (!trimmed) ...[
        SubtitleMenu(playback: playback, onPopupChanged: onPopupChanged),
        IconButton(
          tooltip: windowFullScreen ? '退出窗口全屏' : '窗口全屏',
          onPressed: onWindowFullScreen,
          icon: MotionSwap(
            value: windowFullScreen,
            child: Icon(
              windowFullScreen
                  ? Icons.close_fullscreen_rounded
                  : Icons.open_in_full_rounded,
              size: compact ? 16 : 18,
            ),
          ),
        ),
      ],
      IconButton(
        tooltip: fullScreen ? '退出全屏 (F)' : '全屏 (F)',
        onPressed: onFullscreen,
        icon: MotionSwap(
          value: fullScreen,
          child: Icon(
            fullScreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            size: fullscreenIcon,
          ),
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
  settings,
}

/// Player icons Material lacks: the danmaku box (struck through when off,
/// with a cog for its settings), the frame steps, a chevron with a dot, and
/// a solid six-tooth cog, plainer and smaller than Material's settings.
class PlayerGlyph extends StatelessWidget {
  const PlayerGlyph(this.kind, {super.key});
  final PlayerGlyphKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SizedBox.square(
      dimension: theme.size,
      child: CustomPaint(painter: _GlyphPainter(kind, theme.color!)),
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
      old.kind != kind || old.color != color;
}
