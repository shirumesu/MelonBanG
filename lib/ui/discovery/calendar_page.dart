import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
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
  });
  final List<ScheduleDay> calendar;
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
  Widget build(BuildContext context) {
    final today = shanghaiDay(DateTime.now());
    final dates = [
      for (var i = 0; i < 7; i++)
        today.add(Duration(days: i)).toIso8601String().substring(0, 10),
    ];
    final days = {for (final day in widget.calendar) day.date: day};
    final selectedDate = dates.contains(selected) ? selected! : dates.first;
    final items = days[selectedDate]?.items ?? const <Subject>[];
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
                        '${days[dates[i]]?.items.length ?? 0} 部',
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
              ),
              if (items.isEmpty && widget.loading) ...[
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
}
