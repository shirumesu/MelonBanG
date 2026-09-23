import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.resumable = const [],
    this.onResume,
    this.todayLoading = false,
    this.todayError,
  });
  final bool dark, trendingLoading, todayLoading;
  final List<Json> today, trending, watching, resumable;
  final String? error, todayError;
  final VoidCallback onExplore, onCalendar, onRefresh;
  final ActionFeedback feedback;
  final ValueChanged<Json> onOpenSubject;
  final ValueChanged<Json>? onResume;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      SectionTitle(
        title: '热门与精选',
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
        const _FeaturedPlaceholder()
      else if (error != null && trending.isEmpty)
        EmptyState(text: '暂时无法加载番剧', detail: error, action: onRefresh)
      else if (trending.isEmpty)
        EmptyState(text: '暂时没有热门番剧', action: onRefresh)
      else
        _FeaturedSubjects(
          items: trending.take(3).toList(),
          onOpen: onOpenSubject,
        ),
      if (resumable.isNotEmpty && onResume != null) ...[
        const SectionTitle(
          title: '继续播放',
          icon: Icons.play_circle_outline,
          color: mint,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 680 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final item in resumable.take(2))
                  SizedBox(
                    width: width,
                    child: _ResumeCard(item: item, onResume: onResume!),
                  ),
              ],
            );
          },
        ),
      ],
      const SectionTitle(
        title: '正在追',
        subtitle: '我的在看收藏',
        icon: Icons.bookmark_border_rounded,
        color: mint,
      ),
      if (watching.isEmpty)
        EmptyState(text: '还没有在追的番剧', action: onExplore, actionLabel: '搜索番剧')
      else
        SubjectPosters(
          key: const ValueKey('watching-posters'),
          onOpen: onOpenSubject,
          items: watching.take(12).toList(),
          horizontal: true,
          tracking: true,
        ),
      SectionTitle(
        title: '今日更新',
        subtitle: todayLoading && today.isEmpty ? null : '${today.length} 部放送',
        icon: Icons.auto_awesome_outlined,
        trailing: TextButton(
          onPressed: onCalendar,
          child: const Text('新番时间表 →'),
        ),
      ),
      if (todayLoading && today.isEmpty)
        const MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('正在加载今日放送…'),
              SizedBox(height: 12),
              LinearProgressIndicator(),
            ],
          ),
        )
      else if (todayError != null && today.isEmpty)
        EmptyState(text: '暂时无法加载今日放送', detail: todayError, action: onRefresh)
      else if (today.isEmpty)
        const EmptyState(text: '今日暂无放送数据')
      else
        BroadcastTimeline(items: today, onOpen: onOpenSubject),
      if (trending.isNotEmpty) ...[
        const SectionTitle(
          title: '本季热度',
          subtitle: '当季最受欢迎的番剧',
          icon: Icons.local_fire_department_outlined,
        ),
        SubjectPosters(
          key: const ValueKey('trending-posters'),
          onOpen: onOpenSubject,
          items: trending.take(8).toList(),
          horizontal: true,
          ranked: true,
        ),
      ],
    ],
  );
}

class _FeaturedSubjects extends StatefulWidget {
  const _FeaturedSubjects({required this.items, required this.onOpen});
  final List<Json> items;
  final ValueChanged<Json> onOpen;

  @override
  State<_FeaturedSubjects> createState() => _FeaturedSubjectsState();
}

class _FeaturedSubjectsState extends State<_FeaturedSubjects> {
  String? _selectedId;
  bool _restored = false;

