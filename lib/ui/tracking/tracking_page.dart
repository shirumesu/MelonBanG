import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../features/playback/resume_controller.dart';
import '../../features/tracking/tracking_controller.dart';
import '../core/action_feedback.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'collection_labels.dart';

class TrackingPage extends StatefulWidget {
  const TrackingPage({
    super.key,
    required this.personal,
    required this.resume,
    required this.airing,
    required this.onSync,
    required this.feedback,
    required this.onSignIn,
    required this.onOpenSubject,
    this.onExplore,
  });
  final TrackingController personal;
  final ResumeController resume;

  /// Subjects with an episode in the schedule's coming seven days.
  final Set<int> airing;
  final VoidCallback onSync, onSignIn;
  final ActionFeedback feedback;
  final ValueChanged<Subject> onOpenSubject;
  final VoidCallback? onExplore;
  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

enum _Order { collected, score, personal, played, popularity }

/// The airing quarter of [item], `2024-10`, or empty when unknown.
String _season(Subject item) {
  final match = RegExp(r'^(\d{4})-(\d{2})').firstMatch(item.airDate ?? '');
  if (match == null) return '';
  final month = (int.parse(match[2]!) - 1) ~/ 3 * 3 + 1;
  return '${match[1]}-${'$month'.padLeft(2, '0')}';
}

String _seasonLabel(String season) => season.isEmpty
    ? '未标明'
    : '${season.substring(0, 4)}年${int.parse(season.substring(5))}月';

class _TrackingPageState extends State<TrackingPage> {
  String query = '';
  bool airingOnly = false;
  Set<String> seasons = {};
  _Order order = _Order.collected;
  final search = TextEditingController();
  bool restored = false;
  late final listenable = Listenable.merge([widget.personal, widget.resume]);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (restored) return;
    restored = true;
    final saved = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: 'tracking-filters') as Map?;
    if (saved == null) return;
    query = saved['query'] as String;
    search.text = query;
    airingOnly = saved['airing'] as bool;
    seasons = {...saved['seasons'] as List<String>};
    order = _Order.values.byName(saved['order'] as String);
  }

  void updateFilters(VoidCallback update) {
    setState(update);
    PageStorage.maybeOf(context)?.writeState(context, {
      'query': query,
      'airing': airingOnly,
      'seasons': seasons.toList(),
      'order': order.name,
    }, identifier: 'tracking-filters');
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: listenable, builder: _page);

  Widget _page(BuildContext context, Widget? _) {
    final personal = widget.personal;
    final collection = personal.collection;
    final text = query.toLowerCase();
    final base = collection
        .where(
          (item) =>
              item.status == personal.filter &&
              [
                item.title,
                item.name,
              ].any((name) => name?.toLowerCase().contains(text) ?? false) &&
              (!airingOnly || widget.airing.contains(item.id)),
        )
        .toList();
    final seasonCounts = <String, int>{for (final season in seasons) season: 0};
    for (final item in base) {
      seasonCounts.update(_season(item), (n) => n + 1, ifAbsent: () => 1);
    }
    final years = <String, List<String>>{};
    for (final season
        in seasonCounts.keys.where((s) => s.isNotEmpty).toList()
          ..sort((a, b) => b.compareTo(a))) {
      years.putIfAbsent(season.substring(0, 4), () => []).add(season);
    }
    final items = base
        .where((item) => seasons.isEmpty || seasons.contains(_season(item)))
        .toList();
    // Ties fall back to the newest collected, then the stored order.
    final position = {for (final (i, item) in items.indexed) item.id: i};
    final played = {for (final (i, id) in widget.resume.played.indexed) id: i};
    num publicScore(Subject item) => item.score ?? 0;
    final keys = <num Function(Subject)>[
      ...switch (order) {
        _Order.collected => [],
        _Order.score => [publicScore],
        _Order.personal => [(item) => item.collection?.score ?? 0, publicScore],
        _Order.played => [(item) => -(played[item.id] ?? played.length)],
        _Order.popularity => [(item) => item.collectionTotal ?? 0],
      },
      (item) => item.collection?.collectedAt?.millisecondsSinceEpoch ?? 0,
    ];
    items.sort((a, b) {
      for (final key in keys) {
        final result = key(b).compareTo(key(a));
        if (result != 0) return result;
      }
      return position[a.id]!.compareTo(position[b.id]!);
    });
    final filtered = query.isNotEmpty || airingOnly || seasons.isNotEmpty;
    return PageScroll(
      children: [
        const SizedBox(height: 8),
        MelonSegmentedControl<CollectionStatus>(
          options: {
            for (final entry in collectionLabels.entries)
              entry.key:
                  '${entry.value} ${collection.where((item) => item.status == entry.key).length}',
          },
          value: personal.filter,
          onChanged: personal.setFilter,
          semanticLabel: '追番分类',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 235,
              child: TextField(
                key: const PageStorageKey('collection-search'),
                controller: search,
                decoration: const InputDecoration(
                  hintText: '搜索收藏',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (value) => updateFilters(() => query = value),
              ),
            ),
            Tooltip(
              message: '7 天内有新一话放送',
              child: FilterChip(
                label: const Text('本周更新'),
                selected: airingOnly,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh,
                showCheckmark: true,
                checkmarkColor: Theme.of(context).colorScheme.primary,
                onSelected: (value) => updateFilters(() => airingOnly = value),
              ),
            ),
            MelonFilterMenu<String>(
              label: '放送',
              icon: Icons.date_range_outlined,
              summary: seasons.length == 1
                  ? _seasonLabel(seasons.single)
                  : '${seasons.length} 项',
              tooltip: '按放送季度筛选',
              sections: [
                for (final MapEntry(key: year, value: quarters)
                    in years.entries)
                  MelonFilterSection([
                    for (final season in quarters)
                      MelonFilterOption(
                        season,
                        '${int.parse(season.substring(5))}月',
                        detail: '${seasonCounts[season]}',
                      ),
                  ], title: '$year 年'),
                if (seasonCounts[''] case final count?)
                  MelonFilterSection([
                    MelonFilterOption('', _seasonLabel(''), detail: '$count'),
                  ]),
                if (seasonCounts.isEmpty)
                  const MelonFilterSection([], title: '没有可筛选的季度'),
              ],
              selected: seasons,
              onToggle: (season, on) => updateFilters(
                () => on ? seasons.add(season) : seasons.remove(season),
              ),
              actions: [
                if (seasons.isNotEmpty)
                  ('清除', () => updateFilters(seasons.clear)),
              ],
            ),
            MelonChoiceMenu<_Order>(
              options: const {
                _Order.collected: '最近收藏',
                _Order.score: '按评分',
                _Order.personal: '按我的评分',
                _Order.played: '最近观看',
                _Order.popularity: '按收藏人数',
              },
              value: order,
              onSelected: (value) => updateFilters(() => order = value),
              icon: Icons.sort,
              tooltip: '追番排序',
            ),
            FeedbackButton(
              feedback: widget.feedback,
              label: '同步收藏',
              runningLabel: '同步中…',
              successLabel: '同步完成',
              icon: Icons.sync,
              onPressed: widget.onSync,
            ),
          ],
        ),
        FeedbackIssue(
          feedback: widget.feedback,
          onRetry: personal.signedIn ? widget.onSync : widget.onSignIn,
          actionLabel: personal.signedIn ? '重试' : '去登录',
        ),
        if (personal.sync.pending > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${personal.sync.pending} 项修改等待同步',
              style: const TextStyle(color: gold, fontSize: 12),
            ),
          ),
        const SizedBox(height: Gap.lg),
        if (items.isEmpty)
          EmptyState(
            text: collection.isEmpty ? '还没有收藏的番剧' : '没有符合条件的番剧',
            actionLabel: filtered ? '清除筛选' : '搜索番剧',
            action: filtered
                ? () => updateFilters(() {
                    query = '';
                    search.clear();
                    airingOnly = false;
                    seasons.clear();
                  })
                : widget.onExplore,
          )
        else
          PageSliver(
            child: SubjectPosterGrid(
              onOpen: widget.onOpenSubject,
              items: items,
              tracking: true,
              personalScore: order == _Order.personal,
            ),
          ),
      ],
    );
  }
}
