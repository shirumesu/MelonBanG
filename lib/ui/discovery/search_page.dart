import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../features/discovery/discovery_controller.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.discovery,
    required this.onOpenSubject,
  });
  final DiscoveryController discovery;
  final ValueChanged<Subject> onOpenSubject;

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
              title: '“${search.query}” 的搜索结果',
              subtitle: results.isEmpty && busy ? null : '${search.total} 部',
              icon: Icons.search,
              top: Gap.lg,
            ),
            if (results.isEmpty && busy)
              const PosterPlaceholders()
            else if (results.isEmpty && error != null)
              EmptyState(text: error, action: discovery.retrySearch)
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
