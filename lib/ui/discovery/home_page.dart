import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../features/discovery/discovery_controller.dart';
import '../../features/playback/playback_library.dart';
import '../../features/playback/resume_controller.dart';
import '../../features/tracking/tracking_controller.dart';
import '../core/action_feedback.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'schedule_timelines.dart';

const _showcaseHeight = 328.0;

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.discovery,
    required this.personal,
    required this.resume,
    required this.onExplore,
    required this.feedback,
    required this.onCalendar,
    required this.onRefresh,
    required this.onOpenSubject,
    required this.onPlayEpisode,
    required this.onOpenTracking,
  });
  final DiscoveryController discovery;
  final TrackingController personal;
  final ResumeController resume;
  final VoidCallback onExplore, onCalendar, onRefresh, onOpenTracking;
  final ActionFeedback feedback;
  final ValueChanged<Subject> onOpenSubject;
  final void Function(Subject subject, Episode episode) onPlayEpisode;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([discovery, personal, resume]),
    builder: (context, _) => LayoutBuilder(builder: _layout),
  );

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final trending = discovery.trending, today = discovery.today;
    final trendingLoading = discovery.trendingLoading;
    final error = discovery.trendingError;
    final watching = personal.watching;
    final wide = constraints.maxWidth - 2 * pageGutter >= 860;
    // The lower row fills the rest of the window so the timeline scrolls inside it.
    final lowerHeight = math.max(
      380.0,
      constraints.maxHeight - Gap.lg - _showcaseHeight - Gap.xxl - Gap.xl,
    );
    final refresh = FeedbackButton(
      feedback: feedback,
      label: '刷新',
      runningLabel: '刷新中…',
      successLabel: '已更新',
      icon: Icons.refresh,
      onPressed: onRefresh,
      iconOnly: true,
    );
    final Widget showcase;
    if (trendingLoading && trending.isEmpty) {
      showcase = const SizedBox(
        height: _showcaseHeight,
        child: MelonPanel(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('正在加载本季热度…'),
              SizedBox(height: Gap.md),
              SizedBox(width: 220, child: LinearProgressIndicator()),
            ],
          ),
        ),
      );
    } else if (trending.isEmpty) {
      showcase = EmptyState(
        text: error == null ? '暂时没有热门番剧' : '暂时无法加载番剧',
        detail: error,
        action: onRefresh,
      );
    } else {
      showcase = _TrendingShowcase(
        key: const PageStorageKey('trending-showcase'),
        items: trending,
        wide: wide,
        refresh: refresh,
        onOpen: onOpenSubject,
      );
    }
    final timeline = TodayTimeline(
      items: today,
      loading: discovery.todayLoading,
      error: discovery.todayError,
      watchingIds: {for (final item in watching) item.id},
      onOpen: onOpenSubject,
      onCalendar: onCalendar,
      onRetry: onRefresh,
    );
    final airings = <int, List<DateTime>>{};
    for (final day in discovery.calendar) {
      for (final item in day.items) {
        if (item.airingAt case final at?) (airings[item.id] ??= []).add(at);
      }
    }
    final continuation = _ContinueSection(
      watching: watching,
      details: resume.watching,
      playable: resume.watchingPlayable,
      resumable: resume.resumable,
      played: resume.played,
      airings: airings,
      airingToday: {for (final item in today) item.id},
      onOpenSubject: onOpenSubject,
      onPlayEpisode: onPlayEpisode,
      onExplore: onExplore,
      onOpenTracking: onOpenTracking,
    );
    return ListView(
      key: const PageStorageKey('page-scroll'),
      padding: const EdgeInsets.fromLTRB(
        pageGutter,
        Gap.lg,
        pageGutter,
        Gap.xl,
      ),
      children: [
        FeedbackIssue(feedback: feedback, onRetry: onRefresh),
        if (!wide)
          SectionTitle(
            title: '本季热度',
            icon: Icons.local_fire_department_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            top: 0,
            trailing: refresh,
          ),
        showcase,
        const SizedBox(height: Gap.xxl),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(height: lowerHeight, child: continuation),
              ),
              const SizedBox(width: Gap.lg),
              SizedBox(
                width: homeSideColumnWidth,
                height: lowerHeight,
                child: timeline,
              ),
            ],
          )
        else ...[
          SizedBox(height: 420, child: continuation),
          const SizedBox(height: Gap.xxl),
          SizedBox(height: 460, child: timeline),
        ],
      ],
    );
  }
}

