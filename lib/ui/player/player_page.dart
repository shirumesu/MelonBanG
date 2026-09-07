import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app_services.dart';
import '../core/theme.dart';
import 'danmaku.dart';
import 'playback.dart';
import 'player_controls.dart';
import 'player_settings.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.playback,
    required this.service,
    required this.onOpen,
    required this.onBack,
    required this.onError,
    required this.fullScreen,
    required this.onFullScreenChanged,
    this.subject,
    required this.onEpisode,
  });
  final Playback playback;
  final AppServices service;
  final VoidCallback onOpen, onBack;
  final void Function(Object) onError;
  final bool fullScreen;
  final Future<void> Function(bool) onFullScreenChanged;
  final Json? subject;
  final void Function(Json) onEpisode;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final focus = FocusNode();
  bool panel = true, controls = true;
  double? dragging;
  Timer? hideTimer;
  String? _sessionId;
  Playback get playback => widget.playback;
  Player get player => playback.player;
  @override
  void initState() {
    super.initState();
    _sessionId = playback.session?['id'] as String?;
    playback.addListener(refresh);
  }

  void refresh() {
    final sessionId = playback.session?['id'] as String?;
    if (sessionId != _sessionId) {
      _sessionId = sessionId;
      dragging = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    playback.removeListener(refresh);
    focus.dispose();
    hideTimer?.cancel();
    super.dispose();
  }

  void reveal() {
    if (!mounted) return;
    if (!controls) setState(() => controls = true);
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && player.state.playing && dragging == null) {
        setState(() => controls = false);
      }
    });
  }

  Future<void> seekRelative(int seconds) async {
    final maximum = player.state.duration.inMilliseconds;
    final target = (player.state.position.inMilliseconds + seconds * 1000)
        .clamp(0, maximum > 0 ? maximum : 1 << 40);
    await player.seek(Duration(milliseconds: target));
    reveal();
  }

  Future<void> fullscreen() async {
    await widget.onFullScreenChanged(!widget.fullScreen);
    if (mounted) focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: appTheme(true),
    child: Material(
      color: const Color(0xff0a0f14),
      child: Builder(builder: _buildBody),
    ),
  );

  Widget _buildBody(BuildContext context) {
    if (playback.uri == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline,
              size: 72,
              color: Color(0xff22b388),
            ),
            const SizedBox(height: 18),
            const Text(
              '选一部作品，开始观看',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('本地视频 · 内嵌字幕 · 音轨切换'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: widget.onOpen,
              icon: const Icon(Icons.folder_open),
              label: const Text('打开视频'),
            ),
            if (widget.fullScreen)
              TextButton.icon(
                onPressed: () => widget.onFullScreenChanged(false),
                icon: const Icon(Icons.fullscreen_exit),
                label: const Text('退出全屏'),
              ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              if (!widget.fullScreen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 12, 12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '返回探索',
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Text(
                          '${playback.session?['title'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: '播放设置',
                        onPressed: () {
                          setState(() => panel = !panel);
                          if (!panel) focus.requestFocus();
                        },
                        icon: Icon(panel ? Icons.chevron_right : Icons.tune),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Focus(
                  focusNode: focus,
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.space) {
                      unawaited(player.playOrPause());
                    } else if (event.logicalKey ==
                        LogicalKeyboardKey.arrowRight) {
                      unawaited(seekRelative(5));
                    } else if (event.logicalKey ==
                        LogicalKeyboardKey.arrowLeft) {
                      unawaited(seekRelative(-5));
                    } else if (event.logicalKey == LogicalKeyboardKey.keyF ||
                        event.logicalKey == LogicalKeyboardKey.f11) {
                      unawaited(fullscreen());
                    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                      unawaited(widget.onFullScreenChanged(false));
                    } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
                      unawaited(
                        player.setVolume(player.state.volume == 0 ? 80 : 0),
                      );
                    } else {
                      return KeyEventResult.ignored;
                    }
                    reveal();
                    return KeyEventResult.handled;
                  },
                  child: MouseRegion(
                    onHover: (_) => reveal(),
                    cursor: controls
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.none,
                    child: GestureDetector(
                      onTap: () {
                        focus.requestFocus();
                        reveal();
                      },
                      onDoubleTap: fullscreen,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Video(
                            controller: playback.video,
                            controls: NoVideoControls,
                            subtitleViewConfiguration:
                                const SubtitleViewConfiguration(visible: false),
                          ),
                          DanmakuLayer(playback: playback),
                          if (playback.opening)
                            const Center(child: CircularProgressIndicator()),
                          StreamBuilder<bool>(
                            stream: player.stream.buffering,
                            initialData: player.state.buffering,
                            builder: (_, snapshot) => snapshot.data == true
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          if (playback.error != null)
                            Center(
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 440,
                                ),
                                padding: const EdgeInsets.all(24),
                                color: Colors.black87,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.orange,
                                      size: 38,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      playback.error!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: widget.onOpen,
                                      child: const Text('选择其他视频'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (controls)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: PlayerControls(
                                playback: playback,
                                fullScreen: widget.fullScreen,
                                dragging: dragging,
                                onDragStart: (value) {
                                  setState(() => dragging = value);
                                  hideTimer?.cancel();
                                },
                                onDragChanged: (value) =>
                                    setState(() => dragging = value),
                                onDragEnd: (value) async {
                                  await player.seek(
                                    Duration(
                                      milliseconds: (value * 1000).round(),
                                    ),
                                  );
                                  if (mounted) setState(() => dragging = null);
                                  reveal();
                                },
                                onSeekRelative: seekRelative,
                                onFocus: focus.requestFocus,
                                onReveal: reveal,
                                onFullscreen: fullscreen,
                                onToggleDanmaku: () => setState(
                                  () => playback.danmakuEnabled =
                                      !playback.danmakuEnabled,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Preserve panel drafts while hidden, without intercepting video shortcuts.
        ExcludeFocus(
          excluding: !panel || widget.fullScreen,
          child: Offstage(
            offstage: !panel || widget.fullScreen,
            child: SizedBox(
              width: 290,
              child: PlayerSettings(
                playback: playback,
                service: widget.service,
                subject: widget.subject,
                onEpisode: widget.onEpisode,
                onError: widget.onError,
                onPresentationChanged: refresh,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