  String _id(Json item) =>
      '${item['subjectId'] ?? item['id'] ?? titleOf(item)}';
  int get _index {
    final index = widget.items.indexWhere((item) => _id(item) == _selectedId);
    return index < 0 ? 0 : index;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restored) {
      _selectedId = PageStorage.maybeOf(
        context,
      )?.readState(context, identifier: 'home-featured-subject') as String?;
      _restored = true;
    }
  }

  void _select(int index) {
    final next = (index + widget.items.length) % widget.items.length;
    final id = _id(widget.items[next]);
    if (id == _selectedId) return;
    setState(() => _selectedId = id);
    PageStorage.maybeOf(context)
        ?.writeState(context, id, identifier: 'home-featured-subject');
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final scheme = Theme.of(context).colorScheme;
    return FocusTraversalGroup(
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent || widget.items.length < 2) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _select(_index - 1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _select(_index + 1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Card(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer.withValues(alpha: .55),
                  scheme.surface,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final showArt = constraints.maxWidth >= 520;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AnimatedSwitcher(
                                  duration: motionDuration(context, 180),
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeOut,
                                  layoutBuilder: (current, previous) => Stack(
                                    alignment: Alignment.topLeft,
                                    children: [
                                      for (final child in previous)
                                        ExcludeSemantics(child: child),
                                      ?current,
                                    ],
                                  ),
                                  child: _FeaturedCopy(
                                    key: ValueKey(_id(item)),
                                    item: item,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextButton.icon(
                                  key: const ValueKey('open-featured-subject'),
                                  onPressed: () => widget.onOpen(item),
                                  icon: const Icon(
                                    Icons.arrow_outward,
                                    size: 17,
                                  ),
                                  label: const Text('查看作品'),
                                ),
                              ],
                            ),
                          ),
                          if (showArt) ...[
                            const SizedBox(width: 22),
                            AnimatedSwitcher(
                              duration: motionDuration(context, 180),
                              child: _FeaturedCover(
                                key: ValueKey(_id(item)),
                                item: item,
                                onPressed: () => widget.onOpen(item),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  if (widget.items.length > 1) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < widget.items.length; i++)
                              Semantics(
                                selected: i == _index,
                                child: Tooltip(
                                  message:
                                      '精选 ${i + 1}：${titleOf(widget.items[i])}',
                                  child: TextButton(
                                    onPressed: () => _select(i),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(36, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      foregroundColor: i == _index
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurfaceVariant,
                                      backgroundColor: i == _index
                                          ? scheme.primaryContainer
                                          : Colors.transparent,
                                    ),
                                    child: Text('${i + 1}'),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              liveRegion: true,
                              label:
                                  '精选 ${_index + 1}，共 ${widget.items.length} 项，${titleOf(item)}',
                              child: ExcludeSemantics(
                                child: Text(
                                  '${_index + 1} / ${widget.items.length}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: '上一项精选',
                              onPressed: () => _select(_index - 1),
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            IconButton(
                              tooltip: '下一项精选',
                              onPressed: () => _select(_index + 1),
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedCopy extends StatelessWidget {
  const _FeaturedCopy({super.key, required this.item});
  final Json item;

  @override
  Widget build(BuildContext context) {
    final season = object(item['season'])['label'];
    final date = DateTime.tryParse('${item['airDate'] ?? ''}');
    final seasonLabel = season is String && season.trim().isNotEmpty
        ? season.trim()
        : date == null
        ? null
        : '${date.year} ${['冬', '春', '夏', '秋'][(date.month - 1) ~/ 3]}';
    final summary = '${item['summary'] ?? ''}'.trim();
    final originalName = '${item['name'] ?? ''}'.trim();
    final detail = summary.isNotEmpty
        ? summary
        : originalName != titleOf(item)
        ? originalName
        : '';
    final tags = objects(item['tags'])
        .map((tag) => '${tag['name'] ?? ''}'.trim())
        .where((name) => name.isNotEmpty)
        .take(2);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 146),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (seasonLabel != null) ...[
            MelonBadge(seasonLabel, color: coral),
            const SizedBox(height: 10),
          ],
          Semantics(
            header: true,
            child: Text(
              titleOf(item),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(height: 1.6),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              if ('${item['platform'] ?? ''}'.trim().isNotEmpty)
                MelonBadge('${item['platform']}', color: sky),
              for (final tag in tags) MelonBadge(tag, color: grape),
              if (number(item['score']) > 0)
                MelonBadge('★ ${scoreLabel(item['score'])}', color: gold),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeaturedCover extends StatelessWidget {
  const _FeaturedCover({
    super.key,
    required this.item,
    required this.onPressed,
  });
  final Json item;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    height: 240,
    child: Tooltip(
      message: '查看 ${titleOf(item)}',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: posterBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ExcludeSemantics(
            child: SubjectCover(
              url: item['coverUrl'],
              title: titleOf(item),
              id: number(item['subjectId']).toInt(),
            ),
          ),
        ),
      ),
    ),
  );
}

class _FeaturedPlaceholder extends StatelessWidget {
  const _FeaturedPlaceholder();
  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载精选番剧',
    child: MelonPanel(
      child: SizedBox(
        height: 206,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(
            Icons.movie_outlined,
            size: 36,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.item, required this.onResume});
  final Json item;
  final ValueChanged<Json> onResume;

  @override
  Widget build(BuildContext context) {
    final position = number(item['positionSeconds']);
    final duration = number(item['durationSeconds']);
    final episode = number(item['episodeSort']);
    final episodeLabel = episode > 0
        ? '第 ${episode == episode.roundToDouble() ? episode.toInt() : episode} 话'
        : null;
    final remaining = ((duration - position) / 60).ceil();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${titleOf(item)}，${episodeLabel ?? '继续观看'}',
      child: MelonPanel(
        padding: const EdgeInsets.all(15),
        onTap: () => onResume(item),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                child: SizedBox(
                  width: 68,
                  height: 96,
                  child: SubjectCover(
                    url: item['coverUrl'],
                    title: titleOf(item),
                    id: number(item['subjectId']).toInt(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleOf(item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      ?episodeLabel,
                      if (duration > position && remaining > 0)
                        '剩余 $remaining 分钟',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 9),
                  if (duration > 0)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (position / duration).clamp(0, 1),
                        minHeight: 3,
                        backgroundColor: scheme.primary.withValues(alpha: .12),
                        semanticsLabel: '观看进度',
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 19,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          episodeLabel == null ? '继续观看' : '继续$episodeLabel',
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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
    );
  }
}

class SearchPage extends StatelessWidget {
  const SearchPage({
    super.key,
    required this.results,
    required this.busy,
    required this.onOpenSubject,
    this.error,
    this.onRetry,
  });
  final List<Json> results;
  final bool busy;
  final String? error;
  final VoidCallback? onRetry;
  final ValueChanged<Json> onOpenSubject;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      SectionTitle(title: '搜索结果 · ${results.length}', icon: Icons.search),
      if (results.isEmpty && busy)
        const PosterPlaceholders()
      else if (results.isEmpty && error != null)
        EmptyState(text: error!, action: onRetry)
      else if (results.isEmpty)
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
    final value = '${item['airingAtShanghai'] ?? item['airingAt'] ?? ''}';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return '放送';
    final shanghai = parsed.toUtc().add(const Duration(hours: 8));
    return '${shanghai.hour.toString().padLeft(2, '0')}:${shanghai.minute.toString().padLeft(2, '0')}';
  }
}
