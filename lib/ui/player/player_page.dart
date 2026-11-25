import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../core/error_message.dart';
import '../../core/file_manager.dart';
import '../../core/notices.dart';
import '../../core/system_settings.dart';
import '../../domain/catalog.dart';
import '../../domain/community.dart';
import '../../domain/play_candidate.dart';
import '../../domain/playback_session.dart';
import '../../features/downloads/downloads_controller.dart';
import '../../features/playback/opening_ending.dart';
import '../../features/playback/play_ranking.dart';
import '../../features/playback/playback.dart';
import '../../features/playback/playback_coordinator.dart';
import '../../features/playback/resource_search.dart';
import '../core/motion.dart';
import '../core/notice_cards.dart';
import '../core/overlay_glass.dart';
import '../core/theme.dart';
import 'danmaku.dart';
import 'player_controls.dart';
import 'player_corner_cards.dart';
import 'player_episodes_pane.dart';
import 'player_preparing.dart';
import 'player_progress_bar.dart';
import 'player_resource_sheet.dart';
import 'player_settings.dart';
import 'player_side_panel.dart';
import 'player_stats.dart';
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
    required this.onRetryPreparing,
    required this.onChoosePreparing,
    required this.downloads,
    required this.windowFullScreen,
    required this.onWindowFullScreenChanged,
    required this.onPlayFile,
    required this.onPlayCandidate,
    required this.onOpenResources,
    required this.panelOpen,
    required this.community,
    this.source,
    this.remembered,
    required this.onForgetSource,
    this.failure,
    required this.onRetryFailure,
    required this.onMarkEpisode,
    required this.onOpenSubject,
    required this.mini,
    required this.onMiniChanged,
    required this.onDragWindow,
  });
  final Playback playback;
  final ResourceSearchController Function() newResourceSearch;
  final VoidCallback onBack;
  final ValueChanged<Object> onError;
  final bool fullScreen, windowFullScreen;
  final Future<void> Function(bool) onFullScreenChanged;
  final Future<void> Function(bool) onWindowFullScreenChanged;
  final Subject? subject;

  /// Set while the player was opened before a source started.
  final PreparingPlayback? preparing;
  final VoidCallback onRetryPreparing, onChoosePreparing;
  final DownloadsController downloads;
  final ValueChanged<Episode> onEpisode;
  final void Function(String id, String? fileId) onPlayFile;

  final Future<void> Function(PlayCandidate candidate, Episode episode)
  onPlayCandidate;

  /// Continues a resource-sheet search on the resources page.
  final void Function(ResourceSearchController search) onOpenResources;

  /// Whether the side panel shows; null until the first layout picks a
  /// default from the width. The title bar toggles it too.
  final ValueNotifier<bool?> panelOpen;
  final SubjectCommunitySource community;

  /// The source chosen for the session, when one was.
  final PlayCandidate? source;

  /// The source the subject remembers, and forgetting it.
  final RememberedSource? remembered;
  final VoidCallback onForgetSource;

  /// Why the chosen source stopped; the video stays paused under it.
  final PlaybackFailure? failure;
  final VoidCallback onRetryFailure;
  final Future<void> Function(Episode episode, bool watched) onMarkEpisode;
  final ValueChanged<Subject> onOpenSubject;

  /// The player alone in a small window above the others; dragging the
  /// video moves it.
  final bool mini;
  final Future<void> Function(bool) onMiniChanged;
  final VoidCallback onDragWindow;
  @override
  State<PlayerPage> createState() => PlayerPageState();
}

class PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  final focus = FocusNode();
  final preparingFocus = FocusNode();
  final menuCloseFocus = FocusNode();
  final danmakuMenuFocus = FocusNode();

  /// The video and the danmaku settings, outside which a tap closes them.
  final menuTapGroup = Object();
  final danmakuDraft = TextEditingController();
  final danmakuInput = FocusNode();

  /// The comment field's placeholder, picked anew for each episode.
  String danmakuHint = _danmakuHint();

  bool controls = true;
  bool controlsHovered = false, controlsFocused = false, controlsPopup = false;
  bool handleHovered = false;
  bool resourcesOpen = false;
  int? resourceEpisode;
  bool danmakuMenu = false;

  /// 详细参数 over the video's top left.
  bool stats = false;
  PlayerPanelTab panelTab = PlayerPanelTab.episodes;

  /// → held past [_boostDelay] plays at 3× until released; a tap seeks.
  Timer? boostTimer;
  bool boosting = false;
  static const _boostDelay = Duration(milliseconds: 300);

  /// Position shown instead of the player's while dragging or seeking.
  double? dragging;
  int seekTicket = 0;
  String? feedback;

  /// The last confirmation shown, kept while it fades out.
  String shownFeedback = '';
  bool shownBoost = false;
  Timer? hideTimer, feedbackTimer;
  String? overload;

  /// The share of the overload card's six seconds left, run down like a
  /// notice's: held while the pointer rests on it, closing it at zero.
  late final overloadLeft =
      AnimationController(
        vsync: this,
        duration: const Duration(seconds: 6),
        animationBehavior: AnimationBehavior.preserve,
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) playback.dismissOverload();
      });
  late final StreamSubscription<bool> playingSubscription;
  String? sessionId;
  int lastNotice = 0;
  Playback get playback => widget.playback;
  Player get player => playback.player;
  bool get immersive =>
      widget.fullScreen || widget.windowFullScreen || widget.mini;

  @override
  void initState() {
    super.initState();
    sessionId = playback.session?.id;
    // Notices from before this page was shown are not repeated.
    lastNotice = playback.noticeRevision;
    syncOverload();
    playback.addListener(refresh);
    widget.panelOpen.addListener(refresh);
    // Follows every player without opening one while a source is prepared.
    playingSubscription = playback.playingChanges.listen((_) => reveal());
  }

  @override
  void didUpdateWidget(PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject?.id != widget.subject?.id) {
      resourcesOpen = false;
      resourceEpisode = null;
    }
    if (oldWidget.fullScreen != widget.fullScreen ||
        oldWidget.windowFullScreen != widget.windowFullScreen ||
        oldWidget.mini != widget.mini) {
      danmakuMenu = false;
      controls = true;
      // Shell changes reparent the player; restore focus after it reattaches.
      WidgetsBinding.instance.addPostFrameCallback((_) => focusView());
    } else if ((oldWidget.preparing == null) != (widget.preparing == null)) {
      // The keys go to whichever of the video and the preparing view shows.
      WidgetsBinding.instance.addPostFrameCallback((_) => focusView());
    }
  }

  void focusView() {
    if (!mounted) return;
    (widget.preparing == null ? focus : preparingFocus).requestFocus();
  }

  void refresh() {
    if (playback.notice != null && playback.noticeRevision != lastNotice) {
      lastNotice = playback.noticeRevision;
      showFeedback(playback.notice!);
    }
    syncOverload();
    final next = playback.session?.id;
    if (next != sessionId) {
      sessionId = next;
      danmakuHint = _danmakuHint();
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
    unawaited(playingSubscription.cancel());
    boostTimer?.cancel();
    if (boosting) unawaited(playback.boost(false));
    focus.dispose();
    preparingFocus.dispose();
    menuCloseFocus.dispose();
    danmakuMenuFocus.dispose();
    danmakuDraft.dispose();
    danmakuInput.dispose();
    hideTimer?.cancel();
    feedbackTimer?.cancel();
    overloadLeft.dispose();
    super.dispose();
  }

  void reveal() {
    if (!mounted) return;
    if (!controls) setState(() => controls = true);
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 3), () {
      if (playback.playing &&
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
    // Long enough to read: a word flashes by, a sentence stays a little.
    feedbackTimer = Timer(Duration(milliseconds: 400 + 40 * text.length), () {
      setState(() => feedback = null);
    });
  }

  /// A new overload suggestion goes away by itself after a while.
  void syncOverload() {
    if (playback.overloaded == overload) return;
    overload = playback.overloaded;
    if (overload != null) {
      overloadLeft.value = 1;
      unawaited(overloadLeft.reverse());
    } else {
      overloadLeft.stop();
    }
  }

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

  /// The episode broadcast next. Unlike autoplay this keeps one Bangumi dates
  /// in the future: an early release may already be cached or online.
  Episode? get nextEpisode => switch (playback.session?.episodeId) {
    final id? => widget.subject?.after(
      id,
      skipExtras: playback.settings.skipExtras,
    ),
    null => null,
  };

  /// The episode broadcast before, chosen as [nextEpisode] is.
  Episode? get previousEpisode => switch (playback.session?.episodeId) {
    final id? => widget.subject?.before(
      id,
      skipExtras: playback.settings.skipExtras,
    ),
    null => null,
  };

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

  /// Closes the danmaku settings. Focus returns to their button for the
  /// keyboard, else to the video, where Space plays and pauses; a tap
  /// outside the player leaves it where the tap put it.
  void closeMenu({bool refocus = true}) {
    if (!danmakuMenu) return;
    setState(() => danmakuMenu = false);
    if (refocus) {
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional
          ? danmakuMenuFocus.requestFocus()
          : focus.requestFocus();
    }
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
    // Before the duration is known only the start bounds the seek.
    final value = duration > 0
        ? seconds.clamp(0.0, duration)
        : math.max(0.0, seconds);
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

  Future<void> exitImmersive() async {
    if (widget.mini) {
      await widget.onMiniChanged(false);
    } else if (widget.fullScreen) {
      await widget.onFullScreenChanged(false);
    } else if (widget.windowFullScreen) {
      await widget.onWindowFullScreenChanged(false);
    }
  }

  /// The preparing view has no controls; Escape and F still leave or enter
  /// fullscreen, which an episode autoplayed there would otherwise trap.
  KeyEventResult handlePreparingKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && immersive) {
      unawaited(exitImmersive());
    } else if (key == LogicalKeyboardKey.keyF ||
        key == LogicalKeyboardKey.f11) {
      unawaited(widget.onFullScreenChanged(!widget.fullScreen));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> windowFullscreen() async {
    playback.cancelAutoplay();
    await widget.onWindowFullScreenChanged(!widget.windowFullScreen);
    if (mounted) {
      focus.requestFocus();
      reveal();
    }
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    // Typing a comment: keys edit the text, and Escape returns to the video.
    if (danmakuInput.hasFocus) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        focus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
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
    } else if ((event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        FocusManager.instance.primaryFocus != focus) {
      // A focused control takes Space and Enter as a press.
      return KeyEventResult.ignored;
    } else if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.keyK) {
      playback.cancelAutoplay();
      unawaited(playback.playOrPause());
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      unawaited(seekTo(0));
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      unawaited(seekRelative(-5));
    } else if (event.logicalKey == LogicalKeyboardKey.keyF ||
        event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(fullscreen());
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (immersive) {
        unawaited(exitImmersive());
      } else if (stats) {
        setState(() => stats = false);
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
    } else if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        playback.danmaku.sendBlocked == null &&
        danmakuInput.context != null) {
      danmakuInput.requestFocus();
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

  /// Saves the frame on screen in the pictures folder's MelonBanG folder.
  Future<void> screenshot() async {
    final notices = NoticesScope.of(context);
    final at = formatTime(player.state.position.inMilliseconds / 1000)
        .replaceAll(':', '-');
    final name = safeFileName(
      [
        widget.subject?.title ?? playback.session?.title ?? 'MelonBanG',
        ?episode?.label,
        at,
      ].join(' '),
    );
    try {
      final folder = p.join(await SystemSettings.picturesFolder(), 'MelonBanG');
      final file = await playback.screenshot(folder, name);
      notices.show(
        Notice(
          '已保存截图',
          detail: p.basename(file.path),
          tone: NoticeTone.done,
          key: 'screenshot',
          actions: [
            NoticeAction(
              showInFileManagerLabel,
              () => unawaited(
                showInFileManager(
                  file.path,
                  select: true,
                ).catchError((Object e) => widget.onError(e)),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      notices.show(
        Notice(
          '截图失败',
          detail: errorMessage(e),
          tone: NoticeTone.failed,
          key: 'screenshot',
        ),
      );
    }
  }

  Future<void> openMenu(Offset position) async {
    playback.cancelAutoplay();
    if (danmakuMenu) closeMenu(refocus: false);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final previous = previousEpisode, next = nextEpisode;
    final episodes =
        widget.subject != null && playback.session?.episodeId != null;
    final playable = playback.uri != null && !playback.opening;
    PopupMenuItem<String> item(
      String value,
      String label, {
      bool enabled = true,
      bool checked = false,
    }) => PopupMenuItem(
      value: value,
      enabled: enabled,
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: checked
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : null,
          ),
          const SizedBox(width: Gap.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: FontSize.body,
              color: enabled ? Colors.white : Colors.white38,
            ),
          ),
        ],
      ),
    );
    final choice = await showMenu<String>(
      context: context,
      color: overlaySurface,
      shape: const RoundedRectangleBorder(borderRadius: controlBorderRadius),
      menuPadding: const EdgeInsets.all(Gap.xs),
      popUpAnimationStyle: AnimationStyle(
        duration: motionDuration(context, 150),
        reverseDuration: motionDuration(context, 100),
        curve: Curves.easeOutCubic,
      ),
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        item('screenshot', '截图', enabled: playable),
        if (!widget.mini) item('stats', '详细参数', checked: stats),
        if (episodes) ...[
          const PopupMenuDivider(height: 9, color: Colors.white12),
          item('previous', '上一话', enabled: previous != null),
          item('next', '下一话', enabled: next != null),
        ],
      ],
    );
    if (!mounted) return;
    focus.requestFocus();
    switch (choice) {
      case 'screenshot':
        unawaited(screenshot());
      case 'stats':
        setState(() => stats = !stats);
      case 'previous' when previous != null:
        widget.onEpisode(previous);
      case 'next' when next != null:
        widget.onEpisode(next);
    }
  }

  /// The notices in the bottom right of a page with no video, where the
  /// rest of the app shows them; the small window has no room for them.
  Widget notices() => Positioned(
    key: const ValueKey('player-notices'),
    bottom: pageGutter,
    right: pageGutter,
    child: widget.mini
        ? const SizedBox.shrink()
        : NoticeStack(notices: NoticesScope.of(context), glass: true),
  );

  /// Whether autoplay counts down or says why it did not, in the corner.
  bool get autoplayShown =>
      playback.autoplayTarget != null || playback.autoplayMessage != null;

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
      return Stack(
        fit: StackFit.expand,
        children: [
          Focus(
            focusNode: preparingFocus,
            autofocus: true,
            onKeyEvent: handlePreparingKey,
            child: ValueListenableBuilder(
              valueListenable: widget.downloads.snapshot,
              builder: (context, snapshot, _) => PreparingView(
                preparing: preparing,
                task: switch (preparing.downloadId) {
                  final id? => snapshot.task(id),
                  null => null,
                },
                onRetry: widget.onRetryPreparing,
                onChoose: widget.onChoosePreparing,
                onExitFullScreen: immersive
                    ? () => unawaited(exitImmersive())
                    : null,
                exitLabel: widget.mini ? '回到窗口 (Esc)' : '退出全屏 (Esc)',
              ),
            ),
          ),
          notices(),
        ],
      );
    }
    if (playback.uri == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_circle_outline, size: 48),
                const SizedBox(height: Gap.lg),
                Text(playback.error ?? '选一部作品，开始观看'),
                TextButton(onPressed: widget.onBack, child: const Text('返回')),
              ],
            ),
          ),
          notices(),
        ],
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
        return Stack(
          children: [
            Row(
              children: [
                Expanded(child: video(context, panel: showPanel)),
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
                        child: PlayerSidePanel(
                          playback: playback,
                          community: widget.community,
                          subject: widget.subject,
                          session: playback.session,
                          source: widget.source,
                          remembered: widget.remembered,
                          onForgetSource: widget.onForgetSource,
                          downloads: widget.downloads.snapshot,
                          tab: panelTab,
                          onTab: (tab) => setState(() => panelTab = tab),
                          onEpisode: widget.onEpisode,
                          onFindResources: findResources,
                          onPlayFile: widget.onPlayFile,
                          onToggleTask: widget.downloads.toggle,
                          onMarkEpisode: widget.onMarkEpisode,
                          onOpenSubject: widget.onOpenSubject,
                          onError: widget.onError,
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
                bottom: _transportInset,
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
                              constraints.maxHeight - _transportInset - 24,
                            ),
                          ),
                          child: PlayerResourceSheet(
                            key: ValueKey(
                              'resource-sheet:${widget.subject!.id}',
                            ),
                            newSearch: widget.newResourceSearch,
                            playback: playback,
                            onPlay: widget.onPlayCandidate,
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

  Widget video(BuildContext context, {required bool panel}) => LayoutBuilder(
    builder: (context, constraints) {
      final failure = widget.failure?.reason ?? playback.error;
      final toast = feedback != null || boosting;
      if (toast) {
        shownBoost = boosting;
        shownFeedback = boosting ? '3× 快进中' : feedback!;
      }
      // The prompts and popovers over the video read the picture behind
      // their glass once between them.
      return BackdropGroup(
        // A tap on the video closes the danmaku settings itself, without
        // also playing or pausing; one beside it closes them as well.
        child: TapRegion(
          groupId: menuTapGroup,
          child: Focus(
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
                    onSecondaryTapUp: (details) =>
                        unawaited(openMenu(details.globalPosition)),
                    // The small window has no title bar: the video moves
                    // it, and a double click brings the window back.
                    onPanStart: widget.mini
                        ? (_) => widget.onDragWindow()
                        : null,
                    onDoubleTap: widget.mini
                        ? () => unawaited(widget.onMiniChanged(false))
                        : fullscreen,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Super-resolution renders at the shown size.
                        final ratio = MediaQuery.devicePixelRatioOf(context);
                        playback.showAt(
                          Size(
                            constraints.maxWidth * ratio,
                            constraints.maxHeight * ratio,
                          ),
                        );
                        return Video(
                          controller: playback.video,
                          controls: NoVideoControls,
                          fit: playback.aspect == 'fill'
                              ? BoxFit.fill
                              : BoxFit.contain,
                          aspectRatio: switch (playback.aspect.split(':')) {
                            [final width, final height] =>
                              double.parse(width) / double.parse(height),
                            _ => null,
                          },
                          subtitleViewConfiguration:
                              const SubtitleViewConfiguration(visible: false),
                        );
                      },
                    ),
                  ),
                  DanmakuLayer(
                    playback: playback,
                    onJump: (seconds) {
                      focus.requestFocus();
                      showFeedback('跳到 ${formatTime(seconds)}');
                      unawaited(seekTo(seconds));
                    },
                  ),
                  StreamBuilder<bool>(
                    stream: player.stream.buffering,
                    initialData: player.state.buffering,
                    builder: (_, snapshot) =>
                        (playback.opening || snapshot.data == true) &&
                            failure == null
                        // Fades in after a moment, so a brief stall does not
                        // flash the spinner.
                        ? MotionAppear(
                            offset: 0,
                            delay: 250,
                            child: ValueListenableBuilder(
                              valueListenable: widget.downloads.snapshot,
                              builder: (context, downloads, _) =>
                                  BufferingStatus(
                                    opening: playback.opening,
                                    task: switch (playback.session) {
                                      PlaybackSession(
                                        :final downloadId?,
                                        streamId: _?,
                                      ) =>
                                        downloads.task(downloadId),
                                      _ => null,
                                    },
                                  ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (failure != null)
                    Center(
                      child: MotionAppear(
                        offset: 10,
                        milliseconds: 280,
                        child: FailureCard(
                          reason: failure,
                          onRetry: widget.failure == null
                              ? null
                              : widget.onRetryFailure,
                          onChoose: widget.subject == null
                              ? null
                              : () => findResources(
                                  widget.failure?.episode ?? episode,
                                ),
                          onBack: widget.onBack,
                          onExitFullScreen: immersive
                              ? () => unawaited(exitImmersive())
                              : null,
                          exitLabel: widget.mini ? '回到窗口 (Esc)' : '退出全屏 (Esc)',
                        ),
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
                                    padding: const EdgeInsets.all(Gap.md),
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
                  // In the middle, just above the paused play button.
                  Positioned.fill(
                    key: const ValueKey('player-feedback'),
                    bottom: 144,
                    child: IgnorePointer(
                      child: Center(
                        // The glass fades itself: an Opacity around its blur
                        // would blur nothing on some renderers. Faded out it
                        // is not painted, so no blur runs under the video.
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: toast ? 1 : 0),
                          duration: motionDuration(context, toast ? 150 : 200),
                          builder: (context, visibility, child) => Offstage(
                            offstage: visibility == 0 && !toast,
                            child: AnimatedScale(
                              scale: toast ? 1 : .94,
                              duration: motionDuration(context, 220),
                              curve: Curves.easeOutCubic,
                              child: OverlayGlass(
                                visibility: visibility,
                                child: child!,
                              ),
                            ),
                          ),
                          child: AnimatedSize(
                            duration: motionDuration(context, 180),
                            curve: Curves.easeOutCubic,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Gap.lg,
                                vertical: Gap.sm,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (shownBoost) ...[
                                    const Icon(
                                      Icons.fast_forward_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: Gap.sm),
                                  ],
                                  Text(
                                    shownFeedback,
                                    style: const TextStyle(
                                      fontSize: FontSize.body,
                                      color: Colors.white,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
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
                              colors: [overlayScrim, Colors.transparent],
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
                  if (!immersive)
                    Positioned(
                      key: const ValueKey('player-panel-handle'),
                      top: 0,
                      right: 0,
                      bottom: 0,
                      // Folded, it stays out of sight until the pointer comes
                      // near the right edge, anywhere along its height; clicks
                      // there still reach the video.
                      child: MouseRegion(
                        opaque: false,
                        onEnter: (_) => setState(() => handleHovered = true),
                        onExit: (_) => setState(() => handleHovered = false),
                        child: SizedBox(
                          width: panel ? null : _handleReach,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: IgnorePointer(
                              ignoring: panel && !controls && !danmakuMenu,
                              child: AnimatedOpacity(
                                opacity:
                                    (panel
                                        ? controls || danmakuMenu
                                        : handleHovered)
                                    ? 1
                                    : 0,
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
                                  child: _PanelHandle(
                                    open: panel,
                                    onPressed: () =>
                                        widget.panelOpen.value = !panel,
                                  ),
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
                                danmakuMenuGroup: menuTapGroup,
                                onDanmakuMenuOutside: () =>
                                    closeMenu(refocus: false),
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
                                danmakuDraft: danmakuDraft,
                                danmakuHint: danmakuHint,
                                danmakuInput: danmakuInput,
                                onDanmakuInputDone: () {
                                  focus.requestFocus();
                                  reveal();
                                },
                                danmakuMenu: (visibility) => ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: math.max(
                                      120,
                                      constraints.maxHeight - 160,
                                    ),
                                  ),
                                  child: DanmakuQuickSettings(
                                    visibility: visibility,
                                    closeFocusNode: menuCloseFocus,
                                    preferences: playback.danmaku.preferences,
                                    onClose: closeMenu,
                                    // The panel is hidden in immersive modes.
                                    onOpenSources: immersive
                                        ? null
                                        : () =>
                                              showPanel(PlayerPanelTab.danmaku),
                                  ),
                                ),
                                mini: widget.mini,
                                onMini: () => unawaited(
                                  widget.onMiniChanged(!widget.mini),
                                ),
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
                  if (playback.overloaded case final mode? when failure == null)
                    AnimatedPositioned(
                      duration: motionDuration(context),
                      curve: Curves.easeOutCubic,
                      left: pageGutter,
                      right: pageGutter,
                      bottom: controls ? _transportInset : pageGutter,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: MotionAppear(
                          offset: 8,
                          milliseconds: 260,
                          child: MouseRegion(
                            onEnter: (_) => overloadLeft.stop(),
                            onExit: (_) {
                              if (overload != null) {
                                unawaited(overloadLeft.reverse());
                              }
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: NoticeStack.width,
                              ),
                              child: NoticeCard(
                                title: mode == 'quality'
                                    ? '画面卡顿，可改用效率档'
                                    : '画面卡顿，可关闭超分',
                                tone: NoticeTone.warning,
                                actions: [
                                  if (mode == 'quality')
                                    NoticeAction(
                                      '改用效率档',
                                      () => unawaited(
                                        playback.setSuperResolution('fast'),
                                      ),
                                    ),
                                  NoticeAction(
                                    '关闭超分',
                                    () => unawaited(
                                      playback.setSuperResolution('off'),
                                    ),
                                  ),
                                ],
                                onClose: playback.dismissOverload,
                                remaining: overloadLeft,
                                glass: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (stats && !widget.mini)
                    Positioned(
                      key: const ValueKey('player-stats'),
                      top: 56,
                      left: pageGutter,
                      child: MotionAppear(
                        offset: 6,
                        milliseconds: 200,
                        child: PlayerStatsPanel(
                          playback: playback,
                          source: widget.source,
                          downloads: widget.downloads.snapshot,
                          onClose: () {
                            setState(() => stats = false);
                            focus.requestFocus();
                          },
                        ),
                      ),
                    ),
                  // Above the controls, whose gradient would catch its clicks:
                  // the window's notices, then the player's prompts nearest the
                  // corner, over the transport bar while it shows and while
                  // autoplay counts down, so its buttons stay put.
                  AnimatedPositioned(
                    key: const ValueKey('player-corner'),
                    duration: motionDuration(context),
                    curve: Curves.easeOutCubic,
                    right: pageGutter,
                    bottom: controls || autoplayShown
                        ? _transportInset
                        : pageGutter,
                    // Holds the controls, and so the corner's place, while
                    // the pointer is in it. It stays when its cards go, so
                    // leaving is always heard, and lets the pointer through
                    // where nothing is drawn.
                    child: MouseRegion(
                      opaque: false,
                      onEnter: (_) {
                        controlsHovered = true;
                        reveal();
                      },
                      onExit: (_) {
                        controlsHovered = false;
                        reveal();
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // The small window has no room for them.
                          if (!widget.mini)
                            NoticeStack(
                              notices: NoticesScope.of(context),
                              glass: true,
                            ),
                          if (playback.openingEnding case final marks?)
                            StreamBuilder<Duration>(
                              stream: player.stream.position,
                              initialData: player.state.position,
                              builder: (_, position) {
                                final now =
                                    position.data!.inMilliseconds / 1000;
                                // Offered until 3 s before the song ends.
                                bool inside(ChapterSpan? span) =>
                                    span != null &&
                                    now >= span.start &&
                                    now < span.end - 3;
                                final (label, target) = inside(marks.opening)
                                    ? ('跳过 OP', marks.opening!.end)
                                    : inside(marks.ending)
                                    ? ('跳过 ED', marks.ending!.end)
                                    : (null, 0.0);
                                final upcoming = playback.upcomingSkip;
                                if ((label == null && upcoming == null) ||
                                    failure != null) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: Gap.sm),
                                  child: MotionAppear(
                                    key: ValueKey(upcoming ?? label),
                                    offset: 8,
                                    milliseconds: 260,
                                    child: upcoming != null
                                        ? CountdownCard(
                                            title: '即将跳过 $upcoming',
                                            detail:
                                                '跳到 ${formatTime(playback.skipTarget!)}',
                                            seconds: playback.skipCountdown,
                                            // Five seconds of the media
                                            // count down.
                                            remaining:
                                                ((playback.skipAt - now) / 5)
                                                    .clamp(0, 1),
                                            confirm: '立即跳过',
                                            onConfirm: () {
                                              playback.skipNow();
                                              focus.requestFocus();
                                            },
                                            onCancel: () {
                                              playback.cancelSkip();
                                              focus.requestFocus();
                                            },
                                          )
                                        : SkipButton(
                                            label: label!,
                                            onPressed: () {
                                              showFeedback(label);
                                              unawaited(seekTo(target));
                                            },
                                          ),
                                  ),
                                );
                              },
                            ),
                          if (autoplayShown)
                            Padding(
                              padding: const EdgeInsets.only(top: Gap.sm),
                              child: MotionAppear(
                                offset: 8,
                                milliseconds: 260,
                                child: switch (playback.autoplayTarget) {
                                  final target? => CountdownCard(
                                    title: '即将播放${target.episode.label}',
                                    detail: target.sourceLabel,
                                    seconds: playback.autoplaySeconds,
                                    // Five seconds tick one at a time; the ring
                                    // runs through each toward the next.
                                    remaining:
                                        (playback.autoplaySeconds - 1) / 5,
                                    ease: 1000,
                                    confirm: '立即播放',
                                    onConfirm: playback.playAutoplay,
                                    onCancel: playback.cancelAutoplay,
                                  ),
                                  // As wide as the notices above it, and no
                                  // wider than the small window.
                                  null => SizedBox(
                                    width: math.min(
                                      NoticeStack.width,
                                      constraints.maxWidth - 2 * pageGutter,
                                    ),
                                    child: NoticeCard(
                                      title: playback.autoplayMessage!,
                                      tone: playback.autoplayTone,
                                      actions: [
                                        if (playback.autoplayEndEpisode
                                            case final episode?)
                                          NoticeAction(
                                            '查找资源',
                                            () => findResources(episode),
                                          ),
                                      ],
                                      onClose: playback.dismissAutoplayMessage,
                                      glass: true,
                                    ),
                                  ),
                                },
                              ),
                            ),
                        ],
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

/// Room the transport bar takes at the bottom of the video.
const _transportInset = 108.0;

/// How far from the right edge the folded panel handle shows up; wide
/// enough to still steer onto it on the way there.
const _handleReach = 160.0;

const _danmakuHints = ['发个友善的弹幕见证当下', '请输入文本', '前方高能？', '我掌握了弹幕的核心！'];

String _danmakuHint() =>
    _danmakuHints[math.Random().nextInt(_danmakuHints.length)];

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
            style: const TextStyle(
              fontSize: FontSize.emphasis,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (episode case final episode?)
            TextSpan(
              text: '   ${episodeLabel(episode)}',
              style: const TextStyle(
                fontSize: FontSize.body,
                color: overlayMuted,
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

/// Sits on the video's edge beside the side panel, so folding or unfolding
/// it is a short move from either side.
class _PanelHandle extends StatelessWidget {
  const _PanelHandle({required this.open, required this.onPressed});
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: open ? '收起侧边栏' : '展开侧边栏',
    child: Material(
      color: overlaySurface,
      borderRadius: BorderRadius.horizontal(left: controlBorderRadius.topLeft),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 24,
          height: 64,
          child: Icon(
            open ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
            size: 22,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}
