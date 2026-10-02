import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'playback.dart';
import 'player_theme.dart';

/// Bottom transport bar: progress on top, playback on the left, viewing
/// options on the right. Everything sits on a gradient over the video.
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
    required this.onMenu,
    required this.onWindowFullScreen,
    required this.windowFullScreen,
    required this.menu,
    required this.menuFocusNodes,
    required this.onPopupChanged,
    required this.panelOpen,
    required this.onTogglePanel,
    required this.onFeedback,
    this.nextLabel,
    this.onNext,
    this.lightsOff,
    this.onToggleLights,
  });
  final Playback playback;
  final bool fullScreen, windowFullScreen, panelOpen;
  final PlayerMenu? menu;
  final ValueChanged<PlayerMenu> onMenu;
  final Map<PlayerMenu, FocusNode> menuFocusNodes;
  final ValueChanged<bool> onPopupChanged;
  final VoidCallback onWindowFullScreen, onTogglePanel;
  final double? dragging;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragChanged;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onReveal;
  final VoidCallback onFullscreen;
  final ValueChanged<String> onFeedback;
  final String? nextLabel;
  final VoidCallback? onNext;
  final bool? lightsOff;
  final VoidCallback? onToggleLights;
  Player get player => playback.player;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(Gap.lg, 56, Gap.lg, Gap.sm),
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
              StreamBuilder<Duration>(
                stream: player.stream.buffer,
                initialData: player.state.buffer,
                builder: (_, buffer) => PlayerProgressBar(
                  position: dragging ?? current,
                  duration: duration,
                  buffered: buffer.data!.inMilliseconds / 1000,
                  onDragStart: onDragStart,
                  onDragChanged: onDragChanged,
                  onDragEnd: onDragEnd,
                ),
              ),
              const SizedBox(height: 2),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 680;
                  final left = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StreamBuilder<bool>(
                        stream: player.stream.playing,
                        initialData: player.state.playing,
                        builder: (_, playing) => IconButton(
                          tooltip: playing.data == true ? '暂停（空格）' : '播放（空格）',
                          iconSize: 28,
                          onPressed: () {
                            unawaited(player.playOrPause());
                            onReveal();
                          },
                          icon: Icon(
                            playing.data == true
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                      ),
                      if (nextLabel != null)
                        IconButton(
                          tooltip: nextLabel,
                          onPressed: onNext,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      PlayerVolumeControl(
                        playback: playback,
                        showSlider: wide,
                        onFeedback: onFeedback,
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
                  final right = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DanmakuToggle(
                        enabled: playback.danmakuEnabled,
                        onPressed: () {
                          playback.toggleDanmaku();
                          onFeedback(
                            playback.danmakuEnabled ? '弹幕已开启' : '弹幕已关闭',
                          );
                          onReveal();
                        },
                      ),
                      IconButton(
                        focusNode: menuFocusNodes[PlayerMenu.danmaku],
                        tooltip: '弹幕设置',
                        isSelected: menu == PlayerMenu.danmaku,
                        onPressed: () => onMenu(PlayerMenu.danmaku),
                        icon: const Icon(Icons.tune_rounded),
                      ),
                      _SpeedMenu(
                        player: player,
                        onPopupChanged: onPopupChanged,
                        onFeedback: onFeedback,
                        onReveal: onReveal,
                      ),
                      IconButton(
                        focusNode: menuFocusNodes[PlayerMenu.settings],
                        tooltip: '字幕与音轨',
                        isSelected: menu == PlayerMenu.settings,
                        onPressed: () => onMenu(PlayerMenu.settings),
                        icon: const Icon(Icons.closed_caption_outlined),
                      ),
                      if (lightsOff case final off?)
                        IconButton(
                          tooltip: off ? '开灯（L）' : '关灯（L）',
                          onPressed: onToggleLights,
                          // A lit bulb while the lights are on.
                          icon: Icon(
                            off
                                ? Icons.lightbulb_outline_rounded
                                : Icons.lightbulb_rounded,
                          ),
                        ),
                      _TextAction(
                        label: '选集',
                        tooltip: panelOpen ? '收起选集' : '展开选集与缓存',
                        selected: panelOpen,
                        onPressed: onTogglePanel,
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
                        tooltip: fullScreen ? '退出全屏（F）' : '全屏（F）',
                        onPressed: onFullscreen,
                        icon: Icon(
                          fullScreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          size: 24,
                        ),
                      ),
                    ],
                  );
                  return IconButtonTheme(
                    data: IconButtonThemeData(
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? mintOnDark
                              : Colors.white,
                        ),
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.white12,
                        ),
                        minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
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
            ],
          );
        },
      ),
    ),
  );
}

