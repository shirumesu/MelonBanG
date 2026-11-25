import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/notices.dart';
import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';
import '../../features/discovery/continue_range.dart';
import '../../features/playback/playback_library.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_cover.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import '../core/tone.dart';
import 'release_labels.dart';

/// A subscribed show on the home page: the episode it waited too long
/// for, and how long, as 等字幕组 26 小时.
typedef SubscriptionMark = ({int? lateEpisode, String? late});

/// A watched subject and what it offers next.
class _Watch {
  _Watch({
    required this.item,
    required this.detail,
    required this.resume,
    required this.seen,
    required this.airings,
    this.subscription,
  }) {
    // Recorded episodes decide; without any, the watched count does.
    final marked = episodes.any((e) => e.watched);
    final counted = item.watchedEpisodes ?? 0;
    watched = [
      for (final (i, e) in episodes.indexed) marked ? e.watched : i < counted,
    ];
    aired = [for (final e in episodes) episodeAired(e, airings)];
    // The one after the furthest watched: a gap before it is more often
    // watched elsewhere than skipped. Past the last, the first unwatched.
    final furthest = watched.lastIndexOf(true);
    final following = furthest + 1 < episodes.length
        ? furthest + 1
        : watched.indexOf(false);
    final resumed = episodes.indexWhere((e) => e.id == resume?.episodeId);
    nextIndex = resumed >= 0 && (resumed == following || resume!.engaged)
        ? resumed
        : following;
    release = nextIndex < 0 || aired[nextIndex]
        ? null
        : episodeRelease(episodes[nextIndex], airings);
  }

  /// The collection row, which carries the score and watched count.
  final Subject item;

  /// The detail with its episodes; null until it loads.
  final Subject? detail;
  final PlaybackResume? resume;

  /// When an episode of it last played.
  final DateTime? seen;
  final List<DateTime> airings;

  final SubscriptionMark? subscription;
  late final List<Episode> episodes = [
    ...?detail?.episodes.where((e) => e.main),
  ];
  late final List<bool> watched, aired;
  late final int nextIndex;

  /// When the next episode airs, while it has not.
  late final Release? release;

  Episode? get next => nextIndex < 0 ? null : episodes[nextIndex];

  /// Whether the next episode can be watched now; assumed until the
  /// episodes load.
  bool get ready => detail == null || (nextIndex >= 0 && aired[nextIndex]);

  /// Aired episodes not yet watched.
  int get unwatched => [
    for (final (i, value) in watched.indexed)
      if (!value && aired[i]) i,
  ].length;

  /// The saved position of the next episode, from 0 to 1.
  double? get resumed => switch (resume) {
    final resume? when resume.episodeId == next?.id && resume.duration > 0 =>
      (resume.position / resume.duration).clamp(0, 1),
    _ => null,
  };

  String get remaining =>
      '剩余 ${((resume!.duration - resume!.position) / 60).ceil()} 分钟';
}

class _Progress extends StatelessWidget {
  const _Progress(this.watch, {required this.style});
  final _Watch watch;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => MotionCount(
    value: watch.item.watchedEpisodes ?? 0,
    builder: (context, watched) => Text(switch (watch.item.episodeTotal) {
      null => '已看 $watched 话',
      final total => '已看 $watched/$total',
    }, style: style),
  );
}

/// How long ago [at] was: minutes and hours today, then 昨天, days within a
/// week, else the date.
String _ago(DateTime at) {
  final now = DateTime.now();
  final passed = now.difference(at);
  final days = DateUtils.dateOnly(now)
      .difference(DateUtils.dateOnly(at))
      .inDays;
  return switch (days) {
    0 when passed.inMinutes < 1 => '刚刚',
    0 when passed.inHours < 1 => '${passed.inMinutes} 分钟前',
    0 => '${passed.inHours} 小时前',
    1 => '昨天',
    < 7 => '$days 天前',
    _ when at.year == now.year => '${at.month}月${at.day}日',
    _ => '${at.year}年${at.month}月${at.day}日',
  };
}

