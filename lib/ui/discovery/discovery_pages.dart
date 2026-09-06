import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.dark,
    required this.today,
    required this.trending,
    required this.trendingLoading,
    required this.error,
    required this.onOpenVideo,
    required this.onCalendar,
    required this.onRefresh,
    required this.onOpenSubject,
  });
  final bool dark;
  final List<Json> today;
  final List<Json> trending;
  final bool trendingLoading;
  final String? error;
  final VoidCallback onOpenVideo;
  final VoidCallback onCalendar;
  final VoidCallback onRefresh;
  final ValueChanged<Json> onOpenSubject;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: dark
                ? [const Color(0xff244c40), const Color(0xff263946)]
                : [const Color(0xffc8f0df), const Color(0xffe3eefb)],
          ),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '好故事，慢慢看。',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 10),
                  Text('发现新番，记录每一话，也给喜欢的故事留个位置。'),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onOpenVideo,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('打开视频'),
            ),
          ],
        ),
      ),
      SectionTitle(
        title: '今日放送',
        trailing: TextButton(
          onPressed: onCalendar,
          child: const Text('查看日历 →'),
        ),
      ),
      SubjectPosters(onOpen: onOpenSubject, items: today, horizontal: true),
      SectionTitle(
        title: '当季热门',
        trailing: IconButton(
          tooltip: '刷新',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ),
      if (trendingLoading && trending.isEmpty)
        const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (error != null && trending.isEmpty)
        EmptyState(text: '暂时无法加载番剧', detail: error, action: onRefresh)
      else
        SubjectPosters(onOpen: onOpenSubject, items: trending),
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
      SectionTitle(title: '搜索结果 · ${results.length}'),
      if (results.isEmpty && !busy)
        EmptyState(text: '没有找到匹配的番剧')
      else
        SubjectPosters(onOpen: onOpenSubject, items: results),
    ],
  );
}

class CalendarPage extends StatelessWidget {
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
  Widget build(BuildContext context) => PageScroll(
    children: [
      for (final day in calendar) ...[
        SectionTitle(title: '${object(day['weekday'])['cn'] ?? ''}'),
        SubjectPosters(
          onOpen: onOpenSubject,
          items: objects(day['items']),
          horizontal: true,
        ),
      ],
      if (calendar.isEmpty) EmptyState(text: '日历尚未加载', action: onRetry),
    ],
  );
}
