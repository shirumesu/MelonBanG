import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../features/playback/playback.dart';
import '../core/motion.dart';
import '../core/overlay_glass.dart';
import '../core/theme.dart';
import 'danmaku_composer.dart';
import 'player_glyphs.dart';
import 'player_menus.dart';
import 'player_popovers.dart';
import 'player_progress_bar.dart';
import 'player_settings.dart';

/// Video widths at which the transport gives up room; see
/// [PlayerControls._buttons].
const _fullWidth = 720.0, _trimmedWidth = 620.0, _bareWidth = 520.0;

/// The small window's width below which volume leaves its bar too.
const _miniVolumeWidth = 400.0;

/// Room before a glyph that starts [margin] units into Material's 24-unit
/// grid, drawn at [size] in the middle of a button [side] wide.
double _inset(double side, double size, double margin) =>
    (side - size) / 2 + margin * size / 24;

/// The transport bar on a gradient over the video: progress on top,
/// playback left, danmaku in the middle, viewing options right. It stays
/// white; the mint accent belongs to the light panels.
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
    required this.mini,
    required this.onMini,
    this.danmakuMenuFocus,
    this.danmakuMenuGroup,
    this.onDanmakuMenuOutside,
  });
  final Playback playback;
  final bool fullScreen, windowFullScreen, danmakuMenuOpen;
  final VoidCallback onDanmakuMenu;
  final FocusNode? danmakuMenuFocus;

  /// The tap region group the danmaku settings belong to, and what a tap
  /// outside it does while they are open.
  final Object? danmakuMenuGroup;
  final VoidCallback? onDanmakuMenuOutside;

  /// The danmaku settings shown above their button while
  /// [danmakuMenuOpen], given how far they have faded in.
  final Widget Function(double visibility) danmakuMenu;

  final TextEditingController danmakuDraft;
  final FocusNode danmakuInput;

  /// Gives the keys back to the video after sending or leaving the field.
  final VoidCallback onDanmakuInputDone;
  final String danmakuHint;
  final ValueChanged<bool> onPopupChanged;
  final VoidCallback onWindowFullScreen;

  /// The small window's bar, without the menus; see [_buttons].
  final bool mini;
  final VoidCallback onMini;
  final double? dragging;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragChanged;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onReveal;
  final VoidCallback onFullscreen;
  final ValueChanged<String> onFeedback;
  final ValueChanged<bool> onStepFrame;
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
    padding: EdgeInsets.fromLTRB(0, mini ? Gap.xl : 56, 0, Gap.sm),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, overlayScrim, Color(0xcc000000)],
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
  /// shrink; below [_trimmedWidth] volume (still on ↑↓), subtitles, the
  /// small window and window fullscreen leave; below [_bareWidth] the frame
  /// steps (still on , and .) leave too. The small window keeps small
  /// buttons and none of the menus or frame steps, and volume while it is
  /// [_miniVolumeWidth] wide.
  Widget _buttons(double width) {
    final compact = mini || width < _fullWidth;
    final trimmed = mini || width < _trimmedWidth;
    final bare = mini || width < _bareWidth;
    final volume = mini ? width >= _miniVolumeWidth : !trimmed;
    final side = compact ? 32.0 : 36.0;
    final padding = compact ? 4.0 : 6.0;
    final icon = compact ? 20.0 : 22.0;
    final play = compact ? 26.0 : 28.0;
    final fullscreenIcon = compact ? 22.0 : 24.0;
    final gap = compact ? Gap.sm : Gap.lg;
    // Line the first and last glyphs up with the title and the timeline.
    final leading = _inset(math.max(side, play + padding * 2), play, 8);
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
                  ? overlayFillActive
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
            _left(play: play, volume: volume, frames: !bare),
            SizedBox(width: gap),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ..._danmaku(),
                    // Beside the two danmaku buttons, where it fits.
                    if (playback.danmaku.sendable &&
                        constraints.maxWidth >=
                            (mini
                                    ? DanmakuComposer.compactMinWidth
                                    : DanmakuComposer.minWidth) +
                                side * 2 +
                                Gap.sm)
                      Flexible(
                        child: DanmakuComposer(
                          playback: playback,
                          draft: danmakuDraft,
                          focusNode: danmakuInput,
                          onPopupChanged: onPopupChanged,
                          onFeedback: onFeedback,
                          onDone: onDanmakuInputDone,
                          hint: danmakuHint,
                          compact: mini,
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
    required double play,
    required bool volume,
    required bool frames,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
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
      if (frames) ...[
        IconHover(
          child: IconButton(
            tooltip: '上一帧 (,)',
            onPressed: () => onStepFrame(false),
            icon: const GestureIcon(
              IconGesture.back,
              child: PlayerGlyph(PlayerGlyphKind.previousFrame),
            ),
          ),
        ),
        IconHover(
          child: IconButton(
            tooltip: '下一帧 (.)',
            onPressed: () => onStepFrame(true),
            icon: const GestureIcon(
              IconGesture.forward,
              child: PlayerGlyph(PlayerGlyphKind.nextFrame),
            ),
          ),
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
            fontSize: FontSize.small,
            color: overlayMuted,
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
      tapGroup: danmakuMenuGroup,
      onTapOutside: onDanmakuMenuOutside,
      child: IconHover(
        child: IconButton(
          focusNode: danmakuMenuFocus,
          tooltip: '弹幕设置',
          isSelected: danmakuMenuOpen,
          onPressed: onDanmakuMenu,
          icon: const PlayerGlyph(PlayerGlyphKind.danmakuSettings),
        ),
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
      if (mini)
        IconHover(
          child: IconButton(
            tooltip: '回到窗口 (Esc)',
            onPressed: onMini,
            icon: const GestureIcon(
              IconGesture.swell,
              child: Icon(Icons.open_in_full_rounded, size: 16),
            ),
          ),
        )
      else ...[
        PlaybackMenu(playback: playback, onPopupChanged: onPopupChanged),
        if (Playback.superResolutionAvailable)
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
          IconHover(
            child: IconButton(
              tooltip: '小窗播放',
              onPressed: onMini,
              icon: GestureIcon(
                IconGesture.swell,
                child: Icon(
                  Icons.picture_in_picture_alt_rounded,
                  size: compact ? 18 : 20,
                ),
              ),
            ),
          ),
          IconHover(
            child: IconButton(
              tooltip: windowFullScreen ? '退出窗口全屏' : '窗口全屏',
              onPressed: onWindowFullScreen,
              icon: GestureIcon(
                IconGesture.swell,
                child: MotionSwap(
                  value: windowFullScreen,
                  child: Icon(
                    windowFullScreen
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    size: compact ? 16 : 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
      IconHover(
        child: IconButton(
          tooltip: fullScreen ? '退出全屏 (F)' : '全屏 (F)',
          onPressed: onFullscreen,
          icon: GestureIcon(
            IconGesture.swell,
            child: MotionSwap(
              value: fullScreen,
              child: Icon(
                fullScreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                size: fullscreenIcon,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
