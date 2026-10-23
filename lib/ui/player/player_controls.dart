import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/error_message.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../../domain/danmaku.dart';
import '../../features/danmaku/danmaku_preferences.dart';
import '../../features/playback/playback.dart';
import '../../features/playback/super_resolution.dart';
import 'player_theme.dart';

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
                                                _DanmakuComposer.minWidth + 80)
                                          Flexible(
                                            child: _DanmakuComposer(
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
    _AnchoredPanel(
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
      _SuperResolutionMenu(playback: playback, onPopupChanged: onPopupChanged),
      _SpeedMenu(
        player: player,
        onPopupChanged: onPopupChanged,
        onFeedback: onFeedback,
      ),
      _SubtitleMenu(playback: playback, onPopupChanged: onPopupChanged),
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
class PlayerVolumeControl extends StatelessWidget {
  const PlayerVolumeControl({
    super.key,
    required this.playback,
    required this.onFeedback,
    required this.onPopupChanged,
  });
  final Playback playback;
  final ValueChanged<String> onFeedback;
  final ValueChanged<bool> onPopupChanged;
  Player get player => playback.player;

  Future<void> _wheel(PointerSignalEvent event) async {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final volume = await playback.adjustVolume(
      event.scrollDelta.dy < 0 ? 5 : -5,
    );
    onFeedback('音量 ${volume.round()}%');
  }

  @override
  Widget build(BuildContext context) => _HoverPopover(
    onPopupChanged: onPopupChanged,
    onPointerSignal: _wheel,
    anchor: (_) => StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snapshot) {
        final volume = snapshot.data!;
        return IconButton(
          onPressed: playback.toggleMute,
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
    popover: (popover) => SizedBox(
      width: 40,
      height: 140,
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
                  fontWeight: FontWeight.w600,
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
                    onChangeStart: (_) => popover.hold(true),
                    onChangeEnd: (_) => popover.hold(false),
                    onChanged: player.setVolume,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// A control whose popover rises above it while the pointer rests on either,
/// and closes shortly after leaving both. Clicking the control toggles it as
/// well, for the keyboard; a click elsewhere closes it.
class _HoverPopover extends StatefulWidget {
  const _HoverPopover({
    required this.onPopupChanged,
    required this.anchor,
    required this.popover,
    this.onPointerSignal,
  });
  final ValueChanged<bool> onPopupChanged;
  final Widget Function(_HoverPopoverState popover) anchor, popover;
  final void Function(PointerSignalEvent)? onPointerSignal;

  @override
  State<_HoverPopover> createState() => _HoverPopoverState();
}

class _HoverPopoverState extends State<_HoverPopover>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  late final _fade = AnimationController(vsync: this);
  Timer? _timer;
  bool open = false;
  bool _overAnchor = false, _overPopover = false, _held = false;

  @override
  void dispose() {
    _timer?.cancel();
    _fade.dispose();
    // A popover still open would keep the controls from ever hiding.
    if (open) {
      final changed = widget.onPopupChanged;
      scheduleMicrotask(() => changed(false));
    }
    super.dispose();
  }

  void _show() {
    _timer?.cancel();
    if (open) return;
    setState(() => open = true);
    _portal.show();
    _fade.duration = motionDuration(context, 140);
    _fade.forward();
    widget.onPopupChanged(true);
  }

  void close() {
    _timer?.cancel();
    // The popover's region disappears without an exit event.
    _overPopover = _held = false;
    if (!open) return;
    setState(() => open = false);
    widget.onPopupChanged(false);
    _fade.reverse().whenComplete(() {
      if (mounted && !open) _portal.hide();
    });
  }

  void toggle() => open ? close() : _show();

  /// Keeps the popover open while a slider in it is dragged past its edge.
  void hold(bool value) {
    _held = value;
    _update();
  }

  /// Opens after a short rest so sweeping across the bar does not flash
  /// every popover on the way.
  void _update() {
    _timer?.cancel();
    final wanted = _overAnchor || _overPopover || _held;
    if (wanted == open) return;
    _timer = Timer(Duration(milliseconds: wanted ? 90 : 180), () {
      if (!mounted) return;
      wanted ? _show() : close();
    });
  }

  @override
  Widget build(BuildContext context) => TapRegion(
    groupId: this,
    onTapOutside: (_) => close(),
    child: Listener(
      onPointerSignal: widget.onPointerSignal,
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder: (context, info) => CustomSingleChildLayout(
          delegate: _AboveAnchor(
            MatrixUtils.transformRect(
              info.childPaintTransform,
              Offset.zero & info.childSize,
            ),
          ),
          child: _popover(),
        ),
        child: MouseRegion(
          onEnter: (_) {
            _overAnchor = true;
            _update();
          },
          onExit: (_) {
            _overAnchor = false;
            _update();
          },
          child: widget.anchor(this),
        ),
      ),
    ),
  );

  // Fading out, it no longer catches the pointer, which would reopen it.
  Widget _popover() => TapRegion(
    groupId: this,
    child: IgnorePointer(
      ignoring: !open,
      child: Listener(
        onPointerSignal: widget.onPointerSignal,
        child: MouseRegion(
          hitTestBehavior: HitTestBehavior.opaque,
          onEnter: (_) {
            _overPopover = true;
            _update();
          },
          onExit: (_) {
            _overPopover = false;
            _update();
          },
          child: Padding(
            // Bridges the gap to the control so the pointer never falls between.
            padding: const EdgeInsets.only(bottom: 6),
            child: AnimatedBuilder(
              animation: _fade,
              builder: (context, child) {
                final value = Curves.easeOutCubic.transform(_fade.value);
                return Transform.translate(
                  offset: Offset(0, 4 * (1 - value)),
                  child: OverlayGlass(visibility: value, child: child!),
                );
              },
              child: Theme(data: overlayTheme(), child: widget.popover(this)),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A panel held open above its control by the page, such as the danmaku
/// settings; unlike [_HoverPopover] it stays until closed.
class _AnchoredPanel extends StatefulWidget {
  const _AnchoredPanel({
    required this.open,
    required this.panel,
    required this.child,
  });
  final bool open;
  final Widget Function(double visibility) panel;
  final Widget child;

  @override
  State<_AnchoredPanel> createState() => _AnchoredPanelState();
}

class _AnchoredPanelState extends State<_AnchoredPanel>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  late final _fade = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      _fade.value = 1;
      _portal.show();
    }
  }

  @override
  void didUpdateWidget(_AnchoredPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    _fade.duration = motionDuration(context);
    if (widget.open) {
      _portal.show();
      _fade.forward();
    } else {
      _fade.reverse().whenComplete(() {
        if (mounted && !widget.open) _portal.hide();
      });
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
    controller: _portal,
    overlayChildBuilder: (context, info) => CustomSingleChildLayout(
      delegate: _AboveAnchor(
        MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: IgnorePointer(
          ignoring: !widget.open,
          child: AnimatedBuilder(
            animation: _fade,
            builder: (context, _) {
              final value = Curves.easeOutCubic.transform(_fade.value);
              // The glass fades itself: an Opacity around its backdrop blur
              // would blur nothing on some renderers.
              return Transform.translate(
                offset: Offset(0, 5 * (1 - value)),
                child: Transform.scale(
                  scale: .98 + .02 * value,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(width: 312, child: widget.panel(value)),
                ),
              );
            },
          ),
        ),
      ),
    ),
    child: widget.child,
  );
}

/// Centres the popover above its control, kept inside the window.
class _AboveAnchor extends SingleChildLayoutDelegate {
  _AboveAnchor(this.anchor);
  final Rect anchor;
  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.max(0, constraints.maxWidth - 2 * _margin),
          math.max(0, anchor.top - _margin),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (anchor.center.dx - childSize.width / 2).clamp(
      _margin,
      math.max(_margin, size.width - childSize.width - _margin),
    ),
    anchor.top - childSize.height,
  );

  @override
  bool shouldRelayout(_AboveAnchor old) => old.anchor != anchor;
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
    required this.onPressed,
    this.open = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool open;

  @override
  Widget build(BuildContext context) => TextButton(
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
  );
}

typedef _Choice = ({String label, bool selected, VoidCallback onPressed});

/// The choices in a popover; the current one is filled white like the
/// segmented choices in the danmaku settings. Choosing closes the popover.
class _ChoiceList extends StatelessWidget {
  const _ChoiceList({required this.items, required this.popover});
  final List<_Choice> items;
  final _HoverPopoverState popover;

  static const _ink = Color(0xff15181d);

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 76, maxWidth: 220),
    child: IntrinsicWidth(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              Material(
                color: item.selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  overlayColor: WidgetStatePropertyAll(
                    (item.selected ? _ink : Colors.white).withValues(alpha: .1),
                  ),
                  onTap: () {
                    item.onPressed();
                    popover.close();
                  },
                  child: Container(
                    height: 30,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: item.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: item.selected ? _ink : Colors.white,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SpeedMenu extends StatelessWidget {
  const _SpeedMenu({
    required this.player,
    required this.onPopupChanged,
    required this.onFeedback,
  });
  final Player player;
  final ValueChanged<bool> onPopupChanged;
  final ValueChanged<String> onFeedback;

  static const rates = [2.0, 1.5, 1.25, 1.0, .75, .5];

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
    stream: player.stream.rate,
    initialData: player.state.rate,
    builder: (context, snapshot) {
      final rate = snapshot.data!;
      return _HoverPopover(
        onPopupChanged: onPopupChanged,
        anchor: (popover) => _TextAction(
          label: rate == 1 ? '倍速' : speedLabel(rate),
          open: popover.open,
          onPressed: popover.toggle,
        ),
        popover: (popover) => _ChoiceList(
          popover: popover,
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
        ),
      );
    },
  );
}

/// Anime4K super-resolution: clicking turns it on or off, and the label
/// names the resolution it renders. Hovering shows the exact sizes and the
/// chain.
class _SuperResolutionMenu extends StatelessWidget {
  const _SuperResolutionMenu({
    required this.playback,
    required this.onPopupChanged,
  });
  final Playback playback;
  final ValueChanged<bool> onPopupChanged;

  static const _chains = {'fast': '效率', 'quality': '质量'};

  String _size(Size size) => '${size.width.round()}×${size.height.round()}';

  @override
  Widget build(BuildContext context) {
    final mode = playback.settings.superResolution;
    final on = mode != 'off';
    final upscale = playback.upscale;
    final output = upscale?.output;
    return _HoverPopover(
      onPopupChanged: onPopupChanged,
      anchor: (popover) => TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: on ? Colors.white : Colors.white70,
          backgroundColor: popover.open
              ? Colors.white.withValues(alpha: .14)
              : null,
          overlayColor: Colors.white,
          minimumSize: const Size(44, 36),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        onPressed: () => unawaited(playback.toggleSuperResolution()),
        icon: on ? const Icon(Icons.auto_awesome_rounded, size: 15) : null,
        label: Text(output == null ? '超分' : '${resolutionLabel(output)} 超分'),
      ),
      popover: (popover) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: Text(
              switch (upscale) {
                _ when !on => 'Anime4K 放大到窗口分辨率',
                (:final source, output: final output?) =>
                  '${_size(source)} → ${_size(output)}',
                (:final source, output: null) =>
                  '${_size(source)} 原生\n画面不小于窗口，只修复线条',
                null => '打开视频后放大到窗口分辨率',
              },
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Colors.white70,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _ChoiceList(
            popover: popover,
            items: [
              for (final MapEntry(:key, :value) in {
                ..._chains,
                'off': '关闭',
              }.entries)
                (
                  label: value,
                  selected: key == mode,
                  onPressed: () => unawaited(playback.setSuperResolution(key)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The comment field: its look on the left, sending on the right. Enter
/// sends, an empty Enter or Escape gives the keys back to the video.
class _DanmakuComposer extends StatefulWidget {
  const _DanmakuComposer({
    required this.playback,
    required this.draft,
    required this.focusNode,
    required this.onPopupChanged,
    required this.onFeedback,
    required this.onDone,
    required this.hint,
  });
  final Playback playback;
  final TextEditingController draft;
  final FocusNode focusNode;
  final ValueChanged<bool> onPopupChanged;
  final ValueChanged<String> onFeedback;
  final VoidCallback onDone;

  /// The empty field's line while it can send.
  final String hint;

  /// The narrowest it is shown at; the field keeps about eight characters.
  static const minWidth = 220.0;

  @override
  State<_DanmakuComposer> createState() => _DanmakuComposerState();
}

class _DanmakuComposerState extends State<_DanmakuComposer> {
  bool _sending = false;

  /// Counts down the wait between comments.
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Whole seconds until the next comment may go.
  int get _wait {
    final after = widget.playback.danmaku.sendAfter;
    if (after == null) return 0;
    final left = after.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  void _countDown() {
    _tick?.cancel();
    if (_wait == 0) return;
    _tick = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {});
      if (_wait == 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    final text = widget.draft.text.trim();
    if (text.isEmpty) {
      widget.onDone();
      return;
    }
    if (_wait case final wait when wait > 0) {
      widget.onFeedback('$wait 秒后才能再发送');
      return;
    }
    if (_sending) return;
    setState(() => _sending = true);
    final player = widget.playback.player;
    try {
      await widget.playback.danmaku.send(
        player.state.position.inMilliseconds / 1000,
        text,
      );
      widget.draft.clear();
      widget.onDone();
    } catch (e) {
      widget.onFeedback(
        e is StateError ? errorMessage(e) : '弹幕发送失败：${errorMessage(e)}',
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _countDown();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final danmaku = widget.playback.danmaku;
    final blocked = danmaku.sendBlocked;
    final wait = _wait;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: _DanmakuComposer.minWidth,
        maxWidth: 400,
      ),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(
          children: [
            _SendStyleMenu(
              preferences: danmaku.preferences,
              onPopupChanged: widget.onPopupChanged,
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.draft,
                builder: (context, _) => TextField(
                  controller: widget.draft,
                  focusNode: widget.focusNode,
                  enabled: blocked == null,
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  inputFormatters: [LengthLimitingTextInputFormatter(100)],
                  onSubmitted: (_) => unawaited(_send()),
                  cursorColor: Colors.white,
                  cursorHeight: 15,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintText: blocked ?? widget.hint,
                    hintMaxLines: 1,
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Colors.white38,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(3),
              child: ListenableBuilder(
                listenable: widget.draft,
                builder: (context, _) => FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xff15181d),
                    disabledBackgroundColor: Colors.white.withValues(
                      alpha: .12,
                    ),
                    disabledForegroundColor: Colors.white38,
                    minimumSize: const Size(52, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed:
                      blocked == null &&
                          !_sending &&
                          wait == 0 &&
                          widget.draft.text.trim().isNotEmpty
                      ? () => unawaited(_send())
                      : null,
                  child: Text(
                    wait > 0 ? '$wait 秒' : '发送',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How a sent comment looks: where it runs and its colour. The A shows the
/// colour chosen.
class _SendStyleMenu extends StatelessWidget {
  const _SendStyleMenu({
    required this.preferences,
    required this.onPopupChanged,
  });
  final DanmakuPreferences preferences;
  final ValueChanged<bool> onPopupChanged;

  /// Bilibili's palette for sending.
  static const colors = [
    0xfe0302, 0xff7204, 0xffaa02, 0xffd302, 0xffff00, 0xa0ee00, 0x00cd00, //
    0x019899, 0x4266be, 0x89d5ff, 0xcc0273, 0x222222, 0x9b9b9b, 0xffffff,
  ];
  static const modes = {
    DanmakuMode.scroll: '滚动',
    DanmakuMode.top: '顶部',
    DanmakuMode.bottom: '底部',
  };
  static const _ink = Color(0xff15181d);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: preferences.sendStyle,
    builder: (context, style, _) => _HoverPopover(
      onPopupChanged: onPopupChanged,
      anchor: (popover) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          overlayColor: const WidgetStatePropertyAll(Colors.white12),
          onTap: popover.toggle,
          child: SizedBox(
            width: 34,
            height: 30,
            child: Center(
              child: Text(
                'A',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff000000 | style.color),
                  shadows: const [Shadow(blurRadius: 2)],
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white54,
                ),
              ),
            ),
          ),
        ),
      ),
      popover: (popover) => Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: SizedBox(
          width: 7 * 26 + 6 * 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 28,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: badgeBorderRadius,
                ),
                child: Row(
                  children: [
                    for (final MapEntry(key: mode, value: label)
                        in modes.entries)
                      Expanded(
                        child: Material(
                          color: mode == style.mode
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => preferences.sendStyle.value = (
                              mode: mode,
                              color: style.color,
                            ),
                            child: Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: mode == style.mode
                                      ? _ink
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final color in colors)
                    Semantics(
                      selected: color == style.color,
                      label: '#${color.toRadixString(16).padLeft(6, '0')}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => preferences.sendStyle.value = (
                          mode: style.mode,
                          color: color,
                        ),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Color(0xff000000 | color),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: color == style.color
                                  ? Colors.white
                                  : Colors.white24,
                              width: color == style.color ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Subtitle tracks of the file; audio follows the language preference in
/// settings and has no menu here.
class _SubtitleMenu extends StatelessWidget {
  const _SubtitleMenu({required this.playback, required this.onPopupChanged});
  final Playback playback;
  final ValueChanged<bool> onPopupChanged;

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
        return _HoverPopover(
          onPopupChanged: onPopupChanged,
          anchor: (popover) => IconButton(
            isSelected: popover.open,
            onPressed: popover.toggle,
            icon: const Icon(Icons.closed_caption_outlined),
          ),
          popover: (popover) => _ChoiceList(
            popover: popover,
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
