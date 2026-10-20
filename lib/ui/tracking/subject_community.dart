import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/json.dart' show coverAddress;
import '../../domain/catalog.dart';
import '../core/account_avatar.dart';
import '../core/action_feedback.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../../domain/collection_edit.dart';
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

  /// Keeps the posts' selectable text from sharing the page's saved scroll
  /// offset, which built each row scrolled away and springing back into view.
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
    unawaited(
      request(id)
          .then(
            (value) => AsyncSnapshot.withData(ConnectionState.done, value),
            onError: (Object error) =>
                AsyncSnapshot<T>.withError(ConnectionState.done, error),
          )
          .then((snapshot) {
            if (mounted && identical(cache[id], pending)) {
              setState(() => cache[id] = snapshot);
            }
          }),
    );
  }

  Widget _row(CommunityEntry entry) {
    final name = entry.author;
    final small = Theme.of(context).textTheme.bodySmall;
    final title = entry.title ?? '无标题';
    if (segment == 'topics') _fetch(_topics, entry.id, widget.client.topic);
    return Padding(
      // Expanded text belongs to its entry, not the list position.
      key: ValueKey('$segment:${entry.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountAvatar(url: entry.avatarUrl, name: name, size: 32),
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
                    onPressed: entry.id <= 0
                        ? null
                        : () => _open(
                            segment == 'reviews'
                                ? '/blog/${entry.id}'
                                : '/subject/topic/${entry.id}',
                          ),
                    child: Text(title),
                  ),
                _PostMeta(
                  name: name,
                  time: communityDate(entry.time),
                  details: [
                    if (segment == 'comments' && entry.score > 0)
                      _ScoreStars(entry.score),
                    if (segment == 'comments')
                      if (collectionLabels[entry.status] case final status?)
                        Text(status, style: small),
                    if (segment == 'topics')
                      Text('${entry.replies} 回复', style: small),
                  ],
                ),
                const SizedBox(height: 6),
                switch (segment) {
                  // Short comments stay whole; Bangumi caps them at 380.
                  'comments' => SelectableText(entry.text, style: _postText),
                  'reviews' => _Review(
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
                  _ => _TopicThread(
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
    await widget.onSaveComment(text);
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
                if (score > 0) ...[
                  _ScoreStars(score),
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
              if (score > 0) ...[const SizedBox(width: 8), _ScoreStars(score)],
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
                url: coverAddress(profile?.avatarUrl),
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
  final SubjectCommunitySource client;
  final int subjectId;
  final ValueChanged<Subject> onOpenSubject;

  @override
  State<SubjectRelations> createState() => _SubjectRelationsState();
}

class _SubjectRelationsState extends State<SubjectRelations> {
  static const _groups = ['前传', '续集', '番外', '总集篇', '其他'];
  final _feedback = ActionFeedback();
  List<Subject> _relations = [];
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

  String _group(Subject row) {
    final relation = '${row.relation}';
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
                          url: row.coverUrl,
                          title: row.title,
                          id: row.id,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              if (row.relation != _group(row)) ?row.relation,
                              ?row.platform,
                              ?row.season?.year,
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

const _postText = TextStyle(fontSize: 13, height: 1.6);

/// A post's date as YYYY-MM-DD, or empty without one.
String communityDate(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}

final _compactButton = TextButton.styleFrom(
  minimumSize: const Size(0, 28),
  padding: const EdgeInsets.symmetric(horizontal: 6),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// The author, details such as score or reply count, and the date flush
/// right.
class _PostMeta extends StatelessWidget {
  const _PostMeta({
    required this.name,
    required this.time,
    this.details = const [],
  });
  final String name, time;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final detail in details) ...[
                const SizedBox(width: Gap.sm),
                detail,
              ],
            ],
          ),
        ),
        const SizedBox(width: Gap.md),
        Text(
          time,
          style: small?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Scrolls back to [context] once a collapse or page change leaves its top
/// above the view.
void _reveal(BuildContext context) =>
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ),
      );
    });

/// Text cut to [maxLines] with 展开 / 收起 when it is longer; 展开 follows the
/// ellipsis on the last line. Plain text ends at the last punctuation in the
/// second half of the shown lines, or is cut where the lines end.
class _ClampedText extends StatefulWidget {
  _ClampedText.plain(
    String text, {
    required this.maxLines,
    this.truncated = false,
    this.onExpand,
  }) : span = TextSpan(text: text),
       punctuation = true;
  const _ClampedText.rich(this.span, {required this.maxLines})
    : punctuation = false,
      truncated = false,
      onExpand = null;
  final TextSpan span;
  final int maxLines;
  final bool punctuation;

  /// The text goes on past [span], so 展开 shows even when it fits.
  final bool truncated;

  /// Replaces expanding in place, for text read in full elsewhere.
  final VoidCallback? onExpand;

  @override
  State<_ClampedText> createState() => _ClampedTextState();
}

class _ClampedTextState extends State<_ClampedText>
    with AutomaticKeepAliveClientMixin {
  static const _breaks = '。，、；：！？…,.;:!?～~ ';
  static const _closers = '）)」』】》”’"';
  bool _expanded = false;
  late final _expand = TapGestureRecognizer()
    ..onTap = () => (widget.onExpand ?? _toggle)();

  @override
  bool get wantKeepAlive => _expanded;

  @override
  void dispose() {
    _expand.dispose();
    super.dispose();
  }

  /// How much of [text] to show before the ellipsis when the shown lines
  /// end at [end].
  int _cut(String text, int end) {
    // One character makes room for the ellipsis.
    final shown = text.substring(0, math.max(0, end - 1));
    if (widget.punctuation) {
      for (var i = shown.length - 1; i >= shown.length ~/ 2; i--) {
        if (_closers.contains(shown[i])) return i + 1;
        if (_breaks.contains(shown[i])) {
          return shown.substring(0, i).trimRight().length;
        }
      }
    }
    return shown.trimRight().length;
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    updateKeepAlive();
    if (!_expanded) _reveal(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = DefaultTextStyle.of(context).style.merge(_postText);
        final span = TextSpan(style: style, children: [widget.span]);
        TextPainter layout(InlineSpan text) => TextPainter(
          text: text,
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final painter = layout(span);
        final clamped = painter.didExceedMaxLines;
        if (!clamped && !widget.truncated || _expanded) {
          painter.dispose();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText.rich(span),
              if (_expanded)
                TextButton(
                  style: _compactButton,
                  onPressed: _toggle,
                  child: const Text('收起'),
                ),
            ],
          );
        }
        final link = TextSpan(
          text: '展开',
          style: style.copyWith(color: Theme.of(context).colorScheme.primary),
          recognizer: _expand,
        );
        TextSpan ending(TextSpan shown) => TextSpan(
          style: style,
          children: [
            shown,
            const TextSpan(text: '…'),
            link,
          ],
        );
        var text = ending(widget.span);
        final whole = layout(text);
        if (clamped || whole.didExceedMaxLines) {
          final label = layout(link);
          final end = painter
              .getPositionForOffset(
                Offset(constraints.maxWidth - label.width, painter.height - 1),
              )
              .offset;
          label.dispose();
          text = ending(_prefix(widget.span, _cut(span.toPlainText(), end)));
        }
        whole.dispose();
        painter.dispose();
        return Text.rich(text);
      },
    );
  }
}