/// The latest first; subjects never played follow, most recently collected
/// first.
int _bySeen(_Watch a, _Watch b) => switch ((a.seen, b.seen)) {
  (final x?, final y?) => y.compareTo(x),
  (_?, null) => -1,
  (null, _?) => 1,
  _ => switch ((
    a.item.collection?.collectedAt,
    b.item.collection?.collectedAt,
  )) {
    (final x?, final y?) => y.compareTo(x),
    (_?, null) => -1,
    (null, _?) => 1,
    _ => 0,
  },
};

class ContinueSection extends StatefulWidget {
  const ContinueSection({
    super.key,
    required this.loaded,
    required this.watching,
    required this.details,
    required this.playable,
    required this.resumable,
    required this.played,
    required this.airings,
    required this.airingToday,
    required this.onOpenSubject,
    required this.onPlayEpisode,
    required this.onExplore,
    required this.onOpenTracking,
    required this.subscriptions,
    required this.outOfRange,
    required this.range,
  });

  /// Whether the saved collection has been read; until then the panel
  /// stays empty rather than say nothing is being watched.
  final bool loaded;
  final List<Subject> watching;

  /// Watched shows [range] leaves out.
  final int outOfRange;
  final ContinueRange range;
  final Map<int, SubscriptionMark> subscriptions;
  final Map<int, Subject> details;
  final Map<int, Set<int>> playable;
  final List<PlaybackResume> resumable;
  final Map<int, DateTime> played;
  final Map<int, List<DateTime>> airings;
  final Set<int> airingToday;
  final ValueChanged<Subject> onOpenSubject;
  final void Function(Subject subject, Episode episode) onPlayEpisode;
  final VoidCallback onExplore, onOpenTracking;

  @override
  State<ContinueSection> createState() => _ContinueSectionState();
}

class _ContinueSectionState extends State<ContinueSection> {
  /// Subjects the queue has shown; later ones fade in as they join.
  final _shown = <int>{};

  // Episodes become watchable as they air.
  @override
  Widget build(BuildContext context) =>
      ShownClock(period: const Duration(minutes: 1), builder: _build);

