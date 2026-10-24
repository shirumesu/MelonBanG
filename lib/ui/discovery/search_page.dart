import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../features/discovery/discovery_controller.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.discovery,
    required this.onOpenSubject,
    required this.onQuery,
  });
  final DiscoveryController discovery;
  final ValueChanged<Subject> onOpenSubject;

  /// A filter or the order changed.
  final ValueChanged<SubjectQuery> onQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  DiscoveryController get discovery => widget.discovery;
  SearchResults get search => discovery.search;

  bool loadMoreIfNeeded(ScrollMetrics metrics) {
    if (metrics.axis == Axis.vertical &&
        metrics.extentAfter < 480 &&
        search.hasMore &&
        !discovery.searching &&
        search.error == null &&
        search.items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) discovery.loadMore();
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: discovery, builder: _results);

  Widget _results(BuildContext context, Widget? _) {
    final results = search.items;
    final busy = discovery.searching;
    final error = search.error;
    final query = search.query;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => notification.depth == 0
          ? loadMoreIfNeeded(notification.metrics)
          : false,
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) => notification.depth == 0
            ? loadMoreIfNeeded(notification.metrics)
            : false,
        child: PageScroll(
          children: [
            SectionTitle(
              title: query.keyword.isNotEmpty
                  ? '“${query.keyword}” 的搜索结果'
                  : query.tag != null
                  ? '#${query.tag}'
                  : query.filtered
                  ? '筛选结果'
                  : '全部番剧',
              // Bangumi counts at most 1000 matches.
              subtitle: results.isEmpty && busy
                  ? null
                  : search.total >= 1000
                  ? '1000+ 部'
                  : '${search.total} 部',
              icon: query.keyword.isEmpty && query.tag != null
                  ? Icons.sell_outlined
                  : Icons.search,
              top: Gap.lg,
              trailing: MelonChoiceMenu<SubjectSort>(
                options: {
                  for (final sort in SubjectSort.values)
                    if (sort != SubjectSort.match || query.keyword.isNotEmpty)
                      sort: sort.label,
                },
                value: query.order,
                onSelected: (sort) =>
                    widget.onQuery(query.copyWith(sort: sort)),
                icon: Icons.sort,
                tooltip: '排序',
              ),
            ),
            _Filters(query: query, onQuery: widget.onQuery),
            const SizedBox(height: Gap.lg),
            if (results.isEmpty && busy)
              const PosterPlaceholders()
            else if (results.isEmpty && error != null)
              EmptyState(text: error, action: discovery.retrySearch)
            else if (results.isEmpty && query.filtered)
              EmptyState(
                text: '没有符合筛选的番剧',
                action: () => widget.onQuery(query.unfiltered),
                actionLabel: '清除筛选',
              )
            else if (results.isEmpty && query.keyword.isEmpty)
              const EmptyState(text: '没有带这个标签的番剧')
            else if (results.isEmpty)
              const EmptyState(text: '没有找到匹配的番剧，换个名称或别名试试')
            else
              PageSliver(
                child: SubjectPosterGrid(
                  onOpen: widget.onOpenSubject,
                  items: results,
                ),
              ),
            if (results.isNotEmpty && error != null)
              EmptyState(
                text: error,
                action: busy ? null : discovery.retrySearch,
              )
            else if (results.isNotEmpty && search.hasMore)
              Padding(
                padding: const EdgeInsets.only(top: Gap.xl),
                child: Center(
                  child: MotionSwap(
                    value: busy,
                    child: busy
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        // Short result lists do not scroll, so loading stays reachable.
                        : TextButton.icon(
                            onPressed: discovery.loadMore,
                            icon: const Icon(Icons.expand_more, size: 18),
                            label: const Text('加载更多'),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bangumi's public tags and air time narrowing the results; each menu
/// picks one value, genres combine.
class _Filters extends StatelessWidget {
  const _Filters({required this.query, required this.onQuery});
  final SubjectQuery query;
  final ValueChanged<SubjectQuery> onQuery;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().year;
    final year = query.year;
    final time = year == null
        ? null
        : query.before
        ? '<$year'
        : query.month == null
        ? '$year'
        : '$year-${query.month}';
    Widget single(
      String label,
      List<String> values,
      String? value,
      SubjectQuery Function(String?) change,
    ) => MelonFilterMenu<String>(
      label: label,
      multiple: false,
      summary: value,
      sections: [
        MelonFilterSection([for (final v in values) MelonFilterOption(v, v)]),
      ],
      selected: {?value},
      onToggle: (v, on) => onQuery(change(on ? v : null)),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        single(
          '分类',
          SubjectQuery.kinds,
          query.kind,
          (v) => query.copyWith(kind: v),
        ),
        single(
          '来源',
          SubjectQuery.sources,
          query.source,
          (v) => query.copyWith(source: v),
        ),
        single(
          '地区',
          SubjectQuery.regions,
          query.region,
          (v) => query.copyWith(region: v),
        ),
        MelonFilterMenu<String>(
          label: '类型',
          columns: 4,
          summary: query.genres.length == 1
              ? query.genres.single
              : '${query.genres.length} 项',
          tooltip: '同时符合所选类型',
          sections: [
            MelonFilterSection([
              for (final genre in SubjectQuery.genreTags)
                MelonFilterOption(genre, genre),
            ]),
          ],
          selected: query.genres,
          onToggle: (genre, on) => onQuery(
            query.copyWith(
              genres: on
                  ? {...query.genres, genre}
                  : ({...query.genres}..remove(genre)),
            ),
          ),
          actions: [
            if (query.genres.isNotEmpty)
              ('清除', () => onQuery(query.copyWith(genres: {}))),
          ],
        ),
        MelonFilterMenu<String>(
          label: '时间',
          multiple: false,
          columns: 4,
          summary: query.before
              ? '更早'
              : '$year年${query.month == null ? '' : '${query.month}月'}',
          tooltip: '按放送时间筛选',
          sections: [
            MelonFilterSection([
              for (var y = now + 1; y > now - 10; y--)
                MelonFilterOption(
                  '$y',
                  '$y年',
                  more: [
                    for (final month in const [1, 4, 7, 10])
                      MelonFilterOption('$y-$month', '$month月'),
                  ],
                ),
              MelonFilterOption('<${now - 9}', '更早'),
            ]),
          ],
          selected: {?time},
          onToggle: (value, on) {
            final [y, ...month] = value.replaceFirst('<', '').split('-');
            onQuery(
              query.copyWith(
                year: on ? int.parse(y) : null,
                month: on && month.isNotEmpty ? int.parse(month.single) : null,
                before: on && value.startsWith('<'),
              ),
            );
          },
        ),
        if (query.filtered)
          TextButton(
            onPressed: () => onQuery(query.unfiltered),
            child: const Text('清除筛选'),
          ),
      ],
    );
  }
}