class _TrendingShowcase extends StatefulWidget {
  const _TrendingShowcase({
    super.key,
    required this.items,
    required this.wide,
    required this.refresh,
    required this.onOpen,
  });
  final List<Subject> items;
  final bool wide;
  final Widget refresh;
  final ValueChanged<Subject> onOpen;

  @override
  State<_TrendingShowcase> createState() => _TrendingShowcaseState();
}

class _TrendingShowcaseState extends State<_TrendingShowcase> {
  int index = 0;

  /// Which way the last change moved, so the next title enters from there.
  int direction = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    index = PageStorage.maybeOf(context)?.readState(context) as int? ?? index;
  }

  void select(int value) {
    final current = index.clamp(0, widget.items.length - 1);
    if (value == current) return;
    setState(() {
      direction = value > current ? 1 : -1;
      index = value % widget.items.length;
    });
    PageStorage.maybeOf(context)?.writeState(context, index);
  }

  @override
  Widget build(BuildContext context) {
    final current = index.clamp(0, widget.items.length - 1);
    final spotlight = _Spotlight(
      item: widget.items[current],
      direction: direction,
      rank: current + 1,
      onOpen: widget.onOpen,
      onPrevious: () => select(current - 1),
      onNext: () => select(current + 1),
    );
    if (!widget.wide) {
      return SizedBox(height: _showcaseHeight, child: spotlight);
    }
    return SizedBox(
      height: _showcaseHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: spotlight),
          const SizedBox(width: Gap.lg),
          SizedBox(
            width: homeSideColumnWidth,
            child: _RankList(
              items: widget.items,
              selected: current,
              refresh: widget.refresh,
              onSelect: select,
            ),
          ),
        ],
      ),
    );
  }
}

class _Spotlight extends StatelessWidget {
  const _Spotlight({
    required this.item,
    required this.direction,
    required this.rank,
    required this.onOpen,
    required this.onPrevious,
    required this.onNext,
  });
  final Subject item;

  /// 1 when moving down the ranking, -1 when moving back up.
  final int direction;
  final int rank;
  final ValueChanged<Subject> onOpen;
  final VoidCallback onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final id = item.id;
    final title = item.title;
    final original = item.name ?? '';
    final summary = (item.summary ?? '').replaceAll(RegExp(r'\s+'), ' ');
    final tags = <String>[
      ?item.season?.label,
      ?item.platform,
      if (item.episodeTotal != null) '全 ${item.episodeTotal} 话',
      ...item.metaTags.where((tag) => tag != item.platform && tag != '日本'),
    ].take(5);
    const white = Colors.white;
    final muted = white.withValues(alpha: .72);
    return ClipRRect(
      borderRadius: panelBorderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xff1d2a30)),
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Transform.scale(
              scale: 1.4,
              child: SubjectCover(url: item.coverUrl, title: title, id: id),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xb3101a1e), Color(0x80101a1e)],
              ),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => onOpen(item),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: AnimatedSwitcher(
                  duration: motionDuration(context, 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  // The new title slides in from the side it came from while
                  // the old one leaves the other way.
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: animation.drive(
                        Tween(
                          begin: Offset(
                            (child.key == ValueKey(id) ? .04 : -.04) *
                                direction,
                            0,
                          ),
                          end: Offset.zero,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                  child: Row(
                    key: ValueKey(id),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: .72,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            borderRadius: posterBorderRadius,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x59000000),
                                blurRadius: 18,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: posterBorderRadius,
                            child: SubjectCover(
                              url: item.coverUrl,
                              title: title,
                              id: id,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.xl),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#$rank',
                              style: TextStyle(
                                color: rank <= 3 ? gold : muted,
                                fontSize: 13,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: Gap.sm),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: white,
                                fontSize: 24,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (original.isNotEmpty && original != title)
                              Text(
                                original,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                            const SizedBox(height: Gap.lg),
                            Wrap(
                              spacing: Gap.sm,
                              runSpacing: Gap.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '★ ${scoreLabel(item.score)}',
                                  style: const TextStyle(
                                    color: gold,
                                    fontSize: 17,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                for (final tag in tags)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: white.withValues(alpha: .14),
                                      borderRadius: badgeBorderRadius,
                                    ),
                                    child: Text(
                                      tag,
                                      style: const TextStyle(
                                        color: white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: Gap.lg),
                            Expanded(
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    summary,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 13,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: white,
                                    foregroundColor: const Color(0xff164d39),
                                  ),
                                  onPressed: () => onOpen(item),
                                  child: const Text('查看详情'),
                                ),
                                const Spacer(),
                                for (final (icon, tooltip, action) in [
                                  (Icons.chevron_left, '上一部', onPrevious),
                                  (Icons.chevron_right, '下一部', onNext),
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: IconButton(
                                      tooltip: tooltip,
                                      onPressed: action,
                                      style: IconButton.styleFrom(
                                        backgroundColor: white.withValues(
                                          alpha: .16,
                                        ),
                                        foregroundColor: white,
                                        hoverColor: white.withValues(
                                          alpha: .12,
                                        ),
                                      ),
                                      icon: Icon(icon),
                                    ),
                                  ),
                              ],
                            ),
                          ],
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
    );
  }
}

class _RankList extends StatelessWidget {
  const _RankList({
    required this.items,
    required this.selected,
    required this.refresh,
    required this.onSelect,
  });
  final List<Subject> items;
  final int selected;
  final Widget refresh;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MelonPanel(
      padding: const EdgeInsets.all(Gap.sm),
      child: MotionSelection<int>(
        selected: selected,
        highlight: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: .35),
            borderRadius: badgeBorderRadius,
          ),
        ),
        builder: (context, keyOf) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: Gap.sm, bottom: Gap.xs),
              child: Row(
                children: [
                  Icon(
                    Icons.local_fire_department_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text('本季热度', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  refresh,
                ],
              ),
            ),
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Material(
                  key: keyOf(i),
                  color: Colors.transparent,
                  borderRadius: badgeBorderRadius,
                  child: InkWell(
                    borderRadius: badgeBorderRadius,
                    onTap: () => onSelect(i),
                    child: Semantics(
                      selected: i == selected,
                      button: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: i < 3
                                      ? coral
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                items[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: Gap.sm),
                            Text(
                              '★ ${scoreLabel(items[i].score)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: scheme.tertiary,
                              ),
                            ),
                          ],
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
  }
}

