import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/notices.dart';
import '../../domain/catalog.dart';
import '../../features/playback/resume_controller.dart';
import '../../features/tracking/tracking_controller.dart';
import '../core/action_feedback.dart';
import '../core/collection_labels.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/poster_zoom.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'collection_menu.dart';

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
    required this.zoom,
    required this.menu,
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
  final PosterZoom zoom;
  final CollectionMenu menu;

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
  late final listenable = Listenable.merge([
    widget.personal,
    widget.resume,
    widget.zoom,
  ]);

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
        actions: [NoticeAction('重新登录', widget.onAccountAction)],
      );
    }
    if (personal.needsAuthorization) {
      return IssueBanner(
        issue: '没有获得钥匙串授权，收藏暂时无法与 Bangumi 同步',
        actions: [NoticeAction('授权', widget.onUnlock)],
      );
    }
    if (personal.credentialsUnsaved) {
      return IssueBanner(
        issue: 'Bangumi 登录未保存到钥匙串，下次启动需重新登录',
        actions: [NoticeAction('保存', widget.onSaveCredentials)],
      );
    }
    return IssueBanner(
      issue: personal.pullError == null
          ? null
          : '无法获取 Bangumi 最新收藏，当前显示本地记录：${personal.pullError}',
      actions: [NoticeAction('重试', () => personal.pull(force: true))],
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
    // Until the saved collection is read, or while the first pull fills an
    // empty one, an empty grid is not yet known to be empty.
    final waiting =
        collection.isEmpty &&
        (!personal.loaded || (personal.signedIn && personal.syncing));
    return DelayedBusy(
      busy: waiting,
      builder: (context, skeleton) => _scroll(
        context,
        personal: personal,
        collection: collection,
        items: items,
        filtered: filtered,
        years: years,
        seasonCounts: seasonCounts,
        skeleton: skeleton,
        waiting: waiting,
      ),
    );
  }

  Widget _scroll(
    BuildContext context, {
    required TrackingController personal,
    required List<Subject> collection,
    required List<Subject> items,
    required bool filtered,
    required Map<String, List<String>> years,
    required Map<String, int> seasonCounts,
    required bool skeleton,
    required bool waiting,
  }) {
    return PosterZoomRegion(
      zoom: widget.zoom,
      child: _content(
        context,
        personal: personal,
        collection: collection,
        items: items,
        filtered: filtered,
        years: years,
        seasonCounts: seasonCounts,
        skeleton: skeleton,
        waiting: waiting,
      ),
    );
  }

  Widget _content(
    BuildContext context, {
    required TrackingController personal,
    required List<Subject> collection,
    required List<Subject> items,
    required bool filtered,
    required Map<String, List<String>> years,
    required Map<String, int> seasonCounts,
    required bool skeleton,
    required bool waiting,
  }) {
    return PageScroll(
      children: [
        const SizedBox(height: Gap.sm),
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
            // Unselected, the same fill as the filter menus beside it.
            FilterChip(
              label: const Text('7 天内更新'),
              selected: airingOnly,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHigh,
              onSelected: (value) => updateFilters(() => airingOnly = value),
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
            if (personal.signedIn)
              _SyncStatus(
                syncing: personal.syncing,
                syncedAt: personal.syncedAt,
                updated: personal.updated.length,
              ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        _accountIssue(personal),
        if (skeleton)
          PosterGridSkeleton(tracking: true, level: widget.zoom.level)
        else if (waiting)
          const SizedBox.shrink()
        else if (collection.isEmpty && !filtered && !personal.signedIn)
          EmptyState(
            text: '还没有收藏的番剧',
            detail: '登录后同步收藏和观看进度',
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
              onMenu: (item, position) =>
                  unawaited(widget.menu.show(context, item, position)),
              items: items,
              tracking: true,
              statusBadge: false,
              personalScore: order == _Order.personal,
              marked: personal.updated,
              markedAt: personal.syncedAt,
              zoom: widget.zoom,
            ),
          ),
      ],
    );
  }
}

/// The pull from Bangumi, quietly at the end of the filters: a turning
/// sync mark once it has run [busyDelay], then for a few seconds what it
/// changed. A quick pull that changed nothing says nothing.
class _SyncStatus extends StatefulWidget {
  const _SyncStatus({
    required this.syncing,
    required this.syncedAt,
    required this.updated,
  });
  final bool syncing;
  final DateTime? syncedAt;

  /// How many subjects the last pull changed.
  final int updated;

  @override
  State<_SyncStatus> createState() => _SyncStatusState();
}

class _SyncStatusState extends State<_SyncStatus>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  String? _result;
  Timer? _hide;

  /// Whether the turning mark showed for the running pull.
  bool _shown = false;

  @override
  void didUpdateWidget(_SyncStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    final finished = widget.syncedAt != oldWidget.syncedAt;
    if (!finished || widget.syncedAt == null) return;
    if (!_shown && widget.updated == 0) return;
    _hide?.cancel();
    _result = widget.updated == 0 ? '已同步' : '${widget.updated} 部有更新';
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _result = null);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _turn.dispose();
    super.dispose();
  }

  /// Turns while [spinning], then ends its turn so the mark comes to rest
  /// upright.
  void _spin(bool spinning) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    if (spinning) {
      if (!_turn.isAnimating) _turn.repeat();
    } else if (_turn.isAnimating) {
      _turn.forward().then((_) => _turn.value = 0);
    }
  }

  @override
  Widget build(BuildContext context) => DelayedBusy(
    busy: widget.syncing,
    builder: (context, spinning) {
      if (spinning) _shown = true;
      if (!widget.syncing && !spinning) _shown = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _spin(spinning);
      });
      final small = Theme.of(context).textTheme.bodySmall;
      final (IconData icon, String? label) = spinning
          ? (Icons.sync_rounded, '正在同步 Bangumi')
          : (Icons.check_rounded, _result);
      return Semantics(
        liveRegion: true,
        child: AnimatedOpacity(
          opacity: label == null ? 0 : 1,
          duration: motionDuration(context, 200),
          child: label == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(left: Gap.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RotationTransition(
                        turns: _turn,
                        child: Icon(
                          icon,
                          size: 14,
                          color: spinning
                              ? small?.color
                              : accentOf(context).accent,
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      Text(label, style: small),
                    ],
                  ),
                ),
        ),
      );
    },
  );
}
