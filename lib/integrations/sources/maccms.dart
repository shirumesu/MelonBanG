import 'dart:convert';

import '../../data/json.dart';
import '../../data/network.dart';
import '../../domain/sources.dart';
import 'rule_engine.dart';

/// MacCMS collection API (`/api.php/provide/vod/`): JSON search and detail,
/// with lines separated by `$$$` and entries by `#`.
class MaccmsApiEngine extends HttpRuleEngine implements OnlineSourceEngine {
  MaccmsApiEngine(super.api, super.instance);

  @override
  void validate(String body) {
    final payload = jsonDecode(body);
    if (payload is! Map || payload['list'] is! List) {
      throw const FormatException('视频源未返回有效的资源列表');
    }
  }

  @override
  Future<List<SourceSubject>> searchSubjects(
    String name, {
    RequestCancellation? cancel,
  }) => searchWithCompactRetry(name, (query) async {
    final (body, _) = await request(object(config['search']), {
      'query': query,
    }, cancel: cancel);
    return [
      for (final row in objects(object(jsonDecode(body))['list']))
        if ('${row['vod_name'] ?? ''}'.isNotEmpty) _subject(row),
    ];
  });

  SourceSubject _subject(Json row) => SourceSubject(
    id: '${row['vod_id']}',
    title: '${row['vod_name']}',
    year: int.tryParse('${row['vod_year'] ?? ''}'),
    episodeTotal: int.tryParse(
      RegExp(r'\d+').firstMatch('${row['vod_remarks'] ?? ''}')?[0] ?? '',
    ),
    data: row,
  );

  @override
  Future<List<SourceEpisode>> episodes(
    SourceSubject subject, {
    RequestCancellation? cancel,
  }) async {
    cancel?.throwIfCancelled();
    var raw = subject.data;
    // Search rows that already carry episodes avoid a detail request.
    if ('${raw['vod_play_url'] ?? ''}'.isEmpty) {
      final (body, _) = await request(object(config['detail']), {
        'id': subject.id,
      }, cancel: cancel);
      raw = object(array(object(jsonDecode(body))['list']).firstOrNull);
    }
    final lines = '${raw['vod_play_from'] ?? ''}'.split(r'$$$');
    final groups = '${raw['vod_play_url'] ?? ''}'.split(r'$$$');
    final filter = '${config['lineFilter'] ?? ''}';
    final result = <SourceEpisode>[];
    for (var line = 0; line < groups.length; line++) {
      final name = line < lines.length ? lines[line] : '${line + 1}';
      if (filter.isNotEmpty && !RegExp(filter).hasMatch(name)) continue;
      for (final entry in groups[line].split('#')) {
        final separator = entry.indexOf(r'$');
        if (separator < 0) continue;
        final label = entry.substring(0, separator);
        result.add(
          SourceEpisode(
            label: label,
            line: name,
            ref: StreamRef(instance.id, {
              'subjectId': subject.id,
              'line': name,
              'episodeLabel': label,
              'url': entry.substring(separator + 1),
            }),
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<ResolvedStream> resolve(
    StreamRef ref, {
    RequestCancellation? cancel,
  }) async {
    cancel?.throwIfCancelled();
    // Read the current catalogue entry so expiring links are refreshed.
    final rows = await episodes(
      SourceSubject(id: '${ref.data['subjectId']}', title: ''),
      cancel: cancel,
    );
    final fresh = rows
        .where(
          (row) =>
              row.line == ref.data['line'] &&
              row.label == ref.data['episodeLabel'],
        )
        .firstOrNull;
    if (fresh == null) throw StateError('该线路已移除这一集');
    return stream('${fresh.ref.data['url']}', ref);
  }
}