/// A watched subject and what it offers next.
class _Watch {
  _Watch({
    required this.item,
    required this.detail,
    required this.resume,
    required this.seen,
    required this.airings,
  }) {
    // Recorded episodes decide; without any, the watched count does.
    final marked = episodes.any((e) => e.watched);
    final counted = item.watchedEpisodes ?? 0;
    watched = [
      for (final (i, e) in episodes.indexed) marked ? e.watched : i < counted,
    ];
    aired = [for (final e in episodes) episodeAired(e, airings)];
    final resumed = episodes.indexWhere((e) => e.id == resume?.episodeId);
    nextIndex = resumed >= 0 ? resumed : watched.indexOf(false);
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

  String get progress => switch ((item.watchedEpisodes, item.episodeTotal)) {
    (final watched, null) => '已看 ${watched ?? 0} 话',
    (final watched, final total?) => '已看 ${watched ?? 0}/$total',
  };
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

class _ContinueSection extends StatefulWidget {
  const _ContinueSection({
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
  });
  final List<Subject> watching;
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
  State<_ContinueSection> createState() => _ContinueSectionState();
}

class _ContinueSectionState extends State<_ContinueSection> {
  late final Timer clock;

  @override
  void initState() {
    super.initState();
    // Episodes become watchable as they air.
    clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    Widget row(_Watch watch) => _QueueRow(
      key: ValueKey(watch.item.id),
      watch: watch,
      today: widget.airingToday.contains(watch.item.id),
      onOpen: widget.onOpenSubject,
      onPlay: widget.onPlayEpisode,
    );
    return HeadedPanel(
      icon: Icons.play_circle_outline,
      title: '继续观看',
      action: TextButton(
        onPressed: widget.onOpenTracking,
        child: const Text('全部追番'),
      ),
      child: hero == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '还没有在追的番剧',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  TextButton(
                    onPressed: widget.onExplore,
                    child: const Text('搜索番剧'),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.lg,
                      Gap.lg,
                      0,
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
                  Expanded(
                    // Ends on the hero's bottom edge.
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Gap.lg),
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
                ],
              ),
            ),
    );
  }
}

