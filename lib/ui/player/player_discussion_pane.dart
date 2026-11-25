import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/error_message.dart';
import '../../domain/catalog.dart';
import '../../domain/community.dart';
import '../core/account_avatar.dart';
import '../core/bbcode.dart';
import '../core/external_link.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';
import '../tracking/community_posts.dart';

/// The episode's Bangumi comments, oldest first like the site.
class PlayerDiscussionPane extends StatefulWidget {
  const PlayerDiscussionPane({
    super.key,
    required this.community,
    required this.episode,
  });
  final SubjectCommunitySource community;
  final Episode? episode;

  @override
  State<PlayerDiscussionPane> createState() => _PlayerDiscussionPaneState();
}

class _PlayerDiscussionPaneState extends State<PlayerDiscussionPane> {
  List<TopicPost>? posts;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool refresh = false}) async {
    final episode = widget.episode;
    if (episode == null) return;
    if (refresh) {
      setState(() {
        error = null;
        posts = null;
      });
    }
    try {
      final result = await widget.community.episodeComments(
        episode.id,
        refresh: refresh,
      );
      if (mounted) setState(() => posts = result);
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final episode = widget.episode;
    if (episode == null) {
      return const EmptyState.compact(text: '这个视频没有对应的剧集');
    }
    final posts = this.posts;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              posts == null ? '本话吐槽' : '本话吐槽  ${posts.length} 条',
              style: small,
            ),
          ),
          TextButton.icon(
            onPressed: () =>
                openExternal(context, 'https://bgm.tv/ep/${episode.id}'),
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('在 Bangumi 打开'),
          ),
        ],
      ),
    );
    final Widget body;
    if (error case final error?) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        child: EmptyState.compact(
          text: '吐槽加载失败',
          detail: error,
          action: () => load(refresh: true),
        ),
      );
    } else if (posts == null) {
      body = const Center(child: BusyIndicator(size: 22));
    } else if (posts.isEmpty) {
      body = const EmptyState.compact(text: '这一话还没有吐槽');
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xl),
        itemCount: posts.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        itemBuilder: (_, index) =>
            _Comment(post: posts[index], floor: index + 1),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(child: body),
      ],
    );
  }
}

class _Comment extends StatefulWidget {
  const _Comment({required this.post, required this.floor});
  final TopicPost post;
  final int floor;

  @override
  State<_Comment> createState() => _CommentState();
}

class _CommentState extends State<_Comment> {
  static const _preview = 2;
  bool all = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final post = widget.post;
    final replies = post.replies;
    final shown = all ? replies : replies.take(_preview).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountAvatar(url: post.avatarUrl, name: post.author, size: 28),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _byline(context, post, '#${widget.floor}'),
                const SizedBox(height: 2),
                _text(context, post),
                if (replies.isNotEmpty) ...[
                  const SizedBox(height: Gap.sm),
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.md,
                      Gap.sm,
                      Gap.md,
                      Gap.sm,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: badgeBorderRadius,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, reply) in shown.indexed)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: Gap.xs,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _byline(
                                  context,
                                  reply,
                                  '#${widget.floor}-${index + 1}',
                                ),
                                const SizedBox(height: 2),
                                _text(context, reply),
                              ],
                            ),
                          ),
                        if (replies.length > _preview)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              // Its text lines up with the replies'.
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                              ).merge(compactTextButtonStyle),
                              onPressed: () => setState(() => all = !all),
                              child: Text(
                                all
                                    ? '收起回复'
                                    : '还有 ${replies.length - _preview} 条回复',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _byline(BuildContext context, TopicPost post, String floor) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Flexible(
          child: Text(
            post.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: Gap.sm),
        Text(floor, style: small),
        const Spacer(),
        Text(
          communityDate(post.time),
          style: small?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _text(BuildContext context, TopicPost post) =>
      post.content.trim().isEmpty
      ? Text('（内容已删除）', style: Theme.of(context).textTheme.bodySmall)
      : BBCode(
          post.content,
          style: const TextStyle(fontSize: FontSize.body, height: 1.55),
        );
}
