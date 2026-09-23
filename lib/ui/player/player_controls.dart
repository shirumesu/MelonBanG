import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/theme.dart';
import 'playback.dart';
import 'player_theme.dart';

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
    required this.onReveal,
    required this.onFullscreen,
    required this.onMenu,
    required this.onWindowFullScreen,
    required this.windowFullScreen,
    required this.menu,
    required this.menuFocusNodes,
    required this.onPopupChanged,
  });
  final Playback playback;
  final bool fullScreen, windowFullScreen;
  final PlayerMenu? menu;
  final ValueChanged<PlayerMenu> onMenu;
  final Map<PlayerMenu, FocusNode> menuFocusNodes;
  final ValueChanged<bool> onPopupChanged;
  final VoidCallback onWindowFullScreen;
  final double? dragging;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragChanged;
  final ValueChanged<double> onDragEnd;
  final ValueChanged<int> onSeekRelative;
  final VoidCallback onReveal;
  final VoidCallback onFullscreen;
  Player get player => playback.player;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 35, 12, 6),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black54],
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
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  showValueIndicator: ShowValueIndicator.onlyForContinuous,
                  activeTrackColor: mintOnDark,
                  thumbColor: mintOnDark,
                  inactiveTrackColor: Colors.white24,
                ),
                child: Slider(
                  value: (dragging ?? current).clamp(
                    0,
                    duration > 0 ? duration : 1,
                  ),
                  max: duration > 0 ? duration : 1,
                  onChangeStart: onDragStart,
                  onChanged: duration > 0 ? onDragChanged : null,
                  onChangeEnd: onDragEnd,
                  label: formatTime(dragging ?? current),
                  semanticFormatterCallback: formatTime,
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final primary = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StreamBuilder<bool>(
                        stream: player.stream.playing,
                        initialData: player.state.playing,
                        builder: (_, playing) => IconButton(
                          tooltip: '播放 / 暂停（空格）',
                          color: mintOnDark,
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
                    ],
                  );
                  final secondary = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in [
                        (PlayerMenu.audio, '音轨', Icons.graphic_eq),
                        (PlayerMenu.danmaku, '弹幕', Icons.chat_bubble_outline),
                      ])
                        IconButton(
                          focusNode: menuFocusNodes[entry.$1],
                          tooltip: entry.$2,
                          isSelected: menu == entry.$1,
                          onPressed: () => onMenu(entry.$1),
                          icon: Icon(entry.$3),
                        ),
                      StreamBuilder<double>(
                        stream: player.stream.volume,
                        initialData: player.state.volume,
                        builder: (_, snapshot) => IconButton(
                          tooltip: snapshot.data == 0 ? '取消静音（M）' : '静音（M）',
                          onPressed: playback.toggleMute,
                          icon: Icon(
                            snapshot.data == 0
                                ? Icons.volume_off
                                : Icons.volume_up,
                          ),
                        ),
                      ),
                      StreamBuilder<double>(
                        stream: player.stream.rate,
                        initialData: player.state.rate,
                        builder: (_, snapshot) => PopupMenuButton<double>(
                          tooltip: '播放速度',
                          onOpened: () {
                            onPopupChanged(true);
                            onReveal();
                          },
                          onCanceled: () => onPopupChanged(false),
                          onSelected: (value) {
                            player.setRate(value);
                            onPopupChanged(false);
                            onReveal();
                          },
                          itemBuilder: (_) => [.5, .75, 1.0, 1.25, 1.5, 2.0]
                              .map(
                                (rate) => PopupMenuItem(
                                  value: rate,
                                  child: Text('${rate}x'),
                                ),
                              )
                              .toList(),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              '${snapshot.data}x',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        focusNode: menuFocusNodes[PlayerMenu.subtitles],
                        tooltip: '播放设置',
                        isSelected: menu == PlayerMenu.subtitles,
                        onPressed: () => onMenu(PlayerMenu.subtitles),
                        icon: const Icon(Icons.tune),
                      ),
                      IconButton(
                        tooltip: windowFullScreen ? '退出窗口全屏' : '窗口全屏',
                        onPressed: onWindowFullScreen,
                        icon: Icon(
                          windowFullScreen
                              ? Icons.close_fullscreen
                              : Icons.fit_screen,
                        ),
                      ),
                      IconButton(
                        tooltip: fullScreen ? '退出显示屏全屏（F）' : '显示屏全屏（F）',
                        onPressed: onFullscreen,
                        icon: Icon(
                          fullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        ),
                      ),
                    ],
                  );
                  return IconButtonTheme(
                    data: IconButtonThemeData(
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(34, 36),
                        padding: const EdgeInsets.all(7),
                        iconSize: 20,
                      ),
                    ),
                    child: constraints.maxWidth >= 600
                        ? Row(children: [primary, const Spacer(), secondary])
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              primary,
                              Align(
                                alignment: Alignment.centerRight,
                                child: secondary,
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

String formatTime(double seconds) {
  final total = seconds.isFinite ? seconds.floor().clamp(0, 1 << 40) : 0;
  final minutes = (total ~/ 60).toString().padLeft(2, '0');
  return '$minutes:${(total % 60).toString().padLeft(2, '0')}';
}
