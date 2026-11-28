import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';
import '../../features/discovery/schedule_week.dart';
import '../core/help_hint.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_cover.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'release_labels.dart';
import 'schedule_week_panel.dart';

const _panelTitle = TextStyle(
  fontSize: FontSize.emphasis,
  fontWeight: FontWeight.w700,
);

const _tabular = [FontFeature.tabularFigures()];

/// What the full chart shows: the week the page shows and its chart, and
/// how to step to the weeks either side; the page keeps it current while
/// the chart is open.
class ChartView {
  const ChartView({
    required this.monday,
    required this.week,
    required this.entries,
    required this.comparable,
    required this.error,
    required this.onPrevious,
    required this.onNext,
  });
  final String monday;

  /// Null while [monday]'s week loads, or when it failed to.
  final ScheduleWeek? week;
  final List<ChartEntry> entries;

  /// Whether the week before has heat, so moves can be shown.
  final bool comparable;
  final String? error;
  final VoidCallback? onPrevious, onNext;
}

/// The week's top ten shows by heat, with 完整榜单 for all of them.
class WeeklyChartPanel extends StatelessWidget {
  const WeeklyChartPanel({
    super.key,
    required this.view,
    required this.full,
    required this.onOpen,
  });
  final ChartView view;

  /// [view] as the page keeps it, for the full chart.
  final ValueListenable<ChartView> full;
  final ValueChanged<Subject> onOpen;

  static const _shown = 10;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final entries = view.entries;
    return MelonPanel(
      // The rows' own 7 below the last cover makes up the 18 above.
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                const Text('热度周榜', style: _panelTitle),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    _range(view.monday, short: true),
                    style: text.bodySmall?.copyWith(fontFeatures: _tabular),
                  ),
                ),
                if (entries.isNotEmpty)
                  // Its label lines up with the rows' right edge.
                  Transform.translate(
                    offset: const Offset(Gap.sm, 0),
                    child: TextButton(
                      style: compactTextButtonStyle,
                      onPressed: () => showMelonDialog<void>(
                        context: context,
                        builder: (_) =>
                            _ChartDialog(view: full, onOpen: onOpen),
                      ),
                      child: const Text('完整榜单'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xs),
          if (entries.isEmpty)
            EmptyState.compact(text: _emptyText(view.monday))
          else
            for (final entry in entries.take(_shown))
              _ChartRow(
                entry: entry,
                comparable: view.comparable,
                onOpen: onOpen,
              ),
        ],
      ),
    );
  }
}

const _chartHelp =
    '热度按这一周 Bangumi 上的新增收藏（35%）、\n'
    '本集吐槽（35%）和在看人数（30%）计算，\n'
    '每项先按这周最高的一部折算；名次变化对比上一周';

/// The week starting [monday], as 11/23 – 11/29 or 11月23日 – 11月29日.
String _range(String monday, {bool short = false}) {
  final start = DateTime.parse('${monday}T00:00:00Z');
  final end = start.add(const Duration(days: 6));
  return short
      ? '${start.month}/${start.day} – ${end.month}/${end.day}'
      : '${start.month}月${start.day}日 – ${end.month}月${end.day}日';
}

/// Why the chart of the week starting [monday] is empty.
String _emptyText(String monday) =>
    DateTime.now().isBefore(
      DateTime.parse('${monday}T00:00:00Z').subtract(const Duration(hours: 8)),
    )
    ? '这一周还没开始'
    : '这一周还没有热度数据';

/// How a show's rank moved since the week before, and its colour.
(String, Color) _move(BuildContext context, ChartEntry entry, bool comparable) {
  final scheme = Theme.of(context).colorScheme;
  return switch (entry.move) {
    final m? when m > 0 => ('↑$m', scheme.primary),
    final m? when m < 0 => ('↓${-m}', scheme.onSurfaceVariant),
    0 => ('–', scheme.onSurfaceVariant),
    _ => (comparable ? '新' : '', scheme.primary),
  };
}

/// A show's episode in the chart's week and, unless [comments] is false,
/// the comments its heat counted; or that it took the week off.
String _episodeLine(ScheduleSlot slot, {bool comments = true}) => [
  if (slot.episode case final episode?)
    '第 ${episode.round()} 话'
  else if (slot.breakUntil != null)
    '本周停播',
  if (slot.heatComments case final count? when comments && count > 0)
    '$count 条吐槽',
].join('  ');

/// Every show of the week's chart in a table, a week at a time: rank,
/// move, the show and its episode, then heat and what it is made of, and
/// the score.
class _ChartDialog extends StatelessWidget {
  const _ChartDialog({required this.view, required this.onOpen});
  final ValueListenable<ChartView> view;
  final ValueChanged<Subject> onOpen;

