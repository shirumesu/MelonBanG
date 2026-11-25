import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_cover.dart';
import '../core/theme.dart';

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
    this.hidden = 0,
    this.skeletonAtOnce = false,
  });
  final List<Subject> items;

  /// Shows the skeleton from the first frame, following the startup's.
  final bool skeletonAtOnce;

  /// How many of today's shows the schedule's filter leaves out of [items].
  final int hidden;
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
  bool positioned = false;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  // Rebuilt on a clock: air status compares the schedule's times with now.
  @override
  Widget build(BuildContext context) =>
      ShownClock(period: const Duration(seconds: 30), builder: _build);

  Widget _build(BuildContext context) {
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
    final waiting = items.isEmpty && widget.loading && widget.hidden == 0;
    final Widget body;
    if (waiting) {
      body = const SizedBox.shrink();
    } else if (items.isEmpty) {
      body = EmptyState.compact(
        text: widget.hidden > 0
            ? '筛选后今日没有番剧'
            : widget.error != null
            ? '暂时无法加载今日放送'
            : '今日没有番剧放送',
        action: widget.hidden > 0
            ? widget.onCalendar
            : !widget.loading && widget.error != null
            ? widget.onRetry
            : null,
        actionLabel: widget.hidden > 0 ? '到时间表调整筛选' : '重试',
      );
    } else {
      body = ScrollEdgeFade(
        child: ListView.builder(
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
        ),
      );
    }
    final airedCount = aired.where((value) => value).length;
    return HeadedPanel(
      icon: Icons.calendar_today_outlined,
      title: '今日更新',
      detail: [
        if (items.isNotEmpty) '已更新 $airedCount/${items.length}',
        if (widget.hidden > 0) '隐藏 ${widget.hidden} 部',
      ].join('  '),
      action: TextButton(
        onPressed: widget.onCalendar,
        child: const Text('时间表'),
      ),
      child: DelayedBusy(
        busy: waiting,
        immediate: widget.skeletonAtOnce,
        builder: (context, shown) =>
            shown ? const _TodayTimelineSkeleton() : body,
      ),
    );
  }
}

/// [_TimelineEntry] rows in grey while today's shows load.
class _TodayTimelineSkeleton extends StatelessWidget {
  const _TodayTimelineSkeleton();

  static const _shares = [.7, .5, .85, .6, .75, .55, .8];

  @override
  Widget build(BuildContext context) {
    final rail = Theme.of(context).colorScheme.outlineVariant;
    return SkeletonGroup(
      label: '正在加载今日放送',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: Gap.sm),
        children: [
          for (final (i, share) in _shares.indexed)
            SizedBox(
              height: _TodayTimelineState.rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 40,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SkeletonBlock(width: 32, height: 10),
                      ),
                    ),
                    _TimelineRail(
                      above: i == 0 ? null : rail,
                      below: i == _shares.length - 1 ? null : rail,
                      dot: const SkeletonBlock(
                        width: 10,
                        height: 10,
                        radius: pillBorderRadius,
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    const SkeletonBlock(
                      width: 34,
                      height: 46,
                      radius: badgeBorderRadius,
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: share,
                          child: const SkeletonBlock(height: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
        ? scheme.primary.withValues(alpha: .35)
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
                    fontSize: FontSize.small,
                    fontWeight: FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: aired ? scheme.onSurface : scheme.onSurfaceVariant,
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
              const SizedBox(width: Gap.md),
              CoverFrame(
                radius: badgeBorderRadius,
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
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: FontSize.body,
                    fontWeight: FontWeight.w700,
                    color: aired ? null : scheme.onSurfaceVariant,
                  ),
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
    final ink = coralInk(Theme.of(context).brightness == Brightness.dark);
    return SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '现在',
                style: TextStyle(
                  fontSize: FontSize.small,
                  fontWeight: FontWeight.w400,
                  color: ink,
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
            const SizedBox(width: Gap.md),
            Expanded(
              child: Container(height: 1, color: coral.withValues(alpha: .45)),
            ),
            const SizedBox(width: Gap.sm),
            Text(
              label,
              style: TextStyle(
                fontSize: FontSize.caption,
                fontWeight: FontWeight.w400,
                color: ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
