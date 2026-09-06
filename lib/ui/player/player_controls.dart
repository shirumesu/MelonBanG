import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'playback.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.playback,
    required this.fullScreen,
    required this.dragging,
    required this.onDragStart,
    required this.onDragChanged,
    required this.onDragEnd,
    required this.onSeekRelative,
    required this.onFocus,
    required this.onReveal,
    required this.onFullscreen,
    required this.onToggleDanmaku,
  });
  final Playback playback;
  final bool fullScreen;
  final double? dragging;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragChanged;
  final ValueChanged<double> onDragEnd;
  final ValueChanged<int> onSeekRelative;
  final VoidCallback onFocus;
  final VoidCallback onReveal;
  final VoidCallback onFullscreen;
  final VoidCallback onToggleDanmaku;
  Player get player => playback.player;
  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData.dark(useMaterial3: true),
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 35, 12, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: StreamBuilder<Duration>(
        stream: player.stream.position,
        initialData: player.state.position,
        builder: (context, position) {
          final duration = player.state.duration.inMilliseconds / 1000;
          final current = position.data!.inMilliseconds / 1000;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: (dragging ?? current).clamp(
                  0,
                  duration > 0 ? duration : 1,
                ),
                max: duration > 0 ? duration : 1,
                onChangeStart: onDragStart,
                onChanged: duration > 0 ? onDragChanged : null,
                onChangeEnd: onDragEnd,
              ),
              Row(
                children: [
                  StreamBuilder<bool>(
                    stream: player.stream.playing,
                    initialData: player.state.playing,
                    builder: (_, playing) => IconButton(
                      tooltip: '播放 / 暂停（空格）',
                      onPressed: () {
                        unawaited(player.playOrPause());
                        onFocus();
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
                    tooltip: '后退 5 秒',
                    onPressed: () => onSeekRelative(-5),
                    icon: const Icon(Icons.replay_5),
                  ),
                  IconButton(
                    tooltip: '前进 5 秒',
                    onPressed: () => onSeekRelative(5),
                    icon: const Icon(Icons.forward_5),
                  ),
                  Text(
                    '${formatTime(dragging ?? current)} / ${formatTime(duration)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '弹幕开关',
                    onPressed: onToggleDanmaku,
                    icon: Icon(
                      playback.danmakuEnabled
                          ? Icons.subtitles
                          : Icons.subtitles_off,
                    ),
                  ),
                  StreamBuilder<double>(
                    stream: player.stream.volume,
                    initialData: player.state.volume,
                    builder: (_, snapshot) => Row(
                      children: [
                        IconButton(
                          tooltip: '静音（M）',
                          onPressed: () =>
                              player.setVolume(snapshot.data! == 0 ? 80 : 0),
                          icon: Icon(
                            snapshot.data == 0
                                ? Icons.volume_off
                                : Icons.volume_up,
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Slider(
                            value: snapshot.data!.clamp(0, 100),
                            max: 100,
                            onChanged: (value) => player.setVolume(value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<double>(
                    tooltip: '播放速度',
                    onSelected: (value) => player.setRate(value),
                    itemBuilder: (_) => [.5, .75, 1.0, 1.25, 1.5, 2.0]
                        .map(
                          (rate) => PopupMenuItem(
                            value: rate,
                            child: Text('${rate}x'),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text('${player.state.rate}x'),
                    ),
                  ),
                  IconButton(
                    tooltip: '全屏（F）',
                    onPressed: onFullscreen,
                    icon: Icon(
                      fullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

String formatTime(double seconds) {
  final total = seconds.isFinite ? seconds.floor().clamp(0, 1 << 40) : 0;
  final minutes = (total ~/ 60).toString().padLeft(2, '0');
  return '$minutes:${(total % 60).toString().padLeft(2, '0')}';
}
