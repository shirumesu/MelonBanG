import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' show Element;

import '../json.dart';
import '../network.dart';

const onlineEngineVersion = 1;
List<dynamic> array(dynamic value) => value is List ? value : [];

class SourceVerificationRequired implements Exception {
  const SourceVerificationRequired(this.url);
  final String url;
  @override
  String toString() => '站点需要人机验证，请在浏览器打开 $url';
}

abstract class OnlineSource {
  Future<List<Json>> searchSubjects(
    Iterable<String> names, {
    RequestCancellation? cancel,
  });
  Future<List<Json>> episodes(Json subject, {RequestCancellation? cancel});
  Future<Json> resolve(Json ref, {RequestCancellation? cancel});
}

class RuleOnlineSource implements OnlineSource {
  RuleOnlineSource(this.api, this.rule);
  final ApiClient api;
  final Json rule;
  String? currentBase;
  Uri? lastRequest;
  int? lastStatus;
  String get id => '${rule['id']}';
  String get engine => '${rule['engine']}';
  Map<String, String> get headers =>
      object(rule['headers']).map((key, value) => MapEntry(key, '$value'));
  String template(String text, Json values) => text.replaceAllMapped(
    RegExp(r'\{(\w+)\}'),
    (match) => Uri.encodeComponent('${values[match[1]] ?? ''}'),
  );

  Future<(String, Uri)> request(
    Json step,
    Json values, {
    RequestCancellation? cancel,
  }) async {
    final bases = <String>{
      ?currentBase,
      ...array(rule['baseUrls']).map((value) => '$value'),
    };
    Object? issue;
    for (final base in bases) {
      cancel?.throwIfCancelled();
      final uri = Uri.parse(base).resolve(template('${step['url']}', values));
      lastRequest = uri;
      lastStatus = null;
      try {
        final response = await api.send(
          uri,
          cancel: cancel,
          headers: {
            ...headers,
            ...object(step['headers']).map((k, v) => MapEntry(k, '$v')),
          },
        );
        lastStatus = response.statusCode;
        final body = utf8.decode(response.bodyBytes);
        if (RegExp(
              r'cf-chl-|captcha|人机验证|安全验证|Just a moment',
              caseSensitive: false,
            ).hasMatch(body) &&
            !body.trimLeft().startsWith('{')) {
          throw SourceVerificationRequired(uri.toString());
        }
        if (engine == 'maccms-api') {
          final payload = jsonDecode(body);
          if (payload is! Map || payload['list'] is! List) {
            throw const FormatException('视频源未返回有效的资源列表');
          }
        }
        currentBase = base;
        return (body, uri);
      } on SourceVerificationRequired {
        rethrow;
      } on ApiException catch (error) {
        lastStatus = error.status;
        if (error.status == 403 || error.status == 429) {
          throw SourceVerificationRequired(uri.toString());
        }
        issue = error;
      } catch (error) {
        cancel?.throwIfCancelled();
        issue = error;
      }
    }
    throw issue ?? StateError('视频源没有可用域名');
  }

  @override
  Future<List<Json>> searchSubjects(
    Iterable<String> names, {
    RequestCancellation? cancel,
  }) async {
    final rows = <String, Json>{};
    Object? issue;
    var completed = false;
    Future<List<Json>> query(String name) async {
      final (body, uri) = await request(object(rule['search']), {
        'query': name,
      }, cancel: cancel);
      return engine == 'maccms-api'
          ? array(object(jsonDecode(body))['list'])
                .map((value) => _maccmsSubject(object(value)))
                .toList()
          : _rows(body, object(rule['search']), uri);
    }

    for (final name
        in names.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()) {
      cancel?.throwIfCancelled();
      try {
        var parsed = await query(name);
        final compact = name.replaceAll(RegExp(r'\s+'), '');
        if (parsed.isEmpty && compact != name) parsed = await query(compact);
        for (final row in parsed) {
          if ('${row['title'] ?? ''}'.isNotEmpty) {
            rows['${row['id'] ?? row['url']}'] = row;
          }
        }
        completed = true;
      } on SourceVerificationRequired {
        rethrow;
      } catch (error) {
        cancel?.throwIfCancelled();
        issue = error;
      }
    }
    if (!completed && issue != null) throw issue;
    return rows.values.toList();
  }

