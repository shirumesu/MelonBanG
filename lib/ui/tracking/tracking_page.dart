import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'collection_labels.dart';

class TrackingPage extends StatefulWidget {
  const TrackingPage({
    super.key,
    required this.collection,
    required this.collectionFilter,
    required this.sync,
    required this.onFilterChanged,
    required this.onSync,
    required this.onOpenSubject,
  });
  final List<Json> collection;
  final String collectionFilter;
  final Json sync;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onSync;
  final ValueChanged<Json> onOpenSubject;
  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  String query = '', quickFilter = '全部';
  bool sortByScore = false;
  @override
  Widget build(BuildContext context) {
    final items = widget.collection
        .where(
          (item) =>
              item['status'] == widget.collectionFilter &&
              titleOf(item).toLowerCase().contains(query.toLowerCase()) &&
              (quickFilter != '有进度' || number(item['watchedEpisodes']) > 0) &&
              (quickFilter != '已评分' || number(item['userScore']) > 0),
        )
        .toList();
    if (sortByScore) {
      items.sort(
        (a, b) => number(b['userScore']).compareTo(number(a['userScore'])),
      );
    }
    return PageScroll(
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: surfaceColor(context),
              border: Border.all(color: lineColor(context)),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: collectionLabels.entries
                  .map(
                    (entry) => ChoiceChip(
                      label: Text(
                        '${entry.value} ${widget.collection.where((item) => item['status'] == entry.key).length}',
                      ),
                      selected: widget.collectionFilter == entry.key,
                      onSelected: (_) => widget.onFilterChanged(entry.key),
                    ),
                  )
                  .toList(),
            ),
          ),
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
                decoration: const InputDecoration(
                  hintText: '在追番列表中搜索…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
            ),
            for (final filter in ['全部', '有进度', '已评分'])
              ChoiceChip(
                label: Text(filter),
                selected: quickFilter == filter,
                onSelected: (_) => setState(() => quickFilter = filter),
              ),
            OutlinedButton.icon(
              onPressed: () => setState(() => sortByScore = !sortByScore),
              icon: const Icon(Icons.sort, size: 16),
              label: Text(sortByScore ? '按我的评分' : '默认顺序'),
            ),
            TextButton.icon(
              onPressed: widget.onSync,
              icon: const Icon(Icons.sync, size: 17),
              label: const Text('同步收藏'),
            ),
          ],
        ),
        if (number(widget.sync['pendingMutationCount']) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${widget.sync['pendingMutationCount']} 项修改等待同步',
              style: const TextStyle(color: gold, fontSize: 12),
            ),
          ),
        SectionTitle(title: '${items.length} 部收藏', color: mint),
        if (items.isEmpty)
          const EmptyState(text: '当前筛选下没有收藏条目')
        else
          SubjectPosters(
            onOpen: widget.onOpenSubject,
            items: items,
            tracking: true,
          ),
      ],
    );
  }
}
