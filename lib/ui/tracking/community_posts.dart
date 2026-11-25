import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../domain/community.dart';
import '../core/account_avatar.dart';
import '../core/action_feedback.dart';
import '../core/bbcode.dart';
import '../core/collection_labels.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

const postTextStyle = TextStyle(fontSize: FontSize.body, height: 1.6);

/// A post's date as YYYY-MM-DD, or empty without one.
String communityDate(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
      .toIso8601String()
      .substring(0, 10);
}

/// A post's author line: the name, [details] and the date flush right.
class PostMeta extends StatelessWidget {
  const PostMeta({
    super.key,
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

/// A post in Bangumi BBCode shown to [maxLines] lines of text, with 展开 /
/// 收起 below when it is longer; stickers, pictures and quotes count by the
/// room they take.
class _ClampedPost extends StatefulWidget {
  const _ClampedPost(
    this.source, {
    required this.maxLines,
    this.truncated = false,
    this.onExpand,
  });
  final String source;
  final int maxLines;

  /// The post goes on past [source], so 展开 shows even when it fits.
  final bool truncated;

  /// Replaces expanding in place, for posts read in full elsewhere.
  final VoidCallback? onExpand;

  @override
  State<_ClampedPost> createState() => _ClampedPostState();
}

class _ClampedPostState extends State<_ClampedPost>
    with AutomaticKeepAliveClientMixin {
  bool _expanded = false, _overflows = false;

  @override
  bool get wantKeepAlive => _expanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    updateKeepAlive();
    if (!_expanded) _reveal(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedSize(
      duration: motionDuration(context, 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: _post(context),
    );
  }

  Widget _post(BuildContext context) {
    final post = BBCode(widget.source, style: postTextStyle);
    if (_expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          post,
          TextButton(
            style: compactTextButtonStyle,
            onPressed: _toggle,
            child: const Text('收起'),
          ),
        ],
      );
    }
    final line = MediaQuery.textScalerOf(context)
        .scale(postTextStyle.fontSize! * postTextStyle.height!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeightClamp(
          maxHeight: line * widget.maxLines,
          onOverflow: (value) {
            if (mounted && value != _overflows) {
              setState(() => _overflows = value);
            }
          },
          child: post,
        ),
        if (_overflows || widget.truncated)
          TextButton(
            style: compactTextButtonStyle,
            onPressed: widget.onExpand ?? _toggle,
            child: const Text('展开'),
          ),
      ],
    );
  }
}

/// Shows at most [maxHeight] of its child and reports whether the rest was
/// cut off.
class _HeightClamp extends SingleChildRenderObjectWidget {
  const _HeightClamp({
    required this.maxHeight,
    required this.onOverflow,
    super.child,
  });
  final double maxHeight;
  final ValueChanged<bool> onOverflow;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightClamp(maxHeight, onOverflow);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightClamp renderObject,
  ) {
    renderObject
      ..maxHeight = maxHeight
      ..onOverflow = onOverflow;
  }
}

class _RenderHeightClamp extends RenderProxyBox {
  _RenderHeightClamp(this._maxHeight, this.onOverflow);
  double _maxHeight;
  ValueChanged<bool> onOverflow;
  bool? _reported;

  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity),
      parentUsesSize: true,
    );
    final overflows = child.size.height > _maxHeight + .5;
    size = constraints.constrain(
      Size(child.size.width, math.min(child.size.height, _maxHeight)),
    );
    if (overflows != _reported) {
      _reported = overflows;
      final report = onOverflow;
      WidgetsBinding.instance.addPostFrameCallback((_) => report(overflows));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_reported != true) return super.paint(context, offset);
    layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      oldLayer: layer as ClipRectLayer?,
    );
  }
}

/// A review's summary in three lines; 展开 reads the whole post, since the
/// listing holds only its first 120 characters.
class ReviewPost extends StatefulWidget {
  const ReviewPost({
    super.key,
    required this.summary,
    required this.content,
    required this.onLoad,
  });

