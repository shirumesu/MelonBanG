import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';
import '../../features/discovery/schedule_filter.dart';
import '../../features/discovery/schedule_week.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_cover.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'release_labels.dart';

/// Width of the time column and the rail beside it, which folded shows and
/// the 现在 line line up with.
const _timeWidth = 52.0, _railWidth = 28.0;

/// A day's broadcasts by air time: a card for each show listed, a 现在 line
/// between aired and upcoming [today], and the [folded] shows gathered at
/// the end.
class ScheduleTimeline extends StatelessWidget {
  const ScheduleTimeline({
    super.key,
    required this.slots,
    required this.folded,
    required this.foldOpen,
    required this.onFoldToggle,
    required this.onOpen,
    required this.watchingIds,
    required this.chart,
    required this.today,
  });
  final List<ScheduleSlot> slots;
  final List<(ScheduleSlot, ScheduleFold)> folded;
  final bool foldOpen, today;
  final VoidCallback onFoldToggle;
  final ValueChanged<Subject> onOpen;
  final Set<int> watchingIds;

  /// The week's chart places worth a badge, by show.
  final Map<int, ChartEntry> chart;

  @override
  Widget build(BuildContext context) => ShownClock(
    period: const Duration(minutes: 1),
    builder: (context) {
      final now = DateTime.now();
      final aired = [
        for (final slot in slots) slot.subject.airingAt?.isBefore(now) ?? false,
      ];
      final upcoming = aired.indexOf(false);
      final nowIndex = today ? (upcoming < 0 ? slots.length : upcoming) : -1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < slots.length; i++) ...[
            if (i == nowIndex) _NowLine(now: now, first: i == 0),
            _ScheduleEntry(
              key: ValueKey(
                '${slots[i].subject.id}:${slots[i].subject.airingAt}',
              ),
              slot: slots[i],
              aired: aired[i],
              // The time and dot mark the first show of each time.
              opensSlot:
                  i == 0 ||
                  slots[i - 1].subject.airingAt != slots[i].subject.airingAt,
              first: i == 0 && nowIndex != 0,
              last: i == slots.length - 1 && nowIndex != slots.length,
              status: aired[i]
                  ? '已更新'
                  : today && i == upcoming
                  ? '${releaseWhen((at: slots[i].subject.airingAt!, timed: true))}更新'
                  : null,
              watching: watchingIds.contains(slots[i].subject.id),
              chart: chart[slots[i].subject.id],
              onOpen: onOpen,
            ),
          ],
          if (nowIndex == slots.length && slots.isNotEmpty)
            _NowLine(now: now, first: false, last: true),
          if (folded.isNotEmpty)
            _FoldedShows(
              folded: folded,
              open: foldOpen,
              onToggle: onFoldToggle,
              onOpen: onOpen,
            ),
        ],
      );
    },
  );
}

/// [ScheduleTimeline] cards in grey while the week loads, once the wait
/// has lasted [busyDelay].
class ScheduleTimelineSkeleton extends StatelessWidget {
  const ScheduleTimelineSkeleton({super.key});

  static const _shares = [.55, .4, .7];

