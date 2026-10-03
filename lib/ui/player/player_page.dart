import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app_services.dart';
import '../../data/play_candidates.dart';
import '../core/motion.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'danmaku.dart';
import 'playback.dart';
import 'player_controls.dart';
import 'player_library_panel.dart';
import 'player_resource_sheet.dart';
import 'player_settings.dart';
import 'player_theme.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.playback,
    required this.service,
    required this.onBack,
    required this.onError,
    required this.fullScreen,
    required this.onFullScreenChanged,
    required this.onEpisode,
    this.subject,
    this.preparing,
    this.onRetryPreparing,
    this.onChoosePreparing,
    required this.downloads,
    this.windowFullScreen = false,
    this.onWindowFullScreenChanged,
    this.onPlayFile,
    this.onPlayCandidate,
    this.onFindAllResources,
    this.lightsOff,
    this.onLightsChanged,
  });
  final Playback playback;
  final AppServices service;
  final VoidCallback onBack;
  final ValueChanged<Object> onError;
  final bool fullScreen, windowFullScreen;
  final Future<void> Function(bool) onFullScreenChanged;
  final Future<void> Function(bool)? onWindowFullScreenChanged;
  final Json? subject;

  /// Set while the player was opened before a source started; see
  /// `preparePlayback` in app.dart.
  final Json? preparing;
  final VoidCallback? onRetryPreparing, onChoosePreparing;
  final ValueListenable<Json> downloads;
  final ValueChanged<Json> onEpisode;
  final void Function(String id, String? fileId)? onPlayFile;
  final Future<void> Function(PlayCandidate candidate, Json episode)?
  onPlayCandidate;
  final ValueChanged<Json?>? onFindAllResources;

  /// Null when the app theme is already dark and there are no lights to switch.
  final bool? lightsOff;
  final ValueChanged<bool>? onLightsChanged;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final focus = FocusNode();
  final menuCloseFocus = FocusNode();
  final menuFocusNodes = {
    for (final menu in PlayerMenu.values) menu: FocusNode(),
  };

  /// Null until the first layout picks a default from the window width.
  bool? panel;
  bool controls = true, panelBeforeImmersive = true;
  bool controlsHovered = false, controlsFocused = false, controlsPopup = false;
  bool resourcesOpen = false;
  int? resourceEpisode;
  PlayerMenu? menu;
  PlayerMenu lastMenu = PlayerMenu.settings;
  double? dragging;
  String? feedback;
  Timer? hideTimer, feedbackTimer;
  StreamSubscription<bool>? playingSubscription;
  String? sessionId, lastNotice;
  Playback get playback => widget.playback;
  Player get player => playback.player;
  bool get immersive => widget.fullScreen || widget.windowFullScreen;

  @override
  void initState() {
    super.initState();
    sessionId = playback.session?['id'] as String?;
    playback.addListener(refresh);
    playingSubscription = player.stream.playing.listen((_) => reveal());
  }

  @override
  void didUpdateWidget(PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject?['subjectId'] != widget.subject?['subjectId']) {
      resourcesOpen = false;
      resourceEpisode = null;
    }
    final wasImmersive = oldWidget.fullScreen || oldWidget.windowFullScreen;
    if (!wasImmersive && immersive) {
      panelBeforeImmersive = panel ?? true;
      panel = false;
    } else if (wasImmersive && !immersive) {
      panel = panelBeforeImmersive;
    }
    if (oldWidget.fullScreen != widget.fullScreen ||
        oldWidget.windowFullScreen != widget.windowFullScreen) {
      menu = null;
      controls = true;
      // Shell changes reparent the player; restore focus after it reattaches.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus.requestFocus();
      });
    }
  }

  void refresh() {
    if (!mounted) return;
    if (playback.notice != null && playback.notice != lastNotice) {
      lastNotice = playback.notice;
      showFeedback(lastNotice!);
    }
    final next = playback.session?['id'] as String?;
    if (next != sessionId) {
      sessionId = next;
      dragging = null;
      menu = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    playback.removeListener(refresh);
    playback.cancelAutoplay(notify: false);
    unawaited(playingSubscription?.cancel());
    focus.dispose();
    menuCloseFocus.dispose();
    for (final node in menuFocusNodes.values) {
      node.dispose();
    }
    hideTimer?.cancel();
    feedbackTimer?.cancel();
    super.dispose();
  }

  void reveal() {
    if (!mounted) return;
    if (!controls) setState(() => controls = true);
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          player.state.playing &&
          dragging == null &&
          menu == null &&
          !controlsHovered &&
          !controlsFocused &&
          !controlsPopup &&
          !resourcesOpen) {
        setState(() => controls = false);
      }
    });
  }

  /// Brief on-screen confirmation for actions without a visible control.
  void showFeedback(String text) {
    feedbackTimer?.cancel();
    setState(() => feedback = text);
    feedbackTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => feedback = null);
    });
  }

  void toggleLights() {
    playback.cancelAutoplay();
    final off = widget.lightsOff;
    if (off == null) return;
    widget.onLightsChanged?.call(!off);
    showFeedback(off ? '已开灯' : '已关灯');
  }

  void togglePanel() {
    playback.cancelAutoplay();
    setState(() => panel = !(panel ?? false));
    focus.requestFocus();
    reveal();
  }

  /// The next episode by order, with whether it can be played right away.
  (Json, bool)? get nextEpisode {
    final episodes = objects(widget.subject?['episodes']);
    final index = episodes.indexWhere(
      (e) => e['episodeId'] == playback.session?['episodeId'],
    );
    if (index < 0 || index + 1 >= episodes.length) return null;
    final next = episodes[index + 1];
    final id = next['episodeId'] as int;
    final tasks = subjectTasks(
      widget.downloads.value,
      widget.subject?['subjectId'] as int?,
    );
    return (next, playableTask(widget.downloads.value, tasks, id) != null);
  }

  void toggleMenu(PlayerMenu value) {
    playback.cancelAutoplay();
    resourcesOpen = false;
    if (menu == value) {
      closeMenu();
      return;
    }
    setState(() {
      menu = value;
      lastMenu = value;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && menu == value) menuCloseFocus.requestFocus();
    });
    reveal();
  }

  void closeMenu() {
    final trigger = menuFocusNodes[menu];
    setState(() => menu = null);
    (trigger ?? focus).requestFocus();
    reveal();
  }

  void findResources(Json? episode) {
    playback.cancelAutoplay();
    setState(() {
      resourceEpisode = episode?['episodeId'] as int?;
      resourcesOpen = true;
      menu = null;
    });
    reveal();
  }

  void closeResources() {
    setState(() => resourcesOpen = false);
    focus.requestFocus();
    reveal();
  }

  Future<void> seekRelative(int seconds) async {
    playback.cancelAutoplay();
    final maximum = player.state.duration.inMilliseconds;
    final target = (player.state.position.inMilliseconds + seconds * 1000)
        .clamp(0, maximum > 0 ? maximum : 1 << 40);
    await player.seek(Duration(milliseconds: target));
    showFeedback(seconds > 0 ? '快进 $seconds 秒' : '快退 ${-seconds} 秒');
    reveal();
  }

  Future<void> changeVolume(double delta) async {
    final volume = await playback.adjustVolume(delta);
    if (mounted) showFeedback('音量 ${volume.round()}%');
  }

  Future<void> fullscreen() async {
    playback.cancelAutoplay();
    await widget.onFullScreenChanged(!widget.fullScreen);
    if (mounted) {
      focus.requestFocus();
      reveal();
    }
  }

  Future<void> windowFullscreen() async {
    playback.cancelAutoplay();
    await widget.onWindowFullScreenChanged?.call(!widget.windowFullScreen);
    if (mounted) {
      focus.requestFocus();
      reveal();
    }
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        playback.autoplayTarget != null) {
      playback.cancelAutoplay();
      return KeyEventResult.handled;
    }
    if (resourcesOpen && event.logicalKey == LogicalKeyboardKey.escape) {
      closeResources();
      return KeyEventResult.handled;
    }
    if (menu != null) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        closeMenu();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.period ||
        event.logicalKey == LogicalKeyboardKey.comma) {
      unawaited(stepFrame(event.logicalKey == LogicalKeyboardKey.period));
    } else if (event.logicalKey == LogicalKeyboardKey.space) {
      playback.cancelAutoplay();
      unawaited(playback.playOrPause());
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      unawaited(seekRelative(5));
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      unawaited(seekRelative(-5));
    } else if (event.logicalKey == LogicalKeyboardKey.keyF ||
        event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(fullscreen());
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (widget.fullScreen) {
        unawaited(widget.onFullScreenChanged(false));
      } else if (widget.windowFullScreen) {
        unawaited(widget.onWindowFullScreenChanged?.call(false));
      }
    } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
      final muting = player.state.volume > 0;
      unawaited(playback.toggleMute());
      showFeedback(muting ? '已静音' : '已取消静音');
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      unawaited(changeVolume(5));
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      unawaited(changeVolume(-5));
    } else if (event.logicalKey == LogicalKeyboardKey.keyL &&
        widget.lightsOff != null) {
      toggleLights();
    } else if (event.logicalKey == LogicalKeyboardKey.keyD) {
      playback.toggleDanmaku();
      showFeedback(playback.danmakuEnabled ? '弹幕已开启' : '弹幕已关闭');
    } else {
      return KeyEventResult.ignored;
    }
    reveal();
    return KeyEventResult.handled;
  }

  Future<void> stepFrame(bool forward) async {
    try {
      final position = await playback.stepFrame(forward);
      if (!mounted) return;
      final milliseconds = position.inMilliseconds;
      final hours = (milliseconds ~/ 3600000).toString().padLeft(2, '0');
      final minutes = ((milliseconds ~/ 60000) % 60).toString().padLeft(2, '0');
      final seconds = ((milliseconds ~/ 1000) % 60).toString().padLeft(2, '0');
      final fraction = (milliseconds % 1000).toString().padLeft(3, '0');
      showFeedback(
        '${forward ? '下一帧' : '上一帧'} · $hours:$minutes:$seconds.$fraction',
      );
    } catch (e) {
      widget.onError(e);
    }
  }

  String get title {
    if (widget.subject == null) return '${playback.session?['title'] ?? '播放器'}';
    final episode = objects(widget.subject?['episodes'])
        .where((e) => e['episodeId'] == playback.session?['episodeId'])
        .firstOrNull;
    return '${titleOf(widget.subject!)}${episode == null ? '' : ' · 第 ${episode['sort']} 话'}';
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: playerTheme(Theme.of(context)),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      child: Builder(builder: body),
    ),
  );

  Widget body(BuildContext context) {
    if (widget.preparing case final preparing?) {
      return _PreparingView(
        preparing: preparing,
        onRetry: widget.onRetryPreparing,
        onChoose: widget.onChoosePreparing,
        onFindResources: () =>
            widget.onFindAllResources?.call(object(preparing['episode'])),
      );
    }
    if (playback.uri == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_outline, size: 48),
            const SizedBox(height: 16),
            Text(playback.error ?? '选一部作品，开始观看'),
            TextButton(onPressed: widget.onBack, child: const Text('返回')),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Open the episode list by default only when the video keeps room.
        final showPanel = panel ??= constraints.maxWidth >= 1080;
        final panelWidth = constraints.maxWidth < 900 ? 296.0 : 336.0;
        final libraryWidth = math.min(panelWidth, constraints.maxWidth * .45);
        final videoWidth =
            constraints.maxWidth - (showPanel ? libraryWidth : 0);
        final transportInset = videoWidth < 680 ? 136.0 : 108.0;
        return Stack(
          children: [
            Row(
              children: [
                Expanded(child: video(context)),
                ExcludeFocus(
                  excluding: !showPanel,
                  child: IgnorePointer(
                    ignoring: !showPanel,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: showPanel ? 1 : 0),
                      duration: motionDuration(context, 220),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, child) => Offstage(
                        offstage: value == 0,
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: value,
                            child: child,
                          ),
                        ),
                      ),
                      child: SizedBox(
                        width: libraryWidth,
                        child: ValueListenableBuilder<Json>(
                          valueListenable: widget.downloads,
                          builder: (context, downloads, _) =>
                              PlayerLibraryPanel(
                                key: ValueKey(playback.session?['subjectId']),
                                service: widget.service,
                                subjectId:
                                    playback.session?['subjectId'] as int?,
                                subject: widget.subject,
                                episodeId:
                                    playback.session?['episodeId'] as int?,
                                title: '${playback.session?['title'] ?? '播放器'}',
                                downloads: downloads,
                                onEpisode: widget.onEpisode,
                                onFindResources: findResources,
                                onPlayFile: widget.onPlayFile ?? (_, _) {},
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.subject != null)
              Positioned(
                key: const ValueKey('player-resource-overlay'),
                left: 16,
                right: 16,
                bottom: transportInset,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ExcludeFocus(
                    excluding: !resourcesOpen,
                    child: IgnorePointer(
                      ignoring: !resourcesOpen,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: resourcesOpen ? 1 : 0),
                        duration: motionDuration(context, 220),
                        curve: Curves.easeOutCubic,
                        builder: (_, value, child) => Offstage(
                          offstage: value == 0,
                          child: Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 32 * (1 - value)),
                              child: child,
                            ),
                          ),
                        ),
                        child: SizedBox(
                          width: 1000,
                          height: math.max(
                            0,
                            math.min(
                              560,
                              constraints.maxHeight - transportInset - 24,
                            ),
                          ),
                          child: PlayerResourceSheet(
                            key: ValueKey(
                              'resource-sheet:${widget.subject!['subjectId']}',
                            ),
                            service: widget.service,
                            playback: playback,
                            onPlayCandidate: widget.onPlayCandidate,
                            onFindAllResources: widget.onFindAllResources,
                            subject: widget.subject!,
                            episodeId: resourceEpisode,
                            visible: resourcesOpen,
                            onClose: closeResources,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget video(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return Focus(
        focusNode: focus,
        autofocus: true,
        onKeyEvent: handleKey,
        child: MouseRegion(
          onHover: (_) => reveal(),
          cursor: controls || menu != null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.none,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: () {
                  playback.cancelAutoplay();
                  if (menu != null) {
                    closeMenu();
                  } else {
                    focus.requestFocus();
                    reveal();
                  }
                },
                onDoubleTap: fullscreen,
                child: Video(
                  controller: playback.video,
                  controls: NoVideoControls,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    visible: false,
                  ),
                ),
              ),
              DanmakuLayer(playback: playback),
              StreamBuilder<bool>(
                stream: player.stream.buffering,
                initialData: player.state.buffering,
                builder: (_, snapshot) =>
                    playback.opening || snapshot.data == true
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const SizedBox.shrink(),
              ),
              if (playback.error != null)
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(playback.error!),
                  ),
                ),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: player.state.playing,
                builder: (_, playing) => StreamBuilder<bool>(
                  stream: player.stream.buffering,
                  initialData: player.state.buffering,
                  builder: (_, buffering) {
                    final paused =
                        playing.data == false &&
                        buffering.data != true &&
                        !playback.opening &&
                        playback.error == null &&
                        !playback.frameStepping &&
                        menu == null;
                    return Center(
                      child: IgnorePointer(
                        ignoring: !paused,
                        child: AnimatedOpacity(
                          opacity: paused ? 1 : 0,
                          duration: motionDuration(context, 150),
                          child: AnimatedScale(
                            scale: paused ? 1 : .85,
                            duration: motionDuration(context, 150),
                            child: Material(
                              color: Colors.black45,
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: IconButton(
                                tooltip: '播放（空格）',
                                iconSize: 40,
                                padding: const EdgeInsets.all(14),
                                color: Colors.white,
                                onPressed: () {
                                  playback.cancelAutoplay();
                                  unawaited(playback.resume());
                                },
                                icon: const Icon(Icons.play_arrow_rounded),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                key: const ValueKey('player-feedback'),
                top: 64,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: feedback == null ? 0 : 1,
                      duration: motionDuration(context, 150),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xb3000000),
                          borderRadius: controlBorderRadius,
                        ),
                        child: Text(
                          feedback ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                key: const ValueKey('player-title'),
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: controls || menu != null ? 1 : 0,
                    duration: motionDuration(context),
                    curve: Curves.easeOutCubic,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(
                        pageGutter,
                        Gap.lg,
                        pageGutter,
                        Gap.xxl,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Colors.transparent],
                        ),
                      ),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (playback.autoplayTarget != null ||
                  playback.autoplayMessage != null)
                Positioned(
                  right: 20,
                  bottom: constraints.maxWidth < 680 ? 150 : 112,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            playback.autoplayTarget == null
                                ? playback.autoplayMessage!
                                : '即将播放第 ${playback.autoplayTarget!.episode['sort']} 话 · ${playback.autoplayTarget!.sourceLabel}',
                          ),
                          if (playback.autoplayTarget != null) ...[
                            const SizedBox(height: 8),
                            Text('${playback.autoplaySeconds} 秒后播放'),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: playback.playAutoplay,
                                  child: const Text('立即播放'),
                                ),
                                TextButton(
                                  onPressed: playback.cancelAutoplay,
                                  child: const Text('取消'),
                                ),
                              ],
                            ),
                          ] else if (playback.autoplayEndEpisode != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => findResources(
                                    playback.autoplayEndEpisode,
                                  ),
                                  child: const Text('查找资源'),
                                ),
                                if (widget.onFindAllResources != null)
                                  TextButton(
                                    onPressed: () => widget.onFindAllResources!(
                                      playback.autoplayEndEpisode,
                                    ),
                                    child: const Text('改用 BT'),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                key: const ValueKey('player-controls'),
                left: 0,
                right: 0,
                bottom: 0,
                child: ExcludeFocus(
                  excluding: !controls && menu == null,
                  child: IgnorePointer(
                    ignoring: !controls && menu == null,
                    child: AnimatedOpacity(
                      opacity: controls || menu != null ? 1 : 0,
                      duration: motionDuration(context),
                      curve: Curves.easeOutCubic,
                      child: MouseRegion(
                        onEnter: (_) {
                          controlsHovered = true;
                          reveal();
                        },
                        onExit: (_) {
                          controlsHovered = false;
                          reveal();
                        },
                        child: Focus(
                          canRequestFocus: false,
                          onFocusChange: (value) {
                            controlsFocused = value;
                            reveal();
                          },
                          child: PlayerControls(
                            playback: playback,
                            fullScreen: widget.fullScreen,
                            windowFullScreen: widget.windowFullScreen,
                            menu: menu,
                            dragging: dragging,
                            onDragStart: (value) {
                              playback.cancelAutoplay();
                              setState(() => dragging = value);
                              hideTimer?.cancel();
                            },
                            onDragChanged: (value) =>
                                setState(() => dragging = value),
                            onDragEnd: (value) async {
                              await player.seek(
                                Duration(milliseconds: (value * 1000).round()),
                              );
                              if (mounted) setState(() => dragging = null);
                              reveal();
                            },
                            menuFocusNodes: menuFocusNodes,
                            panelOpen: panel ?? false,
                            onTogglePanel: togglePanel,
                            lightsOff: widget.lightsOff,
                            onToggleLights: toggleLights,
                            onFeedback: showFeedback,
                            nextLabel: switch (nextEpisode) {
                              null => null,
                              (final next, true) => '下一话 · 第 ${next['sort']} 话',
                              (final next, false) =>
                                '下一话 · 第 ${next['sort']} 话',
                            },
                            onNext: switch (nextEpisode) {
                              null => null,
                              (final next, true) => () => widget.onEpisode(
                                next,
                              ),
                              (final next, false) => () => widget.onEpisode(
                                next,
                              ),
                            },
                            onPopupChanged: (value) {
                              controlsPopup = value;
                              reveal();
                            },
                            onReveal: reveal,
                            onFullscreen: fullscreen,
                            onWindowFullScreen: windowFullscreen,
                            onMenu: toggleMenu,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                key: const ValueKey('player-menu'),
                right: 12,
                bottom: constraints.maxWidth < 680 ? 136 : 108,
                child: ExcludeFocus(
                  excluding: menu == null,
                  child: IgnorePointer(
                    ignoring: menu == null,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: menu == null ? 0 : 1),
                      duration: motionDuration(context),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, child) => Offstage(
                        offstage: value == 0,
                        child: Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 5 * (1 - value)),
                            child: Transform.scale(
                              scale: .98 + .02 * value,
                              alignment: Alignment.bottomRight,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                      child: SizedBox(
                        width: math.min(300, constraints.maxWidth - 24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: math.max(
                              120,
                              constraints.maxHeight - 160,
                            ),
                          ),
                          child: PlayerSettings(
                            closeFocusNode: menuCloseFocus,
                            playback: playback,
                            service: widget.service,
                            menu: lastMenu,
                            onClose: closeMenu,
                            onError: widget.onError,
                            onPresentationChanged: refresh,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PreparingView extends StatelessWidget {
  const _PreparingView({
    required this.preparing,
    required this.onRetry,
    required this.onChoose,
    required this.onFindResources,
  });
  final Json preparing;
  final VoidCallback? onRetry, onChoose;
  final VoidCallback onFindResources;

  @override
  Widget build(BuildContext context) {
    final item = object(preparing['subject']);
    final episode = object(preparing['episode']);
    final failed = preparing['failed'] as String?;
    const white = Colors.white;
    final muted = white.withValues(alpha: .7);
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: white,
      backgroundColor: white.withValues(alpha: .08),
      side: BorderSide(color: white.withValues(alpha: .3)),
    );
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 96,
                height: 128,
                child: ClipRRect(
                  borderRadius: posterBorderRadius,
                  child: SubjectCover(
                    url: item['coverUrl'],
                    title: titleOf(item),
                    id: number(item['subjectId']).toInt(),
                  ),
                ),
              ),
              const SizedBox(height: Gap.lg),
              Text(
                titleOf(item),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                '第 ${episode['sort']} 话 · ${titleOf(episode)}',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: Gap.xl),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (failed == null)
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: white,
                      ),
                    )
                  else
                    Icon(Icons.error_outline_rounded, size: 18, color: muted),
                  const SizedBox(width: Gap.sm),
                  Flexible(
                    child: Text(
                      failed ?? '正在查找第 ${episode['sort']} 话的可播放资源…',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.lg),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                alignment: WrapAlignment.center,
                children: [
                  if (failed != null)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: white,
                        foregroundColor: const Color(0xff164d39),
                      ),
                      onPressed: onRetry,
                      child: const Text('重试'),
                    ),
                  OutlinedButton(
                    style: buttonStyle,
                    onPressed: onChoose,
                    child: const Text('手动选择资源'),
                  ),
                  OutlinedButton(
                    style: buttonStyle,
                    onPressed: onFindResources,
                    child: const Text('完整资源查找'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