  static const _rank = 32.0, _moveWidth = 40.0, _heat = 56.0;
  static const _number = 80.0, _score = 48.0;

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 880, maxHeight: 760),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 20, Gap.lg, Gap.md),
        child: ValueListenableBuilder(
          valueListenable: view,
          builder: (context, view, _) => _content(context, view),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context, ChartView view) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    Widget head(String label, double width) => SizedBox(
      width: width,
      child: Text(label, textAlign: TextAlign.end, style: small),
    );
    const gap = SizedBox(width: Gap.lg);
    final body = switch (view) {
      ChartView(week: null, error: final error?) => EmptyState.compact(
        text: '这一周没能加载：$error',
      ),
      ChartView(week: null) => const Padding(
        padding: EdgeInsets.symmetric(vertical: Gap.xl),
        child: Center(child: BusyIndicator(size: 20)),
      ),
      ChartView(entries: []) => EmptyState.compact(
        text: _emptyText(view.monday),
      ),
      _ => ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: Gap.xs),
        itemCount: view.entries.length,
        itemBuilder: (context, index) =>
            _row(context, view.entries[index], view.comparable),
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              '热度周榜',
              style: TextStyle(
                fontSize: FontSize.title,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: Gap.md),
            Text(
              _range(view.monday),
              style: TextStyle(
                fontSize: FontSize.body,
                color: scheme.onSurfaceVariant,
                fontFeatures: _tabular,
              ),
            ),
            const SizedBox(width: Gap.xs),
            const HelpHint(message: _chartHelp),
            const Spacer(),
            WeekStepper(onPrevious: view.onPrevious, onNext: view.onNext),
            const SizedBox(width: Gap.sm),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Container(
          padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.sm),
          margin: const EdgeInsets.only(right: Gap.sm),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _rank,
                child: Text('名次', style: small),
              ),
              gap,
              SizedBox(
                width: _moveWidth,
                child: Text('变化', style: small),
              ),
              gap,
              Expanded(child: Text('番剧', style: small)),
              head('热度', _heat),
              gap,
              head('新增收藏', _number),
              head('本集吐槽', _number),
              head('在看', _number),
              gap,
              head('评分', _score),
            ],
          ),
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(right: Gap.sm),
            child: body,
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, ChartEntry entry, bool comparable) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final slot = entry.slot;
    final item = slot.subject;
    final (move, moveColor) = _move(context, entry, comparable);
    final watching = item.collectionStats[CollectionStatus.watching];
    final score = item.score;
    String count(int? value) => value == null ? '—' : thousands(value);
    Widget number(
      String text,
      double width, {
      bool quiet = true,
      FontWeight? weight,
    }) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: FontSize.body,
          fontWeight: weight,
          color: quiet ? scheme.onSurfaceVariant : null,
          fontFeatures: _tabular,
        ),
      ),
    );
    const gap = SizedBox(width: Gap.lg);
    final episode = _episodeLine(slot, comments: false);
    return InkWell(
      borderRadius: controlBorderRadius,
      onTap: () {
        Navigator.pop(context);
        onOpen(item);
      },
      child: Padding(
        padding: const EdgeInsets.all(Gap.sm),
        child: Row(
          children: [
            SizedBox(
              width: _rank,
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  fontSize: FontSize.title,
                  fontWeight: FontWeight.w700,
                  fontFeatures: _tabular,
                  color: entry.rank <= 3
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            gap,
            SizedBox(
              width: _moveWidth,
              child: Text(
                move,
                style: small?.copyWith(
                  color: moveColor,
                  fontFeatures: _tabular,
                ),
              ),
            ),
            gap,
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
                    style: const TextStyle(
                      fontSize: FontSize.body,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (episode.isNotEmpty) Text(episode, style: small),
                ],
              ),
            ),
            number(
              '${slot.heat!.round()}',
              _heat,
              quiet: false,
              weight: FontWeight.w700,
            ),
            gap,
            number(count(slot.collectionGain), _number, quiet: false),
            number(count(slot.heatComments), _number, quiet: false),
            number(count(watching), _number),
            gap,
            number(
              score == null || score <= 0 ? '—' : scoreLabel(score),
              _score,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartRow extends StatelessWidget {
  const _ChartRow({
    required this.entry,
    required this.comparable,
    required this.onOpen,
  });
  final ChartEntry entry;
  final bool comparable;
  final ValueChanged<Subject> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final item = entry.slot.subject;
    final (move, moveColor) = _move(context, entry, comparable);
    return _SideRow(
      onTap: () => onOpen(item),
      leading: SizedBox(
        width: 22,
        child: Text(
          '${entry.rank}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: FontSize.emphasis,
            fontWeight: FontWeight.w700,
            fontFeatures: _tabular,
            color: entry.rank <= 3 ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
      item: item,
      detail: _episodeLine(entry.slot),
      trailing: SizedBox(
        width: 32,
        child: Text(
          move,
          textAlign: TextAlign.end,
          style: small?.copyWith(color: moveColor, fontFeatures: _tabular),
        ),
      ),
    );
  }
}

/// The week's final episodes, each with its day and time.
class WeekFinalesPanel extends StatelessWidget {
  const WeekFinalesPanel({
    super.key,
    required this.finales,
    required this.onOpen,
  });
  final List<ScheduleSlot> finales;
  final ValueChanged<Subject> onOpen;

  @override
  Widget build(BuildContext context) => MelonPanel(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('本周最终话', style: _panelTitle),
        const SizedBox(height: Gap.sm),
        for (final slot in finales)
          _SideRow(
            onTap: () => onOpen(slot.subject),
            item: slot.subject,
            detail: [
              if (slot.subject.airingAt case final at?)
                '${weekdayLabels[shanghaiDay(at).weekday - 1]} ${shanghaiClock(at)}',
              if (slot.episode case final episode?) '第 ${episode.round()} 话',
            ].join('  '),
          ),
      ],
    ),
  );
}

/// A show in a side panel: [leading], its cover and title over [detail],
/// then [trailing].
class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.onTap,
    required this.item,
    required this.detail,
    this.leading,
    this.trailing,
  });
  final VoidCallback onTap;
  final Subject item;
  final String detail;
  final Widget? leading, trailing;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: controlBorderRadius,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: Gap.md)],
          SizedBox(
            width: 34,
            height: 48,
            child: CoverFrame(
              radius: badgeBorderRadius,
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
                  style: const TextStyle(
                    fontSize: FontSize.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}
