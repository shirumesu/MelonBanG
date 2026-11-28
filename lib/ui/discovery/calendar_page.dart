import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/notices.dart';
import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';
import '../../features/discovery/schedule_filter.dart';
import '../../features/discovery/schedule_week.dart';
import '../core/action_feedback.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';
import 'release_labels.dart';
import 'schedule_filter_menu.dart';
import 'schedule_side.dart';
import 'schedule_timeline.dart';
import 'schedule_week_panel.dart';

/// The weekly schedule: Monday to Sunday with a cell for each day, the
/// chosen day's shows on a timeline, and the week's chart and finales.
class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.week,
    required this.monday,
    required this.thisMonday,
    required this.loading,
    required this.error,
    required this.onWeek,
    required this.onRetry,
    required this.onOpenSubject,
    required this.filter,
    this.watchingIds = const {},
    this.collectedIds = const {},
  });

  /// The week starting [monday] once loaded; another week's is ignored.
  final ScheduleWeek? week;
  final String monday, thisMonday;
  final bool loading;
  final String? error;
  final ValueChanged<String> onWeek;
  final VoidCallback onRetry;
  final ValueChanged<Subject> onOpenSubject;
  final SchedulePreference filter;

  /// The shows the user is watching, marked 在追.
  final Set<int> watchingIds;

  /// Every show in the user's collection; none of them folds.
  final Set<int> collectedIds;

  /// Weeks browsable before and after this one: the Melon API keeps a
  /// show's episodes for about six weeks back and three ahead.
  static const weeksBack = 4, weeksAhead = 1;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  int? day;
  ScheduleScope scope = ScheduleScope.all;
  bool foldOpen = false;

  /// Whether the week panel has scrolled under the compact bar, which then
  /// stands in for it.
  bool compact = false;
  final _scroll = ScrollController();
  final _panelKey = GlobalKey(), _bodyKey = GlobalKey();

  /// Where the compact bar ends, from the top of the page.
  static const _compactBottom = Gap.sm + ScheduleCompactBar.height;

  /// The chart as last built, for the full chart's dialog, which lives in
  /// its own route and steps through weeks with the page.
  ValueNotifier<ChartView>? _chartView;

  @override
  void initState() {
    super.initState();
    final storage = PageStorage.maybeOf(context);
    day = storage?.readState(context, identifier: 'calendar-day') as int?;
    scope =
        storage?.readState(context, identifier: 'calendar-scope')
            as ScheduleScope? ??
        ScheduleScope.all;
    _scroll.addListener(_onScrolled);
  }

  @override
  void didUpdateWidget(CalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This week opens on today; another keeps the weekday chosen.
    if (oldWidget.monday != widget.monday &&
        widget.monday == widget.thisMonday) {
      day = null;
      foldOpen = false;
      PageStorage.maybeOf(context)
          ?.writeState(context, null, identifier: 'calendar-day');
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _chartView?.dispose();
    super.dispose();
  }

  /// Hands [view] to an open full chart once this frame is built: the
  /// dialog cannot be marked to rebuild while the page builds.
  void _showChart(ChartView view) {
    final notifier = _chartView;
    if (notifier == null) {
      _chartView = ValueNotifier(view);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notifier.value = view;
    });
  }

  /// The week panel's height when last laid out: scrolled far enough, the
  /// list lets go of it.
  double? _panelHeight;

  void _onScrolled() {
    final panel = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (panel != null && panel.hasSize) _panelHeight = panel.size.height;
    final height = _panelHeight;
    if (height == null || !_scroll.hasClients) return;
    // PageScroll starts the panel Gap.sm down.
    final hidden = _scroll.offset > Gap.sm + height - _compactBottom;
    if (hidden != compact) setState(() => compact = hidden);
  }

  /// After a choice in the compact bar, brings the chosen day's first show
  /// up under the bar, unless the page is above it already.
  void _revealBody() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final body = _bodyKey.currentContext?.findRenderObject();
    if (body == null || !_scroll.hasClients) return;
    final top =
        RenderAbstractViewport.of(body).getOffsetToReveal(body, 0).offset -
        _compactBottom -
        Gap.md;
    if (_scroll.offset > top) _scroll.jumpTo(math.max(0, top));
  });

  void _selectDay(int? value) {
    setState(() {
      day = value;
      foldOpen = false;
    });
    PageStorage.maybeOf(context)
        ?.writeState(context, value, identifier: 'calendar-day');
  }

  void _selectScope(ScheduleScope value) {
    setState(() => scope = value);
    PageStorage.maybeOf(context)
        ?.writeState(context, value, identifier: 'calendar-scope');
  }

  /// The Monday [weeks] from the one shown, when browsable.
  String? _monday(int weeks) {
    final thisWeek = DateTime.parse('${widget.thisMonday}T00:00:00Z');
    final target = DateTime.parse('${widget.monday}T00:00:00Z')
        .add(Duration(days: 7 * weeks));
    final offset = target.difference(thisWeek).inDays ~/ 7;
    return offset < -CalendarPage.weeksBack || offset > CalendarPage.weeksAhead
        ? null
        : target.toIso8601String().substring(0, 10);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.filter,
    builder: (context, _) => _page(context, widget.filter.value),
  );

  Widget _page(BuildContext context, ScheduleFilter filter) {
    final now = DateTime.now();
    final week = widget.week?.monday == widget.monday ? widget.week : null;
    final start = DateTime.parse('${widget.monday}T00:00:00Z');
    final todayIndex = shanghaiDay(now).difference(start).inDays;
    final thisWeek = widget.monday == widget.thisMonday;
    final selected = day ?? (thisWeek ? todayIndex.clamp(0, 6) : 0);
    bool accepts(Subject subject) => filter.accepts(subject, now);

    final listed = <List<ScheduleSlot>>[];
    final folded = <List<(ScheduleSlot, ScheduleFold)>>[];
    for (var i = 0; i < 7; i++) {
      final shows = <ScheduleSlot>[];
      final quiet = <(ScheduleSlot, ScheduleFold)>[];
      for (final slot in week?.days[i] ?? const <ScheduleSlot>[]) {
        if (!accepts(slot.subject)) continue;
        final fold = filter.fold(
          slot.subject,
          now,
          collected: widget.collectedIds.contains(slot.subject.id),
        );
        if (fold == null) {
          shows.add(slot);
        } else {
          quiet.add((slot, fold));
        }
      }
      listed.add(shows);
      folded.add(quiet);
    }
    final days = [
      for (var i = 0; i < 7; i++)
        (
          label: weekdayLabels[i],
          date: start.add(Duration(days: i)),
          today: thisWeek && i == todayIndex,
          listed: listed[i],
          folded: folded[i].length,
          watching: listed[i]
              .where((slot) => widget.watchingIds.contains(slot.subject.id))
              .length,
        ),
    ];
    final chart = week == null
        ? const <ChartEntry>[]
        : weeklyChart(week, accepts);
    final finales = week == null
        ? const <ScheduleSlot>[]
        : weekFinales(week, accepts);
    final previous = _monday(-1), next = _monday(1);
    final chartView = ChartView(
      monday: widget.monday,
      week: week,
      entries: chart,
      comparable: week != null && chartComparable(week),
      error: widget.error,
      onPrevious: previous == null ? null : () => widget.onWeek(previous),
      onNext: next == null ? null : () => widget.onWeek(next),
    );
    _showChart(chartView);

    final main = _dayBody(
      context,
      filter,
      week,
      selected,
      listed,
      folded,
      chart,
      now,
    );
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (week != null)
          WeeklyChartPanel(
            view: chartView,
            full: _chartView!,
            onOpen: widget.onOpenSubject,
          ),
        if (finales.isNotEmpty) ...[
          const SizedBox(height: Gap.lg),
          WeekFinalesPanel(finales: finales, onOpen: widget.onOpenSubject),
        ],
      ],
    );
    ScheduleFilterMenu filterMenu({bool iconOnly = false}) =>
        ScheduleFilterMenu(
          preference: widget.filter,
          week: week,
          day: selected,
          collectedIds: widget.collectedIds,
          iconOnly: iconOnly,
        );
    final page = PageScroll(
      controller: _scroll,
      children: [
        ScheduleWeekPanel(
          key: _panelKey,
          days: days,
          selected: selected,
          onSelect: _selectDay,
          onPrevious: chartView.onPrevious,
          onNext: chartView.onNext,
          onThisWeek: thisWeek ? null : () => widget.onWeek(widget.thisMonday),
          scope: scope,
          scopeCounts: {
            for (final value in ScheduleScope.values)
              value: listed[selected]
                  .where(
                    (slot) =>
                        value.includes(slot.subject, now, widget.watchingIds),
                  )
                  .length,
          },
          onScope: _selectScope,
          filter: filterMenu(),
        ),
        // Days from an earlier load stay readable when a refresh fails.
        if (widget.error != null && !widget.loading && week != null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: InlineIssue('刷新失败，仍显示上次内容', onRetry: widget.onRetry),
          ),
        if (week != null && week.incomplete > 0)
          Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: InlineIssue(
              '还有 ${week.incomplete} 部番剧的评分和话数正在获取，稍后自动刷新',
              tone: NoticeTone.info,
            ),
          ),
        const SizedBox(height: Gap.xl),
        LayoutBuilder(
          key: _bodyKey,
          builder: (context, constraints) => constraints.maxWidth >= 1000
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: Gap.xl),
                    SizedBox(width: 340, child: side),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    main,
                    const SizedBox(height: Gap.xl),
                    side,
                  ],
                ),
        ),
      ],
    );
    final duration = motionDuration(context, 160);
    return Stack(
      children: [
        page,
        Positioned(
          top: Gap.sm,
          left: pageGutter,
          right: pageGutter,
          child: ExcludeFocus(
            excluding: !compact,
            child: IgnorePointer(
              ignoring: !compact,
              child: AnimatedSlide(
                offset: compact ? Offset.zero : const Offset(0, -.25),
                duration: duration,
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: compact ? 1 : 0,
                  duration: duration,
                  child: ScheduleCompactBar(
                    days: days,
                    selected: selected,
                    onSelect: (value) {
                      _selectDay(value);
                      _revealBody();
                    },
                    scope: scope,
                    onScope: (value) {
                      _selectScope(value);
                      _revealBody();
                    },
                    filter: filterMenu(iconOnly: true),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayBody(
    BuildContext context,
    ScheduleFilter filter,
    ScheduleWeek? week,
    int selected,
    List<List<ScheduleSlot>> listed,
    List<List<(ScheduleSlot, ScheduleFold)>> folded,
    List<ChartEntry> chart,
    DateTime now,
  ) {
    if (week == null) {
      return widget.loading || widget.error == null
          ? const ScheduleTimelineSkeleton()
          : EmptyState(
              text: '暂时无法加载时间表',
              detail: widget.error,
              action: widget.onRetry,
            );
    }
    final all = week.days[selected];
    if (all.isEmpty) return const EmptyState(text: '本日没有番剧放送');
    if (listed[selected].isEmpty && folded[selected].isEmpty) {
      return _filteredOut(filter, all, now);
    }
    final shown = [
      for (final slot in listed[selected])
        if (scope.includes(slot.subject, now, widget.watchingIds)) slot,
    ];
    final quiet = scope == ScheduleScope.all
        ? folded[selected]
        : const <(ScheduleSlot, ScheduleFold)>[];
    if (shown.isEmpty && quiet.isEmpty) {
      return scope == ScheduleScope.watching
          ? _nothingWatched(week, selected, listed)
          : EmptyState(
              text: '本日没有${scope == ScheduleScope.fresh ? '新番' : '跨季的番剧'}',
            );
    }
    return PageEntrance(
      key: ValueKey('${week.monday}:$selected:${scope.name}'),
      child: ScheduleTimeline(
        slots: shown,
        folded: quiet,
        foldOpen: foldOpen,
        onFoldToggle: () => setState(() => foldOpen = !foldOpen),
        onOpen: widget.onOpenSubject,
        watchingIds: widget.watchingIds,
        chart: {
          for (final entry in chart.take(10)) entry.slot.subject.id: entry,
        },
        today:
            widget.monday == widget.thisMonday &&
            selected == shanghaiDay(now).difference(week.start).inDays,
      ),
    );
  }

  /// 在追 on a day without the user's shows: the next day that has one.
  Widget _nothingWatched(
    ScheduleWeek week,
    int selected,
    List<List<ScheduleSlot>> listed,
  ) {
    final label = weekdayLabels[selected];
    for (var i = selected + 1; i < 7; i++) {
      final next = listed[i]
          .where((slot) => widget.watchingIds.contains(slot.subject.id))
          .firstOrNull;
      if (next == null) continue;
      final at = next.subject.airingAt;
      return EmptyState(
        text: '$label没有在追的番剧更新',
        detail: [
          '下一次是${weekdayLabels[i]}',
          if (at != null) ' ${shanghaiClock(at)}',
          '《${next.subject.title}》',
          if (next.episode case final episode?) '第 ${episode.round()} 话',
        ].join(),
        action: () => _selectDay(i),
        actionLabel: '查看${weekdayLabels[i]}',
      );
    }
    return EmptyState(text: '$label没有在追的番剧更新');
  }

  /// The day when the filter leaves nothing. Clearing it keeps hiding R18
  /// shows as the menu's 清除筛选 does, unless only R18 shows air that day.
  Widget _filteredOut(
    ScheduleFilter filter,
    List<ScheduleSlot> day,
    DateTime now,
  ) {
    final cleared = filter.cleared;
    final onlyAdult = !day.any((slot) => cleared.accepts(slot.subject, now));
    return EmptyState(
      text: onlyAdult ? '本日只有 R18 番剧，已隐藏' : '筛选后本日没有番剧',
      action: () => widget.filter.set(
        onlyAdult ? cleared.copyWith(adult: AdultFilter.show) : cleared,
      ),
      actionLabel: onlyAdult ? '显示 R18' : '清除筛选',
    );
  }
}
