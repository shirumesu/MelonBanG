const collectionTagLimit = 10;
const collectionCommentLimit = 380;

List<String> normalizeCollectionTags(Iterable<String> values) {
  final tags = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
  if (tags.length > collectionTagLimit) {
    throw const FormatException('最多 $collectionTagLimit 个标签');
  }
  if (tags.any((tag) => RegExp(r'\s').hasMatch(tag))) {
    throw const FormatException('标签不能包含空白字符');
  }
  if (tags.any((tag) => tag.runes.length < 2)) {
    throw const FormatException('标签至少两个字');
  }
  return tags;
}
