import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app_services.dart';
import '../core/motion.dart';
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
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final focus = FocusNode();
  final menuCloseFocus = FocusNode();
  final menuFocusNodes = {
    for (final menu in PlayerMenu.values) menu: FocusNode(),
  };
  bool panel = true, controls = true, nearPanel = false, panelFocused = false;
  bool controlsHovered = false, controlsFocused = false, controlsPopup = false;
  bool titleVisible = false, panelBeforeImmersive = true;
  bool resourcesOpen = false;
  int? resourceEpisode;
  PlayerMenu? menu;
  PlayerMenu lastMenu = PlayerMenu.subtitles;
  double? dragging;
  Timer? hideTimer, titleTimer;
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
      panelBeforeImmersive = panel;
      panel = false;
    } else if (wasImmersive && !immersive) {
      panel = panelBeforeImmersive;
    }
    if (oldWidget.fullScreen != widget.fullScreen ||
        oldWidget.windowFullScreen != widget.windowFullScreen) {
      menu = null;
      titleVisible = false;
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
    titleTimer?.cancel();
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
    reveal();
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
      unawaited(playback.toggleMute());
    } else {
      return KeyEventResult.ignored;
    }
    reveal();
    return KeyEventResult.handled;
  }

  void hoverTitle(double y) {
    if (!immersive) return;
    final near = y < 72;
    if (titleVisible != near) setState(() => titleVisible = near);
    titleTimer?.cancel();
    if (near) {
      titleTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => titleVisible = false);
      });
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
        final panelWidth = constraints.maxWidth < 820 ? 284.0 : 310.0;
        final libraryWidth = math.min(panelWidth, constraints.maxWidth * .5);
        final videoWidth = constraints.maxWidth - (panel ? libraryWidth : 0);
        final transportInset = videoWidth < 624 ? 132.0 : 100.0;
        final showButton = panel || nearPanel || panelFocused;
        return MouseRegion(
          onHover: (event) {
            final near =
                event.localPosition.dx > constraints.maxWidth - 92 &&
                event.localPosition.dy < 84;
            if (nearPanel != near) setState(() => nearPanel = near);
          },
          onExit: (_) {
            if (nearPanel) setState(() => nearPanel = false);
          },
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(child: video(context)),
                  ExcludeFocus(
                    excluding: !panel,
                    child: IgnorePointer(
                      ignoring: !panel,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: panel ? 1 : 0),
                        duration: motionDuration(context, 220),
                        curve: Curves.easeOutCubic,
                        builder: (_, value, child) => Offstage(
                          offstage: value == 0,
                          child: ClipRect(
                            child: Align(
                              alignment: Alignment.centerRight,
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
              Positioned(
                top: 14,
                right: 12,
                child: Focus(
                  canRequestFocus: false,
                  onFocusChange: (value) =>
                      setState(() => panelFocused = value),
                  child: IgnorePointer(
                    ignoring: !showButton,
                    child: AnimatedOpacity(
                      opacity: showButton ? (panel ? 1 : .85) : 0,
                      duration: motionDuration(context, 150),
                      child: Material(
                        color: panel
                            ? Colors.transparent
                            : Theme.of(context).colorScheme.surface,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          tooltip: panel ? '收起选集与资源' : '展开选集与资源',
                          onPressed: () {
                            setState(() => panel = !panel);
                            focus.requestFocus();
                          },
                          icon: const Icon(
                            Icons.view_sidebar_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
          onHover: (event) {
            reveal();
            hoverTitle(event.localPosition.dy);
          },
          onExit: (_) {
            if (titleVisible) setState(() => titleVisible = false);
          },
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
              if (immersive)
                Positioned(
                  key: const ValueKey('player-title'),
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: AnimatedSlide(
                      offset: titleVisible
                          ? Offset.zero
                          : const Offset(0, -.08),
                      duration: motionDuration(context),
                      child: AnimatedOpacity(
                        opacity: titleVisible ? 1 : 0,
                        duration: motionDuration(context),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(22, 20, 68, 36),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
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
                            onSeekRelative: seekRelative,
                            menuFocusNodes: menuFocusNodes,
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
                bottom: constraints.maxWidth < 624 ? 132 : 100,
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
