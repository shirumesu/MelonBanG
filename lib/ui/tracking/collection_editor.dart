import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/notices.dart';
import '../../domain/catalog.dart';
import '../../domain/collection_edit.dart';
import '../core/action_feedback.dart';
import '../core/collection_labels.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/subject_cover.dart';
import '../core/theme.dart';
import 'collection_controls.dart';

/// An unsaved drawer edit.
class CollectionDraft {
  const CollectionDraft(this.collection, {this.completeEpisodes = false});
  final SubjectCollection collection;
  final bool completeEpisodes;
}

/// Unsaved drawer edits, kept per account and subject for this app run.
abstract final class CollectionDrafts {
  static final _values = <String, CollectionDraft>{};
  static String key(String user, int? subjectId) => '$user:$subjectId';
  static CollectionDraft? read(String key) => _values[key];
  static bool has(String key) => _values.containsKey(key);
  static void write(String key, CollectionDraft value) => _values[key] = value;
  static void clear(String key) => _values.remove(key);
}

/// Opens the right-side editor. Returns the changed fields, or null when the
/// drawer was closed; closing keeps any difference as a draft.
Future<CollectionChange?> showCollectionDrawer(
  BuildContext context, {
  required Subject subject,
  required String draftKey,
  bool focusComment = false,
}) => showGeneralDialog<CollectionChange>(
  context: context,
  barrierDismissible: true,
  barrierLabel: '关闭编辑收藏',
  barrierColor: Colors.black.withValues(alpha: .18),
  transitionDuration: motionDuration(context, 220),
  pageBuilder: (_, _, _) => Align(
    alignment: Alignment.centerRight,
    child: _CollectionDrawer(
      subject: subject,
      draftKey: draftKey,
      focusComment: focusComment,
    ),
  ),
  transitionBuilder: (_, animation, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  ),
);

class _CollectionDrawer extends StatefulWidget {
  const _CollectionDrawer({
    required this.subject,
    required this.draftKey,
    this.focusComment = false,
  });
  final Subject subject;
  final String draftKey;
  final bool focusComment;

  @override
  State<_CollectionDrawer> createState() => _CollectionDrawerState();
}

class _CollectionDrawerState extends State<_CollectionDrawer> {
  late final SubjectCollection saved =
      widget.subject.collection ?? const SubjectCollection();
  late final bool restored = CollectionDrafts.has(widget.draftKey);
  late CollectionDraft draft =
      CollectionDrafts.read(widget.draftKey) ?? CollectionDraft(saved);
  late final comment = TextEditingController(text: draft.collection.comment);
  final tagInput = TextEditingController();
  String? tagError;

  CollectionStatus? get status => draft.collection.status;
  int get score => draft.collection.score;
  List<String> get tags => draft.collection.tags;

  // A score set before switching to 想看 is not saved, so it is no change.
  bool get changed =>
      status != saved.status ||
      (status != CollectionStatus.wish && score != saved.score) ||
      !listEquals(tags, saved.tags) ||
      draft.collection.comment != saved.comment ||
      draft.completeEpisodes;

  @override
  void dispose() {
    comment.dispose();
    tagInput.dispose();
    super.dispose();
  }

  void _update({
    CollectionStatus? status,
    int? score,
    List<String>? tags,
    String? comment,
    bool? completeEpisodes,
  }) {
    final current = draft.collection;
    setState(
      () => draft = CollectionDraft(
        SubjectCollection(
          status: status ?? current.status,
          score: score ?? current.score,
          tags: tags ?? current.tags,
          comment: comment ?? current.comment,
        ),
        completeEpisodes: completeEpisodes ?? draft.completeEpisodes,
      ),
    );
    if (changed) {
      CollectionDrafts.write(widget.draftKey, draft);
    } else {
      CollectionDrafts.clear(widget.draftKey);
    }
  }

  void _discard() {
    CollectionDrafts.clear(widget.draftKey);
    Navigator.pop(context);
  }

  bool _addTags(String text) {
    try {
      final updated = normalizeCollectionTags([
        ...tags,
        ...splitCollectionTags(text),
      ]);
      setState(() => tagError = null);
      tagInput.clear();
      _update(tags: updated);
      return true;
    } on FormatException catch (error) {
      setState(() => tagError = error.message);
      return false;
    }
  }

  void _toggleTag(String tag) {
    if (tags.contains(tag)) {
      _update(tags: [...tags]..remove(tag));
    } else {
      _addTags(tag);
    }
  }

  bool get _canSave =>
      status != null &&
      changed &&
      comment.text.runes.length <= collectionCommentLimit;

