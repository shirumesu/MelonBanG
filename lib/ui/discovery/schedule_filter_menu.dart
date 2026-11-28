import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../features/discovery/schedule_filter.dart';
import '../../features/discovery/schedule_week.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';

/// The schedule's filter button and menu: chips for what to list, R18, what
/// to hide and a lowest score, then a switch for each kind of show that
/// folds to the end of its day. Each count is of the chosen day's shows: what
/// the day would list with that chip picked, under the other choices, as 全部
/// counts; a fold's count is the day's +N. Choices take effect on 保存;
/// closing the menu otherwise drops them. [iconOnly] is the compact bar's
/// button.
class ScheduleFilterMenu extends StatefulWidget {
  const ScheduleFilterMenu({
    super.key,
    required this.preference,
    required this.week,
    required this.day,
    required this.collectedIds,
    this.iconOnly = false,
  });
  final SchedulePreference preference;
  final ScheduleWeek? week;

  /// The day of the week shown, whose shows the options count.
  final int day;

  /// The user's collection, which never folds.
  final Set<int> collectedIds;
  final bool iconOnly;

  @override
  State<ScheduleFilterMenu> createState() => _ScheduleFilterMenuState();
}

class _ScheduleFilterMenuState extends State<ScheduleFilterMenu> {
  static const _width = 600.0, _labelWidth = 44.0;
  final _menu = MenuController();

  /// The choices made since the menu opened, not yet saved.
  ScheduleFilter? draft;

