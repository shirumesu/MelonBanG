import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/motion.dart';
import '../core/theme.dart';
import '../../features/playback/playback.dart';
import 'player_theme.dart';

/// Horizontal room before the play glyph and after the fullscreen glyph inside
/// their buttons, so the glyphs line up with the title and the timeline.
const _leadingInset = 15.0, _trailingInset = 11.0;

/// Bottom transport bar: progress on top, playback on the left, viewing
/// options on the right. Everything sits on a gradient over the video and
/// stays white: the mint accent belongs to the light panels.
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
    this.danmakuMenuFocus,
    this.onNext,
  });
  final Playback playback;
  final bool fullScreen, windowFullScreen, danmakuMenuOpen;
  final VoidCallback onDanmakuMenu;
  final FocusNode? danmakuMenuFocus;
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
                          ? Row(children: [left, const Spacer(), right])
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                left,
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: right,
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

  Widget _right(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
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
      IconButton(
        focusNode: danmakuMenuFocus,
        tooltip: '弹幕设置',
        isSelected: danmakuMenuOpen,
        onPressed: onDanmakuMenu,
        icon: const PlayerGlyph(PlayerGlyphKind.danmakuSettings),
      ),
      _SpeedMenu(
        player: player,
        onPopupChanged: onPopupChanged,
        onFeedback: onFeedback,
        onReveal: onReveal,
      ),
      _SubtitleMenu(
        playback: playback,
        onPopupChanged: onPopupChanged,
        onReveal: onReveal,
      ),
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
                        child: Text(
                          hovered == null
                              ? formatTime(valueAt(bubbleX, width))
                              : '${formatTime(hovered.at)}  ${hovered.label}',
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

/// Mute button; hovering it raises a vertical volume slider above it, and the
/// wheel adjusts volume anywhere over either.
class PlayerVolumeControl extends StatefulWidget {
  const PlayerVolumeControl({
    super.key,
    required this.playback,
    required this.onFeedback,
    required this.onPopupChanged,
  });
  final Playback playback;
  final ValueChanged<String> onFeedback;
  final ValueChanged<bool> onPopupChanged;

  @override
  State<PlayerVolumeControl> createState() => _PlayerVolumeControlState();
}

class _PlayerVolumeControlState extends State<PlayerVolumeControl> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _hide;
  bool _overButton = false, _overSlider = false, _sliding = false;
  Player get player => widget.playback.player;

  @override
  void dispose() {
    _hide?.cancel();
    // A slider still open would keep the controls from ever hiding.
    if (_portal.isShowing) {
      final changed = widget.onPopupChanged;
      scheduleMicrotask(() => changed(false));
    }
    super.dispose();
  }

  /// Shows the slider while the pointer is over the button or the slider,
  /// and lets it close shortly after leaving both.
  void _update() {
    _hide?.cancel();
    if (_overButton || _overSlider || _sliding) {
      if (!_portal.isShowing) {
        _portal.show();
        widget.onPopupChanged(true);
      }
      return;
    }
    _hide = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || !_portal.isShowing) return;
      _portal.hide();
      widget.onPopupChanged(false);
    });
  }

  Future<void> _wheel(PointerSignalEvent event) async {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final volume = await widget.playback.adjustVolume(
      event.scrollDelta.dy < 0 ? 5 : -5,
    );
    widget.onFeedback('音量 ${volume.round()}%');
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _wheel,
    child: CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            child: Listener(onPointerSignal: _wheel, child: _slider()),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) {
            _overButton = true;
            _update();
          },
          onExit: (_) {
            _overButton = false;
            _update();
          },
          child: StreamBuilder<double>(
            stream: player.stream.volume,
            initialData: player.state.volume,
            builder: (context, snapshot) {
              final volume = snapshot.data!;
              return IconButton(
                onPressed: widget.playback.toggleMute,
                icon: Icon(
                  volume == 0
                      ? Icons.volume_off_rounded
                      : volume < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _slider() => MouseRegion(
    onEnter: (_) {
      _overSlider = true;
      _update();
    },
    onExit: (_) {
      _overSlider = false;
      _update();
    },
    child: Padding(
      // Bridges the gap to the button so the pointer never falls between.
      padding: const EdgeInsets.only(bottom: 4),
      child: Theme(
        data: overlayTheme(),
        child: Material(
          color: overlaySurface,
          borderRadius: controlBorderRadius,
          elevation: 6,
          child: SizedBox(
            width: 40,
            height: 150,
            child: StreamBuilder<double>(
              stream: player.stream.volume,
              initialData: player.state.volume,
              builder: (context, snapshot) {
                final volume = snapshot.data!.clamp(0.0, 100.0);
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      '${volume.round()}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Slider(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          value: volume,
                          max: 100,
                          semanticFormatterCallback: (value) =>
                              '音量 ${value.round()}%',
                          onChangeStart: (_) => _sliding = true,
                          onChangeEnd: (_) {
                            _sliding = false;
                            _update();
                          },
                          onChanged: player.setVolume,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
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

/// A text control in the transport, such as the speed.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.open = false,
  });
  final String label, tooltip;
  final VoidCallback? onPressed;
  final bool open;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: open ? Colors.white.withValues(alpha: .14) : null,
        overlayColor: Colors.white,
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}

/// A dark menu over the video whose rows mark the current choice.
class _OverlayMenu extends StatelessWidget {
  const _OverlayMenu({
    required this.onPopupChanged,
    required this.onReveal,
    required this.items,
    required this.builder,
  });
  final ValueChanged<bool> onPopupChanged;
  final VoidCallback onReveal;
  final List<({String label, bool selected, VoidCallback onPressed})> items;
  final Widget Function(MenuController controller) builder;

  @override
  Widget build(BuildContext context) => Theme(
    data: overlayTheme(),
    child: MenuAnchor(
      onOpen: () {
        onPopupChanged(true);
        onReveal();
      },
      onClose: () {
        onPopupChanged(false);
        onReveal();
      },
      alignmentOffset: const Offset(0, -8),
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(120, 34)),
              backgroundColor: WidgetStatePropertyAll(
                item.selected ? Colors.white.withValues(alpha: .1) : null,
              ),
              shape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: badgeBorderRadius),
              ),
            ),
            onPressed: item.onPressed,
            leadingIcon: SizedBox.square(
              dimension: 16,
              child: item.selected
                  ? const Icon(Icons.check_rounded, size: 16)
                  : null,
            ),
            child: Text(
              item.label,
              style: TextStyle(
                fontWeight: item.selected ? FontWeight.w700 : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => builder(controller),
    ),
  );
}

class _SpeedMenu extends StatelessWidget {
  const _SpeedMenu({
    required this.player,
    required this.onPopupChanged,
    required this.onFeedback,
    required this.onReveal,
  });
  final Player player;
  final ValueChanged<bool> onPopupChanged;
  final ValueChanged<String> onFeedback;
  final VoidCallback onReveal;

  static const rates = [2.0, 1.5, 1.25, 1.0, .75, .5];

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
    stream: player.stream.rate,
    initialData: player.state.rate,
    builder: (context, snapshot) {
      final rate = snapshot.data!;
      return _OverlayMenu(
        onPopupChanged: onPopupChanged,
        onReveal: onReveal,
        items: [
          for (final value in rates)
            (
              label: speedLabel(value),
              selected: value == rate,
              onPressed: () {
                unawaited(player.setRate(value));
                onFeedback('倍速 ${speedLabel(value)}');
              },
            ),
        ],
        builder: (controller) => _TextAction(
          label: rate == 1 ? '倍速' : speedLabel(rate),
          tooltip: '播放速度',
          open: controller.isOpen,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      );
    },
  );
}

/// Subtitle tracks of the file; audio follows the language preference in
/// settings and has no menu here.
class _SubtitleMenu extends StatelessWidget {
  const _SubtitleMenu({
    required this.playback,
    required this.onPopupChanged,
    required this.onReveal,
  });
  final Playback playback;
  final ValueChanged<bool> onPopupChanged;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) => StreamBuilder<Track>(
    stream: playback.player.stream.track,
    initialData: playback.player.state.track,
    builder: (context, current) => StreamBuilder<Tracks>(
      stream: playback.player.stream.tracks,
      initialData: playback.player.state.tracks,
      builder: (context, tracks) {
        final selected = current.data!.subtitle;
        final all = tracks.data!.subtitle;
        final ordered = [
          ...all.where((track) => track.id == 'auto'),
          ...all.where((track) => track.id != 'auto' && track.id != 'no'),
          ...all.where((track) => track.id == 'no'),
        ];
        return _OverlayMenu(
          onPopupChanged: onPopupChanged,
          onReveal: onReveal,
          items: [
            for (final track in ordered)
              (
                label: switch (track.id) {
                  'no' => '关闭字幕',
                  'auto' => '自动',
                  _ => track.title ?? track.language ?? '字幕 ${track.id}',
                },
                selected: track == selected,
                onPressed: () => unawaited(playback.selectSubtitle(track)),
              ),
          ],
          builder: (controller) => IconButton(
            tooltip: '字幕',
            isSelected: controller.isOpen,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.closed_caption_outlined),
          ),
        );
      },
    ),
  );
}

String speedLabel(double rate) =>
    '${rate == rate.roundToDouble() ? rate.toStringAsFixed(1) : rate}x';

String formatTime(double seconds) {
  final total = seconds.isFinite ? seconds.floor().clamp(0, 1 << 40) : 0;
  final hours = total ~/ 3600;
  final minutes = (total % 3600 ~/ 60).toString().padLeft(2, '0');
  final rest = (total % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$rest' : '$minutes:$rest';
}
