import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/action_feedback.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';

const _showcaseHeight = 328.0;

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.today,
    required this.trending,
    required this.trendingLoading,
    required this.error,
    required this.onExplore,
    required this.feedback,
    required this.onCalendar,
    required this.onRefresh,
    required this.onOpenSubject,
    required this.onOpenTracking,
    this.watching = const [],
    this.resumable = const [],
    this.onResume,
    this.todayLoading = false,
    this.todayError,
  });
  final bool trendingLoading, todayLoading;
  final List<Json> today, trending, watching, resumable;
  final String? error, todayError;
  final VoidCallback onExplore, onCalendar, onRefresh, onOpenTracking;
  final ActionFeedback feedback;
  final ValueChanged<Json> onOpenSubject;
  final ValueChanged<Json>? onResume;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
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
      final timeline = _TodayTimeline(
        items: today,
        loading: todayLoading,
        error: todayError,
        watchingIds: {for (final item in watching) item['subjectId']},
        onOpen: onOpenSubject,
        onCalendar: onCalendar,
        onRetry: onRefresh,
      );
      final continuation = _ContinueSection(
        watching: watching,
        resumable: onResume == null ? const [] : resumable,
        airingToday: {for (final item in today) item['subjectId']},
        onResume: onResume,
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
    },
  );
}

class _TrendingShowcase extends StatefulWidget {
  const _TrendingShowcase({
    super.key,
    required this.items,
    required this.wide,
    required this.refresh,
    required this.onOpen,
  });
  final List<Json> items;
  final bool wide;
  final Widget refresh;
  final ValueChanged<Json> onOpen;

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
  final Json item;
  final int rank, count;
  final ValueChanged<Json> onOpen;
  final VoidCallback onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final id = number(item['subjectId']).toInt();
    final title = titleOf(item);
    final original = '${item['name'] ?? ''}';
    final summary = '${item['summary'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ');
    final season = object(item['season'])['label'];
    final tags = <String>[
      if (season != null) '$season',
      if (item['platform'] != null) '${item['platform']}',
      if (item['episodeTotal'] != null) '全 ${item['episodeTotal']} 话',
      ...(item['metaTags'] as List? ?? []).whereType<String>().where(
        (tag) => tag != item['platform'] && tag != '日本',
      ),
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
              child: SubjectCover(url: item['coverUrl'], title: title, id: id),
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
                              url: item['coverUrl'],
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
                                  '★ ${scoreLabel(item['score'])}',
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
  final List<Json> items;
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
                              titleOf(items[i]),
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
                            '★ ${scoreLabel(items[i]['score'])}',
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
    required this.airingToday,
    required this.onResume,
    required this.onOpenSubject,
    required this.onExplore,
    required this.onOpenTracking,
  });
  final List<Json> watching, resumable;
  final Set<Object?> airingToday;
  final ValueChanged<Json>? onResume;
  final ValueChanged<Json> onOpenSubject;
  final VoidCallback onExplore, onOpenTracking;

  @override
  Widget build(BuildContext context) {
    final resume = resumable.take(4).toList();
    final resumeIds = {for (final item in resume) item['subjectId']};
    final rest = watching.where((e) => !resumeIds.contains(e['subjectId']));
    // Shows airing today lead the watching list.
    final posters = [
      ...rest.where((e) => airingToday.contains(e['subjectId'])),
      ...rest.where((e) => !airingToday.contains(e['subjectId'])),
    ];
    final updated = watching
        .where((e) => airingToday.contains(e['subjectId']))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title: '继续 · 正在追',
          subtitle: [
            if (watching.isNotEmpty) '在看 ${watching.length} 部',
            if (updated > 0) '今天 $updated 部更新',
          ].join(' · '),
          icon: Icons.play_circle_outline,
          color: mint,
          top: 0,
          trailing: TextButton(
            onPressed: onOpenTracking,
            child: const Text('全部追番 →'),
          ),
        ),
        if (resume.isEmpty && posters.isEmpty)
          EmptyState(text: '还没有在追的番剧', action: onExplore, actionLabel: '搜索番剧')
        else
          HorizontalPosters(
            storageId: const ValueKey('continue-posters'),
            ranked: false,
            itemCount: resume.length + posters.length,
            itemBuilder: (i) => i < resume.length
                ? _ResumePoster(item: resume[i], onResume: onResume!)
                : SubjectPoster(
                    item: posters[i - resume.length],
                    onOpen: onOpenSubject,
                    tracking: true,
                    badge:
                        airingToday.contains(
                          posters[i - resume.length]['subjectId'],
                        )
                        ? '今日更新'
                        : null,
                  ),
          ),
      ],
    );
  }
}

