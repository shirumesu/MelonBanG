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
    required this.panelOpen,
    required this.community,
    this.source,
    this.failure,
    this.onRetryFailure,
    required this.onMarkEpisode,
    required this.onOpenSubject,
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

  /// Whether the side panel shows; null until the first layout picks a
  /// default from the width. The title bar toggles it too.
  final ValueNotifier<bool?> panelOpen;
  final SubjectCommunitySource community;

  /// The source chosen for the session, when one was.
  final PlayCandidate? source;

  /// Why the chosen source stopped; the video stays paused under it.
  final PlaybackFailure? failure;
  final VoidCallback? onRetryFailure;
  final Future<void> Function(Episode episode, bool watched) onMarkEpisode;
  final ValueChanged<Subject> onOpenSubject;
  @override
  State<PlayerPage> createState() => PlayerPageState();
}

class PlayerPageState extends State<PlayerPage> {
  final focus = FocusNode();
  final menuCloseFocus = FocusNode();
  final danmakuMenuFocus = FocusNode();

  bool controls = true;
  bool controlsHovered = false, controlsFocused = false, controlsPopup = false;
  bool resourcesOpen = false;
  int? resourceEpisode;
  bool danmakuMenu = false;
  PlayerPanelTab panelTab = PlayerPanelTab.episodes;

