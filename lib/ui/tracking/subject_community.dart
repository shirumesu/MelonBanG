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
import '../../data/collection_edit.dart';
import '../core/theme.dart';
import 'collection_labels.dart';

class SubjectCommunity extends StatefulWidget {
  const SubjectCommunity({
    super.key,
    required this.client,
    required this.subjectId,
    required this.collection,
    required this.canWrite,
    required this.onSaveComment,
  });
  final BangumiPrivateClient client;
  final int subjectId;

  /// The signed-in user's collection, the source of the pinned own comment.
  final Json collection;
  final bool canWrite;
  final Future<void> Function(String comment) onSaveComment;

  @override
  State<SubjectCommunity> createState() => _SubjectCommunityState();
}

class _SubjectCommunityState extends State<SubjectCommunity> {
  String segment = 'comments';
  final _pages = <String, List<Json>>{};
  final _totals = <String, int>{};
  final _feedback = ActionFeedback();
  final _commentFeedback = ActionFeedback();
  final _composer = TextEditingController();
  bool _editing = false, _confirmDelete = false;
  late String _account = widget.client.account.userId;
  int _generation = 0;
  bool _requested = false;

  @override
  void didUpdateWidget(SubjectCommunity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId ||
        _account != widget.client.account.userId) {
      _generation++;
      _account = widget.client.account.userId;
      _pages.clear();
      _totals.clear();
      _requested = false;
      _editing = _confirmDelete = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    _feedback.dispose();
    _commentFeedback.dispose();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (!_requested) return;
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

  bool _own(Json row) =>
      segment == 'comments' &&
      '${object(row['user'])['id']}' == widget.client.account.userId;

  Future<void> _saveComment(String text) => _commentFeedback.run(() async {
    await widget.onSaveComment(text);
    if (mounted) setState(() => _editing = _confirmDelete = false);
    return null;
  });

  /// The user's own 吐槽: an input when empty, otherwise pinned above others.
  Widget _mine(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final session = object(widget.client.account.session);
    final name = '${session['nickname'] ?? session['username'] ?? '我'}';
    final status = widget.collection['status'] as String?;
    final score = number(widget.collection['score']).toInt();
    final comment = '${widget.collection['comment'] ?? ''}';
    final scoreStyle = small?.copyWith(
      color: Color.lerp(gold, Colors.black, .35),
      fontWeight: FontWeight.w700,
    );
    final Widget body;
    if (status == null) {
      body = Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Text('先在页面顶部选择收藏状态，才能写吐槽。', style: small),
      );
    } else if (_editing) {
      final length = _composer.text.runes.length;
      body = ListenableBuilder(
        listenable: _commentFeedback,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _composer,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '写一句吐槽…',
                counterText: '$length/$collectionCommentLimit',
                errorText: length > collectionCommentLimit ? '吐槽超过字数上限' : null,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('我的评分 ', style: small),
                Text(
                  score > 0 ? '★ $score ${scoreLabels[score]}' : '未评分',
                  style: score > 0 ? scoreStyle : small,
                ),
                const Spacer(),
                TextButton(
                  onPressed: _commentFeedback.busy
                      ? null
                      : () => setState(() => _editing = false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed:
                      _commentFeedback.busy ||
                          _composer.text.trim().isEmpty ||
                          length > collectionCommentLimit ||
                          _composer.text == comment
                      ? null
                      : () => unawaited(_saveComment(_composer.text)),
                  child: Text(comment.isEmpty ? '发布' : '保存'),
                ),
              ],
            ),
          ],
        ),
      );
    } else if (comment.isEmpty) {
      body = Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: controlBorderRadius,
        child: InkWell(
          borderRadius: controlBorderRadius,
          onTap: () => setState(() {
            _composer.text = '';
            _editing = true;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: [Text('写一句吐槽…', style: small)]),
          ),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('我', style: small?.copyWith(fontWeight: FontWeight.w700)),
              if (score > 0) Text('  ★ $score', style: scoreStyle),
              Text('  ${collectionLabels[status] ?? ''}', style: small),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  _composer.text = comment;
                  _editing = true;
                  _confirmDelete = false;
                }),
                child: const Text('编辑'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: () => setState(() => _confirmDelete = true),
                child: const Text('删除'),
              ),
            ],
          ),
          SelectableText(
            comment,
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
          if (_confirmDelete)
            ListenableBuilder(
              listenable: _commentFeedback,
              builder: (context, _) => Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: .5),
                  borderRadius: controlBorderRadius,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '删除这条吐槽？评分、标签和收藏状态都会保留。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _confirmDelete = false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                      onPressed: _commentFeedback.busy
                          ? null
                          : () => unawaited(_saveComment('')),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: controlBorderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountAvatar(
                url: coverAddress(session['avatarUrl']),
                name: name,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(child: body),
            ],
          ),
          FeedbackIssue(
            feedback: _commentFeedback,
            onRetry: () =>
                unawaited(_saveComment(_editing ? _composer.text : '')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      if (!_requested && constraints.remainingCacheExtent > 0) {
        _requested = true;
        final generation = _generation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _generation) return;
          unawaited(_load());
        });
      }
      return _content(context);
    },
  );

  Widget _content(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      DecoratedSliver(
        decoration: BoxDecoration(
          color: CardTheme.of(context).color ?? Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        sliver: SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
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
                              if (!_pages.containsKey(value)) {
                                unawaited(_load());
                              }
                            },
                          ),
                        ),
                        ListenableBuilder(
                          listenable: _feedback,
                          builder: (context, _) => IconButton(
                            tooltip: '刷新社区',
                            onPressed: _feedback.busy
                                ? null
                                : () => unawaited(_load(refresh: true)),
                            icon: const Icon(Icons.refresh, size: 18),
                          ),
                        ),
                        IconButton(
                          tooltip: '在 Bangumi 打开',
                          onPressed: () =>
                              _open('/subject/${widget.subjectId}'),
                          icon: const Icon(Icons.open_in_new, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FeedbackIssue(
                      feedback: _feedback,
                      onRetry: () => unawaited(_load(refresh: true)),
                    ),
                    if (segment == 'comments' && widget.canWrite)
                      _mine(context),
                  ],
                ),
              ),
              ListenableBuilder(
                listenable: _feedback,
                builder: (context, _) {
                  final rows = (_pages[segment] ?? [])
                      .where((row) => !_own(row))
                      .toList();
                  return SliverMainAxisGroup(
                    slivers: [
                      if (rows.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _feedback.busy
                                  ? '正在加载…'
                                  : _feedback.issue == null
                                  ? '这里还没有内容'
                                  : '内容暂时无法读取',
                            ),
                          ),
                        ),
                      SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (_, index) => _row(rows[index]),
                      ),
                      if ((_pages[segment]?.length ?? 0) <
                          (_totals[segment] ?? 0))
                        SliverToBoxAdapter(
                          child: Center(
                            child: TextButton(
                              onPressed: _feedback.busy
                                  ? null
                                  : () => unawaited(_load()),
                              child: Text(_feedback.busy ? '正在加载…' : '加载更多'),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Related subjects grouped by relation, as a compact list.
class SubjectRelations extends StatefulWidget {
  const SubjectRelations({
    super.key,
    required this.client,
    required this.subjectId,
    required this.onOpenSubject,
  });
  final BangumiPrivateClient client;
  final int subjectId;
  final ValueChanged<Json> onOpenSubject;

  @override
  State<SubjectRelations> createState() => _SubjectRelationsState();
}

class _SubjectRelationsState extends State<SubjectRelations> {
  static const _groups = ['前传', '续集', '番外', '总集篇', '其他'];
  final _feedback = ActionFeedback();
  List<Json> _relations = [];
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) => _feedback.run(() async {
    final values = await widget.client.relations(
      widget.subjectId,
      refresh: refresh,
    );
    if (mounted) setState(() => _relations = values);
    return null;
  });

  String _group(Json row) {
    final relation = '${row['relation']}';
    if (relation.contains('前传')) return '前传';
    if (relation.contains('续集')) return '续集';
    if (relation.contains('番外') || relation.contains('外传')) return '番外';
    if (relation.contains('总集')) return '总集篇';
    return '其他';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ordered = [
      for (final group in _groups)
        ..._relations.where((row) => _group(row) == group),
    ];
    final shown = _expanded ? ordered : ordered.take(6).toList();
    return MelonPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('关联作品', style: text.titleMedium),
          const SizedBox(height: 4),
          FeedbackIssue(
            feedback: _feedback,
            onRetry: () => unawaited(_load(refresh: true)),
          ),
          ListenableBuilder(
            listenable: _feedback,
            builder: (context, _) => _relations.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _feedback.busy ? '正在加载关联作品…' : '暂无关联作品',
                      style: text.bodySmall,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          for (final (index, row) in shown.indexed) ...[
            if (index == 0 || _group(shown[index - 1]) != _group(row))
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(
                  _group(row),
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            InkWell(
              borderRadius: controlBorderRadius,
              onTap: () => widget.onOpenSubject(row),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 54,
                      child: ClipRRect(
                        borderRadius: badgeBorderRadius,
                        child: SubjectCover(
                          url: row['coverUrl'],
                          title: titleOf(row),
                          id: number(row['subjectId']).toInt(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleOf(row),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              '${row['relation']}',
                              '${row['platform']}',
                              ?object(row['season'])['year'],
                            ].join(' · '),
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (ordered.length > 6)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起' : '全部 ${ordered.length} 部'),
            ),
        ],
      ),
    );
  }
}