/// Thin seek bar that thickens on hover and shows the time under the pointer.
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onDragStart,
    required this.onDragChanged,
    required this.onDragEnd,
  });
  final double position, duration, buffered;
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
      final bubbleX = hoverX ?? (widget.position / widget.duration) * width;
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
                    final value = valueAt(details.localPosition.dx, width);
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
                          emphasis: emphasis,
                        ),
                      ),
                    ),
                  ),
                  if (active)
                    Positioned(
                      left: (bubbleX - 28).clamp(0, width - 56),
                      bottom: 24,
                      width: 56,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xe6151922),
                          borderRadius: badgeBorderRadius,
                        ),
                        child: Text(
                          formatTime(valueAt(bubbleX, width)),
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
    required this.emphasis,
  });
  final double played, buffered, emphasis;
  final double? hover;

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
    canvas.drawRRect(bar(played), Paint()..color = mintOnDark);
    if (emphasis > 0) {
      canvas.drawCircle(
        Offset(size.width * played.clamp(0.0, 1.0), size.height / 2),
        6.5 * emphasis,
        Paint()..color = mintOnDark,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.hover != hover ||
      old.emphasis != emphasis;
}

/// Mute button plus a volume slider; the wheel adjusts volume anywhere over it.
class PlayerVolumeControl extends StatelessWidget {
  const PlayerVolumeControl({
    super.key,
    required this.playback,
    required this.showSlider,
    required this.onFeedback,
  });
  final Playback playback;
  final bool showSlider;
  final ValueChanged<String> onFeedback;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) async {
      if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
      final volume = await playback.adjustVolume(
        event.scrollDelta.dy < 0 ? 5 : -5,
      );
      onFeedback('音量 ${volume.round()}%');
    },
    child: StreamBuilder<double>(
      stream: playback.player.stream.volume,
      initialData: playback.player.state.volume,
      builder: (context, snapshot) {
        final volume = snapshot.data!.clamp(0.0, 100.0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: volume == 0 ? '取消静音（M）' : '静音（M）',
              onPressed: playback.toggleMute,
              icon: Icon(
                volume == 0
                    ? Icons.volume_off_rounded
                    : volume < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
              ),
            ),
            if (showSlider)
              SizedBox(
                width: 84,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white12,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    value: volume,
                    max: 100,
                    semanticFormatterCallback: (value) =>
                        '音量 ${value.round()}%',
                    onChanged: playback.player.setVolume,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Bilibili-style "弹" switch: filled when danmaku is shown.
class _DanmakuToggle extends StatelessWidget {
  const _DanmakuToggle({required this.enabled, required this.onPressed});
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: enabled ? '关闭弹幕（D）' : '开启弹幕（D）',
    onPressed: onPressed,
    icon: AnimatedContainer(
      duration: motionDuration(context, 150),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? mintOnDark : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        border: Border.all(
          color: enabled ? mintOnDark : Colors.white70,
          width: 1.5,
        ),
      ),
      child: Text(
        '弹',
        style: TextStyle(
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w700,
          color: enabled ? const Color(0xff123a2a) : Colors.white70,
          decoration: enabled ? null : TextDecoration.lineThrough,
          decorationColor: Colors.white70,
        ),
      ),
    ),
  );
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });
  final String label, tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton(
      style: TextButton.styleFrom(
        foregroundColor: selected ? mintOnDark : Colors.white,
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
      final scheme = Theme.of(context).colorScheme;
      return MenuAnchor(
        onOpen: () {
          onPopupChanged(true);
          onReveal();
        },
        onClose: () {
          onPopupChanged(false);
          onReveal();
        },
        alignmentOffset: const Offset(0, -8),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuSurface(context)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: controlBorderRadius),
          ),
          elevation: const WidgetStatePropertyAll(6),
        ),
        menuChildren: [
          for (final value in rates)
            MenuItemButton(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(112, 36)),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: controlBorderRadius),
                ),
              ),
              onPressed: () {
                unawaited(player.setRate(value));
                onFeedback('倍速 ${speedLabel(value)}');
              },
              leadingIcon: SizedBox.square(
                dimension: 18,
                child: value == rate
                    ? Icon(Icons.check_rounded, size: 17, color: scheme.primary)
                    : null,
              ),
              child: Text(
                value == 1 ? '正常' : speedLabel(value),
                style: TextStyle(
                  color: value == rate ? scheme.primary : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
        builder: (context, controller, _) => _TextAction(
          label: rate == 1 ? '倍速' : speedLabel(rate),
          tooltip: '播放速度',
          selected: rate != 1 || controller.isOpen,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      );
    },
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