  /// Bangumi BBCode, possibly cut inside a tag.
  final String summary;
  final AsyncSnapshot<String>? content;
  final void Function({bool retry}) onLoad;

  @override
  State<ReviewPost> createState() => _ReviewPostState();
}

class _ReviewPostState extends State<ReviewPost>
    with AutomaticKeepAliveClientMixin {
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
    return AnimatedSize(
      duration: motionDuration(context, 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final content = widget.content;
    if (_expanded && content != null && content.hasData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BBCode(content.data!, style: postTextStyle),
          TextButton(
            style: compactTextButtonStyle,
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
        _ClampedPost(
          summary,
          maxLines: 3,
          truncated: widget.summary.runes.length >= _summaryLimit,
          onExpand: _toggle,
        ),
        if (_expanded && content != null && content.hasError)
          InlineIssue('全文加载失败', onRetry: () => widget.onLoad(retry: true))
        else if (_expanded)
          const _PostSkeleton(label: '正在加载全文', lines: 2),
      ],
    );
  }
}

/// A post's lines in grey while it loads, after [busyDelay].
class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton({required this.label, required this.lines});
  final String label;
  final int lines;

  @override
  Widget build(BuildContext context) => DelayedBusy(
    busy: true,
    builder: (context, shown) => SkeletonGroup(
      label: label,
      shown: shown,
      child: Column(
        children: [
          for (var i = 0; i < lines; i++)
            SkeletonLine(
              style: postTextStyle,
              widthFactor: i == lines - 1 ? .6 : 1,
            ),
        ],
      ),
    ),
  );
}

/// A topic's opening post; its replies sit in a box below, closed until
/// asked for and then shown ten floors a page.
class TopicThread extends StatefulWidget {
  const TopicThread({super.key, required this.posts, required this.onRetry});
  final AsyncSnapshot<List<TopicPost>> posts;
  final VoidCallback onRetry;

  @override
  State<TopicThread> createState() => _TopicThreadState();
}

class _TopicThreadState extends State<TopicThread>
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
      return InlineIssue('正文加载失败', onRetry: widget.onRetry);
    }
    final posts = snapshot.data;
    if (posts == null) {
      return const _PostSkeleton(label: '正在加载正文', lines: 3);
    }
    final floors = posts.skip(1).toList();
    final count = floors.fold(0, (n, post) => n + 1 + post.replies.length);
    final pages = (floors.length / _perPage).ceil();
    final page = _page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (posts.firstOrNull case final first?)
          _ClampedPost(first.content, maxLines: 4),
        if (floors.isNotEmpty)
          Container(
            key: _replies,
            width: double.infinity,
            margin: const EdgeInsets.only(top: Gap.sm),
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
                        horizontal: Gap.md,
                        vertical: Gap.sm,
                      ),
                      child: Text(
                        '查看 $count 条回复',
                        style: small?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.md,
                      Gap.xs,
                      Gap.md,
                      Gap.xs,
                    ),
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
                        const SizedBox(height: Gap.xs),
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
    final square = compactTextButtonStyle.copyWith(
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

/// One reply floor; its first three nested replies show until expanded.
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
      padding: const EdgeInsets.only(top: Gap.sm),
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
                      style: compactTextButtonStyle,
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
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountAvatar(url: post.avatarUrl, name: post.author, size: avatar),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PostMeta(
                  name: post.author,
                  time: communityDate(post.time),
                  details: [Text(label, style: small)],
                ),
                const SizedBox(height: 2),
                if (post.content.trim().isEmpty)
                  Text('（内容已删除）', style: small)
                else
                  _ClampedPost(post.content, maxLines: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A 1–10 score as five stars in half steps, as Bangumi shows comments.
class ScoreStars extends StatelessWidget {
  const ScoreStars(this.score, {super.key});
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
