import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/action_feedback.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
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
    required this.feedback,
    required this.signedIn,
    required this.onSignIn,
    required this.onOpenSubject,
    this.onExplore,
  });
  final List<Json> collection;
  final String collectionFilter;
  final Json sync;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onSync, onSignIn;
  final ActionFeedback feedback;
  final bool signedIn;
  final ValueChanged<Json> onOpenSubject;
  final VoidCallback? onExplore;
  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  String query = '', quickFilter = '全部';
  bool sortByScore = false;
  final search = TextEditingController();
  bool restored = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (restored) return;
    restored = true;
    final saved = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: 'tracking-filters') as Json?;
    if (saved == null) return;
    query = saved['query'] as String;
    search.text = query;
    quickFilter = saved['quickFilter'] as String;
    sortByScore = saved['sortByScore'] as bool;
  }

  void updateFilters(VoidCallback update) {
    setState(update);
    PageStorage.maybeOf(context)?.writeState(context, {
      'query': query,
      'quickFilter': quickFilter,
      'sortByScore': sortByScore,
    }, identifier: 'tracking-filters');
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

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
        MelonSegmentedControl<String>(
          options: {
            for (final entry in collectionLabels.entries)
              entry.key:
                  '${entry.value} ${widget.collection.where((item) => item['status'] == entry.key).length}',
          },
          value: widget.collectionFilter,
          onChanged: widget.onFilterChanged,
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
                  hintText: '在追番列表中搜索…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (value) => updateFilters(() => query = value),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: MelonSegmentedControl<String>(
                options: const {'全部': '全部', '有进度': '有进度', '已评分': '已评分'},
                value: quickFilter,
                onChanged: (value) => updateFilters(() => quickFilter = value),
                semanticLabel: '追番筛选',
              ),
            ),
            MelonChoiceMenu<bool>(
              options: const {false: '默认顺序', true: '按我的评分'},
              value: sortByScore,
              onSelected: (value) => updateFilters(() => sortByScore = value),
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
          onRetry: widget.signedIn ? widget.onSync : widget.onSignIn,
          actionLabel: widget.signedIn ? '重试' : '去登录',
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
          EmptyState(
            text: widget.collection.isEmpty ? '还没有收藏的番剧' : '当前筛选下没有收藏条目',
            actionLabel: query.isNotEmpty || quickFilter != '全部'
                ? '清除筛选'
                : '搜索番剧',
            action: query.isNotEmpty || quickFilter != '全部'
                ? () => updateFilters(() {
                    query = '';
                    search.clear();
                    quickFilter = '全部';
                  })
                : widget.onExplore,
          )
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
