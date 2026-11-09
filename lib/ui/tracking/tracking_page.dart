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
    required this.onAccountAction,
    required this.onUnlock,
    required this.onSaveCredentials,
    required this.onOpenSubject,
    this.onExplore,
  });
  final TrackingController personal;
  final ResumeController resume;

  /// Subjects with an episode in the schedule's coming seven days.
  final Set<int> airing;

  /// Signs in, or again once Bangumi refused to renew the login.
  final VoidCallback onAccountAction;

  /// Asks the keychain again for the saved login.
  final VoidCallback onUnlock;

  /// Saves the renewed login the keychain refused.
  final VoidCallback onSaveCredentials;
  final ValueChanged<Subject> onOpenSubject;
  final VoidCallback? onExplore;
  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

enum _Order { collected, score, personal, played, popularity }

final _yearMonth = RegExp(r'^(\d{4})-(\d{2})');

/// The airing quarter of [item], `2024-10`, or empty when unknown.
String _season(Subject item) {
  final match = _yearMonth.firstMatch(item.airDate ?? '');
  if (match == null) return '';
  final month = (int.parse(match[2]!) - 1) ~/ 3 * 3 + 1;
  return '${match[1]}-${'$month'.padLeft(2, '0')}';
}

String _seasonLabel(String season) => season.isEmpty
    ? '未标明'
    : '${season.substring(0, 4)}年${int.parse(season.substring(5))}月';

class _TrackingPageState extends State<TrackingPage> {
  bool airingOnly = false;
  Set<String> seasons = {};
  _Order order = _Order.collected;
  final search = TextEditingController();
  late final listenable = Listenable.merge([widget.personal, widget.resume]);

  @override
  void initState() {
    super.initState();
    final saved = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: 'tracking-filters') as Map?;
    if (saved == null) return;
    search.text = saved['query'] as String;
    airingOnly = saved['airing'] as bool;
    seasons = {...saved['seasons'] as List<String>};
    order = _Order.values.byName(saved['order'] as String);
  }

  void updateFilters(VoidCallback update) {
    setState(update);
    PageStorage.maybeOf(context)?.writeState(context, {
      'query': search.text,
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

  /// Why the collection may be behind Bangumi, with the step that fixes it.
  Widget _accountIssue(TrackingController personal) {
    if (!personal.signedIn) return const IssueBanner(issue: null);
    if (personal.sessionExpired) {
      return IssueBanner(
        issue: 'Bangumi 登录已过期，重新登录后继续同步',
        actionLabel: '重新登录',
        onAction: widget.onAccountAction,
      );
    }
    if (personal.needsAuthorization) {
      return IssueBanner(
        issue: '没有获得钥匙串授权，收藏暂时无法与 Bangumi 同步',
        actionLabel: '授权',
        onAction: widget.onUnlock,
      );
    }
    if (personal.credentialsUnsaved) {
      return IssueBanner(
        issue: '续期后的 Bangumi 登录没能保存到钥匙串，不保存的话下次打开需要重新登录',
        actionLabel: '保存',
        onAction: widget.onSaveCredentials,
      );
    }
    return IssueBanner(
      issue: personal.pullError == null
          ? null
          : '未能获取 Bangumi 上的最新收藏，先显示本地记录：${personal.pullError}',
      onAction: () => personal.pull(force: true),
    );
  }

  Widget _page(BuildContext context, Widget? _) {
    final personal = widget.personal;
    final collection = personal.collection;
    final text = search.text.toLowerCase();
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
    final played = {
      for (final (i, id) in widget.resume.played.keys.indexed) id: i,
    };
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
    final filtered = search.text.isNotEmpty || airingOnly || seasons.isNotEmpty;
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
        const SizedBox(height: Gap.lg),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 236,
              child: TextField(
                key: const PageStorageKey('collection-search'),
                controller: search,
                decoration: InputDecoration(
                  hintText: '搜索收藏',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () => updateFilters(search.clear),
                          icon: const Icon(Icons.close_rounded, size: 16),
                        ),
                ),
                onChanged: (_) => updateFilters(() {}),
              ),
            ),
            Tooltip(
              message: '7 天内有新一话放送',
              child: FilterChip(
                label: const Text('本周更新'),
                labelStyle: const TextStyle(fontSize: 13),
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
          ],
        ),
        const SizedBox(height: Gap.lg),
        _accountIssue(personal),
        if (collection.isEmpty && !filtered && !personal.signedIn)
          EmptyState(
            text: '还没有收藏的番剧',
            detail: '登录 Bangumi 后同步你在 Bangumi 上的收藏和观看进度',
            actionLabel: personal.accountBusy ? '登录中…' : '登录 Bangumi',
            action: personal.accountBusy ? null : widget.onAccountAction,
          )
        else if (items.isEmpty)
          EmptyState(
            text: collection.isEmpty
                ? '还没有收藏的番剧'
                : filtered
                ? '没有符合条件的番剧'
                : '还没有${collectionLabels[personal.filter]}的番剧',
            actionLabel: filtered ? '清除筛选' : '搜索番剧',
            action: filtered
                ? () => updateFilters(() {
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
              statusBadge: false,
              personalScore: order == _Order.personal,
            ),
          ),
      ],
    );
  }
}