  Json _maccmsSubject(Json row) => {
    'id': '${row['vod_id']}',
    'title': row['vod_name'],
    'year': int.tryParse('${row['vod_year'] ?? ''}'),
    'episodeTotal': RegExp(r'\d+')
        .allMatches('${row['vod_remarks'] ?? ''}')
        .firstOrNull?[0],
    'raw': row,
  };

  @override
  Future<List<Json>> episodes(
    Json subject, {
    RequestCancellation? cancel,
  }) async {
    cancel?.throwIfCancelled();
    if (engine == 'maccms-api') {
      var raw = object(subject['raw']);
      if ('${raw['vod_play_url'] ?? ''}'.isEmpty) {
        final (body, _) = await request(object(rule['detail']), {
          'id': subject['id'],
        }, cancel: cancel);
        raw = object(array(object(jsonDecode(body))['list']).firstOrNull);
      }
      final lines = '${raw['vod_play_from'] ?? ''}'.split(r'$$$');
      final groups = '${raw['vod_play_url'] ?? ''}'.split(r'$$$');
      final result = <Json>[];
      for (var line = 0; line < groups.length; line++) {
        final name = line < lines.length ? lines[line] : '${line + 1}';
        final filter = '${rule['lineFilter'] ?? ''}';
        if (filter.isNotEmpty && !RegExp(filter).hasMatch(name)) continue;
        for (final entry in groups[line].split('#')) {
          final separator = entry.indexOf(r'$');
          if (separator < 0) continue;
          result.add({
            'label': entry.substring(0, separator),
            'line': name,
            'ref': {
              'sourceId': id,
              'subjectId': subject['id'],
              'line': name,
              'episodeLabel': entry.substring(0, separator),
              'url': entry.substring(separator + 1),
            },
          });
        }
      }
      return result;
    }
    final (body, uri) = await request(
      object(rule['detail']),
      subject,
      cancel: cancel,
    );
    return _rows(body, object(rule['detail']), uri)
        .map(
          (row) => {
            'label': row['label'] ?? row['title'],
            'line': row['line'] ?? '默认线路',
            'ref': {
              'sourceId': id,
              'subjectId': subject['id'],
              'episodeLabel': row['label'] ?? row['title'],
              'line': row['line'] ?? '默认线路',
              'url': row['url'],
            },
          },
        )
        .toList();
  }