/// The first [length] characters of [span], keeping their styles.
TextSpan _prefix(TextSpan span, int length) {
  var left = length;
  TextSpan take(TextSpan span) {
    final text = span.text ?? '';
    final shown = text.substring(0, math.min(left, text.length));
    left -= shown.length;
    return TextSpan(
      text: shown,
      style: span.style,
      children: [
        for (final child in span.children ?? const <InlineSpan>[])
          if (left > 0) take(child as TextSpan),
      ],
    );
  }

  return take(span);
}

/// A review's summary in three lines; 展开 reads the whole post, since the
/// listing holds only its first 120 characters.
class _Review extends StatefulWidget {
  const _Review({
    required this.summary,
    required this.content,
    required this.onLoad,
  });

  /// Bangumi BBCode, possibly cut inside a tag.
  final String summary;
  final AsyncSnapshot<String>? content;
  final void Function({bool retry}) onLoad;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> with AutomaticKeepAliveClientMixin {
  static const _summaryLimit = 120;
  bool _expanded = false;

  @override
  bool get wantKeepAlive => _expanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    updateKeepAlive();
    if (_expanded) {
      widget.onLoad();
    } else {
      _reveal(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final small = Theme.of(context).textTheme.bodySmall;
    final content = widget.content;
    if (_expanded && content != null && content.hasData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText.rich(
            bbcodeSpan(context, content.data!),
            style: _postText,
          ),
          TextButton(
            style: _compactButton,
            onPressed: _toggle,
            child: const Text('收起'),
          ),
        ],
      );
    }
    // A cut summary may end inside a tag; drop the unfinished tag.
    final summary = widget.summary.replaceFirst(RegExp(r'\[[^\]]*$'), '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ClampedText.plain(
          bbcodeSpan(context, summary).toPlainText(),
          maxLines: 3,
          truncated: widget.summary.runes.length >= _summaryLimit,
          onExpand: _toggle,
        ),
        if (_expanded && content != null && content.hasError)
          Row(
            children: [
              Text('全文加载失败', style: small),
              TextButton(
                style: _compactButton,
                onPressed: () => widget.onLoad(retry: true),
                child: const Text('重试'),
              ),
            ],
          )
        else if (_expanded)
          Text('正在加载全文…', style: small),
      ],
    );
  }
}