  /// → held past [_boostDelay] plays at 3× until released; a tap seeks.
  Timer? boostTimer;
  bool boosting = false;
  static const _boostDelay = Duration(milliseconds: 300);

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
    widget.panelOpen.addListener(refresh);
    playingSubscription = player.stream.playing.listen((_) => reveal());
  }

  @override
  void didUpdateWidget(PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject?.id != widget.subject?.id) {
      resourcesOpen = false;
      resourceEpisode = null;
    }
    if (oldWidget.fullScreen != widget.fullScreen ||
        oldWidget.windowFullScreen != widget.windowFullScreen) {
      danmakuMenu = false;
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
      danmakuMenu = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    playback.removeListener(refresh);
    widget.panelOpen.removeListener(refresh);
    playback.cancelAutoplay(notify: false);
    unawaited(playingSubscription?.cancel());
    boostTimer?.cancel();
    if (boosting) unawaited(playback.boost(false));
    focus.dispose();
    menuCloseFocus.dispose();
    danmakuMenuFocus.dispose();
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
          !danmakuMenu &&
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

  /// Opens the side panel on [tab].
  void showPanel(PlayerPanelTab tab) {
    setState(() {
      panelTab = tab;
      danmakuMenu = false;
    });
    widget.panelOpen.value = true;
    focus.requestFocus();
    reveal();
  }

  void startBoost() {
    if (playback.uri == null || playback.opening) return;
    setState(() => boosting = true);
    unawaited(playback.boost(true));
    reveal();
  }

  void endBoost() {
    boostTimer?.cancel();
    if (!boosting) return;
    setState(() => boosting = false);
    unawaited(playback.boost(false));
  }

  /// A tap of → seeks 5 seconds on release; holding it plays at 3×.
  KeyEventResult handleRight(KeyEvent event) {
    if (event is KeyUpEvent) {
      if (boosting) {
        endBoost();
      } else if (boostTimer?.isActive ?? false) {
        boostTimer!.cancel();
        unawaited(seekRelative(5));
        reveal();
      }
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (danmakuMenu ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      boostTimer?.cancel();
      boostTimer = Timer(_boostDelay, startBoost);
    }
    return KeyEventResult.handled;
  }

  /// The next episode by order.
  Episode? get nextEpisode {
    final episodes = widget.subject?.episodes ?? const <Episode>[];
    final index = episodes.indexWhere(
      (e) => e.id == playback.session?.episodeId,
    );
    if (index < 0 || index + 1 >= episodes.length) return null;
    return episodes[index + 1];
  }

  void toggleMenu() {
    playback.cancelAutoplay();
    resourcesOpen = false;
    if (danmakuMenu) {
      closeMenu();
      return;
    }
    setState(() => danmakuMenu = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && danmakuMenu) menuCloseFocus.requestFocus();
    });
    reveal();
  }

  void closeMenu() {
    setState(() => danmakuMenu = false);
    danmakuMenuFocus.requestFocus();
    reveal();
  }

  /// Opens the resource sheet over the video for [episode].
  void findResources(Episode? episode) {
    playback.cancelAutoplay();
    setState(() {
      resourceEpisode = episode?.id;
      resourcesOpen = true;
      danmakuMenu = false;
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
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      return handleRight(event);
    }
    // Held arrows repeat seeks and volume steps like other players.
    if (event is! KeyDownEvent &&
        !(event is KeyRepeatEvent &&
            const [
              LogicalKeyboardKey.arrowLeft,
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
      if (danmakuMenu ||
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
    if (danmakuMenu) {
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
    reveal();
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

  Episode? get episode =>
      widget.subject?.episode(playback.session?.episodeId ?? -1);

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
        // Open the panel by default only when the video keeps room; it stays
        // out of the way in immersive modes and returns after them.
        final wide = constraints.maxWidth >= 1080;
        if (widget.panelOpen.value == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.panelOpen.value ??= wide;
          });
        }
        final showPanel = !immersive && (widget.panelOpen.value ?? wide);
        final libraryWidth = sidePanelWidth(constraints.maxWidth);
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
                          builder: (context, downloads, _) => PlayerSidePanel(
                            playback: playback,
                            community: widget.community,
                            subject: widget.subject,
                            session: playback.session,
                            source: widget.source,
                            downloads: downloads,
                            tab: panelTab,
                            onTab: (tab) => setState(() => panelTab = tab),
                            onEpisode: widget.onEpisode,
                            onFindResources: findResources,
                            onPlayFile: widget.onPlayFile ?? (_, _) {},
                            onToggleTask: widget.downloads.toggle,
                            onMarkEpisode: widget.onMarkEpisode,
                            onOpenSubject: widget.onOpenSubject,
                            onError: widget.onError,
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
      final narrow = constraints.maxWidth < 680;
      final transportInset = narrow ? 136.0 : 108.0;
      final failure = widget.failure?.reason ?? playback.error;
      return Focus(
        focusNode: focus,
        autofocus: true,
        onKeyEvent: handleKey,
        onFocusChange: (focused) {
          // A key released elsewhere never reaches us; stop the 3× there.
          if (!focused) endBoost();
        },
        child: MouseRegion(
          onHover: (_) => reveal(),
          cursor: controls || danmakuMenu
              ? SystemMouseCursors.basic
              : SystemMouseCursors.none,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: () {
                  playback.cancelAutoplay();
                  if (danmakuMenu) {
                    closeMenu();
                    return;
                  }
                  focus.requestFocus();
                  if (playback.uri != null &&
                      !playback.opening &&
                      widget.failure == null) {
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
                    (playback.opening || snapshot.data == true) &&
                        failure == null
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
              if (failure != null)
                Center(
                  child: _FailureCard(
                    reason: failure,
                    onRetry: widget.failure == null
                        ? null
                        : widget.onRetryFailure,
                    onChoose: widget.subject == null
                        ? null
                        : () =>
                              findResources(widget.failure?.episode ?? episode),
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
                        failure == null &&
                        !playback.frameStepping &&
                        !danmakuMenu;
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
                                tooltip: '播放 (Space)',
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
                      opacity: feedback == null && !boosting ? 0 : 1,
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (boosting) ...[
                              const Icon(
                                Icons.fast_forward_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: Gap.sm),
                            ],
                            Text(
                              boosting ? '3× 快进中' : feedback ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
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
                    opacity: controls || danmakuMenu ? 1 : 0,
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
                      child: _Title(
                        title:
                            widget.subject?.title ??
                            playback.session?.title ??
                            '播放器',
                        episode: episode,
                      ),
                    ),
                  ),
                ),
              ),
              if (playback.openingEnding case final marks?)
                StreamBuilder<Duration>(
                  stream: player.stream.position,
                  initialData: player.state.position,
                  builder: (_, position) {
                    final now = position.data!.inMilliseconds / 1000;
                    // Offered until a few seconds before the song ends.
                    bool inside(ChapterSpan? span) =>
                        span != null && now >= span.start && now < span.end - 3;
                    final (label, target) = inside(marks.opening)
                        ? ('跳过片头', marks.opening!.end)
                        : inside(marks.ending)
                        ? ('跳过片尾', marks.ending!.end)
                        : (null, 0.0);
                    if (label == null || failure != null) {
                      return const SizedBox.shrink();
                    }
                    return AnimatedPositioned(
                      duration: motionDuration(context),
                      curve: Curves.easeOutCubic,
                      right: pageGutter,
                      bottom: controls ? transportInset : pageGutter,
                      child: _SkipButton(
                        label: label,
                        onPressed: () {
                          showFeedback(label);
                          unawaited(seekTo(target));
                        },
                      ),
                    );
                  },
                ),
              if (playback.autoplayTarget != null ||
                  playback.autoplayMessage != null)
                Positioned(
                  right: 20,
                  bottom: transportInset + 4,
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
                  excluding: !controls && !danmakuMenu,
                  child: IgnorePointer(
                    ignoring: !controls && !danmakuMenu,
                    child: AnimatedOpacity(
                      opacity: controls || danmakuMenu ? 1 : 0,
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
                            danmakuMenuOpen: danmakuMenu,
                            danmakuMenuFocus: danmakuMenuFocus,
                            onDanmakuMenu: toggleMenu,
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
                            onFeedback: showFeedback,
                            onStepFrame: (forward) =>
                                unawaited(stepFrame(forward)),
                            onNext: switch (nextEpisode) {
                              null => null,
                              final next => () => widget.onEpisode(next),
                            },
                            onPopupChanged: (value) {
                              controlsPopup = value;
                              reveal();
                            },
                            onReveal: reveal,
                            onFullscreen: fullscreen,
                            onWindowFullScreen: windowFullscreen,
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
                bottom: transportInset,
                child: ExcludeFocus(
                  excluding: !danmakuMenu,
                  child: IgnorePointer(
                    ignoring: !danmakuMenu,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: danmakuMenu ? 1 : 0),
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
                        width: math.min(312, constraints.maxWidth - 24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: math.max(
                              120,
                              constraints.maxHeight - 160,
                            ),
                          ),
                          child: DanmakuQuickSettings(
                            closeFocusNode: menuCloseFocus,
                            preferences: playback.danmaku.preferences,
                            onClose: closeMenu,
                            // The panel is hidden in immersive modes.
                            onOpenSources: immersive
                                ? null
                                : () => showPanel(PlayerPanelTab.danmaku),
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

/// The subject's name, then the episode in a quieter style.
class _Title extends StatelessWidget {
  const _Title({required this.title, this.episode});
  final String title;
  final Episode? episode;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Colors.black54, blurRadius: 6)];
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (episode case final episode?)
            TextSpan(
              text: '   ${episodeLabel(episode)}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: .75),
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white, shadows: shadow),
    );
  }
}

/// Why playback stopped, with retrying the same source or choosing another.
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.reason, this.onRetry, this.onChoose});
  final String reason;
  final VoidCallback? onRetry, onChoose;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: .08),
      side: BorderSide(color: Colors.white.withValues(alpha: .3)),
    );
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.all(Gap.xl),
      padding: const EdgeInsets.all(Gap.xl),
      decoration: const BoxDecoration(
        color: overlaySurface,
        borderRadius: panelBorderRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.white70,
            size: 28,
          ),
          const SizedBox(height: Gap.md),
          Text(
            reason.replaceFirst('Bad state: ', ''),
            textAlign: TextAlign.center,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          if (onRetry != null || onChoose != null) ...[
            const SizedBox(height: Gap.lg),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              alignment: WrapAlignment.center,
              children: [
                if (onRetry != null)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xff15181d),
                    ),
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                if (onChoose != null)
                  OutlinedButton(
                    style: buttonStyle,
                    onPressed: onChoose,
                    child: const Text('选择其他资源'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Jumps past the OP or ED the file's chapters mark.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: overlaySurface,
    borderRadius: controlBorderRadius,
    child: InkWell(
      borderRadius: controlBorderRadius,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_double_arrow_right_rounded,
              size: 18,
              color: Colors.white,
            ),
          ],
        ),
      ),
    ),
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
  return '冷门资源找到节点可能要很久，可以在侧栏换个资源';
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
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
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
