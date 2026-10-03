import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/collection_edit.dart';
import '../../data/json.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'collection_labels.dart';

/// Unsaved drawer edits, kept per account and subject for this app run.
abstract final class CollectionDrafts {
  static final _values = <String, Json>{};
  static String key(String user, Object? subjectId) => '$user:$subjectId';
  static Json? read(String key) => _values[key];
  static bool has(String key) => _values.containsKey(key);
  static void write(String key, Json value) => _values[key] = value;
  static void clear(String key) => _values.remove(key);
}

/// Opens the right-side editor. Returns the changed fields, or null when the
/// drawer was closed; closing keeps any difference as a draft.
Future<Json?> showCollectionDrawer(
  BuildContext context, {
  required Json subject,
  required String draftKey,
  bool focusComment = false,
}) => showGeneralDialog<Json>(
  context: context,
  barrierDismissible: true,
  barrierLabel: '关闭编辑收藏',
  barrierColor: Colors.black.withValues(alpha: .18),
  transitionDuration: motionDuration(context, 220),
  pageBuilder: (_, _, _) => Align(
    alignment: Alignment.centerRight,
    child: CollectionDrawer(
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

class CollectionDrawer extends StatefulWidget {
  const CollectionDrawer({
    super.key,
    required this.subject,
    required this.draftKey,
    this.focusComment = false,
  });
  final Json subject;
  final String draftKey;
  final bool focusComment;

  @override
  State<CollectionDrawer> createState() => _CollectionDrawerState();
}

class _CollectionDrawerState extends State<CollectionDrawer> {
  late final Json saved = _fields(object(widget.subject['collection']));
  late final bool restored = CollectionDrafts.has(widget.draftKey);
  late Json draft = {...saved, ...?CollectionDrafts.read(widget.draftKey)};
  late final comment = TextEditingController(text: '${draft['comment']}');
  final tagInput = TextEditingController();
  String? tagError;

  static Json _fields(Json collection) => {
    'status': collection['status'],
    'score': number(collection['score']).toInt(),
    'tags': (collection['tags'] as List? ?? []).whereType<String>().toList(),
    'comment': '${collection['comment'] ?? ''}',
    'completeEpisodes': false,
  };

  String? get status => draft['status'] as String?;
  int get score => draft['score'] as int;
  List<String> get tags => (draft['tags'] as List).cast<String>();

  bool _same(String field) => field == 'tags'
      ? listEquals(tags, (saved['tags'] as List).cast<String>())
      : draft[field] == saved[field];

  bool get changed => draft.keys.any((field) => !_same(field));

  @override
  void dispose() {
    comment.dispose();
    tagInput.dispose();
    super.dispose();
  }

  void _update(Json values) {
    setState(() => draft = {...draft, ...values});
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

  void _reset() {
    CollectionDrafts.clear(widget.draftKey);
    comment.text = '${saved['comment']}';
    setState(() => draft = {...saved});
  }

  bool _addTags(String text) {
    try {
      final updated = normalizeCollectionTags([
        ...tags,
        ...text.split(RegExp('[,，]')),
      ]);
      setState(() => tagError = null);
      tagInput.clear();
      _update({'tags': updated});
      return true;
    } on FormatException catch (error) {
      setState(() => tagError = error.message);
      return false;
    }
  }

  void _toggleTag(String tag) {
    if (tags.contains(tag)) {
      _update({
        'tags': [...tags]..remove(tag),
      });
    } else {
      _addTags(tag);
    }
  }

  void _save() {
    if (tagInput.text.trim().isNotEmpty && !_addTags(tagInput.text)) return;
    Navigator.pop(context, <String, dynamic>{
      for (final field in ['status', 'score', 'tags', 'comment'])
        if (!_same(field)) field: draft[field],
      if (status == 'completed' && draft['completeEpisodes'] == true)
        'completeEpisodes': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final episodes = objects(widget.subject['episodes']);
    final watched = episodes.where((e) => e['status'] == 'watched').length;
    final tooLong = comment.text.runes.length > collectionCommentLimit;
    final popular = objects(widget.subject['tags'])
        .map((tag) => '${tag['name']}')
        .take(16);
    Widget section(String title, Widget child, {String? detail}) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg + 2),
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
    return Material(
      color: scheme.surface,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 440,
        height: double.infinity,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    height: 54,
                    child: ClipRRect(
                      borderRadius: badgeBorderRadius,
                      child: SubjectCover(
                        url: widget.subject['coverUrl'],
                        title: titleOf(widget.subject),
                        id: number(widget.subject['subjectId']).toInt(),
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
                          '${titleOf(widget.subject)} · 已看 $watched / ${episodes.length} 话',
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
                  if (restored && changed)
                    Container(
                      margin: const EdgeInsets.only(bottom: Gap.lg),
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: .5),
                        borderRadius: controlBorderRadius,
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '已恢复上次未保存的编辑',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: _reset,
                            child: const Text('放弃草稿'),
                          ),
                        ],
                      ),
                    ),
                  section(
                    '状态',
                    MelonSegmentedControl<String>(
                      options: collectionLabels,
                      value: status,
                      semanticLabel: '收藏状态',
                      onChanged: (value) => _update({
                        'status': value,
                        if (value == 'wish') 'score': 0,
                        if (value != 'completed') 'completeEpisodes': false,
                      }),
                    ),
                    detail: status == null ? '先选一个状态，才能保存其他内容' : null,
                  ),
                  section(
                    '我的评分',
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: controlBorderRadius,
                      ),
                      child: Row(
                        children: [
                          StarRating(
                            value: score,
                            size: 26,
                            enabled: status != null && status != 'wish',
                            onTap: (value) {
                              if (status != null && status != 'wish') {
                                _update({'score': value});
                              }
                            },
                          ),
                          const SizedBox(width: Gap.sm),
                          Expanded(child: ScoreText(score)),
                          if (score > 0)
                            TextButton(
                              onPressed: () => _update({'score': 0}),
                              child: const Text('清除'),
                            ),
                        ],
                      ),
                    ),
                    detail: status == 'wish' ? '想看状态不能评分' : null,
                  ),
                  section(
                    '标签',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: controlBorderRadius,
                          ),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
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
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                  ),
                                  onSubmitted: _addTags,
                                  onChanged: (value) {
                                    if (value.endsWith(',') ||
                                        value.endsWith('，')) {
                                      _addTags(value);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            tagError ?? '每个标签至少两个字，不能包含空白',
                            style: text.bodySmall?.copyWith(
                              color: tagError == null ? null : scheme.error,
                            ),
                          ),
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
                      onChanged: (value) => _update({'comment': value}),
                      decoration: InputDecoration(
                        hintText: '写一句吐槽…',
                        counterText:
                            '${comment.text.runes.length}/$collectionCommentLimit',
                        errorText: tooLong ? '吐槽超过字数上限' : null,
                      ),
                    ),
                  ),
                  if (status == 'completed')
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: draft['completeEpisodes'] == true,
                      onChanged: (value) =>
                          _update({'completeEpisodes': value ?? false}),
                      title: const Text('同时将全部正片标为已看'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      changed ? '关闭会暂存草稿' : '保存后同步到 Bangumi',
                      style: text.bodySmall,
                    ),
                  ),
                  if (changed)
                    TextButton(onPressed: _discard, child: const Text('放弃修改')),
                  const SizedBox(width: Gap.sm),
                  FilledButton(
                    onPressed: status == null || !changed || tooLong
                        ? null
                        : _save,
                    child: const Text('保存'),
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

/// Ten clickable stars with hover preview. [onTap] fires even when
/// [enabled] is false so callers can explain why scoring is unavailable.
class StarRating extends StatefulWidget {
  const StarRating({
    super.key,
    required this.value,
    required this.onTap,
    this.enabled = true,
    this.size = 18,
  });
  final int value;
  final ValueChanged<int> onTap;
  final bool enabled;
  final double size;

  @override
  State<StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends State<StarRating> {
  int hover = 0;

  @override
  Widget build(BuildContext context) {
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;
    final shown = widget.enabled && hover > 0 ? hover : widget.value;
    return MouseRegion(
      onExit: (_) => setState(() => hover = 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var n = 1; n <= 10; n++)
            Semantics(
              button: true,
              label: '$n 分',
              selected: widget.value == n,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => hover = n),
                child: GestureDetector(
                  onTap: () => widget.onTap(n),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: .5),
                    child: Icon(
                      Icons.star_rounded,
                      size: widget.size,
                      color: n > shown
                          ? empty
                          : hover > 0 && widget.enabled
                          ? gold.withValues(alpha: .6)
                          : widget.enabled
                          ? gold
                          : gold.withValues(alpha: .35),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ScoreText extends StatelessWidget {
  const ScoreText(this.score, {super.key});
  final int score;

  @override
  Widget build(BuildContext context) => score <= 0
      ? Text('未评分', style: Theme.of(context).textTheme.bodySmall)
      : Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$score',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: ' ${scoreLabels[score]}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color.lerp(gold, Colors.black, .35),
                ),
              ),
            ],
          ),
          maxLines: 1,
        );
}

/// Popular tags as on/off chips.
class TagToggles extends StatelessWidget {
  const TagToggles({
    super.key,
    required this.tags,
    required this.selected,
    required this.onToggle,
  });
  final Iterable<String> tags;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final tag in tags)
        FilterChip(
          label: Text(tag),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          selected: selected.contains(tag),
          onSelected: (_) => onToggle(tag),
        ),
    ],
  );
}
