import 'package:pinyin/pinyin.dart';

import 'json.dart';

String resourceEpisodeKeyword(Json? episode) {
  final sort = episode?['sort'] ?? episode?['ep'];
  if (sort is! num) return '';
  return sort == sort.roundToDouble()
      ? sort.toInt().toString().padLeft(2, '0')
      : sort.toString();
}

/// Resource names are catalogue aliases, never guessed from a release title.
List<String> resourceNames(Json subject) {
  final values = <String>[
    titleOf(subject),
    if (subject['name'] is String) subject['name'] as String,
    if (subject['nameCn'] is String) subject['nameCn'] as String,
    if (subject['displayName'] is String) subject['displayName'] as String,
  ];
  for (final alias in subject['aliases'] is List ? subject['aliases'] : []) {
    if (alias is String) values.add(alias);
    if (alias is Map && alias['name'] is String) values.add(alias['name']);
  }
  for (final field in objects(subject['infobox'])) {
    if (field['key'] != '别名') continue;
    final value = field['value'];
    if (value is String) values.add(value);
    for (final entry in objects(value)) {
      if (entry['v'] is String) values.add(entry['v']);
    }
  }
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