class _ResumePoster extends StatefulWidget {
  const _ResumePoster({required this.item, required this.onResume});
  final Json item;
  final ValueChanged<Json> onResume;

  @override
  State<_ResumePoster> createState() => _ResumePosterState();
}

class _ResumePosterState extends State<_ResumePoster> {
  bool hovered = false, focused = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final position = number(item['positionSeconds']);
    final duration = number(item['durationSeconds']);
    final episode = number(item['episodeSort']);
    final episodeLabel = episode > 0
        ? '第 ${episode == episode.roundToDouble() ? episode.toInt() : episode} 话'
        : null;
    final remaining = ((duration - position) / 60).ceil();
    final scheme = Theme.of(context).colorScheme;
    final active = hovered || focused;
    return Semantics(
      label: '${titleOf(item)}，继续${episodeLabel ?? '观看'}',
      child: InkWell(
        onTap: () => widget.onResume(item),
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
                        url: item['coverUrl'],
                        title: titleOf(item),
                        id: number(item['subjectId']).toInt(),
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
                      Center(
                        child: AnimatedScale(
                          scale: active ? 1.08 : 1,
                          duration: motionDuration(context, 150),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Color(0xff168364),
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: const BoxDecoration(
                            color: mint,
                            borderRadius: badgeBorderRadius,
                          ),
                          child: Text(
                            episodeLabel == null ? '继续观看' : '继续$episodeLabel',
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
                          titleOf(item),
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
                            color: mint,
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
            Text(
              duration > position && remaining > 0
                  ? '剩余 $remaining 分钟'
                  : '继续观看',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

DateTime? _airingInstant(Json item) =>
    DateTime.tryParse('${item['airingAt'] ?? ''}');

String _shanghaiClock(DateTime instant) {
  final time = instant.toUtc().add(const Duration(hours: 8));
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class _TodayTimeline extends StatefulWidget {
  const _TodayTimeline({
    required this.items,
    required this.loading,
    required this.error,
    required this.watchingIds,
    required this.onOpen,
    required this.onCalendar,
    required this.onRetry,
  });
  final List<Json> items;
  final bool loading;
  final String? error;
  final Set<Object?> watchingIds;
  final ValueChanged<Json> onOpen;
  final VoidCallback onCalendar, onRetry;

  @override
  State<_TodayTimeline> createState() => _TodayTimelineState();
}

class _TodayTimelineState extends State<_TodayTimeline> {
  static const rowHeight = 64.0;
  final scroll = ScrollController();
  late final Timer clock;
  bool positioned = false;

  @override
  void initState() {
    super.initState();
    // Air status is derived from the schedule time only.
    clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final items = widget.items;
    final aired = [
      for (final item in items) _airingInstant(item)?.isBefore(now) ?? false,
    ];
    final firstUpcoming = aired.indexWhere((value) => !value);
    final nowIndex = firstUpcoming < 0 ? items.length : firstUpcoming;
    if (!positioned && items.isNotEmpty) {
      positioned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scroll.hasClients) return;
        scroll.jumpTo(
          math.min(
            math.max(0, (nowIndex - 2) * rowHeight),
            scroll.position.maxScrollExtent,
          ),
        );
      });
    }
    final Widget body;
    if (items.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.loading) ...[
              const SizedBox(width: 160, child: LinearProgressIndicator()),
              const SizedBox(height: Gap.md),
            ],
            Text(
              widget.loading
                  ? '正在加载今日放送…'
                  : widget.error != null
                  ? '暂时无法加载今日放送'
                  : '今日暂无放送数据',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!widget.loading && widget.error != null)
              TextButton(onPressed: widget.onRetry, child: const Text('重试')),
          ],
        ),
      );
    } else {
      body = ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Gap.sm),
        itemCount: items.length + 1,
        itemBuilder: (context, i) {
          if (i == nowIndex) {
            return _NowMarker(
              label: _shanghaiClock(now),
              connectAbove: nowIndex > 0,
              connectBelow: nowIndex < items.length,
            );
          }
          final index = i > nowIndex ? i - 1 : i;
          return _TimelineEntry(
            item: items[index],
            aired: aired[index],
            first: index == 0 && nowIndex != 0,
            last: index == items.length - 1 && nowIndex != items.length,
            watching: widget.watchingIds.contains(items[index]['subjectId']),
            onOpen: widget.onOpen,
          );
        },
      );
    }
    final airedCount = aired.where((value) => value).length;
    return MelonPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.xs, 0),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 18, color: coral),
                const SizedBox(width: 6),
                Text('今日更新', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: Gap.sm),
                if (items.isNotEmpty)
                  Text(
                    '${items.length} 部 · 已更新 $airedCount',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onCalendar,
                  child: const Text('时间表 →'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _TimelineRail extends StatelessWidget {
  const _TimelineRail({
    required this.above,
    required this.below,
    required this.dot,
  });
  final Color? above, below;
  final Widget dot;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 18,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Column(
          children: [
            Expanded(
              child: Container(width: 2, color: above ?? Colors.transparent),
            ),
            Expanded(
              child: Container(width: 2, color: below ?? Colors.transparent),
            ),
          ],
        ),
        dot,
      ],
    ),
  );
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.item,
    required this.aired,
    required this.first,
    required this.last,
    required this.watching,
    required this.onOpen,
  });
  final Json item;
  final bool aired, first, last, watching;
  final ValueChanged<Json> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final instant = _airingInstant(item);
    final line = aired
        ? scheme.primary.withValues(alpha: .55)
        : scheme.outlineVariant;
    final episodes = item['episodeTotal'] == null
        ? null
        : '全 ${item['episodeTotal']} 话';
    return SizedBox(
      height: _TodayTimelineState.rowHeight,
      child: InkWell(
        onTap: () => onOpen(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  instant == null ? '待定' : _shanghaiClock(instant),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: aired ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              _TimelineRail(
                above: first ? null : line,
                below: last ? null : line,
                dot: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: aired ? scheme.primary : scheme.surface,
                    border: Border.all(
                      color: aired ? scheme.primary : scheme.outline,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                child: SizedBox(
                  width: 34,
                  height: 46,
                  child: Opacity(
                    opacity: aired ? 1 : .75,
                    child: SubjectCover(
                      url: item['coverUrl'],
                      title: titleOf(item),
                      id: number(item['subjectId']).toInt(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleOf(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: aired ? null : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [aired ? '已更新' : '待更新', ?episodes].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: aired ? FontWeight.w700 : FontWeight.w400,
                        color: aired ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (watching)
                const Padding(
                  padding: EdgeInsets.only(left: Gap.sm),
                  child: MelonBadge('在追'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowMarker extends StatelessWidget {
  const _NowMarker({
    required this.label,
    required this.connectAbove,
    required this.connectBelow,
  });
  final String label;
  final bool connectAbove, connectBelow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        child: Row(
          children: [
            const SizedBox(
              width: 40,
              child: Text(
                '现在',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: coral,
                ),
              ),
            ),
            _TimelineRail(
              above: connectAbove
                  ? scheme.primary.withValues(alpha: .55)
                  : null,
              below: connectBelow ? scheme.outlineVariant : null,
              dot: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: coral,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: coral.withValues(alpha: .25),
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(height: 1, color: coral.withValues(alpha: .45)),
            ),
            const SizedBox(width: Gap.sm),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: coral,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.query,
    required this.results,
    required this.busy,
    required this.total,
    required this.hasMore,
    required this.onLoadMore,
    required this.onOpenSubject,
    this.error,
    this.onRetry,
  });
  final String query;
  final List<Json> results;
  final bool busy;
  final int total;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final String? error;
  final VoidCallback? onRetry;
  final ValueChanged<Json> onOpenSubject;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  bool loadMoreIfNeeded(ScrollMetrics metrics) {
    if (metrics.axis == Axis.vertical &&
        metrics.extentAfter < 480 &&
        widget.hasMore &&
        !widget.busy &&
        widget.error == null &&
        widget.results.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLoadMore();
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.results;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => loadMoreIfNeeded(notification.metrics),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) =>
            loadMoreIfNeeded(notification.metrics),
        child: PageScroll(
          children: [
            SectionTitle(
              title: '“${widget.query}” 的搜索结果',
              subtitle: results.isEmpty && widget.busy
                  ? null
                  : '${results.length}${widget.total > results.length ? ' / ${widget.total}' : ''} 部',
              icon: Icons.search,
              top: Gap.lg,
            ),
            if (results.isEmpty && widget.busy)
              const PosterPlaceholders()
            else if (results.isEmpty && widget.error != null)
              EmptyState(text: widget.error!, action: widget.onRetry)
            else if (results.isEmpty)
              const EmptyState(text: '没有找到匹配的番剧，换个名称或别名试试')
            else
              SubjectPosters(onOpen: widget.onOpenSubject, items: results),
            if (results.isNotEmpty && widget.error != null)
              EmptyState(
                text: widget.error!,
                action: widget.busy ? null : widget.onRetry,
              )
            else if (results.isNotEmpty && widget.hasMore)
              Padding(
                padding: const EdgeInsets.only(top: Gap.xl),
                child: Center(
                  child: widget.busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      // Short result lists do not scroll, so loading stays reachable.
                      : TextButton.icon(
                          onPressed: widget.onLoadMore,
                          icon: const Icon(Icons.expand_more, size: 18),
                          label: const Text('加载更多'),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.calendar,
    required this.onRetry,
    required this.onOpenSubject,
  });
  final List<Json> calendar;
  final VoidCallback onRetry;
  final ValueChanged<Json> onOpenSubject;
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  int selected = DateTime.now().weekday;
  bool restored = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!restored) {
      selected =
          PageStorage.maybeOf(context)
                  ?.readState(context, identifier: 'calendar-day')
              as int? ??
          selected;
      restored = true;
    }
  }

  void selectDay(int day) {
    setState(() => selected = day);
    PageStorage.maybeOf(context)
        ?.writeState(context, day, identifier: 'calendar-day');
  }

  @override
  Widget build(BuildContext context) {
    final days = {
      for (final day in widget.calendar)
        number(object(day['weekday'])['id']).toInt(): day,
    };
    final items = objects(days[selected]?['items']);
    return Column(
      children: [
        Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          height: 115,
          child: ListView.separated(
            key: const PageStorageKey('calendar-days'),
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            scrollDirection: Axis.horizontal,
            itemCount: 7,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => SizedBox(
              width: 82,
              child: Semantics(
                selected: selected == i + 1,
                child: TextButton(
                  style: TextButton.styleFrom(
                    textStyle: DefaultTextStyle.of(context).style,
                    backgroundColor: selected == i + 1
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context).colorScheme.surface,
                    foregroundColor: selected == i + 1
                        ? Theme.of(context).colorScheme.onSecondaryContainer
                        : Theme.of(context).colorScheme.onSurface,
                    padding: EdgeInsets.zero,
                    shape: const RoundedRectangleBorder(
                      borderRadius: posterBorderRadius,
                    ),
                  ),
                  onPressed: () => selectDay(i + 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][i],
                        style: TextStyle(
                          color: selected == i + 1
                              ? Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer
                              : null,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][i],
                        style: TextStyle(
                          color: selected == i + 1
                              ? Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        '${objects(days[i + 1]?['items']).length} 部',
                        style: TextStyle(
                          color: selected == i + 1
                              ? Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: PageScroll(
            children: [
              SectionTitle(
                title: ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][selected - 1],
                subtitle: '${items.length} 部放送',
                icon: Icons.calendar_month_outlined,
              ),
              if (items.isEmpty)
                EmptyState(
                  text: widget.calendar.isEmpty ? '日历尚未加载' : '本日暂无新番放送',
                  action: widget.calendar.isEmpty ? widget.onRetry : null,
                )
              else
                PageEntrance(
                  key: ValueKey(selected),
                  child: BroadcastTimeline(
                    items: items,
                    onOpen: widget.onOpenSubject,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class BroadcastTimeline extends StatelessWidget {
  const BroadcastTimeline({
    super.key,
    required this.items,
    required this.onOpen,
  });
  final List<Json> items;
  final ValueChanged<Json> onOpen;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < items.length; i++)
        _BroadcastEntry(
          key: ValueKey('${items[i]['subjectId']}:$i'),
          item: items[i],
          onOpen: onOpen,
          first: i == 0,
          last: i == items.length - 1,
        ),
    ],
  );
}

class _BroadcastEntry extends StatefulWidget {
  const _BroadcastEntry({
    super.key,
    required this.item,
    required this.onOpen,
    required this.first,
    required this.last,
  });
  final Json item;
  final ValueChanged<Json> onOpen;
  final bool first, last;
  @override
  State<_BroadcastEntry> createState() => _BroadcastEntryState();
}

class _BroadcastEntryState extends State<_BroadcastEntry> {
  bool hovered = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final active = hovered || focused;
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (value) => setState(() => focused = value),
        child: Stack(
          children: [
            Positioned(
              left: 66.5,
              top: widget.first ? 68 : 0,
              bottom: widget.last ? 80 : 0,
              child: AnimatedContainer(
                width: 2,
                duration: motionDuration(context, 200),
                color: active
                    ? scheme.primary.withValues(alpha: .4)
                    : scheme.outlineVariant,
              ),
            ),
            Positioned(
              left: 68,
              top: 67.5,
              width: 19,
              height: 1,
              child: ColoredBox(
                color: active
                    ? scheme.primary.withValues(alpha: .4)
                    : scheme.outlineVariant,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      _time(item),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: motionDuration(context, 200),
                    width: 11,
                    height: 11,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary
                                    .withValues(alpha: .14),
                                spreadRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  Expanded(
                    child: AnimatedContainer(
                      duration: motionDuration(context, 200),
                      curve: Curves.easeOut,
                      transform: Matrix4.translationValues(
                        active && !MediaQuery.disableAnimationsOf(context)
                            ? 2
                            : 0,
                        active && !MediaQuery.disableAnimationsOf(context)
                            ? -2
                            : 0,
                        0,
                      ),
                      child: MelonPanel(
                        onTap: () => widget.onOpen(item),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 80,
                              height: 108,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SubjectCover(
                                  url: item['coverUrl'],
                                  title: titleOf(item),
                                  id: number(item['subjectId']).toInt(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    titleOf(item),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    item['episodeTotal'] == null
                                        ? '今日放送'
                                        : '放送 · 全 ${item['episodeTotal']} 话',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () => widget.onOpen(item),
                              child: const Text('详情'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time(Json item) {
    final instant = _airingInstant(item);
    return instant == null ? '放送' : _shanghaiClock(instant);
  }
}
