import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/collection_edit.dart';
import '../../data/json.dart';
import '../core/selection_controls.dart';
import 'collection_labels.dart';

class CollectionEditor extends StatefulWidget {
  const CollectionEditor({
    super.key,
    required this.collection,
    required this.popularTags,
  });
  final Json collection;
  final List<Json> popularTags;

  @override
  State<CollectionEditor> createState() => _CollectionEditorState();
}

class _CollectionEditorState extends State<CollectionEditor> {
  late String status = '${widget.collection['status'] ?? 'wish'}';
  late int score = number(widget.collection['score']).toInt();
  late final tags = (widget.collection['tags'] as List? ?? [])
      .whereType<String>()
      .toList();
  late final comment = TextEditingController(
    text: '${widget.collection['comment'] ?? ''}',
  );
  final tagInput = TextEditingController();
  String? tagError;
  bool completeEpisodes = false;

  @override
  void dispose() {
    comment.dispose();
    tagInput.dispose();
    super.dispose();
  }

  bool _add(String text) {
    try {
      final updated = normalizeCollectionTags([
        ...tags,
        ...text.split(RegExp('[,，]')),
      ]);
      setState(() {
        tags
          ..clear()
          ..addAll(updated);
        tagError = null;
      });
      tagInput.clear();
      return true;
    } on FormatException catch (error) {
      setState(() => tagError = error.message);
      return false;
    }
  }

  void _save() {
    if (tagInput.text.trim().isNotEmpty && !_add(tagInput.text)) return;
    if (comment.text.runes.length > collectionCommentLimit) return;
    final originalTags = (widget.collection['tags'] as List? ?? [])
        .whereType<String>()
        .toList();
    Navigator.pop(context, <String, dynamic>{
      if (status != widget.collection['status']) 'status': status,
      if (score != number(widget.collection['score']).toInt()) 'score': score,
      if (!listEquals(tags, originalTags)) 'tags': tags,
      if (comment.text != '${widget.collection['comment'] ?? ''}')
        'comment': comment.text,
      if (status == 'completed' && completeEpisodes) 'completeEpisodes': true,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑收藏'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MelonSegmentedControl<String>(
              options: collectionLabels,
              value: status,
              onChanged: (value) => setState(() {
                status = value;
                if (value != 'completed') completeEpisodes = false;
                if (value == 'wish' && score > 0) score = 0;
              }),
            ),
            const SizedBox(height: 20),
            const Text('我的评分'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var value = 1; value <= 10; value++)
                  ChoiceChip(
                    label: Text('$value'),
                    selected: score == value,
                    onSelected: status == 'wish'
                        ? null
                        : (_) => setState(() => score = value),
                  ),
                TextButton(
                  onPressed: () => setState(() => score = 0),
                  child: const Text('清除评分'),
                ),
              ],
            ),
            if (status == 'wish')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('想看状态不能评分，请先选择其他收藏状态。'),
              ),
            const SizedBox(height: 16),
            Text('标签 (${tags.length}/$collectionTagLimit)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in tags)
                  InputChip(
                    label: Text(tag),
                    onDeleted: () => setState(() => tags.remove(tag)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tagInput,
              decoration: InputDecoration(
                hintText: '回车或逗号添加标签',
                errorText: tagError,
                helperText: '每个标签至少两个字，不能包含空白',
              ),
              onSubmitted: _add,
              onChanged: (value) {
                if (value.endsWith(',') || value.endsWith('，')) _add(value);
              },
            ),
            if (widget.popularTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('热门标签'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in widget.popularTags.take(16))
                    ActionChip(
                      label: Text('${tag['name']}'),
                      onPressed: () => _add('${tag['name']}'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: comment,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '吐槽',
                alignLabelWithHint: true,
                counterText:
                    '${comment.text.runes.length}/$collectionCommentLimit',
                helperText: '最多 $collectionCommentLimit 字',
                errorText: comment.text.runes.length > collectionCommentLimit
                    ? '吐槽超过字数上限'
                    : null,
              ),
            ),
            if (status == 'completed')
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: completeEpisodes,
                onChanged: (value) =>
                    setState(() => completeEpisodes = value ?? false),
                title: const Text('同时将全部正片标为已看'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
