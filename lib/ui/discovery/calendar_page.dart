import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';
import '../../features/discovery/schedule_filter.dart';
import '../core/action_feedback.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'broadcast_timeline.dart';
import 'release_labels.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.calendar,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onOpenSubject,
    required this.filter,
    this.watchingIds = const {},
  });
  final List<ScheduleDay> calendar;

  /// The shows the user is watching, marked 在追.
  final Set<int> watchingIds;
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
          height: 112,
          child: ListView.separated(
            key: const PageStorageKey('calendar-days'),
            padding: const EdgeInsets.symmetric(
              horizontal: pageGutter,
              vertical: Gap.md,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: 7,
            separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
            itemBuilder: (context, i) => SizedBox(
              width: 82,
              child: Semantics(
                selected: selectedDate == dates[i],
                child: TextButton(
                  style: TextButton.styleFrom(
                    textStyle: DefaultTextStyle.of(context).style,
                    backgroundColor: selectedDate == dates[i]
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surface,
                    foregroundColor: selectedDate == dates[i]
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurface,
                    padding: EdgeInsets.zero,
                    shape: const RoundedRectangleBorder(
                      borderRadius: controlBorderRadius,
                    ),
                  ),
                  onPressed: () => selectDay(dates[i]),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        i == 0 ? '今天' : weekday(dates[i]),
                        style: TextStyle(
                          color: selectedDate == dates[i]
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : null,
                          fontSize: FontSize.body,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        dates[i].substring(5).replaceAll('-', '/'),
                        style: TextStyle(
                          color: selectedDate == dates[i]
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: FontSize.caption,
                        ),
                      ),
                      Text(
                        count(dates[i]),
                        style: TextStyle(
                          color: selectedDate == dates[i]
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: FontSize.caption,
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
                title: _dayTitle(selectedDate, weekday(selectedDate)),
                icon: Icons.calendar_month_outlined,
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
                _filteredOut(filter, all, now)
              else if (items.isEmpty && widget.loading)
                const BroadcastTimelineSkeleton()
              else if (items.isEmpty)
                EmptyState(
                  text: widget.error != null ? '暂时无法加载时间表' : '本日没有番剧放送',
                  detail: widget.error,
                  action: widget.error != null ? widget.onRetry : null,
                )
              else
                PageEntrance(
                  key: ValueKey(selectedDate),
                  child: BroadcastTimeline(
                    items: items,
                    onOpen: widget.onOpenSubject,
                    watchingIds: widget.watchingIds,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// A day's heading, such as 11月18日 周三.
  static String _dayTitle(String date, String weekday) {
    final day = DateTime.parse(date);
    return '${day.month}月${day.day}日 $weekday';
  }

  /// The day when the filter leaves nothing. Clearing it keeps hiding R18
  /// shows as the menu's 清除 does, unless only R18 shows air that day.
  Widget _filteredOut(ScheduleFilter filter, List<Subject> day, DateTime now) {
    final cleared = ScheduleFilter(
      adult: filter.adult == AdultFilter.only ? AdultFilter.show : filter.adult,
    );
    final onlyAdult = !day.any((item) => cleared.accepts(item, now));
    return EmptyState(
      text: onlyAdult ? '本日只有 R18 番剧，已隐藏' : '筛选后本日没有番剧',
      action: () => widget.filter.set(
        onlyAdult ? filter.copyWith(adult: AdultFilter.show) : cleared,
      ),
      actionLabel: onlyAdult ? '显示 R18' : '清除筛选',
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
        _ => throw ArgumentError.value(value, 'value', 'Not a filter option'),
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
                  final other => throw StateError(
                    'Not a filter option: $other',
                  ),
                }
              : '${selected.length} 项',
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
          tooltip: 'Bangumi 标为 R18 或里番的番剧',
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
