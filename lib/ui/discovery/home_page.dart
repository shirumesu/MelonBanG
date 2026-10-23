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
    required this.onOpenTracking,
  });
  final DiscoveryController discovery;
  final TrackingController personal;
  final ResumeController resume;
  final VoidCallback onExplore, onCalendar, onRefresh, onOpenTracking;
  final ActionFeedback feedback;
  final ValueChanged<Subject> onOpenSubject;

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
    final continuation = _ContinueSection(
      watching: watching,
      resumable: resume.resumable,
      played: resume.played,
      airingToday: {for (final item in today) item.id},
      onOpenSubject: onOpenSubject,
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
            top: 0,
            trailing: refresh,
          ),
        showcase,
        const SizedBox(height: Gap.xxl),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: continuation),
              const SizedBox(width: Gap.lg),
              SizedBox(
                width: homeSideColumnWidth,
                height: lowerHeight,
                child: timeline,
              ),
            ],
          )
        else ...[
          continuation,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    index = PageStorage.maybeOf(context)?.readState(context) as int? ?? index;
  }

  void select(int value) {
    setState(() => index = value % widget.items.length);
    PageStorage.maybeOf(context)?.writeState(context, index);
  }

  @override
  Widget build(BuildContext context) {
    final current = index.clamp(0, widget.items.length - 1);
    final spotlight = _Spotlight(
      item: widget.items[current],
      rank: current + 1,
      count: widget.items.length,
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
    required this.rank,
    required this.count,
    required this.onOpen,
    required this.onPrevious,
    required this.onNext,
  });
  final Subject item;
  final int rank, count;
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
                  duration: motionDuration(context, 220),
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
                              '#$rank 本季热度',
                              style: TextStyle(
                                color: rank <= 3 ? gold : muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
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
                                fontWeight: FontWeight.w800,
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
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '★ ${scoreLabel(item.score)}',
                                  style: const TextStyle(
                                    color: gold,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 4),
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
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
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
                                      fontSize: 12.5,
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
                                Text(
                                  '$rank / $count',
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: Gap.sm),
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
      padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.sm, Gap.sm),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Gap.sm, bottom: Gap.xs),
            child: Row(
              children: [
                const Icon(
                  Icons.local_fire_department_outlined,
                  size: 18,
                  color: coral,
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
                color: i == selected
                    ? scheme.primaryContainer.withValues(alpha: .6)
                    : Colors.transparent,
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
                                fontWeight: FontWeight.w800,
                                color: i < 3 ? coral : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              items[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: i == selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: Gap.sm),
                          Text(
                            '★ ${scoreLabel(items[i].score)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
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
    );
  }
}

class _ContinueSection extends StatelessWidget {
  const _ContinueSection({
    required this.watching,
    required this.resumable,
    required this.played,
    required this.airingToday,
    required this.onOpenSubject,
    required this.onExplore,
    required this.onOpenTracking,
  });
  final List<Subject> watching;
  final List<PlaybackResume> resumable;
  final List<int> played;
  final Set<int> airingToday;
  final ValueChanged<Subject> onOpenSubject;
  final VoidCallback onExplore, onOpenTracking;

  @override
  Widget build(BuildContext context) {
    final resume = resumable.take(4).toList();
    final resumeIds = {for (final item in resume) item.subject.id};
    final watchingById = {for (final item in watching) item.id: item};
    final byId = <int, (Subject, PlaybackResume?)>{
      for (final item in resume) item.subject.id: (item.subject, item),
      for (final item in watching)
        if (!resumeIds.contains(item.id)) item.id: (item, null),
    };
    // Most recently played first; of the rest, shows airing today lead.
    final posters = [
      for (final id in played) ?byId.remove(id),
      ...byId.values.where((e) => airingToday.contains(e.$1.id)),
      ...byId.values.where((e) => !airingToday.contains(e.$1.id)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title: '继续观看',
          icon: Icons.play_circle_outline,
          color: accentOf(context).accent,
          top: 0,
          trailing: TextButton(
            onPressed: onOpenTracking,
            child: const Text('全部追番 →'),
          ),
        ),
        if (posters.isEmpty)
          EmptyState(text: '还没有在追的番剧', action: onExplore, actionLabel: '搜索番剧')
        else
          HorizontalPosters(
            storageId: const ValueKey('continue-posters'),
            ranked: false,
            itemCount: posters.length,
            itemBuilder: (i) {
              final (item, resume) = posters[i];
              return resume != null
                  ? _ResumePoster(
                      item: resume,
                      // The collection row carries the watched count.
                      meta: watchingById[item.id] ?? item,
                      onOpen: onOpenSubject,
                    )
                  : SubjectPoster(
                      item: item,
                      onOpen: onOpenSubject,
                      tracking: true,
                      badge: airingToday.contains(item.id) ? '今日更新' : null,
                    );
            },
          ),
      ],
    );
  }
}

class _ResumePoster extends StatefulWidget {
  const _ResumePoster({
    required this.item,
    required this.meta,
    required this.onOpen,
  });
  final PlaybackResume item;

  /// Score and progress shown under the poster.
  final Subject meta;
  final ValueChanged<Subject> onOpen;

  @override
  State<_ResumePoster> createState() => _ResumePosterState();
}

class _ResumePosterState extends State<_ResumePoster> {
  bool hovered = false, focused = false;

  @override
  Widget build(BuildContext context) {
    final resume = widget.item;
    final item = resume.subject;
    final position = resume.position;
    final duration = resume.duration;
    final episodeLabel = resume.episodeSort == null
        ? null
        : '第 ${resume.episodeSort} 话';
    final remaining = ((duration - position) / 60).ceil();
    final scheme = Theme.of(context).colorScheme;
    final active = hovered || focused;
    return Semantics(
      label: item.title,
      child: InkWell(
        onTap: () => widget.onOpen(item),
        onHover: (value) => setState(() => hovered = value),
        onFocusChange: (value) => setState(() => focused = value),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        borderRadius: posterBorderRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: posterBorderRadius,
                  boxShadow: posterShadows(context),
                ),
                child: ClipRRect(
                  borderRadius: posterBorderRadius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SubjectCover(
                        url: item.coverUrl,
                        title: item.title,
                        id: item.id,
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [.35, 1],
                            colors: [Colors.transparent, Color(0xcc000000)],
                          ),
                          color: active
                              ? Colors.black.withValues(alpha: .12)
                              : null,
                        ),
                      ),
                      if (episodeLabel != null)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accentOf(context).accent,
                              borderRadius: badgeBorderRadius,
                            ),
                            child: Text(
                              episodeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.black38,
                            borderRadius: badgeBorderRadius,
                          ),
                          child: Text(
                            '剩余 $remaining 分钟',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 11,
                        right: 10,
                        bottom: 14,
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (duration > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: (position / duration).clamp(0, 1),
                            minHeight: 4,
                            color: accentOf(context).accent,
                            backgroundColor: Colors.white24,
                            semanticsLabel: '观看进度',
                          ),
                        ),
                      if (focused)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: posterBorderRadius,
                            border: Border.all(color: scheme.primary, width: 2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            PosterMeta(item: widget.meta, tracking: true),
          ],
        ),
      ),
    );
  }
}