/// A topic's opening post; its replies sit in a box below, closed until
/// asked for and then shown ten floors a page.
class _TopicThread extends StatefulWidget {
  const _TopicThread({required this.posts, required this.onRetry});
  final AsyncSnapshot<List<TopicPost>> posts;
  final VoidCallback onRetry;

  @override
  State<_TopicThread> createState() => _TopicThreadState();
}

class _TopicThreadState extends State<_TopicThread>
    with AutomaticKeepAliveClientMixin {
  static const _perPage = 10;
  final _replies = GlobalKey();

  /// The reply page shown, or null while the replies are closed.
  int? _page;

  @override
  bool get wantKeepAlive => _page != null;

  void _show(int? page) {
    setState(() => _page = page);
    updateKeepAlive();
    if (_replies.currentContext case final context?) _reveal(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final snapshot = widget.posts;
    if (snapshot.hasError) {
      return Row(
        children: [
          Text('正文加载失败', style: small),
          TextButton(
            style: _compactButton,
            onPressed: widget.onRetry,
            child: const Text('重试'),
          ),
        ],
      );
    }
    final posts = snapshot.data;
    if (posts == null) return Text('正在加载正文…', style: small);
    final floors = posts.skip(1).toList();
    final count = floors.fold(0, (n, post) => n + 1 + post.replies.length);
    final pages = (floors.length / _perPage).ceil();
    final page = _page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (posts.firstOrNull case final first?)
          _ClampedText.rich(bbcodeSpan(context, first.content), maxLines: 4),
        if (floors.isNotEmpty)
          Container(
            key: _replies,
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: controlBorderRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: page == null
                ? InkWell(
                    onTap: () => _show(0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        '共 $count 条回复，点击查看',
                        style: small?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (index, post)
                            in floors
                                .skip(page * _perPage)
                                .take(_perPage)
                                .indexed)
                          _Floor(
                            key: ValueKey(post.id),
                            post: post,
                            floor: page * _perPage + index + 2,
                          ),
                        const SizedBox(height: 4),
                        _Pager(
                          page: page,
                          pages: pages,
                          onPage: _show,
                          onClose: () => _show(null),
                        ),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }
}

/// 共 N 页, the page numbers with the current one highlighted, 上一页 /
/// 下一页, and 收起.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pages,
    required this.onPage,
    required this.onClose,
  });
  final int page, pages;
  final ValueChanged<int> onPage;
  final VoidCallback onClose;

  /// Every page up to seven; beyond that the first, the last and those
  /// next to the current one, with null for the gaps.
  List<int?> get _numbers {
    if (pages <= 7) return List.generate(pages, (index) => index);
    final near = {
      0,
      page - 1,
      page,
      page + 1,
      pages - 1,
    }.where((index) => index >= 0 && index < pages).toList()..sort();
    return [
      for (final (index, number) in near.indexed) ...[
        if (index > 0 && number - near[index - 1] > 1) null,
        number,
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final square = _compactButton.copyWith(
      minimumSize: const WidgetStatePropertyAll(Size(28, 28)),
    );
    final quiet = square.copyWith(
      foregroundColor: WidgetStatePropertyAll(scheme.onSurfaceVariant),
    );
    Widget link(String label, VoidCallback onPressed) =>
        TextButton(style: quiet, onPressed: onPressed, child: Text(label));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (pages > 1) ...[
          Text('共 $pages 页', style: small),
          const SizedBox(width: Gap.sm),
          if (page > 0) link('上一页', () => onPage(page - 1)),
          for (final number in _numbers)
            if (number == null)
              Text(' … ', style: small)
            else if (number == page)
              TextButton(
                style: square,
                onPressed: null,
                child: Text(
                  '${number + 1}',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              link('${number + 1}', () => onPage(number)),
          if (page < pages - 1) link('下一页', () => onPage(page + 1)),
        ],
        link('收起', onClose),
      ],
    );
  }
}

/// One reply floor; its nested replies hang off a guide line, the first
/// three shown until expanded.
class _Floor extends StatefulWidget {
  const _Floor({super.key, required this.post, required this.floor});
  final TopicPost post;
  final int floor;

  @override
  State<_Floor> createState() => _FloorState();
}

class _FloorState extends State<_Floor> {
  static const _preview = 3;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final nested = widget.post.replies;
    final shown = _all ? nested : nested.take(_preview);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PostTile(post: widget.post, label: '#${widget.floor}', avatar: 24),
          if (nested.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 11),
              padding: const EdgeInsets.only(left: 19),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, reply) in shown.indexed)
                    _PostTile(
                      post: reply,
                      label: '#${widget.floor}-${index + 1}',
                      avatar: 20,
                    ),
                  if (nested.length > _preview)
                    TextButton(
                      style: _compactButton,
                      onPressed: () => setState(() => _all = !_all),
                      child: Text(
                        _all ? '收起楼中楼' : '还有 ${nested.length - _preview} 条楼中楼',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({
    required this.post,
    required this.label,
    required this.avatar,
  });
  final TopicPost post;
  final String label;
  final double avatar;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountAvatar(url: post.avatarUrl, name: post.author, size: avatar),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PostMeta(
                  name: post.author,
                  time: communityDate(post.time),
                  details: [Text(label, style: small)],
                ),
                const SizedBox(height: 2),
                if (post.content.trim().isEmpty)
                  Text('（内容已删除）', style: small)
                else
                  _ClampedText.rich(
                    bbcodeSpan(context, post.content),
                    maxLines: 6,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _bbcodeTags = RegExp(
  r'\[(/?)(b|i|u|s|url|img|mask|quote|color|size|font|code|align|left|right|center|sticker|user|subject)(?:=[^\]]*)?\]|\(bgm\d+\)',
  caseSensitive: false,
);

/// Bangumi BBCode as styled text: bold, italic, underline and strike keep
/// their look, spoilers stay blacked out, quotes are muted, images become
/// [图片], and other tags and stickers are dropped.
TextSpan bbcodeSpan(BuildContext context, String raw) {
  final scheme = Theme.of(context).colorScheme;
  final text = raw.replaceAll('\r\n', '\n').trim();
  final open = <String, int>{};
  final spans = <InlineSpan>[];
  bool on(String tag) => (open[tag] ?? 0) > 0;
  void add(String value) {
    if (value.isEmpty) return;
    spans.add(
      TextSpan(
        text: value,
        style: TextStyle(
          fontWeight: on('b') ? FontWeight.w700 : null,
          fontStyle: on('i') ? FontStyle.italic : null,
          decoration: TextDecoration.combine([
            if (on('u')) TextDecoration.underline,
            if (on('s')) TextDecoration.lineThrough,
          ]),
          color: on('mask')
              ? scheme.onSurface
              : on('quote')
              ? scheme.onSurfaceVariant
              : null,
          backgroundColor: on('mask') ? scheme.onSurface : null,
        ),
      ),
    );
  }

  var start = 0;
  var image = false;
  for (final match in _bbcodeTags.allMatches(text)) {
    if (!image) add(text.substring(start, match.start));
    start = match.end;
    final tag = match[2]?.toLowerCase();
    if (tag == null) continue;
    final closing = match[1] == '/';
    if (tag == 'img') {
      image = !closing;
      if (image) add('[图片]');
      continue;
    }
    open[tag] = math.max(0, (open[tag] ?? 0) + (closing ? -1 : 1));
  }
  if (!image) add(text.substring(start));
  return TextSpan(children: spans);
}

/// A 1–10 score as five stars in half steps, as Bangumi shows comments.
class _ScoreStars extends StatelessWidget {
  const _ScoreStars(this.score);
  final int score;

  @override
  Widget build(BuildContext context) {
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;
    const size = 14.0;
    return Tooltip(
      message: '$score 分 ${scoreLabels[score]}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            Stack(
              children: [
                Icon(Icons.star_rounded, size: size, color: empty),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: (score / 2 - star + 1).clamp(0.0, 1.0),
                    child: const Icon(
                      Icons.star_rounded,
                      size: size,
                      color: gold,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
