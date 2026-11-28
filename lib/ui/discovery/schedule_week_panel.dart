import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../features/discovery/schedule_week.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'schedule_timeline.dart';

/// What a day of the week strip shows: the shows listed, how many more are
/// folded, and how many of them the user is watching.
typedef ScheduleDaySummary = ({
  String label,
  DateTime date,
  bool today,
  List<ScheduleSlot> listed,
  int folded,
  int watching,
});

/// The head of the schedule: the week and its navigation, a cell for each
/// day, then the scope and the filter.
class ScheduleWeekPanel extends StatelessWidget {
  const ScheduleWeekPanel({
    super.key,
    required this.days,
    required this.selected,
    required this.onSelect,
    required this.onPrevious,
    required this.onNext,
    required this.onThisWeek,
    required this.scope,
    required this.scopeCounts,
    required this.onScope,
    required this.filter,
  });
  final List<ScheduleDaySummary> days;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Null where there is nowhere to go: before or after the weeks kept,
  /// or this week already.
  final VoidCallback? onPrevious, onNext, onThisWeek;
  final ScheduleScope scope;
  final Map<ScheduleScope, int> scopeCounts;
  final ValueChanged<ScheduleScope> onScope;
  final Widget filter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final first = days.first.date, last = days.last.date;
    return MelonPanel(
      padding: const EdgeInsets.fromLTRB(20, Gap.lg, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('时间表', style: text.titleLarge),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  '${first.month}月${first.day}日 – ${last.month}月${last.day}日',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              WeekStepper(
                onPrevious: onPrevious,
                onNext: onNext,
                thisWeek: true,
                onThisWeek: onThisWeek,
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, day) in days.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _DayCell(
                    day: day,
                    selected: i == selected,
                    onTap: () => onSelect(i),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Gap.md),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final value in ScheduleScope.values)
                  MelonChip(
                    label: value.label,
                    count: '${scopeCounts[value]}',
                    selected: value == scope,
                    onPressed: () => onScope(value),
                  ),
                const _Separator(),
                filter,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The schedule shrunk to one line, pinned over the page once the week
/// panel scrolls away: the days, the scope and the filter.
class ScheduleCompactBar extends StatelessWidget {
  const ScheduleCompactBar({
    super.key,
    required this.days,
    required this.selected,
    required this.onSelect,
    required this.scope,
    required this.onScope,
    required this.filter,
  });
  final List<ScheduleDaySummary> days;
  final int selected;
  final ValueChanged<int> onSelect;
  final ScheduleScope scope;
  final ValueChanged<ScheduleScope> onScope;
  final Widget filter;

  static const height = 52.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .94),
        borderRadius: panelBorderRadius,
        boxShadow: panelShadows(context),
      ),
      child: SizedBox(
        height: height,
        // Narrow pages give up the scope, then the title.
        child: LayoutBuilder(
          builder: (context, constraints) => Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, 10, 0),
            child: Row(
              children: [
                if (constraints.maxWidth >= 680) ...[
                  const Text(
                    '时间表',
                    style: TextStyle(
                      fontSize: FontSize.emphasis,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                ],
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (i, day) in days.indexed) ...[
                          if (i > 0) const SizedBox(width: 2),
                          MelonChip(
                            label: day.today ? '今天' : day.label,
                            count: '${day.listed.length}',
                            selected: i == selected,
                            onPressed: () => onSelect(i),
                          ),
                        ],
                        if (constraints.maxWidth >= 900) ...[
                          const _Separator(),
                          for (final value in ScheduleScope.values)
                            MelonChip(
                              label: value.label,
                              selected: value == scope,
                              onPressed: () => onScope(value),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                filter,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short rule between groups of chips.
class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// The previous week, back to this one, and the next, in one tray. 本周
/// stands raised, and can be pressed once another week is shown.
/// The previous and next week's buttons in a tray, with 本周 between them
/// when [thisWeek]; a null callback disables its button.
class WeekStepper extends StatelessWidget {
  const WeekStepper({
    super.key,
    required this.onPrevious,
    required this.onNext,
    this.thisWeek = false,
    this.onThisWeek,
  });
  final VoidCallback? onPrevious, onNext, onThisWeek;
  final bool thisWeek;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = IconButton.styleFrom(
      fixedSize: const Size.square(28),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size.square(28),
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: badgeBorderRadius),
    );
    return Container(
      height: MelonChip.height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: controlBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '上一周',
            style: step,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
          ),
          if (thisWeek)
            TextButton(
              onPressed: onThisWeek,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                backgroundColor: scheme.surface,
                disabledBackgroundColor: scheme.surface,
                foregroundColor: scheme.onSurface,
                disabledForegroundColor: scheme.onSurfaceVariant,
                side: BorderSide(color: scheme.outlineVariant),
                shape: const RoundedRectangleBorder(
                  borderRadius: badgeBorderRadius,
                ),
                textStyle: appFont.copyWith(fontSize: FontSize.body),
              ),
              child: const Text('本周'),
            ),
          IconButton(
            tooltip: '下一周',
            style: step,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.onTap,
  });
  final ScheduleDaySummary day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = selected
        ? Color.alphaBlend(
            scheme.primaryContainer.withValues(alpha: dark ? .55 : .45),
            scheme.surface,
          )
        : scheme.surfaceContainerLow;
    final ink = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final quiet = selected
        ? scheme.onPrimaryContainer.withValues(alpha: .8)
        : scheme.onSurfaceVariant;
    final empty = day.listed.isEmpty && day.folded == 0;
    // The three covers most watched on Bangumi stand for the day.
    final covers = [...day.listed]
      ..sort(
        (a, b) => (b.subject.collectionStats[CollectionStatus.watching] ?? 0)
            .compareTo(
              a.subject.collectionStats[CollectionStatus.watching] ?? 0,
            ),
      );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: background,
        borderRadius: insetRadius(panelBorderRadius, 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // Narrow cells give up covers, then the date, before the count.
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.md,
                    10,
                    Gap.md,
                    Gap.md,
                  ),
                  child: Opacity(
                    opacity: empty ? .7 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              day.label,
                              style: TextStyle(
                                fontSize: FontSize.emphasis,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (constraints.maxWidth >= 120)
                              Flexible(
                                child: Text(
                                  '${day.date.month}/${day.date.day}',
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: small?.copyWith(
                                    color: quiet,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            const Spacer(),
                            if (day.today)
                              Text(
                                '今天',
                                style: TextStyle(
                                  fontSize: FontSize.caption,
                                  color: coralInk(dark),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: Gap.sm),
                        SizedBox(
                          height: 38,
                          child: empty
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '本日无放送',
                                    style: small?.copyWith(color: quiet),
                                  ),
                                )
                              : Row(
                                  children: [
                                    ScheduleCoverStack(
                                      slots: covers.take(
                                        switch (constraints.maxWidth) {
                                          >= 160 => 3,
                                          >= 140 => 2,
                                          >= 122 => 1,
                                          _ => 0,
                                        },
                                      ).toList(),
                                      ring: background,
                                    ),
                                    if (constraints.maxWidth >= 122)
                                      const SizedBox(width: Gap.sm),
                                    Flexible(
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '${day.listed.length} 部',
                                              style: TextStyle(color: ink),
                                            ),
                                            if (day.folded > 0)
                                              TextSpan(
                                                text: ' +${day.folded}',
                                                style: small?.copyWith(
                                                  color: quiet,
                                                ),
                                              ),
                                          ],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                        style: const TextStyle(
                                          fontSize: FontSize.body,
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 16,
                          child: day.watching == 0
                              ? null
                              : Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: accentOf(context).accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        '在追 ${day.watching}',
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                        style: small?.copyWith(
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 0,
                  height: 3,
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: motionDuration(context, 160),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accentOf(context).accent,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
