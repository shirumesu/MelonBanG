import 'package:pinyin/pinyin.dart';

import '../domain/catalog.dart';

String resourceEpisodeKeyword(Episode? episode) {
  if (episode == null) return '';
  final sort = episode.sort;
  return sort == sort.roundToDouble()
      ? sort.toInt().toString().padLeft(2, '0')
      : sort.toString();
}

/// Resource names are catalogue aliases, never guessed from a release title.
List<String> resourceNames(Subject subject) {
  final values = <String>[
    subject.title,
    ?subject.name,
    ?subject.nameCn,
    ?subject.displayName,
    ...subject.aliases,
  ];
  final seen = <String>{};
  return values
      .where((value) {
        final key = ChineseHelper.convertToSimplifiedChinese(value.trim())
            .toLowerCase();
        return key.isNotEmpty && value != '未命名' && seen.add(key);
      })
      .map((value) => value.trim())
      .toList();
}
