import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../features/playback/playback.dart';
import '../../features/playback/super_resolution.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import 'player_popovers.dart';

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
  Widget build(BuildContext context) => HoverPopover(
    onPopupChanged: onPopupChanged,
    onPointerSignal: _wheel,
    anchor: (_) => StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snapshot) {
        final volume = snapshot.data!;
        final icon = volume == 0
            ? Icons.volume_off_rounded
            : volume < 50
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;
        return IconButton(
          onPressed: playback.toggleMute,
          icon: MotionSwap(value: icon, child: Icon(icon)),
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
                  fontWeight: FontWeight.w700,
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
      textStyle: appFont.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

class SpeedMenu extends StatelessWidget {
  const SpeedMenu({
    super.key,
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
      return HoverPopover(
        onPopupChanged: onPopupChanged,
        anchor: (popover) => _TextAction(
          label: rate == 1 ? '倍速' : speedLabel(rate),
          open: popover.open,
          onPressed: popover.toggle,
        ),
        popover: (popover) => ChoiceList(
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
/// names the resolution it renders unless [compact]. Hovering shows the
/// exact sizes and the chain.
class SuperResolutionMenu extends StatelessWidget {
  const SuperResolutionMenu({
    super.key,
    required this.playback,
    required this.onPopupChanged,
    required this.compact,
  });
  final Playback playback;
  final ValueChanged<bool> onPopupChanged;
  final bool compact;

  static const _chains = {'fast': '效率', 'quality': '质量'};

  String _size(Size size) => '${size.width.round()}×${size.height.round()}';

  @override
  Widget build(BuildContext context) {
    final mode = playback.settings.superResolution;
    final on = mode != 'off';
    final upscale = playback.upscale;
    final output = upscale?.output;
    return HoverPopover(
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
          textStyle: appFont.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: () => unawaited(playback.toggleSuperResolution()),
        icon: on ? const Icon(Icons.auto_awesome_rounded, size: 15) : null,
        label: Text(
          output == null || compact ? '超分' : '${resolutionLabel(output)} 超分',
        ),
      ),
      popover: (popover) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
          ChoiceList(
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

/// Subtitle tracks of the file; audio follows the language preference in
/// settings and has no menu here.
class SubtitleMenu extends StatelessWidget {
  const SubtitleMenu({
    super.key,
    required this.playback,
    required this.onPopupChanged,
  });
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
        return HoverPopover(
          onPopupChanged: onPopupChanged,
          anchor: (popover) => IconButton(
            isSelected: popover.open,
            onPressed: popover.toggle,
            icon: const Icon(Icons.closed_caption_outlined),
          ),
          popover: (popover) => ChoiceList(
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