  @override
  Future<Json> resolve(Json ref, {RequestCancellation? cancel}) async {
    cancel?.throwIfCancelled();
    var address = '${ref['url'] ?? ''}';
    if (engine == 'maccms-api') {
      // Read the current catalogue entry so expiring links can be refreshed.
      final rows = await episodes({'id': ref['subjectId']}, cancel: cancel);
      final fresh = rows
          .where(
            (row) =>
                row['line'] == ref['line'] &&
                row['label'] == ref['episodeLabel'],
          )
          .firstOrNull;
      if (fresh == null) throw StateError('该线路已移除这一集');
      address = '${object(fresh['ref'])['url']}';
    } else {
      final step = object(rule['play']);
      final (body, uri) = await request(
        step.isEmpty ? {'url': address} : step,
        {...ref, 'url': address},
        cancel: cancel,
      );
      if (engine == 'maccms-html') {
        final match = RegExp(r'player_\w+\s*=\s*(\{[^\n]+?\})\s*[;\n<]')
            .firstMatch(body);
        if (match == null) throw StateError('页面没有静态播放地址');
        final player = object(jsonDecode(match[1]!));
        address = '${player['url'] ?? ''}';
        if ('${player['encrypt']}' == '2') {
          address = utf8.decode(base64.decode(address));
        }
        if ('${player['encrypt']}' == '1' || '${player['encrypt']}' == '2') {
          address = _unescape(address);
        }
      } else {
        address = '${extract(body, rule['extract'] ?? step['extract']) ?? ''}';
      }
      address = uri.resolve(address).toString();
    }
    for (final decoder in array(rule['decode'])) {
      address = switch ('$decoder') {
        'base64' => utf8.decode(base64.decode(address)),
        'unescape' => _unescape(address),
        'url' => Uri.decodeComponent(address),
        'json' => '${jsonDecode(address)}',
        _ => throw FormatException('不支持的解码步骤：$decoder'),
      };
    }
    final uri = Uri.tryParse(address);
    if (uri == null || !['https', 'http'].contains(uri.scheme)) {
      throw StateError('站点没有返回直链，无法静态解析');
    }
    return {
      'url': address,
      'headers': headers,
      'kind': uri.path.toLowerCase().contains('.m3u8') ? 'hls' : 'mp4',
      'provider': id,
      'line': ref['line'],
    };
  }

  List<Json> _rows(String body, Json step, Uri uri) {
    final items = object(step['items']);
    final fields = object(step['fields']);
    final values = extract(body, items);
    return (values is List ? values : [values])
        .where((value) => value != null)
        .map((value) {
          final row = <String, dynamic>{};
          for (final field in fields.entries) {
            row[field.key] = extract(value, field.value);
          }
          if (row['url'] != null) {
            row['url'] = uri.resolve('${row['url']}').toString();
          }
          return row;
        })
        .toList();
  }

  dynamic extract(dynamic input, dynamic specification) {
    final spec = object(specification);
    final path = '${spec['path'] ?? ''}';
    switch (spec['type']) {
      case 'css':
        final root = input is Element ? input : html.parse('$input');
        final nodes = path.isEmpty && input is Element
            ? [input]
            : root.querySelectorAll(path);
        dynamic value(Element node) => spec['attribute'] != null
            ? node.attributes['${spec['attribute']}']
            : node.text.trim();
        return spec['all'] == true || spec['nodes'] == true
            ? nodes
                  .map((node) => spec['nodes'] == true ? node : value(node))
                  .toList()
            : nodes.firstOrNull == null
            ? null
            : value(nodes.first);
      case 'regex':
        final matches = RegExp(
          path,
          dotAll: true,
          multiLine: true,
        ).allMatches('$input');
        final group = spec['group'] == null ? 1 : number(spec['group']).toInt();
        return spec['all'] == true
            ? matches.map((m) => m.group(group)).toList()
            : matches.firstOrNull?.group(group);
      case 'jsonpath':
        var values = <dynamic>[input is String ? jsonDecode(input) : input];
        for (final token
            in path
                .replaceFirst(RegExp(r'^\$\.?'), '')
                .replaceAllMapped(RegExp(r'\[(\d+|\*)\]'), (m) => '.${m[1]}')
                .split('.')
                .where((e) => e.isNotEmpty)) {
          values = values
              .expand((value) {
                if (token == '*') {
                  return value is List
                      ? value
                      : value is Map
                      ? value.values
                      : <dynamic>[];
                }
                if (value is Map) return [value[token]];
                final index = int.tryParse(token);
                return value is List && index != null && index < value.length
                    ? [value[index]]
                    : <dynamic>[];
              })
              .where((value) => value != null)
              .toList();
        }
        return spec['all'] == true || path.contains('*')
            ? values
            : values.firstOrNull;
      default:
        return input is Map ? input[path] : input;
    }
  }
}

String _unescape(String input) {
  final unicode = input.replaceAllMapped(
    RegExp(r'%u([a-fA-F0-9]{4})'),
    (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
  );
  return Uri.decodeComponent(unicode);
}