  void _save(ScheduleFilter value) {
    unawaited(widget.preference.set(value));
    _menu.close();
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.preference.value;
    final chosen = _chosen(saved);
    final active = chosen.isNotEmpty;
    final summary = chosen.length == 1 ? chosen.single : '${chosen.length} 项';
    final filter = draft ?? saved;
    return MelonMenuAnchor(
      controller: _menu,
      maxWidth: _width,
      maxHeight: 620,
      // Each opening starts from what is saved.
      onOpen: () => setState(() => draft = null),
      menuChildren: [_panel(context, filter)],
      footer: _footer(context, saved, filter),
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        if (widget.iconOnly) {
          final scheme = Theme.of(context).colorScheme;
          return IconButton(
            tooltip: active ? '筛选：$summary' : '筛选',
            onPressed: toggle,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(MelonChip.height),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size.square(MelonChip.height),
              backgroundColor: active ? scheme.primaryContainer : null,
              foregroundColor: active
                  ? scheme.onPrimaryContainer
                  : scheme.onSurface,
            ),
            icon: const Icon(Icons.filter_list_rounded, size: 18),
          );
        }
        return MelonChip(
          icon: Icons.filter_list_rounded,
          label: '筛选',
          count: active ? summary : null,
          selected: active,
          onPressed: toggle,
        );
      },
    );
  }

  /// What the filter leaves out, in words: one per choice.
  static List<String> _chosen(ScheduleFilter filter) => [
    ...filter.kinds,
    ...filter.sources,
    ...filter.genres,
    ...filter.regions,
    if (filter.adult != AdultFilter.hide) 'R18 ${filter.adult.label}',
    if (filter.hideLongRunning) '隐藏长篇',
    if (filter.hidePastSeasons) '隐藏往季度',
    if (filter.minScore > 0) '${_score(filter.minScore)} 分以上',
  ];

  static String _score(double value) => value.toStringAsFixed(1);

  /// 清除筛选 and 保存, kept in sight below the choices.
  Widget _footer(
    BuildContext context,
    ScheduleFilter saved,
    ScheduleFilter filter,
  ) {
    final cleared = filter.cleared;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.md, Gap.sm),
        child: Row(
          children: [
            TextButton(
              onPressed: filter == cleared
                  ? null
                  : () => setState(() => draft = cleared),
              child: const Text('清除筛选'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: filter == saved ? null : () => _save(filter),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, ScheduleFilter filter) {
    final scheme = Theme.of(context).colorScheme;
    final small = TextStyle(
      fontSize: FontSize.small,
      color: scheme.onSurfaceVariant,
    );
    final now = DateTime.now();
    final shows = widget.week?.days[widget.day] ?? const <ScheduleSlot>[];
    bool collected(Subject item) => widget.collectedIds.contains(item.id);

    /// How many of the day's shows [probe] lists rather than hides or folds,
    /// among those [also] picks.
    String? counted(ScheduleFilter probe, [bool Function(Subject)? also]) {
      if (shows.isEmpty) return null;
      final listed = shows
          .map((slot) => slot.subject)
          .where(
            (item) =>
                probe.accepts(item, now) &&
                probe.fold(item, now, collected: collected(item)) == null &&
                (also?.call(item) ?? true),
          );
      return '${listed.length}';
    }

    // The day's most common genres, and any chosen before.
    final genreCounts = <String, int>{};
    for (final slot in shows) {
      for (final genre in scheduleGenres(slot.subject)) {
        genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
      }
    }
    final genres = {
      ...(genreCounts.keys.toList()
            ..sort((a, b) => genreCounts[b]!.compareTo(genreCounts[a]!)))
          .take(12),
      ...filter.genres,
    };
    void set(ScheduleFilter value) => setState(() => draft = value);
    Set<String> flip(Set<String> values, String value) => values.contains(value)
        ? ({...values}..remove(value))
        : {...values, value};

    /// A line of the menu: [title] in a column of its own, then [child].
    Widget line(String title, Widget child, {String? tooltip}) {
      final label = Text(title, style: small);
      return Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 5, Gap.lg, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _labelWidth,
              height: MelonChip.tintedHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: tooltip == null
                    ? label
                    : Tooltip(message: tooltip, child: label),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    Widget chips(List<Widget> children) =>
        Wrap(spacing: 6, runSpacing: 6, children: children);

    /// A chip of a multiple choice: [choose] is the filter with these
    /// values.
    Widget choice(
      String label,
      Set<String> values,
      ScheduleFilter Function(Set<String>) choose, {
      String? tooltip,
    }) => MelonChip(
      label: label,
      count: counted(choose({label})),
      tooltip: tooltip,
      tinted: true,
      selected: values.contains(label),
      onPressed: () => set(choose(flip(values, label))),
    );

    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Gap.xs),
          line(
            '类型',
            chips([
              for (final kind in ScheduleFilter.kindOptions)
                choice(
                  kind,
                  filter.kinds,
                  (kinds) => filter.copyWith(kinds: kinds),
                  tooltip: kind == '其他' ? 'OVA、剧场版等' : null,
                ),
              const _ChipSeparator(),
              for (final source in scheduleSources)
                choice(
                  source,
                  filter.sources,
                  (sources) => filter.copyWith(sources: sources),
                ),
            ]),
          ),
          if (genres.isNotEmpty)
            line(
              '题材',
              chips([
                for (final genre in genres)
                  choice(
                    genre,
                    filter.genres,
                    (genres) => filter.copyWith(genres: genres),
                  ),
              ]),
            ),
          line(
            '地区',
            chips([
              for (final region in ScheduleFilter.regionOptions)
                choice(
                  region,
                  filter.regions,
                  (regions) => filter.copyWith(regions: regions),
                ),
            ]),
          ),
          line(
            'R18',
            tooltip: 'Bangumi 标为 R18 或里番的番剧',
            chips([
              for (final value in const [
                AdultFilter.hide,
                AdultFilter.show,
                AdultFilter.only,
              ])
                MelonChip(
                  label: value.label,
                  count: value == AdultFilter.only
                      ? counted(filter.copyWith(adult: value))
                      : null,
                  tinted: true,
                  selected: filter.adult == value,
                  onPressed: () => set(filter.copyWith(adult: value)),
                ),
            ]),
          ),
          line(
            '隐藏',
            chips([
              MelonChip(
                label: '长篇',
                count: counted(
                  filter.copyWith(hideLongRunning: false),
                  (item) => isLongRunning(item, now),
                ),
                tooltip: '40 话以上，或已播出一年以上',
                tinted: true,
                selected: filter.hideLongRunning,
                onPressed: () => set(
                  filter.copyWith(hideLongRunning: !filter.hideLongRunning),
                ),
              ),
              MelonChip(
                label: '往季度',
                count: counted(
                  filter.copyWith(hidePastSeasons: false),
                  (item) => isFromPastSeason(item, now),
                ),
                tooltip: '上一季或更早开播，仍在播出',
                tinted: true,
                selected: filter.hidePastSeasons,
                onPressed: () => set(
                  filter.copyWith(hidePastSeasons: !filter.hidePastSeasons),
                ),
              ),
            ]),
          ),
          line(
            '评分',
            tooltip: '还没有评分的番剧不受影响',
            _ScoreSlider(
              value: filter.minScore,
              hidden: filter.minScore > 0
                  ? counted(filter.copyWith(minScore: 0), filter.scoredBelow)
                  : null,
              onChanged: (value) => set(filter.copyWith(minScore: value)),
            ),
          ),
          const Divider(height: 13),
          line(
            '收起',
            tooltip: '放到当天末尾收起，点开才显示',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final fold in ScheduleFold.values)
                  _FoldSwitch(
                    fold: fold,
                    // As many as the day's +N while it is on.
                    count: shows.isEmpty
                        ? null
                        : '${shows.map((slot) => slot.subject).where((item) => filter.accepts(item, now) && !collected(item) && scheduleFold(item, now) == fold).length}',
                    value: filter.folds.contains(fold),
                    onChanged: (on) => set(
                      filter.copyWith(
                        folds: {
                          for (final each in ScheduleFold.values)
                            if (each == fold ? on : filter.folds.contains(each))
                              each,
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xs),
        ],
      ),
    );
  }
}

/// A thin upright line between two groups of chips in one line.
class _ChipSeparator extends StatelessWidget {
  const _ChipSeparator();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.fromLTRB(3, 6, 3, 6),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// The lowest score to list, in half points up to 8; 0 lists every score.
/// [hidden] counts the day's shows it hides.
class _ScoreSlider extends StatelessWidget {
  const _ScoreSlider({
    required this.value,
    required this.hidden,
    required this.onChanged,
  });
  final double value;
  final String? hidden;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: MelonChip.tintedHeight,
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                tickMarkShape: SliderTickMarkShape.noTickMark,
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Slider(
                value: value,
                max: 8,
                divisions: 16,
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: Gap.sm),
          SizedBox(
            width: 150,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value == 0
                        ? '不限'
                        : '低于 ${_ScheduleFilterMenuState._score(value)} 分的隐藏',
                  ),
                  if (hidden != null)
                    TextSpan(
                      text: '  $hidden',
                      style: TextStyle(
                        fontSize: FontSize.small,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              style: const TextStyle(
                fontSize: FontSize.body,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A kind of show that folds, how many the day has, and why, with a switch;
/// the whole row flips it.
class _FoldSwitch extends StatelessWidget {
  const _FoldSwitch({
    required this.fold,
    required this.count,
    required this.value,
    required this.onChanged,
  });
  final ScheduleFold fold;
  final String? count;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: controlBorderRadius,
        child: SizedBox(
          height: MelonChip.tintedHeight + 4,
          child: Row(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: fold.label),
                    if (count != null)
                      TextSpan(
                        text: '  $count',
                        style: small?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                style: const TextStyle(fontSize: FontSize.body),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  fold.reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
              ),
              const SizedBox(width: Gap.sm),
              SizedBox(
                height: 24,
                child: FittedBox(
                  child: Switch(
                    value: value,
                    onChanged: onChanged,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
