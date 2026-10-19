import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../domain/catalog.dart';
import '../../domain/play_candidate.dart';
import '../../domain/playback_session.dart';
import '../../domain/transfer.dart';
import '../../features/downloads/downloads_controller.dart';
import '../../features/playback/playback_coordinator.dart';
import '../../features/playback/resource_search.dart';
import '../acquisition/download_labels.dart';
import '../core/motion.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'danmaku.dart';
import '../../features/playback/playback.dart';
import 'player_controls.dart';
import 'player_library_panel.dart';
import 'player_resource_sheet.dart';
import 'player_settings.dart';
import 'player_theme.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.playback,
    required this.newResourceSearch,
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
    this.onOpenResources,
    this.lightsOff,
    this.onLightsChanged,
  });
  final Playback playback;
  final ResourceSearchController Function() newResourceSearch;
  final VoidCallback onBack;
  final ValueChanged<Object> onError;
  final bool fullScreen, windowFullScreen;
  final Future<void> Function(bool) onFullScreenChanged;
  final Future<void> Function(bool)? onWindowFullScreenChanged;
  final Subject? subject;

  /// Set while the player was opened before a source started.
  final PreparingPlayback? preparing;
  final VoidCallback? onRetryPreparing, onChoosePreparing;
  final DownloadsController downloads;
  final ValueChanged<Episode> onEpisode;
  final void Function(String id, String? fileId)? onPlayFile;

  /// Plays a chosen resource as the episode.
  final Future<void> Function(PlayCandidate candidate, Episode episode)?
  onPlayCandidate;

  /// Continues a resource-sheet search on the resources page.
  final void Function(ResourceSearchController search)? onOpenResources;

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

  /// Position shown instead of the player's while dragging or seeking.
  double? dragging;
  int seekTicket = 0;
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
    sessionId = playback.session?.id;
    playback.addListener(refresh);
    playingSubscription = player.stream.playing.listen((_) => reveal());
  }

  @override
  void didUpdateWidget(PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject?.id != widget.subject?.id) {
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
    final next = playback.session?.id;
    if (next != sessionId) {
      sessionId = next;
      dragging = null;
      seekTicket++;
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
  (Episode, bool)? get nextEpisode {
    final episodes = widget.subject?.episodes ?? const <Episode>[];
    final index = episodes.indexWhere(
      (e) => e.id == playback.session?.episodeId,
    );
    if (index < 0 || index + 1 >= episodes.length) return null;
    final next = episodes[index + 1];
    final tasks = widget.downloads.snapshot.value.forSubject(
      widget.subject?.id,
    );
    return (next, playableTask(tasks, next.id) != null);
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

  void findResources(Episode? episode) {
    playback.cancelAutoplay();
    setState(() {
      resourceEpisode = episode?.id;
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

  /// Seeks to [seconds] and keeps showing that position until the player
  /// reports it, so a slow network seek never flashes the previous one.
  Future<void> seekTo(double seconds) async {
    playback.cancelAutoplay();
    final ticket = ++seekTicket;
    final duration = player.state.duration.inMilliseconds / 1000;
    final value = seconds.clamp(0.0, duration > 0 ? duration : seconds);
    setState(() => dragging = value);
    reveal();
    final target = Duration(milliseconds: (value * 1000).round());
    bool arrived(Duration position) =>
        (position - target).abs() < const Duration(seconds: 2);
    await player.seek(target);
    if (!arrived(player.state.position)) {
      await player.stream.position
          .firstWhere(arrived)
          .timeout(const Duration(seconds: 10), onTimeout: () => target);
    }
    if (mounted && ticket == seekTicket) setState(() => dragging = null);
  }

  /// Relative seeks add up while an earlier one is still in flight.
  Future<void> seekRelative(int seconds) async {
    final from = dragging ?? player.state.position.inMilliseconds / 1000;
    showFeedback(seconds > 0 ? '快进 $seconds 秒' : '快退 ${-seconds} 秒');
    await seekTo(from + seconds);
  }

  Future<void> changeRate(int step) async {
    playback.cancelAutoplay();
    const rates = [.5, .75, 1.0, 1.25, 1.5, 2.0];
    final current = rates.indexWhere((rate) => rate >= player.state.rate);
    final next =
        rates[((current < 0 ? rates.length - 1 : current) + step).clamp(
          0,
          rates.length - 1,
        )];
    await player.setRate(next);
    showFeedback('倍速 $next×');
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
    // Held arrows repeat seeks and volume steps like other players.
    if (event is! KeyDownEvent &&
        !(event is KeyRepeatEvent &&
            const [
              LogicalKeyboardKey.arrowLeft,
              LogicalKeyboardKey.arrowRight,
              LogicalKeyboardKey.arrowUp,
              LogicalKeyboardKey.arrowDown,
            ].contains(event.logicalKey))) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (keyboard.isShiftPressed) {
      if (menu != null ||
          !const [
            LogicalKeyboardKey.period,
            LogicalKeyboardKey.comma,
          ].contains(event.logicalKey)) {
        return KeyEventResult.ignored;
      }
      unawaited(
        changeRate(event.logicalKey == LogicalKeyboardKey.period ? 1 : -1),
      );
      reveal();
      return KeyEventResult.handled;
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
    } else if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.keyK) {
      playback.cancelAutoplay();
      unawaited(playback.playOrPause());
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      unawaited(seekTo(0));
    } else if (_digits.indexOf(event.logicalKey) case final digit
        when digit >= 0) {
      // 0–9 jump to that tenth of the episode.
      unawaited(
        seekTo(player.state.duration.inMilliseconds / 1000 * (digit % 10) / 10),
      );
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
        '${forward ? '下一帧' : '上一帧'}  $hours:$minutes:$seconds.$fraction',
      );
    } catch (e) {
      widget.onError(e);
    }
  }

  String get title {
    final subject = widget.subject;
    if (subject == null) return playback.session?.title ?? '播放器';
    final episode = subject.episodes
        .where((e) => e.id == playback.session?.episodeId)
        .firstOrNull;
    return '${subject.title}${episode == null ? '' : ' · 第 ${episode.number} 话'}';
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
      return ValueListenableBuilder(
        valueListenable: widget.downloads.snapshot,
        builder: (context, snapshot, _) => _PreparingView(
          preparing: preparing,
          task: switch (preparing.downloadId) {
            final id? => snapshot.task(id),
            null => null,
          },
          onRetry: widget.onRetryPreparing,
          onChoose: widget.onChoosePreparing,
        ),
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
                        child: ValueListenableBuilder<TransferSnapshot>(
                          valueListenable: widget.downloads.snapshot,
                          builder: (context, downloads, _) =>
                              PlayerLibraryPanel(
                                key: ValueKey(playback.session?.subjectId),
                                onToggleTask: widget.downloads.toggle,
                                subjectId: playback.session?.subjectId,
                                subject: widget.subject,
                                episodeId: playback.session?.episodeId,
                                title: playback.session?.title ?? '播放器',
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
                              'resource-sheet:${widget.subject!.id}',
                            ),
                            newSearch: widget.newResourceSearch,
                            playback: playback,
                            onPlay: (candidate, episode) async => widget
                                .onPlayCandidate
                                ?.call(candidate, episode),
                            onOpenPage: widget.onOpenResources,
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
                    return;
                  }
                  focus.requestFocus();
                  if (playback.uri != null && !playback.opening) {
                    showFeedback(player.state.playing ? '暂停' : '播放');
                    unawaited(playback.playOrPause());
                  }
                  reveal();
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
                    ? ValueListenableBuilder(
                        valueListenable: widget.downloads.snapshot,
                        builder: (context, downloads, _) => _BufferingStatus(
                          opening: playback.opening,
                          task: switch (playback.session) {
                            PlaybackSession(:final downloadId?, streamId: _?) =>
                              downloads.task(downloadId),
                            _ => null,
                          },
                        ),
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
                          Text(switch (playback.autoplayTarget) {
                            null => playback.autoplayMessage!,
                            final target =>
                              '${playback.autoplaySeconds} 秒后播放第 ${target.episode.number} 话',
                          }),
                          if (playback.autoplayTarget case final target?) ...[
                            const SizedBox(height: 4),
                            Text(
                              target.sourceLabel,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
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
                            TextButton(
                              onPressed: () =>
                                  findResources(playback.autoplayEndEpisode),
                              child: const Text('查找资源'),
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
                              seekTicket++;
                              setState(() => dragging = value);
                              hideTimer?.cancel();
                            },
                            onDragChanged: (value) =>
                                setState(() => dragging = value),
                            onDragEnd: seekTo,
                            menuFocusNodes: menuFocusNodes,
                            panelOpen: panel ?? false,
                            onTogglePanel: togglePanel,
                            lightsOff: widget.lightsOff,
                            onToggleLights: toggleLights,
                            onFeedback: showFeedback,
                            nextLabel: switch (nextEpisode) {
                              null => null,
                              (final next, _) => '下一话（第 ${next.number} 话）',
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
                            menu: lastMenu,
                            onClose: closeMenu,
                            onError: widget.onError,
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

/// What a streamed download is doing while the player waits for its data:
/// its state, speed and connected peers.
String? _transferLine(DownloadTask? task) {
  if (task == null || task.complete) return null;
  return [
    downloadStatus(task),
    if (task.status == DownloadStatus.downloading) ...[
      transferRate(task.downloadSpeed),
      if (task.method == CacheMethod.bt) '${task.swarm.peers} 个节点',
    ],
  ].join('  ');
}

/// Why a BT task waiting for data has no peers yet. Every tracker failing
/// with an empty DHT table means its traffic does not get out, which a proxy
/// routing BT to a node that drops it does.
String? _swarmHint(DownloadTask? task) {
  if (task == null ||
      task.complete ||
      task.method != CacheMethod.bt ||
      task.swarm.peers > 0 ||
      task.downloadSpeed > 0) {
    return null;
  }
  final SwarmStats(:workingTrackers, :failedTrackers, :dhtNodes) = task.swarm;
  if ((failedTrackers ?? 0) > 0 &&
      (workingTrackers ?? 0) == 0 &&
      (dhtNodes ?? 0) == 0) {
    return '连不上任何 Tracker 和 DHT 节点。开着代理软件时，请让 MelonBanG 直连';
  }
  return '冷门资源找到节点可能要很久，可以在选集里换一个资源';
}

/// Shown over the video while it opens or buffers; a streamed download adds
/// its live state, and a BT task finding no peers says why it waits.
class _BufferingStatus extends StatelessWidget {
  const _BufferingStatus({required this.opening, this.task});
  final bool opening;
  final DownloadTask? task;

  @override
  Widget build(BuildContext context) {
    final task = this.task;
    final line = _transferLine(task);
    final hint = _swarmHint(task);
    const shadow = [Shadow(blurRadius: 6)];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: Gap.md),
          Text(
            opening ? '正在打开视频' : '正在缓冲',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              shadows: shadow,
            ),
          ),
          if (line != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              line,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .75),
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: shadow,
              ),
            ),
          ],
          if (hint != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .75),
                fontSize: 12,
                shadows: shadow,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreparingView extends StatelessWidget {
  const _PreparingView({
    required this.preparing,
    required this.onRetry,
    required this.onChoose,
    this.task,
  });
  final PreparingPlayback preparing;

  /// The download being started or streamed.
  final DownloadTask? task;
  final VoidCallback? onRetry, onChoose;

  @override
  Widget build(BuildContext context) {
    final failed = preparing.failed;
    final live = _transferLine(task);
    final hint = _swarmHint(task);
    final canChoose = preparing.subject != null && preparing.episode != null;
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
                    url: preparing.coverUrl,
                    title: preparing.title,
                    id: preparing.subject?.id ?? 0,
                  ),
                ),
              ),
              const SizedBox(height: Gap.lg),
              Text(
                preparing.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (preparing.detail case final detail?) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
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
                      failed ?? preparing.status ?? '正在查找资源…',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
              if (failed == null && live != null) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  live,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (failed == null && hint != null) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
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
                  if (canChoose)
                    OutlinedButton(
                      style: buttonStyle,
                      onPressed: onChoose,
                      child: const Text('选择资源'),
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

const _digits = [
  LogicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
  LogicalKeyboardKey.numpad0,
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];