/// The subject to watch next: its cover, the next few episodes and a play
/// button.
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
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final item = watch.item;
    final next = watch.next;
    final detail = watch.detail;
    const tabular = [FontFeature.tabularFigures()];
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
      null => FilledButton.icon(
        onPressed: () => onPlay(detail, next),
        icon: const Icon(Icons.play_arrow_rounded, size: 19),
        label: Text(
          watch.resumed == null ? '观看${next.label}' : '继续观看${next.label}',
        ),
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: controlBorderRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => onOpen(item),
              borderRadius: controlBorderRadius,
              child: SizedBox(
                height: 134,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: posterBorderRadius,
                        boxShadow: posterShadows(context),
                      ),
                      child: ClipRRect(
                        borderRadius: posterBorderRadius,
                        child: SizedBox(
                          width: 96,
                          child: SubjectCover(
                            url: item.coverUrl,
                            title: item.title,
                            id: item.id,
                          ),
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
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: Gap.xs),
                          Text(
                            '★ ${scoreLabel(item.score)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontFeatures: tabular,
                              color: scheme.tertiary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            watch.progress,
                            style: text.bodySmall!.copyWith(
                              fontFeatures: tabular,
                            ),
                          ),
                          if (detail != null) ...[
                            const SizedBox(height: 6),
                            _EpisodeStrip(watch),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            if (next != null)
              for (final index in [
                for (var i = watch.nextIndex; i < watch.episodes.length; i++) i,
              ].take(3))
                _HeroEpisode(
                  watch: watch,
                  index: index,
                  cached: playable.contains(watch.episodes[index].id),
                  onPlay: onPlay,
                ),
            const Spacer(),
            Row(
              children: [
                Expanded(child: play),
                const SizedBox(width: Gap.sm),
                OutlinedButton(
                  onPressed: () => onOpen(item),
                  child: const Text('详情'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the next episodes in [_Hero]: the next one highlighted with its
/// saved position, aired ones playable, the rest showing when they air.
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final episode = watch.episodes[index];
    final current = index == watch.nextIndex;
    final aired = watch.aired[index];
    final resumed = current ? watch.resumed : null;
    final muted = aired ? null : scheme.onSurfaceVariant;
    final (note, noteColor) = switch (episode) {
      _ when resumed != null => (watch.remaining, scheme.primary),
      _ when !aired => (
        releaseWhen(episodeRelease(episode, watch.airings)!).trim(),
        scheme.onSurfaceVariant,
      ),
      _ when cached => ('已缓存', scheme.primary),
      _ => (null, null),
    };
    return SizedBox(
      height: 36,
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
                          fontSize: 13,
                          fontWeight: current
                              ? FontWeight.w700
                              : FontWeight.w400,
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
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ),
                    if (note != null) ...[
                      const SizedBox(width: Gap.sm),
                      Text(
                        note,
                        style: TextStyle(fontSize: 12, color: noteColor),
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

/// A subject in the queue beside [_Hero]: what it offers next, its episode
/// marks and when it last played; a play button shows under the pointer.
class _QueueRow extends StatefulWidget {
  const _QueueRow({
    super.key,
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
      _Watch(:final release?) => Text(
        '${releaseWhen(release)}更新',
        style: small.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
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
                ClipRRect(
                  borderRadius: badgeBorderRadius,
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
                              style: const TextStyle(fontSize: 13),
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
                          Text(
                            watch.progress,
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

/// One mark per main episode: watched, partly watched, aired, or yet to
/// air. A long run reads better as one bar.
class _EpisodeStrip extends StatelessWidget {
  const _EpisodeStrip(this.watch);
  final _Watch watch;

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(context).accent;
    final scheme = Theme.of(context).colorScheme;
    final episodes = watch.episodes;
    const radius = BorderRadius.all(Radius.circular(2));
    if (episodes.length > 52) {
      return LinearProgressIndicator(
        value: watch.watched.where((value) => value).length / episodes.length,
        minHeight: 6,
        borderRadius: radius,
        color: accent,
        backgroundColor: scheme.outlineVariant,
      );
    }
    final gap = episodes.length > 26 ? 1.0 : 2.0;
    final resumed = watch.resumed;
    return SizedBox(
      height: 6,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, _) in episodes.indexed) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              child: watch.watched[i]
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: radius,
                      ),
                    )
                  : i == watch.nextIndex && resumed != null
                  ? ClipRRect(
                      borderRadius: radius,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: accent),
                          borderRadius: radius,
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: resumed,
                          child: ColoredBox(color: accent),
                        ),
                      ),
                    )
                  : DecoratedBox(
                      decoration: watch.aired[i]
                          ? BoxDecoration(
                              border: Border.all(
                                color: accent.withValues(alpha: .6),
                              ),
                              borderRadius: radius,
                            )
                          : BoxDecoration(
                              color: scheme.outlineVariant,
                              borderRadius: radius,
                            ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