  @override
  Widget build(BuildContext context) => DelayedBusy(
    busy: true,
    builder: (context, shown) => !shown
        ? const SizedBox.shrink()
        : SkeletonGroup(
            label: '正在加载时间表',
            child: Column(
              children: [
                for (final share in _shares)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: _timeWidth + _railWidth,
                      bottom: Gap.md,
                    ),
                    child: MelonPanel(
                      padding: const EdgeInsets.all(Gap.lg),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SkeletonBlock(
                            width: 120,
                            height: 170,
                            radius: posterBorderRadius,
                          ),
                          const SizedBox(width: Gap.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FractionallySizedBox(
                                  widthFactor: share,
                                  child: const SkeletonBlock(height: 14),
                                ),
                                const SizedBox(height: Gap.lg),
                                const SkeletonBlock(width: 160, height: 10),
                                const SizedBox(height: Gap.md),
                                const SkeletonBlock(width: 120, height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
  );
}

/// The rail's line: above the dot, below it, or both.
class _Rail extends StatelessWidget {
  const _Rail({required this.above, required this.below, this.dot = 28});
  final bool above, below;

  /// Where the dot's centre sits from the top.
  final double dot;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return Positioned(
      left: _timeWidth + _railWidth / 2 - 1,
      top: 0,
      bottom: 0,
      width: 2,
      child: Column(
        children: [
          Container(width: 2, height: dot, color: above ? line : null),
          Expanded(child: Container(width: 2, color: below ? line : null)),
        ],
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine({required this.now, required this.first, this.last = false});
  final DateTime now;
  final bool first, last;

  @override
  Widget build(BuildContext context) {
    final ink = coralInk(Theme.of(context).brightness == Brightness.dark);
    final style = TextStyle(
      fontSize: FontSize.small,
      fontWeight: FontWeight.w400,
      color: ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          _Rail(above: !first, below: !last, dot: 14),
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Row(
              children: [
                SizedBox(
                  width: _timeWidth,
                  child: Text('现在', style: style),
                ),
                SizedBox(
                  width: _railWidth,
                  child: Center(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: coral,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: coral.withValues(alpha: .2),
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    color: coral.withValues(alpha: .5),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Text(shanghaiClock(now), style: style),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleEntry extends StatelessWidget {
  const _ScheduleEntry({
    super.key,
    required this.slot,
    required this.aired,
    required this.opensSlot,
    required this.first,
    required this.last,
    required this.status,
    required this.watching,
    required this.chart,
    required this.onOpen,
  });
  final ScheduleSlot slot;
  final bool aired, opensSlot, first, last, watching;
  final String? status;
  final ChartEntry? chart;
  final ValueChanged<Subject> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final instant = slot.subject.airingAt;
    return Stack(
      children: [
        _Rail(above: !first, below: !last),
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _timeWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 19),
                  child: Text(
                    !opensSlot
                        ? ''
                        : instant == null
                        ? '待定'
                        : shanghaiClock(instant),
                    style: TextStyle(
                      fontSize: FontSize.small,
                      fontWeight: FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: aired ? scheme.onSurfaceVariant : scheme.onSurface,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _railWidth,
                child: opensSlot
                    ? Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: Center(
                          child: Container(
                            width: 12,
                            height: 12,
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
                      )
                    : null,
              ),
              Expanded(
                child: _HoverLift(
                  child: _ScheduleCard(
                    slot: slot,
                    status: status,
                    aired: aired,
                    watching: watching,
                    chart: chart,
                    onOpen: onOpen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Raises [child] a little toward the pointer while hovered or focused.
/// Only the lift rebuilds; [child] is kept as built.
class _HoverLift extends StatefulWidget {
  const _HoverLift({required this.child});
  final Widget child;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool hovered = false, focused = false;

  @override
  Widget build(BuildContext context) {
    final lift =
        (hovered || focused) && !MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => focused = value),
        child: AnimatedContainer(
          duration: motionDuration(context, 200),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(lift ? 2 : 0, lift ? -2 : 0, 0),
          child: widget.child,
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.slot,
    required this.status,
    required this.aired,
    required this.watching,
    required this.chart,
    required this.onOpen,
  });
  final ScheduleSlot slot;
  final String? status;
  final bool aired, watching;
  final ChartEntry? chart;
  final ValueChanged<Subject> onOpen;

  @override
  Widget build(BuildContext context) {
    final item = slot.subject;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return MelonPanel(
      onTap: () => onOpen(item),
      padding: const EdgeInsets.all(Gap.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow cards keep room for the text beside a smaller cover.
          final wide = constraints.maxWidth >= 480;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: wide ? 120 : 84,
                height: wide ? 170 : 119,
                child: CoverFrame(
                  child: SubjectCover(
                    url: item.coverUrl,
                    title: item.title,
                    id: item.id,
                  ),
                ),
              ),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: FontSize.emphasis,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (chart case final chart?)
                          Padding(
                            padding: const EdgeInsets.only(left: Gap.sm),
                            child: Tooltip(
                              message: '热度周榜第 ${chart.rank} 名',
                              child: MelonBadge(
                                '周榜 #${chart.rank}',
                                color: gold,
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
                    if ((item.name ?? '').isNotEmpty && item.name != item.title)
                      Text(
                        item.name!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall,
                      ),
                    const SizedBox(height: Gap.md),
                    _Stats(item: item),
                    if (_Progress.shows(slot, status)) ...[
                      const SizedBox(height: Gap.sm),
                      _Progress(slot: slot, status: status, aired: aired),
                    ],
                    const SizedBox(height: Gap.md),
                    _Topics(item: item),
                    if ((item.summary ?? '').isNotEmpty && wide) ...[
                      const SizedBox(height: Gap.md),
                      Text(
                        item.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Score, rank, raters and collectors, as Bangumi counts them.
class _Stats extends StatelessWidget {
  const _Stats({required this.item});
  final Subject item;

  /// Raters below which a score is only a hint.
  static const _fewRatings = 50;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final score = item.score;
    final few = (item.ratingCount ?? 0) < _fewRatings;
    final collected = item.collectionStats.values.fold(
      0,
      (sum, count) => sum + count,
    );
    return Wrap(
      spacing: Gap.md,
      runSpacing: Gap.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (score != null && score > 0)
          Tooltip(
            message: few ? '评分人数较少，仅供参考' : 'Bangumi 评分',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_rounded,
                  size: 17,
                  color: few ? scheme.outline : gold,
                ),
                const SizedBox(width: 2),
                Text(
                  scoreLabel(score),
                  style: TextStyle(
                    fontSize: FontSize.emphasis,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: few ? scheme.onSurfaceVariant : null,
                  ),
                ),
              ],
            ),
          )
        else if (item.collectionStats.isNotEmpty)
          Text('暂无评分', style: small),
        if (item.rank case final rank?) Text('排名 #$rank', style: small),
        if (item.ratingCount case final count? when score != null)
          Text('${thousands(count)} 人评分', style: small),
        if (collected > 0) Text('${thousands(collected)} 人收藏', style: small),
      ],
    );
  }
}

/// Which episode airs, out of how many, and whether it is out yet; or that
/// the show takes the week off.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.slot,
    required this.status,
    required this.aired,
  });
  final ScheduleSlot slot;
  final String? status;
  final bool aired;

  /// Whether there is anything to say: an episode, a count, a status, a
  /// week off.
  static bool shows(ScheduleSlot slot, String? status) =>
      slot.episode != null ||
      slot.subject.episodeTotal != null ||
      status != null ||
      slot.breakUntil != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final small = text.bodySmall;
    final total = slot.subject.episodeTotal;
    final episode = slot.episode;
    if (slot.breakUntil case final next?) {
      return Text('本周休息  ${next.month}月${next.day}日播出下一话', style: small);
    }
    return Wrap(
      spacing: Gap.md,
      runSpacing: Gap.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (episode != null || total != null)
          Text.rich(
            TextSpan(
              children: [
                if (episode != null)
                  TextSpan(
                    text: '第 ${_number(episode)} 话',
                    style: text.bodyMedium,
                  ),
                if (total != null)
                  TextSpan(
                    text: episode != null ? ' / 全 $total 话' : '全 $total 话',
                  ),
              ],
            ),
            style: small?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        if (episode != null && total != null && total > 0)
          SizedBox(
            width: 96,
            child: ClipRRect(
              borderRadius: pillBorderRadius,
              child: LinearProgressIndicator(
                value: (episode / total).clamp(0, 1).toDouble(),
                minHeight: 4,
                color: accentOf(context).accent,
                backgroundColor: scheme.outlineVariant,
              ),
            ),
          ),
        if (status case final status?)
          Text(
            status,
            style: small?.copyWith(
              color: aired ? scheme.primary : scheme.onSurface,
            ),
          ),
        if (slot.finale) MelonBadge('最终话', color: scheme.onSurfaceVariant),
      ],
    );
  }
}

String _number(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

/// The season it began, how it airs, what it is, and 长篇.
class _Topics extends StatelessWidget {
  const _Topics({required this.item});
  final Subject item;

  @override
  Widget build(BuildContext context) {
    final began = DateTime.tryParse(item.airDate ?? '');
    final kind = scheduleKind(item);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (began != null)
          MelonBadge('${began.year}年${began.month}月', color: coral),
        MelonBadge(kind == '其他' ? item.platform ?? kind : kind, color: sky),
        for (final topic in scheduleTopics(item).take(3))
          MelonBadge(topic, color: grape),
        if (isLongRunning(item, DateTime.now()))
          Tooltip(
            message: '40 话以上，或已播出一年以上',
            child: MelonBadge(
              '长篇',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// The folded shows: how many and why, then each as a row once [open].
class _FoldedShows extends StatelessWidget {
  const _FoldedShows({
    required this.folded,
    required this.open,
    required this.onToggle,
    required this.onOpen,
  });
  final List<(ScheduleSlot, ScheduleFold)> folded;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<Subject> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final counts = <ScheduleFold, int>{};
    for (final (_, fold) in folded) {
      counts[fold] = (counts[fold] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(
        left: _timeWidth + _railWidth,
        top: Gap.xs,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: panelBorderRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.md, Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ScheduleCoverStack(
                    slots: [for (final (slot, _) in folded.take(3)) slot],
                    ring: scheme.surfaceContainerHigh,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('另有 ${folded.length} 部已收起'),
                        Text(
                          [
                            for (final fold in ScheduleFold.values)
                              if (counts[fold] case final count?)
                                '${fold.label} $count',
                          ].join('  '),
                          style: small,
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: onToggle,
                    child: Text(open ? '收起' : '展开'),
                  ),
                ],
              ),
              AnimatedSize(
                duration: motionDuration(context, 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !open
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: Gap.md),
                        child: Column(
                          children: [
                            for (final (slot, fold) in folded)
                              _FoldedRow(
                                slot: slot,
                                fold: fold,
                                onOpen: onOpen,
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoldedRow extends StatelessWidget {
  const _FoldedRow({
    required this.slot,
    required this.fold,
    required this.onOpen,
  });
  final ScheduleSlot slot;
  final ScheduleFold fold;
  final ValueChanged<Subject> onOpen;

  @override
  Widget build(BuildContext context) {
    final item = slot.subject;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final watching = item.collectionStats[CollectionStatus.watching];
    final instant = item.airingAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: scheme.surface,
        borderRadius: insetRadius(panelBorderRadius, 2),
        child: InkWell(
          onTap: () => onOpen(item),
          borderRadius: insetRadius(panelBorderRadius, 2),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.sm,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    instant == null ? '待定' : shanghaiClock(instant),
                    style: small?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                SizedBox(
                  width: 30,
                  height: 42,
                  child: CoverFrame(
                    radius: tightBorderRadius,
                    child: SubjectCover(
                      url: item.coverUrl,
                      title: item.title,
                      id: item.id,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        [
                          if (slot.episode case final episode?)
                            '第 ${_number(episode)} 话',
                          if (watching != null) '${thousands(watching)} 人在看',
                        ].join('  '),
                        style: small,
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: fold.reason,
                  child: MelonBadge(fold.label, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three covers overlapping, each ringed in [ring] to part it from
/// the one under it.
class ScheduleCoverStack extends StatelessWidget {
  const ScheduleCoverStack({
    super.key,
    required this.slots,
    required this.ring,
    this.width = 24,
  });
  final List<ScheduleSlot> slots;
  final Color ring;
  final double width;

  static const _overlap = 8.0;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.42;
    final step = width - _overlap;
    return SizedBox(
      width: slots.isEmpty ? 0 : width + 4 + (slots.length - 1) * step,
      height: height + 4,
      child: Stack(
        children: [
          for (final (i, slot) in slots.indexed)
            Positioned(
              left: i * step,
              top: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ring,
                  borderRadius: badgeBorderRadius,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: CoverFrame(
                      radius: tightBorderRadius,
                      child: SubjectCover(
                        url: slot.subject.coverUrl,
                        title: slot.subject.title,
                        id: slot.subject.id,
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
