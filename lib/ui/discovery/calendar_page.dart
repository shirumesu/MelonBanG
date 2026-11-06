import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../features/discovery/schedule_filter.dart';
import '../core/action_feedback.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'schedule_timelines.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.calendar,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onOpenSubject,
    required this.filter,
  });
  final List<ScheduleDay> calendar;
  final SchedulePreference filter;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<Subject> onOpenSubject;
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  String? selected;
  @override
  void initState() {
    super.initState();
    selected = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: 'calendar-day') as String?;
  }

  void selectDay(String day) {
    setState(() => selected = day);
    PageStorage.maybeOf(context)
        ?.writeState(context, day, identifier: 'calendar-day');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.filter,
    builder: (context, _) => _page(context, widget.filter.value),
  );

  Widget _page(BuildContext context, ScheduleFilter filter) {
    final now = DateTime.now();
    final today = shanghaiDay(now);
    final dates = [
      for (var i = 0; i < 7; i++)
        today.add(Duration(days: i)).toIso8601String().substring(0, 10),
    ];
    final days = {for (final day in widget.calendar) day.date: day};
    final selectedDate = dates.contains(selected) ? selected! : dates.first;
    final all = days[selectedDate]?.items ?? const <Subject>[];
    List<Subject> shown(List<Subject> items) =>
        items.where((item) => filter.accepts(item, now)).toList();
    final items = shown(all);
    // Each day reads how many it lists, out of how many air when the filter
    // leaves some out.
    String count(String date) {
      final items = days[date]?.items ?? const <Subject>[];
      final listed = shown(items).length;
      return listed == items.length ? '$listed 部' : '$listed/${items.length} 部';
    }

    String weekday(String date) =>
        weekdayLabels[DateTime.parse('${date}T00:00:00Z').weekday - 1];
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
                selected: selectedDate == dates[i],
                child: TextButton(
                  style: TextButton.styleFrom(
                    textStyle: DefaultTextStyle.of(context).style,
                    backgroundColor: selectedDate == dates[i]
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context).colorScheme.surface,
                    foregroundColor: selectedDate == dates[i]
                        ? Theme.of(context).colorScheme.onSecondaryContainer
                        : Theme.of(context).colorScheme.onSurface,
                    padding: EdgeInsets.zero,
                    shape: const RoundedRectangleBorder(
                      borderRadius: posterBorderRadius,
                    ),
                  ),
                  onPressed: () => selectDay(dates[i]),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        weekday(dates[i]),
                        style: TextStyle(
                          color: selectedDate == dates[i]
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
                        dates[i].substring(5).replaceAll('-', '/'),
                        style: TextStyle(
                          color: selectedDate == dates[i]
                              ? Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        count(dates[i]),
                        style: TextStyle(
                          color: selectedDate == dates[i]
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
                title: '${weekday(selectedDate)}  $selectedDate',
                icon: Icons.calendar_month_outlined,
                subtitle: items.length == all.length
                    ? null
                    : '显示 ${items.length} 部，共 ${all.length} 部',
                trailing: _filters(filter, all, now),
              ),
              // Days from an earlier load stay readable when a refresh fails.
              if (widget.error != null &&
                  !widget.loading &&
                  widget.calendar.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: InlineIssue('刷新失败，仍显示上次内容', onRetry: widget.onRetry),
                ),
              if (items.isEmpty && all.isNotEmpty)
                EmptyState(
                  text: '筛选后本日没有番剧',
                  action: () => widget.filter.set(ScheduleFilter.none),
                  actionLabel: '清除筛选',
                )
              else if (items.isEmpty && widget.loading) ...[
                const LinearProgressIndicator(),
                const EmptyState(text: '正在加载时间表…'),
              ] else if (items.isEmpty)
                EmptyState(
                  text: widget.error != null ? '暂时无法加载时间表' : '本日暂无新番放送',
                  detail: widget.error,
                  action: widget.error != null ? widget.onRetry : null,
                )
              else
                PageEntrance(
                  key: ValueKey(selectedDate),
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

  /// The filter's menus; each option counts the day's shows it concerns.
  Widget _filters(ScheduleFilter filter, List<Subject> day, DateTime now) {
    String? counted(bool Function(Subject) concerns) {
      final count = day.where(concerns).length;
      return day.isEmpty ? null : '$count';
    }

    final hidden = {
      if (filter.hideLongRunning) 'long',
      if (filter.hidePastSeasons) 'past',
    };
    final selected = {
      for (final kind in filter.kinds) 'kind:$kind',
      for (final region in filter.regions) 'region:$region',
      for (final value in hidden) 'hide:$value',
    };
    void toggle(String value, bool on) {
      Set<String> flip(Set<String> values, String value) =>
          on ? {...values, value} : ({...values}..remove(value));
      final (kind, name) = switch (value.split(':')) {
        [final kind, final name] => (kind, name),
        _ => ('', ''),
      };
      widget.filter.set(switch (kind) {
        'kind' => filter.copyWith(kinds: flip(filter.kinds, name)),
        'region' => filter.copyWith(regions: flip(filter.regions, name)),
        _ when name == 'long' => filter.copyWith(hideLongRunning: on),
        _ => filter.copyWith(hidePastSeasons: on),
      });
    }

    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MelonFilterMenu<String>(
          label: '筛选',
          icon: Icons.filter_list_rounded,
          summary: selected.length == 1
              ? switch (selected.single.split(':')) {
                  ['hide', 'long'] => '隐藏长篇',
                  ['hide', _] => '隐藏往季度',
                  [_, final name] => name,
                  _ => null,
                }
              : '${selected.length} 项',
          tooltip: '按类型、地区筛选，或隐藏长篇与往季度番剧',
          sections: [
            MelonFilterSection(title: '类型', [
              for (final kind in ScheduleFilter.kindOptions)
                MelonFilterOption(
                  'kind:$kind',
                  kind,
                  detail: counted((item) => scheduleKind(item) == kind),
                ),
            ]),
            MelonFilterSection(title: '地区', [
              for (final region in ScheduleFilter.regionOptions)
                MelonFilterOption(
                  'region:$region',
                  region,
                  detail: counted((item) => scheduleRegion(item) == region),
                ),
            ]),
            MelonFilterSection(title: '隐藏', [
              MelonFilterOption(
                'hide:long',
                '长篇',
                subtitle: '40 集以上，或已播出一年以上',
                detail: counted((item) => isLongRunning(item, now)),
              ),
              MelonFilterOption(
                'hide:past',
                '往季度',
                subtitle: '上一季或更早开播，仍在播出',
                detail: counted((item) => isFromPastSeason(item, now)),
              ),
            ]),
          ],
          selected: selected,
          onToggle: toggle,
          actions: [
            if (selected.isNotEmpty)
              (
                '清除',
                () => widget.filter.set(ScheduleFilter(adult: filter.adult)),
              ),
          ],
        ),
        MelonFilterMenu<AdultFilter>(
          label: 'R18',
          multiple: false,
          active: filter.adult != AdultFilter.show,
          summary: filter.adult.label,
          tooltip: 'Bangumi 标为 R18，或用户主要标为里番的番剧；只标卖肉的不算',
          sections: [
            MelonFilterSection([
              for (final value in AdultFilter.values)
                MelonFilterOption(
                  value,
                  value.label,
                  detail: value == AdultFilter.only ? counted(isAdult) : null,
                ),
            ]),
          ],
          selected: {filter.adult},
          onToggle: (value, _) =>
              widget.filter.set(filter.copyWith(adult: value)),
        ),
      ],
    );
  }
}
