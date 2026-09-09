import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/action_feedback.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.dark,
    required this.today,
    required this.trending,
    required this.trendingLoading,
    required this.error,
    required this.onExplore,
    required this.feedback,
    required this.onCalendar,
    required this.onRefresh,
    required this.onOpenSubject,
    this.watching = const [],
  });
  final bool dark, trendingLoading;
  final List<Json> today, trending, watching;
  final String? error;
  final VoidCallback onExplore, onCalendar, onRefresh;
  final ActionFeedback feedback;
  final ValueChanged<Json> onOpenSubject;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      SectionTitle(
        title: '本季热度',
        subtitle: '当季最受欢迎的番剧',
        icon: Icons.local_fire_department_outlined,
        trailing: FeedbackButton(
          feedback: feedback,
          label: '刷新',
          runningLabel: '刷新中…',
          successLabel: '已更新',
          icon: Icons.refresh,
          onPressed: onRefresh,
        ),
      ),
      FeedbackIssue(feedback: feedback, onRetry: onRefresh),
      if (trendingLoading && trending.isEmpty)
        const PosterPlaceholders()
      else if (error != null && trending.isEmpty)
        EmptyState(text: '暂时无法加载番剧', detail: error, action: onRefresh)
      else
        SubjectPosters(
          onOpen: onOpenSubject,
          items: trending.take(8).toList(),
          horizontal: true,
          ranked: true,
        ),
      const SectionTitle(
        title: '继续播放',
        subtitle: '接着上次看',
        icon: Icons.play_circle_outline,
        color: mint,
      ),
      if (watching.isEmpty)
        EmptyState(text: '暂无在看收藏', action: onExplore, actionLabel: '查看追番')
      else
        SubjectPosters(
          onOpen: onOpenSubject,
          items: watching.take(12).toList(),
          horizontal: true,
          tracking: true,
        ),
      SectionTitle(
        title: '今日更新',
        subtitle: '${today.length} 部放送',
        icon: Icons.auto_awesome_outlined,
        trailing: TextButton(
          onPressed: onCalendar,
          child: const Text('新番时间表 →'),
        ),
      ),
      if (today.isEmpty)
        const EmptyState(text: '今日暂无放送数据')
      else
        BroadcastTimeline(items: today, onOpen: onOpenSubject),
    ],
  );
}

class SearchPage extends StatelessWidget {
  const SearchPage({
    super.key,
    required this.results,
    required this.busy,
    required this.onOpenSubject,
  });
  final List<Json> results;
  final bool busy;
  final ValueChanged<Json> onOpenSubject;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      SectionTitle(title: '搜索结果 · ${results.length}', icon: Icons.search),
      if (results.isEmpty && !busy)
        const EmptyState(text: '没有找到匹配的番剧')
      else
        SubjectPosters(onOpen: onOpenSubject, items: results),
    ],
  );
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
                  onPressed: () => setState(() => selected = i + 1),
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
    final value = '${item['airingAtShanghai'] ?? item['airingAt'] ?? ''}';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return '放送';
    final shanghai = parsed.toUtc().add(const Duration(hours: 8));
    return '${shanghai.hour.toString().padLeft(2, '0')}:${shanghai.minute.toString().padLeft(2, '0')}';
  }
}