  Widget _build(BuildContext context) {
    final resumes = {
      for (final item in widget.resumable) item.subject.id: item,
    };
    final all = [
      for (final item in widget.watching)
        _Watch(
          item: item,
          detail: widget.details[item.id],
          resume: resumes[item.id],
          seen: widget.played[item.id],
          airings: widget.airings[item.id] ?? const [],
          subscription: widget.subscriptions[item.id],
        ),
    ];
    // Watchable ones by when they last played; the rest below by when
    // their next episode airs, rejoining the order once it does.
    final ready = all.where((e) => e.ready).toList()..sort(_bySeen);
    final waiting = all.where((e) => !e.ready).toList()
      ..sort(
        (a, b) => switch ((a.release, b.release)) {
          (final x?, final y?) => x.at.compareTo(y.at),
          (_?, null) => -1,
          (null, _?) => 1,
          _ => _bySeen(a, b),
        },
      );
    final hero = ready.firstOrNull ?? ([...waiting]..sort(_bySeen)).firstOrNull;
    final readyRest = ready.where((e) => e != hero).toList();
    final waitingRest = waiting.where((e) => e != hero).toList();
    final known = _shown.isNotEmpty;
    var place = 0;
    Widget row(_Watch watch) {
      final id = watch.item.id;
      return MotionSlide(
        key: ValueKey(id),
        index: place++,
        enter: known && !_shown.contains(id),
        child: _QueueRow(
          watch: watch,
          today: widget.airingToday.contains(id),
          onOpen: widget.onOpenSubject,
          onPlay: widget.onPlayEpisode,
        ),
      );
    }

    _shown.addAll([for (final watch in all) watch.item.id]);
    return HeadedPanel(
      icon: Icons.play_circle_outline,
      title: '继续观看',
      action: TextButton(
        onPressed: widget.onOpenTracking,
        child: const Text('全部追番'),
      ),
      child: hero == null && !widget.loaded
          ? const SizedBox.shrink()
          : hero == null
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Shows left out by the range are still being watched;
                    // saying there are none would read as a lost collection.
                    Text(
                      widget.outOfRange > 0
                          ? '${widget.range.label}没有在追的番剧'
                          : '还没有在追的番剧',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (widget.outOfRange > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.xs),
                        child: Tooltip(
                          message: '可在「设置 › 外观 › 首页继续观看」中调整显示范围',
                          child: Text(
                            '另有 ${widget.outOfRange} 部更早开播的在追',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: widget.outOfRange > 0
                          ? widget.onOpenTracking
                          : widget.onExplore,
                      child: Text(widget.outOfRange > 0 ? '全部追番' : '搜索番剧'),
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    // With the header's and rows' own inset, contents line
                    // up with the panel title.
                    padding: const EdgeInsets.fromLTRB(
                      Gap.sm,
                      Gap.sm,
                      Gap.sm,
                      Gap.lg,
                    ),
                    child: SizedBox(
                      width: (constraints.maxWidth * .48).clamp(260.0, 344.0),
                      child: _Hero(
                        watch: hero,
                        playable:
                            widget.playable[hero.item.id] ?? const <int>{},
                        onOpen: widget.onOpenSubject,
                        onPlay: widget.onPlayEpisode,
                      ),
                    ),
                  ),
                  // A hairline keeps the hero part of the panel rather than
                  // a block set into it.
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.lg),
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  Expanded(
                    // Ends on the hero's bottom edge.
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Gap.lg),
                      child: ScrollEdgeFade(
                        child: ListView(
                          key: const PageStorageKey('continue-queue'),
                          padding: const EdgeInsets.fromLTRB(
                            Gap.sm,
                            Gap.sm,
                            Gap.sm,
                            0,
                          ),
                          children: [
                            ...readyRest.map(row),
                            if (waitingRest.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  Gap.sm,
                                  Gap.sm,
                                  Gap.sm,
                                  Gap.xs,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '等待更新',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    const SizedBox(width: Gap.sm),
                                    Expanded(
                                      child: Divider(
                                        height: 1,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ...waitingRest.map(row),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// The subject to watch next.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.watch,
    required this.playable,
    required this.onOpen,
    required this.onPlay,
  });
  final _Watch watch;

  /// Episodes that play from local files.
  final Set<int> playable;
  final ValueChanged<Subject> onOpen;
  final void Function(Subject subject, Episode episode) onPlay;

  @override
  Widget build(BuildContext context) {
    final item = watch.item;
    final next = watch.next;
    final detail = watch.detail;
    final Widget play = switch (watch.release) {
      _ when detail == null => const FilledButton(
        onPressed: null,
        child: Text('加载剧集…'),
      ),
      _ when next == null => const FilledButton(
        onPressed: null,
        child: Text('已看完'),
      ),
      final release? => FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.schedule_rounded, size: 18),
        label: Text('${releaseWhen(release)}更新'),
      ),
      null => ProminentButton(
        onPressed: () => onPlay(detail, next),
        icon: const Icon(Icons.play_arrow_rounded, size: 19),
        label: Text(
          watch.resumed == null ? '观看${next.label}' : '继续观看${next.label}',
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroHeader(watch: watch, onOpen: () => onOpen(item)),
        const SizedBox(height: Gap.sm),
        Expanded(
          child: _HeroEpisodes(
            // Opens at the next episode again when that changes.
            key: ValueKey((item.id, watch.nextIndex)),
            watch: watch,
            playable: playable,
            onPlay: onPlay,
          ),
        ),
        const SizedBox(height: Gap.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
          child: Row(children: [Expanded(child: play)]),
        ),
      ],
    );
  }
}

/// The hero's cover, title and progress; a click opens the subject.
class _HeroHeader extends StatefulWidget {
  const _HeroHeader({required this.watch, required this.onOpen});
  final _Watch watch;
  final VoidCallback onOpen;

  @override
  State<_HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends State<_HeroHeader> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final watch = widget.watch;
    final item = watch.item;
    const tabular = [FontFeature.tabularFigures()];
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onOpen,
        onHover: (value) => setState(() => hovered = value),
        borderRadius: controlBorderRadius,
        child: Padding(
          padding: const EdgeInsets.all(Gap.sm),
          child: SizedBox(
            height: 134,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CoverFrame(
                  shadow: true,
                  child: SizedBox(
                    width: 96,
                    child: SubjectCover(
                      url: item.coverUrl,
                      title: item.title,
                      id: item.id,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (watch.seen case final seen?)
                        Text('${_ago(seen)}看过', style: text.bodySmall),
                      const SizedBox(height: Gap.xs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium,
                            ),
                          ),
                          if (watch.subscription != null)
                            const Padding(
                              padding: EdgeInsets.only(
                                left: Gap.xs,
                                top: Gap.xs,
                              ),
                              child: _SubscribedMark(),
                            ),
                          AnimatedOpacity(
                            opacity: hovered ? 1 : 0,
                            duration: motionDuration(context, 120),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        '★ ${scoreLabel(item.score)}',
                        style: TextStyle(
                          fontSize: FontSize.small,
                          fontFeatures: tabular,
                          color: scheme.tertiary,
                        ),
                      ),
                      const Spacer(),
                      _Progress(
                        watch,
                        style: text.bodySmall!.copyWith(fontFeatures: tabular),
                      ),
                      if (watch.detail != null) ...[
                        const SizedBox(height: Gap.sm),
                        _EpisodeStrip(watch, height: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every episode in [_Hero], filling the room above its buttons: opened at
/// the next one with the one before above it, and scrolled for any other.
class _HeroEpisodes extends StatefulWidget {
  const _HeroEpisodes({
    super.key,
    required this.watch,
    required this.playable,
    required this.onPlay,
  });
  final _Watch watch;
  final Set<int> playable;
  final void Function(Subject subject, Episode episode) onPlay;

  @override
  State<_HeroEpisodes> createState() => _HeroEpisodesState();
}

class _HeroEpisodesState extends State<_HeroEpisodes> {
  ScrollController? scroll;

  @override
  void dispose() {
    scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watch = widget.watch;
    final count = watch.episodes.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Once all are watched, the last ones show. The one before shows
        // when three rows fit.
        final anchor = watch.nextIndex < 0 ? count : watch.nextIndex;
        final before = constraints.maxHeight >= 3 * _HeroEpisode.height ? 1 : 0;
        final room = count * _HeroEpisode.height - constraints.maxHeight;
        scroll ??= ScrollController(
          initialScrollOffset: ((anchor - before) * _HeroEpisode.height).clamp(
            0,
            math.max(0, room),
          ),
          // A place kept from another next episode would not show this one.
          keepScrollOffset: false,
        );
        return ScrollEdgeFade(
          // The fades say it scrolls; a bar would crowd the notes.
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: ListView.builder(
              controller: scroll,
              padding: EdgeInsets.zero,
              itemExtent: _HeroEpisode.height,
              itemCount: count,
              itemBuilder: (context, index) => _HeroEpisode(
                watch: watch,
                index: index,
                cached: widget.playable.contains(watch.episodes[index].id),
                onPlay: widget.onPlay,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroEpisode extends StatelessWidget {
  const _HeroEpisode({
    required this.watch,
    required this.index,
    required this.cached,
    required this.onPlay,
  });
  final _Watch watch;
  final int index;
  final bool cached;
  final void Function(Subject subject, Episode episode) onPlay;

  static const height = 36.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final episode = watch.episodes[index];
    final current = index == watch.nextIndex;
    final aired = watch.aired[index];
    final watched = watch.watched[index] && !current;
    final resumed = current ? watch.resumed : null;
    final muted = aired && !watched ? null : scheme.onSurfaceVariant;
    final subscription = watch.subscription;
    final (note, noteColor) = switch (episode) {
      _ when resumed != null => (watch.remaining, scheme.primary),
      _ when subscription?.lateEpisode == episode.id => (
        subscription!.late,
        toneColor(context, NoticeTone.warning),
      ),
      _ when !aired => (
        releaseWhen(episodeRelease(episode, watch.airings)!).trim(),
        scheme.onSurfaceVariant,
      ),
      _ when watched => ('已看', scheme.onSurfaceVariant),
      _ when cached => ('已缓存', scheme.primary),
      _ => (null, null),
    };
    return SizedBox(
      height: height,
      child: Material(
        color: current
            ? scheme.primaryContainer.withValues(alpha: .35)
            : Colors.transparent,
        borderRadius: badgeBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aired ? () => onPlay(watch.detail!, episode) : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        episode.label,
                        style: TextStyle(
                          fontSize: FontSize.body,
                          fontWeight: FontWeight.w400,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: muted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        episode.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: FontSize.body, color: muted),
                      ),
                    ),
                    if (note != null) ...[
                      const SizedBox(width: Gap.sm),
                      Text(
                        note,
                        style: TextStyle(
                          fontSize: FontSize.small,
                          color: noteColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (resumed != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: resumed,
                    minHeight: 3,
                    color: accentOf(context).accent,
                    backgroundColor: accentOf(context).accent
                        .withValues(alpha: .18),
                    semanticsLabel: '观看进度',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bell saying a subject is subscribed, shown once beside it.
class _SubscribedMark extends StatelessWidget {
  const _SubscribedMark();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '已订阅',
    child: Icon(
      Icons.notifications_active_rounded,
      size: 14,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// A subject in the queue beside [_Hero]; a play button shows under the
/// pointer.
class _QueueRow extends StatefulWidget {
  const _QueueRow({
    required this.watch,
    required this.today,
    required this.onOpen,
    required this.onPlay,
  });
  final _Watch watch;

  /// Whether the schedule airs it today.
  final bool today;
  final ValueChanged<Subject> onOpen;
  final void Function(Subject subject, Episode episode) onPlay;

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final watch = widget.watch;
    final item = watch.item;
    final next = watch.next;
    final detail = watch.detail;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall!;
    final status = switch (watch) {
      _ when detail == null => null,
      _Watch(subscription: (lateEpisode: final id?, late: final late?)) => Text(
        [
          ?watch.episodes.where((e) => e.id == id).firstOrNull?.label,
          late,
        ].join(' '),
        style: small.copyWith(color: toneColor(context, NoticeTone.warning)),
      ),
      _ when watch.ready && watch.resumed != null => Text(
        watch.remaining,
        style: small.copyWith(color: scheme.primary),
      ),
      _ when watch.ready && widget.today => const MelonBadge(
        '今日更新',
        color: coral,
      ),
      _ when watch.ready => Text(
        '${watch.unwatched} 话未看',
        style: small.copyWith(color: scheme.primary),
      ),
      _Watch(:final release?) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${releaseWhen(release)}更新',
            style: small.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (watch.subscription != null) ...[
            const SizedBox(width: Gap.xs),
            const _SubscribedMark(),
          ],
        ],
      ),
      _ => Text('已看完', style: small),
    };
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: controlBorderRadius,
        onTap: () => widget.onOpen(item),
        onHover: (value) => setState(() => hovered = value),
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            child: Row(
              children: [
                CoverFrame(
                  radius: badgeBorderRadius,
                  child: SizedBox(
                    width: 40,
                    height: 56,
                    child: Opacity(
                      opacity: watch.ready ? 1 : .75,
                      child: SubjectCover(
                        url: item.coverUrl,
                        title: item.title,
                        id: item.id,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: FontSize.body),
                            ),
                          ),
                          if (status != null) ...[
                            const SizedBox(width: Gap.sm),
                            status,
                          ],
                        ],
                      ),
                      const SizedBox(height: Gap.sm),
                      Row(
                        children: [
                          if (detail != null) ...[
                            SizedBox(width: 112, child: _EpisodeStrip(watch)),
                            const SizedBox(width: Gap.sm),
                          ],
                          _Progress(
                            watch,
                            style: small.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (watch.seen case final seen?)
                            Text(_ago(seen), style: small),
                        ],
                      ),
                    ],
                  ),
                ),
                if (detail != null && next != null && watch.ready)
                  IgnorePointer(
                    ignoring: !hovered,
                    child: AnimatedOpacity(
                      opacity: hovered ? 1 : 0,
                      duration: motionDuration(context, 120),
                      child: Padding(
                        padding: const EdgeInsets.only(left: Gap.sm),
                        child: IconButton.filledTonal(
                          tooltip: '播放${next.label}',
                          onPressed: () => widget.onPlay(detail, next),
                          icon: const Icon(Icons.play_arrow_rounded),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A continuous bar over the main episodes: watched ones filled, aired ones
/// tinted, the rest grey.
class _EpisodeStrip extends StatelessWidget {
  const _EpisodeStrip(this.watch, {this.height = 4});
  final _Watch watch;
  final double height;

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(context).accent;
    // Watched episodes only: a part played of one further on would stand
    // alone as a stray mark; the episode list shows it.
    final fills = _Fills([
      for (final watched in watch.watched) watched ? 1 : 0,
    ]);
    return TweenAnimationBuilder<_Fills>(
      tween: _FillsTween(end: fills),
      duration: motionDuration(context, 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => CustomPaint(
        size: Size.fromHeight(height),
        painter: _StripPainter(
          fills: value.values,
          aired: watch.aired,
          watchedColor: accent,
          airedColor: accent.withValues(alpha: .28),
          pendingColor: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

/// How much of each episode is watched, from 0 to 1.
class _Fills {
  const _Fills(this.values);
  final List<double> values;

  @override
  bool operator ==(Object other) =>
      other is _Fills && listEquals(other.values, values);

  @override
  int get hashCode => Object.hashAll(values);
}

class _FillsTween extends Tween<_Fills> {
  _FillsTween({required super.end});

  @override
  _Fills lerp(double t) {
    final from = begin!.values, to = end!.values;
    // A changed episode list has nothing to move from.
    if (from.length != to.length) return end!;
    return _Fills([
      for (final (i, value) in to.indexed) from[i] + (value - from[i]) * t,
    ]);
  }
}

class _StripPainter extends CustomPainter {
  const _StripPainter({
    required this.fills,
    required this.aired,
    required this.watchedColor,
    required this.airedColor,
    required this.pendingColor,
  });
  final List<double> fills;
  final List<bool> aired;
  final Color watchedColor, airedColor, pendingColor;

  @override
  void paint(Canvas canvas, Size size) {
    final count = fills.length;
    if (count == 0) return;
    final slot = size.width / count;
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ),
    );
    final paint = Paint()..color = pendingColor;
    canvas.drawRect(Offset.zero & size, paint);
    // Neighbouring episodes of a colour join into one run, so the bar shows
    // no seams between them.
    void runs(double Function(int i) extent) {
      double? start;
      var end = 0.0;
      for (var i = 0; i <= count; i++) {
        final left = i * slot;
        if (start != null &&
            (i == count || end < left - .01 || extent(i) == 0)) {
          canvas.drawRect(Rect.fromLTRB(start, 0, end, size.height), paint);
          start = null;
        }
        if (i == count || extent(i) == 0) continue;
        start ??= left;
        end = left + slot * extent(i);
      }
    }

    paint.color = airedColor;
    runs((i) => aired[i] ? 1 : 0);
    paint.color = watchedColor;
    runs((i) => fills[i]);
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      !listEquals(old.fills, fills) ||
      !listEquals(old.aired, aired) ||
      old.watchedColor != watchedColor ||
      old.airedColor != airedColor ||
      old.pendingColor != pendingColor;
}
