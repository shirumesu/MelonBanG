import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';

String shanghaiClock(DateTime instant) {
  final time = instant.toUtc().add(const Duration(hours: 8));
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class TodayTimeline extends StatefulWidget {
  const TodayTimeline({
    super.key,
    required this.items,
    required this.loading,
    required this.error,
    required this.watchingIds,
    required this.onOpen,
    required this.onCalendar,
    required this.onRetry,
  });
  final List<Subject> items;
  final bool loading;
  final String? error;
  final Set<int> watchingIds;
  final ValueChanged<Subject> onOpen;
  final VoidCallback onCalendar, onRetry;

  @override
  State<TodayTimeline> createState() => _TodayTimelineState();
}

class _TodayTimelineState extends State<TodayTimeline> {
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
      for (final item in items) item.airingAt?.isBefore(now) ?? false,
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
              label: shanghaiClock(now),
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
            watching: widget.watchingIds.contains(items[index].id),
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
                    '已更新 $airedCount/${items.length}',
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
  final Subject item;
  final bool aired, first, last, watching;
  final ValueChanged<Subject> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final instant = item.airingAt;
    final line = aired
        ? scheme.primary.withValues(alpha: .55)
        : scheme.outlineVariant;
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
                  instant == null ? '待定' : shanghaiClock(instant),
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
                      url: item.coverUrl,
                      title: item.title,
                      id: item.id,
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
                      item.title,
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
                      aired ? '已更新' : '待更新',
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

class BroadcastTimeline extends StatelessWidget {
  const BroadcastTimeline({
    super.key,
    required this.items,
    required this.onOpen,
  });
  final List<Subject> items;
  final ValueChanged<Subject> onOpen;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < items.length; i++)
        _BroadcastEntry(
          key: ValueKey('${items[i].id}:$i'),
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
  final Subject item;
  final ValueChanged<Subject> onOpen;
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
                                  url: item.coverUrl,
                                  title: item.title,
                                  id: item.id,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (item.episodeTotal != null) ...[
                                    const SizedBox(height: 7),
                                    Text(
                                      '全 ${item.episodeTotal} 话',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
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

  String _time(Subject item) {
    final instant = item.airingAt;
    return instant == null ? '放送' : shanghaiClock(instant);
  }
}
