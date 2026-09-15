import 'package:html/parser.dart' as html;
import 'package:pinyin/pinyin.dart';

import 'json.dart';
import 'torrent_identity.dart';

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

String resourceIdentity(Json row) {
  final uri = Uri.parse('${row['locator']}');
  if (uri.scheme == 'magnet') {
    try {
      return magnetInfoHash(uri);
    } on FormatException {
      /* Keep unusual locators distinct. */
    }
  }
  final filename = uri.pathSegments.lastOrNull ?? '';
  if (filename.endsWith('.torrent')) {
    final hash = filename.substring(0, filename.length - 8).toLowerCase();
    if (hash.length == 40 &&
        hash.codeUnits.every(
          (c) => c >= 48 && c <= 57 || c >= 97 && c <= 102,
        )) {
      return hash;
    }
  }
  return uri.toString();
}

List<Json> dmhyMetadata(String body, Uri base) {
  final document = html.parse(body);
  final result = <Json>[];
  for (final row in document.querySelectorAll('#topic_list tbody tr')) {
    final title = row.querySelector('td.title a[href*="/topics/view/"]');
    final magnet = row.querySelector('a[href^="magnet:"]')?.attributes['href'];
    if (title == null || magnet == null) continue;
    final cells = row.querySelectorAll('td');
    result.add({
      'title': title.text.trim(),
      'locator': magnet,
      'releaseGroups': row
          .querySelectorAll('td.title a[href*="/team_id/"]')
          .map((e) => e.text.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(),
      if (cells.length > 4) 'sizeLabel': cells[4].text.trim(),
      'detailUrl': base.resolve(title.attributes['href']!).toString(),
    });
  }
  return result;
}

List<Uri> mikanSeriesPages(String body, Uri base) => html
    .parse(body)
    .querySelectorAll('.an-ul a[href^="/Home/Bangumi/"]')
    .map((e) => base.resolve(e.attributes['href']!))
    .toSet()
    .toList();

List<Json> mikanMetadata(String body) {
  final document = html.parse(body);
  final result = <Json>[];
  for (final group in document.querySelectorAll('.subgroup-text')) {
    final name = group
        .querySelector('a[href^="/Home/PublishGroup/"]')
        ?.text
        .trim();
    final table = group.nextElementSibling;
    if (name == null ||
        name.isEmpty ||
        table == null ||
        !table.classes.contains('episode-table')) {
      continue;
    }
    for (final row in table.querySelectorAll('tbody tr')) {
      final title = row.querySelector('a[href^="/Home/Episode/"]');
      final locator =
          row.querySelector('[data-magnet]')?.attributes['data-magnet'] ??
          row.querySelector('a[href^="magnet:"]')?.attributes['href'];
      if (title == null || locator == null) continue;
      result.add({
        'title': title.text.trim(),
        'locator': locator,
        'releaseGroups': [name],
      });
    }
  }
  return result;
}

String resourceProviderLabel(Json provider) {
  final count = '${provider['resultCount'] ?? 0} 条';
  return switch (provider['status']) {
    'loading' => '$count · 搜索中 ${provider['completed']}/${provider['total']}',
    'error' => '搜索失败',
    'partial' => '$count · 部分名称搜索失败',
    _ => count,
  };
}
