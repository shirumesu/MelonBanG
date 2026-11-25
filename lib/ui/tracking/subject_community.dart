import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../core/error_message.dart';
import '../../core/json.dart' show coverAddress;
import '../../core/notices.dart';
import '../../domain/catalog.dart';
import '../../domain/collection_edit.dart';
import '../../domain/community.dart';
import '../core/account_avatar.dart';
import '../core/action_feedback.dart';
import '../core/collection_labels.dart';
import '../core/external_link.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'community_posts.dart';

class SubjectCommunity extends StatefulWidget {
  const SubjectCommunity({
    super.key,
    required this.client,
    required this.subjectId,
    required this.collection,
    required this.canWrite,
    required this.onSaveComment,
  });
  final SubjectCommunitySource client;
  final int subjectId;

  /// The signed-in user's collection, the source of the pinned own comment.
  final SubjectCollection? collection;
  final bool canWrite;
  final Future<void> Function(String comment) onSaveComment;

  @override
  State<SubjectCommunity> createState() => _SubjectCommunityState();
}

class _SubjectCommunityState extends State<SubjectCommunity> {
  String segment = 'comments';
  final _pages = <String, List<CommunityEntry>>{};
  final _totals = <String, int>{};

  /// Discussion topics and full reviews read so far, by id; kept as
  /// snapshots so rows rebuilt while scrolling show them at once.
  final _topics = <int, AsyncSnapshot<List<TopicPost>>>{};
  final _blogs = <int, AsyncSnapshot<String>>{};
  final _queuedReads = Queue<Future<void> Function()>();
  int _reads = 0;

  /// Keeps the posts' selectable text from sharing the page's saved scroll
  /// offset; sharing it builds each row scrolled away, springing back.
  final _storage = PageStorageBucket();
  final _feedback = ActionFeedback();
  final _commentFeedback = ActionFeedback();
  final _composer = TextEditingController();
  bool _editing = false, _confirmDelete = false;
  late String _account = widget.client.userId;
  int _generation = 0;
  bool _requested = false;

