import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/bangumi_private.dart';
import '../../data/json.dart';
import '../core/account_avatar.dart';
import '../core/action_feedback.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import 'collection_labels.dart';

class SubjectCommunity extends StatefulWidget {
  const SubjectCommunity({
    super.key,
    required this.client,
    required this.subjectId,
    required this.onOpenSubject,
  });
  final BangumiPrivateClient client;
  final int subjectId;
  final ValueChanged<Json> onOpenSubject;

  @override
  State<SubjectCommunity> createState() => _SubjectCommunityState();
}

class _SubjectCommunityState extends State<SubjectCommunity> {
  String segment = 'comments';
  final _pages = <String, List<Json>>{};
  final _totals = <String, int>{};
  final _feedback = ActionFeedback();
  final _relationsFeedback = ActionFeedback();
  List<Json> _relations = [];
  late String _account = widget.client.account.userId;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadRelations());
  }

  @override
  void didUpdateWidget(SubjectCommunity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId ||
        _account != widget.client.account.userId) {
      _generation++;
      _account = widget.client.account.userId;
      _pages.clear();
      _totals.clear();
      _relations = [];
      unawaited(_load());
      unawaited(_loadRelations());
    }
  }

  @override
  void dispose() {
    _generation++;
    _feedback.dispose();
    _relationsFeedback.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    final requestedSegment = segment;
    final subjectId = widget.subjectId;
    final generation = _generation;
    await _feedback.run(() async {
      final offset = refresh ? 0 : _pages[requestedSegment]?.length ?? 0;
      final result = await widget.client.page(
        subjectId,
        requestedSegment,
        offset: offset,
        refresh: refresh,
      );
      if (!mounted || generation != _generation) return null;
      setState(() {
        _pages[requestedSegment] = [
          if (!refresh) ...?_pages[requestedSegment],
          ...objects(result['data']),
        ];
        _totals[requestedSegment] = number(result['total']).toInt();
      });
      return null;
    });
    if (mounted && generation != _generation) {
      unawaited(_load(refresh: true));
    } else if (mounted &&
        segment != requestedSegment &&
        !_pages.containsKey(segment)) {
      unawaited(_load());
    }
  }

  Future<void> _loadRelations({bool refresh = false}) async {
    final generation = _generation;
    final subjectId = widget.subjectId;
    await _relationsFeedback.run(() async {
      final values = await widget.client.relations(subjectId, refresh: refresh);
      if (mounted && generation == _generation) {
        setState(() => _relations = values);
      }
      return null;
    });
    if (mounted && generation != _generation) {
      unawaited(_loadRelations(refresh: true));
    }
  }

  Future<void> _open(String path) async {
    try {
      if (!await launchUrl(
        Uri.parse('https://bgm.tv$path'),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('无法打开链接');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开失败：$error')));
      }
    }
  }

  String _time(dynamic value) {
    final seconds = number(value).toInt();
    if (seconds <= 0) return '';
    final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  Widget _row(Json row) {
    final entry = segment == 'reviews' ? object(row['entry']) : row;
    final user = object(row[segment == 'topics' ? 'creator' : 'user']);
    final name = '${user['nickname'] ?? user['username'] ?? '未知用户'}';
    final meta = <String>[
      name,
      if (segment == 'comments' && number(row['rate']) > 0) '★ ${row['rate']}',
      if (segment == 'comments')
        collectionLabels[CollectionStatus.values
                .where((status) => status.remoteValue == number(row['type']))
                .firstOrNull
                ?.key] ??
            '',
      if (segment == 'topics') '${number(row['replyCount']).toInt()} 回复',
      if (segment == 'topics')
        '最后回复 ${_time(row['updatedAt'])}'
      else
        _time(entry['createdAt'] ?? entry['updatedAt']),
    ].where((value) => value.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountAvatar(
            url: coverAddress(object(user['avatar'])['medium']),
            name: name,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (segment != 'comments')
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: number(entry['id']) <= 0
                        ? null
                        : () => _open(
                            segment == 'reviews'
                                ? '/blog/${entry['id']}'
                                : '/subject/topic/${entry['id']}',
                          ),
                    child: Text('${entry['title'] ?? '无标题'}'),
                  ),
                Text(
                  meta.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (segment != 'topics') ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    '${segment == 'comments' ? row['comment'] ?? '' : entry['summary'] ?? ''}',
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _group(Json row) {
    final relation = '${row['relation']}';
    if (relation.contains('前传')) return '前传';
    if (relation.contains('续集')) return '续集';
    if (relation.contains('番外') || relation.contains('外传')) return '番外';
    if (relation.contains('总集')) return '总集篇';
    return '其他';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MelonPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: MelonSegmentedControl<String>(
                    options: const {
                      'comments': '吐槽',
                      'reviews': '评论',
                      'topics': '讨论',
                    },
                    value: segment,
                    onChanged: (value) {
                      setState(() => segment = value);
                      if (!_pages.containsKey(value)) unawaited(_load());
                    },
                  ),
                ),
                IconButton(
                  tooltip: '在 Bangumi 打开',
                  onPressed: () => _open('/subject/${widget.subjectId}'),
                  icon: const Icon(Icons.open_in_new, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FeedbackIssue(
              feedback: _feedback,
              onRetry: () => unawaited(_load(refresh: true)),
            ),
            ListenableBuilder(
              listenable: _feedback,
              builder: (context, _) {
                final rows = _pages[segment] ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _feedback.busy
                              ? '正在加载…'
                              : _feedback.issue == null
                              ? '这里还没有内容'
                              : '内容暂时无法读取',
                        ),
                      ),
                    for (final row in rows) _row(row),
                    if (rows.length < (_totals[segment] ?? 0))
                      Center(
                        child: TextButton(
                          onPressed: _feedback.busy
                              ? null
                              : () => unawaited(_load()),
                          child: Text(_feedback.busy ? '正在加载…' : '加载更多'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const SectionTitle(title: '关联作品', icon: Icons.movie_filter_outlined),
      FeedbackIssue(
        feedback: _relationsFeedback,
        onRetry: () => unawaited(_loadRelations(refresh: true)),
      ),
      ListenableBuilder(
        listenable: _relationsFeedback,
        builder: (context, _) => _relations.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(_relationsFeedback.busy ? '正在加载关联作品…' : '暂无关联作品'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in ['前传', '续集', '番外', '总集篇', '其他'])
                    if (_relations.any((row) => _group(row) == group)) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          group,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      HorizontalPosters(
                        storageId: 'relations:${widget.subjectId}:$group',
                        ranked: false,
                        itemCount: _relations
                            .where((row) => _group(row) == group)
                            .length,
                        itemBuilder: (index) {
                          final row = _relations
                              .where((row) => _group(row) == group)
                              .elementAt(index);
                          return SubjectPoster(
                            item: row,
                            onOpen: widget.onOpenSubject,
                            tracking: false,
                            badge: '${row['relation']}',
                          );
                        },
                      ),
                    ],
                ],
              ),
      ),
    ],
  );
}