  void _save() {
    if (!_canSave) return;
    if (tagInput.text.trim().isNotEmpty && !_addTags(tagInput.text)) return;
    final value = draft.collection;
    Navigator.pop(
      context,
      CollectionChange(
        status: status != saved.status ? status : null,
        score: score != saved.score && status != CollectionStatus.wish
            ? score
            : null,
        tags: listEquals(tags, saved.tags) ? null : tags,
        comment: value.comment != saved.comment ? value.comment : null,
        completeEpisodes:
            status == CollectionStatus.completed && draft.completeEpisodes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tooLong = comment.text.runes.length > collectionCommentLimit;
    final popular = widget.subject.tags.map((tag) => tag.name).take(16);
    Widget section(String title, Widget child, {String? detail}) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: text.titleSmall),
              if (detail != null) ...[
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    detail,
                    style: text.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Gap.sm),
          child,
        ],
      ),
    );
    final saveKeys = defaultTargetPlatform == TargetPlatform.macOS
        ? '⌘ + Enter'
        : 'Ctrl + Enter';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
            _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _save,
      },
      // Holds focus when nothing in the drawer has it, so the shortcuts work
      // from the moment it opens.
      child: Focus(
        autofocus: !widget.focusComment,
        skipTraversal: true,
        child: Material(
          color: scheme.surface,
          elevation: 6,
          shadowColor: Theme.of(context).shadowColor,
          borderRadius: BorderRadius.horizontal(
            left: panelBorderRadius.topLeft,
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 440,
            height: double.infinity,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    Gap.lg,
                    Gap.md,
                    Gap.md,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        height: 54,
                        child: CoverFrame(
                          radius: badgeBorderRadius,
                          child: SubjectCover(
                            url: widget.subject.coverUrl,
                            title: widget.subject.title,
                            id: widget.subject.id,
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('编辑收藏', style: text.titleMedium),
                            Text(
                              widget.subject.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭（保留草稿）',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      IssueBanner(
                        issue: restored && changed ? '已恢复上次未保存的编辑' : null,
                        tone: NoticeTone.info,
                      ),
                      section(
                        '状态',
                        MelonSegmentedControl<CollectionStatus>(
                          options: collectionLabels,
                          value: status,
                          semanticLabel: '收藏状态',
                          onChanged: (value) => _update(
                            status: value,
                            completeEpisodes:
                                value == CollectionStatus.completed
                                ? null
                                : false,
                          ),
                        ),
                        detail: status == null ? '选择收藏状态后可保存' : null,
                      ),
                      section(
                        '我的评分',
                        Container(
                          padding: const EdgeInsets.fromLTRB(
                            Gap.sm,
                            Gap.sm,
                            Gap.xs,
                            Gap.sm,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainer,
                            borderRadius: controlBorderRadius,
                          ),
                          child: Row(
                            children: [
                              StarRating(
                                value: status == CollectionStatus.wish
                                    ? 0
                                    : score,
                                size: 22,
                                labelWidth: 80,
                                enabled:
                                    status != null &&
                                    status != CollectionStatus.wish,
                                onTap: (value) {
                                  if (status != null &&
                                      status != CollectionStatus.wish) {
                                    _update(score: value);
                                  }
                                },
                              ),
                              const Spacer(),
                              if (score > 0 && status != CollectionStatus.wish)
                                TextButton(
                                  onPressed: () => _update(score: 0),
                                  child: const Text('清除'),
                                ),
                            ],
                          ),
                        ),
                        detail: status == CollectionStatus.wish
                            ? '想看状态不能评分'
                            : null,
                      ),
                      section(
                        '标签',
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(Gap.sm),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: controlBorderRadius,
                              ),
                              child: Wrap(
                                spacing: Gap.sm,
                                runSpacing: Gap.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  for (final tag in tags)
                                    InputChip(
                                      label: Text(tag),
                                      onDeleted: () => _toggleTag(tag),
                                      deleteButtonTooltipMessage: '移除 $tag',
                                    ),
                                  SizedBox(
                                    width: 180,
                                    child: TextField(
                                      controller: tagInput,
                                      decoration: const InputDecoration(
                                        hintText: '回车或逗号添加',
                                        filled: false,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: Gap.xs,
                                          vertical: Gap.sm,
                                        ),
                                      ),
                                      onSubmitted: _addTags,
                                      onChanged: (value) {
                                        if (endsWithTagSeparator(value)) {
                                          _addTags(value);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (tagError case final error?)
                              Padding(
                                padding: const EdgeInsets.only(top: Gap.sm),
                                child: InlineIssue(error),
                              ),
                            if (popular.isNotEmpty) ...[
                              const SizedBox(height: Gap.sm),
                              TagToggles(
                                tags: popular,
                                selected: tags.toSet(),
                                onToggle: _toggleTag,
                              ),
                            ],
                          ],
                        ),
                        detail: '${tags.length} / $collectionTagLimit',
                      ),
                      section(
                        '吐槽',
                        TextField(
                          controller: comment,
                          autofocus: widget.focusComment,
                          minLines: 4,
                          maxLines: 8,
                          onChanged: (value) => _update(comment: value),
                          decoration: InputDecoration(
                            hintText: '写一句吐槽…',
                            counterText:
                                '${comment.text.runes.length}/$collectionCommentLimit',
                            errorText: tooLong ? '吐槽超过字数上限' : null,
                          ),
                        ),
                      ),
                      if (status == CollectionStatus.completed)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: draft.completeEpisodes,
                          onChanged: (value) =>
                              _update(completeEpisodes: value ?? false),
                          title: const Text('同时将全部正片标为已看'),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, Gap.md, 20, Gap.md),
                  child: Row(
                    children: [
                      const Spacer(),
                      if (changed)
                        TextButton(
                          onPressed: _discard,
                          child: const Text('放弃修改'),
                        ),
                      const SizedBox(width: Gap.sm),
                      Tooltip(
                        message: saveKeys,
                        child: FilledButton(
                          onPressed: _canSave ? _save : null,
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