  @override
  void didUpdateWidget(SubjectCommunity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId ||
        _account != widget.client.userId) {
      _generation++;
      _account = widget.client.userId;
      _pages.clear();
      _totals.clear();
      _topics.clear();
      _blogs.clear();
      _queuedReads.clear();
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
        if (refresh && requestedSegment == 'topics') _topics.clear();
        _pages[requestedSegment] = [
          if (!refresh) ...?_pages[requestedSegment],
          ...result.entries,
        ];
        _totals[requestedSegment] = result.total;
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

  Future<void> _open(String path) =>
      openExternal(context, 'https://bgm.tv$path');

  /// Starts reading [id] unless it is already read or being read; [retry]
  /// reads it again.
  void _fetch<T>(
    Map<int, AsyncSnapshot<T>> cache,
    int id,
    Future<T> Function(int id) request, {
    bool retry = false,
  }) {
    if (!retry && cache.containsKey(id)) return;
    final pending = AsyncSnapshot<T>.waiting();
    cache[id] = pending;
    _queuedReads.add(() async {
      // A row of a replaced subject or segment no longer waits for it.
      if (!mounted || !identical(cache[id], pending)) return;
      final snapshot = await request(id).then(
        (value) => AsyncSnapshot.withData(ConnectionState.done, value),
        onError: (Object error) =>
            AsyncSnapshot<T>.withError(ConnectionState.done, error),
      );
      if (mounted && identical(cache[id], pending)) {
        setState(() => cache[id] = snapshot);
      }
    });
    _startReads();
  }

  /// Starts queued reads, in the order rows asked, while fewer than four
  /// run: a screen of topics would otherwise send a dozen at once.
  void _startReads() {
    while (_reads < 4 && _queuedReads.isNotEmpty) {
      _reads++;
      unawaited(
        _queuedReads.removeFirst()().whenComplete(() {
          _reads--;
          if (mounted) _startReads();
        }),
      );
    }
  }

  Widget _row(CommunityEntry entry) {
    final name = entry.author;
    final small = Theme.of(context).textTheme.bodySmall;
    final title = entry.title ?? '无标题';
    if (segment == 'topics') _fetch(_topics, entry.id, widget.client.topic);
    return Padding(
      // Expanded text belongs to its entry, not the list position.
      key: ValueKey('$segment:${entry.id}'),
      padding: const EdgeInsets.symmetric(vertical: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountAvatar(url: entry.avatarUrl, name: name, size: 32),
          const SizedBox(width: Gap.md),
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
                    onPressed: entry.id <= 0
                        ? null
                        : () => _open(
                            segment == 'reviews'
                                ? '/blog/${entry.id}'
                                : '/subject/topic/${entry.id}',
                          ),
                    // The post reads here; its title opens the thread on
                    // Bangumi, to reply or read it there.
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: title),
                          if (entry.id > 0)
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsets.only(left: Gap.xs),
                                child: Icon(
                                  Icons.open_in_new_rounded,
                                  size: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                PostMeta(
                  name: name,
                  time: communityDate(entry.time),
                  details: [
                    if (segment == 'comments' && entry.score > 0)
                      ScoreStars(entry.score),
                    if (segment == 'comments')
                      if (collectionLabels[entry.status] case final status?)
                        Text(status, style: small),
                    if (segment == 'topics')
                      Text('${entry.replies} 回复', style: small),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                switch (segment) {
                  // Short comments stay whole; Bangumi caps them at 380.
                  'comments' => SelectableText(
                    entry.text,
                    style: postTextStyle,
                  ),
                  'reviews' => ReviewPost(
                    summary: entry.text,
                    content: _blogs[entry.id],
                    onLoad: ({retry = false}) => setState(
                      () => _fetch(
                        _blogs,
                        entry.id,
                        widget.client.blog,
                        retry: retry,
                      ),
                    ),
                  ),
                  _ => TopicThread(
                    posts: _topics[entry.id]!,
                    onRetry: () => setState(
                      () => _fetch(
                        _topics,
                        entry.id,
                        widget.client.topic,
                        retry: true,
                      ),
                    ),
                  ),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _own(CommunityEntry entry) =>
      segment == 'comments' && entry.userId == widget.client.userId;

  Future<void> _saveComment(String text) => _commentFeedback.run(() async {
    try {
      await widget.onSaveComment(text);
    } catch (e) {
      return '吐槽保存失败：${errorMessage(e)}';
    }
    if (mounted) setState(() => _editing = _confirmDelete = false);
    return null;
  });

  /// The user's own 吐槽: an input when empty, otherwise pinned above others.
  Widget _mine(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final profile = widget.client.profile;
    final name = profile?.nickname ?? profile?.username ?? '我';
    final collection = widget.collection;
    final status = collection?.status;
    final score = collection?.score ?? 0;
    final comment = collection?.comment ?? '';
    final scoreStyle = small?.copyWith(color: scheme.onSurfaceVariant);
    final Widget body;
    if (status == null) {
      body = Padding(
        padding: const EdgeInsets.only(top: Gap.sm),
        child: Text('选择收藏状态后可写吐槽', style: small),
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
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Text('我的评分 ', style: small),
                if (score > 0) ...[
                  ScoreStars(score),
                  Text('  ${scoreLabels[score]}', style: scoreStyle),
                ] else
                  Text('未评分', style: small),
                const Spacer(),
                TextButton(
                  onPressed: _commentFeedback.busy
                      ? null
                      : () => setState(() => _editing = false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: Gap.sm),
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
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.sm,
            ),
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
              Text('我', style: small),
              if (score > 0) ...[
                const SizedBox(width: Gap.sm),
                ScoreStars(score),
              ],
              Text('  ${collectionLabels[status]!}', style: small),
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
            style: const TextStyle(fontSize: FontSize.body, height: 1.6),
          ),
          if (_confirmDelete) const SizedBox(height: Gap.sm),
          // A second press while deleting is ignored by _commentFeedback.
          IssueBanner(
            issue: _confirmDelete ? '删除这条吐槽？评分、标签和收藏状态都会保留。' : null,
            tone: NoticeTone.warning,
            actions: [
              NoticeAction('取消', () => setState(() => _confirmDelete = false)),
              NoticeAction('删除', () => unawaited(_saveComment(''))),
            ],
          ),
        ],
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
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
                url: coverAddress(profile?.avatarUrl),
                name: name,
                size: 32,
              ),
              const SizedBox(width: Gap.md),
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
  Widget build(BuildContext context) {
    // Built once per state change: the layout builder runs on every scroll
    // frame, and returning the same widget keeps the posts from rebuilding.
    final content = PageStorage(bucket: _storage, child: _content(context));
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        if (!_requested && constraints.remainingCacheExtent > 0) {
          _requested = true;
          final generation = _generation;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || generation != _generation) return;
            unawaited(_load());
          });
        }
        return content;
      },
    );
  }

  Widget _content(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      DecoratedSliver(
        decoration: BoxDecoration(
          color: CardTheme.of(context).color,
          borderRadius: panelBorderRadius,
          // Matches MelonPanel's lift; its dark-mode top-edge light needs a
          // foreground layer, which a sliver decoration can't draw.
          boxShadow: panelShadows(context),
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
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                          ),
                        ),
                        IconButton(
                          tooltip: '在 Bangumi 打开',
                          onPressed: () =>
                              _open('/subject/${widget.subjectId}'),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.lg),
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
                  final loaded = _pages[segment];
                  final rows = [...?loaded?.where((row) => !_own(row))];
                  return TweenAnimationBuilder<double>(
                    key: ValueKey(segment),
                    tween: Tween(begin: 0, end: 1),
                    duration: motionDuration(context, 240),
                    curve: Curves.easeOut,
                    builder: (context, value, sliver) =>
                        SliverOpacity(opacity: value, sliver: sliver),
                    child: SliverMainAxisGroup(
                      slivers: [
                        // A failure shows only in the banner above.
                        if (rows.isEmpty && _feedback.issue == null)
                          SliverToBoxAdapter(
                            child: loaded == null
                                ? _EntriesSkeleton(segment: segment)
                                : const EmptyState.compact(
                                    text: '这里还没有内容',
                                    center: false,
                                  ),
                          ),
                        SliverList.builder(
                          itemCount: rows.length,
                          itemBuilder: (_, index) => _row(rows[index]),
                        ),
                        if (loaded != null && loaded.length < _totals[segment]!)
                          SliverToBoxAdapter(
                            child: Center(
                              child: TextButton(
                                onPressed: _feedback.busy
                                    ? null
                                    : () => unawaited(_load()),
                                child: Text(_feedback.busy ? '加载中' : '加载更多'),
                              ),
                            ),
                          ),
                      ],
                    ),
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

/// [segment]'s entries in grey while its first page loads.
class _EntriesSkeleton extends StatelessWidget {
  const _EntriesSkeleton({required this.segment});
  final String segment;

  static const _labels = {
    'comments': '正在加载吐槽',
    'reviews': '正在加载评论',
    'topics': '正在加载讨论',
  };

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return DelayedBusy(
      busy: true,
      builder: (context, shown) => SkeletonGroup(
        label: _labels[segment]!,
        shown: shown,
        child: Column(
          children: [
            for (final share in const [.9, .6, .75])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonBlock(
                      width: 32,
                      height: 32,
                      radius: pillBorderRadius,
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonLine(style: small, width: 96),
                          const SizedBox(height: Gap.sm),
                          const SkeletonLine(style: postTextStyle),
                          SkeletonLine(
                            style: postTextStyle,
                            widthFactor: share,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
