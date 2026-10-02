import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app_services.dart';
import '../core/motion.dart';
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
    this.downloads = const {},
    this.windowFullScreen = false,
    this.onWindowFullScreenChanged,
    this.onPlayFile,
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
  final Json downloads;
  final ValueChanged<Json> onEpisode;
  final void Function(String id, String? fileId)? onPlayFile;

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
  Set<int> localEpisodes = {};
  Timer? hideTimer, feedbackTimer;
  StreamSubscription<bool>? playingSubscription;
  String? sessionId;
  Playback get playback => widget.playback;
  Player get player => playback.player;
  bool get immersive => widget.fullScreen || widget.windowFullScreen;

  @override
  void initState() {
    super.initState();
    sessionId = playback.session?['id'] as String?;
    playback.addListener(refresh);
    playingSubscription = player.stream.playing.listen((_) => reveal());
    unawaited(loadEpisodes());
  }

  Future<void> loadEpisodes() async {
    final id = widget.subject?['subjectId'] as int?;
    final episodes = objects(widget.subject?['episodes']);
    if (id == null) return;
    final available = await loadLocalEpisodes(widget.service, id, episodes);
    if (mounted && widget.subject?['subjectId'] == id) {
      setState(() => localEpisodes = available);
    }
  }

  @override
  void didUpdateWidget(PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject?['subjectId'] != widget.subject?['subjectId']) {
      resourcesOpen = false;
      resourceEpisode = null;
      localEpisodes = {};
    }
    if (oldWidget.subject != widget.subject) unawaited(loadEpisodes());
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
    final off = widget.lightsOff;
    if (off == null) return;
    widget.onLightsChanged?.call(!off);
    showFeedback(off ? '已开灯' : '已关灯');
  }

  void togglePanel() {
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
      widget.downloads,
      widget.subject?['subjectId'] as int?,
    );
    return (
      next,
      localEpisodes.contains(id) ||
          playableTask(widget.downloads, tasks, id) != null,
    );
  }

  void toggleMenu(PlayerMenu value) {
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
    await widget.onFullScreenChanged(!widget.fullScreen);
    if (mounted) {
      focus.requestFocus();
      reveal();
    }
  }

  Future<void> windowFullscreen() async {
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
    if (event.logicalKey == LogicalKeyboardKey.space) {
      unawaited(player.playOrPause());
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
                        child: PlayerLibraryPanel(
                          key: ValueKey(playback.session?['subjectId']),
                          service: widget.service,
                          subjectId: playback.session?['subjectId'] as int?,
                          subject: widget.subject,
                          episodeId: playback.session?['episodeId'] as int?,
                          title: '${playback.session?['title'] ?? '播放器'}',
                          downloads: widget.downloads,
                          localEpisodes: localEpisodes,
                          onEpisode: widget.onEpisode,
                          onFindResources: findResources,
                          onPlayFile: widget.onPlayFile ?? (_, _) {},
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
                                onPressed: () => unawaited(player.play()),
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
                                '第 ${next['sort']} 话未缓存 · 点击查找资源',
                            },
                            onNext: switch (nextEpisode) {
                              null => null,
                              (final next, true) => () => widget.onEpisode(
                                next,
                              ),
                              (final next, false) => () => findResources(next),
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
