import 'dart:convert';

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/sources.dart';
import 'rule_engine.dart';

/// Static HTML/JSON pages described by CSS, JSONPath or regex extraction
/// steps (`search`, `detail`, optional `play` and `extract`).
class SelectorEngine extends HttpRuleEngine implements OnlineSourceEngine {
  SelectorEngine(super.api, super.instance);

  @override
  Future<List<SourceSubject>> searchSubjects(
    String name, {
    RequestCancellation? cancel,
  }) => searchWithCompactRetry(name, (query) async {
    final step = object(config['search']);
    final (body, uri) = await request(step, {'query': query}, cancel: cancel);
    return [
      for (final row in rows(body, step, uri))
        if ('${row['title'] ?? ''}'.isNotEmpty)
          SourceSubject(
            id: '${row['id'] ?? row['url']}',
            title: '${row['title']}',
            year: int.tryParse('${row['year'] ?? ''}'),
            episodeTotal: int.tryParse('${row['episodeTotal'] ?? ''}'),
            data: row,
          ),
    ];
  });

  @override
  Future<List<SourceEpisode>> episodes(
    SourceSubject subject, {
    RequestCancellation? cancel,
  }) async {
    final step = object(config['detail']);
    final (body, uri) = await request(step, {
      ...subject.data,
      'id': subject.id,
    }, cancel: cancel);
    return [
      for (final row in rows(body, step, uri))
        SourceEpisode(
          label: '${row['label'] ?? row['title']}',
          line: '${row['line'] ?? '默认线路'}',
          ref: StreamRef(instance.id, {
            'subjectId': subject.id,
            'episodeLabel': row['label'] ?? row['title'],
            'line': row['line'] ?? '默认线路',
            'url': row['url'],
          }),
        ),
    ];
  }

  @override
  Future<ResolvedStream> resolve(
    StreamRef ref, {
    RequestCancellation? cancel,
  }) async {
    final address = '${ref.data['url'] ?? ''}';
    final configured = object(config['play']);
    final step = configured.isEmpty ? {'url': address} : configured;
    final (body, uri) = await request(step, {
      ...ref.data,
      'url': address,
    }, cancel: cancel);
    return stream(uri.resolve(playerAddress(body, step)).toString(), ref);
  }

  String playerAddress(String body, Json step) =>
      '${extract(body, config['extract'] ?? step['extract']) ?? ''}';
}

/// MacCMS HTML themes, whose play pages embed a `player_xxx = {...}` object.
class MaccmsHtmlEngine extends SelectorEngine {
  MaccmsHtmlEngine(super.api, super.instance);

  @override
  String playerAddress(String body, Json step) {
    final match = RegExp(r'player_\w+\s*=\s*(\{[^\n]+?\})\s*[;\n<]')
        .firstMatch(body);
    if (match == null) throw StateError('页面没有静态播放地址');
    final player = object(jsonDecode(match[1]!));
    var address = '${player['url'] ?? ''}';
    if ('${player['encrypt']}' == '2') {
      address = utf8.decode(base64.decode(address));
    }
    if ('${player['encrypt']}' == '1' || '${player['encrypt']}' == '2') {
      address = unescapeAddress(address);
    }
    return address;
  }
}
