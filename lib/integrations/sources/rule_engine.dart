import 'dart:convert';

import 'package:html/dom.dart' show Element;
import 'package:html/parser.dart' as html;

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/sources.dart';

List<dynamic> array(dynamic value) => value is List ? value : [];

/// Shared HTTP mechanics of declarative rules: ordered base-URL fallback,
/// `{field}` templates, verification detection, extraction and decoding.
abstract class HttpRuleEngine implements SourceEngine {
  HttpRuleEngine(this.api, this.instance);
  final ApiClient api;
  @override
  final SourceInstance instance;
  String? _base;
  @override
  Uri? lastRequest;
  @override
  int? lastStatus;
  @override
  String get currentBase => _base ?? instance.baseUrls.firstOrNull ?? '';
  Json get config => instance.config;
  Map<String, String> get headers =>
      object(config['headers']).map((key, value) => MapEntry(key, '$value'));

  String template(String text, Json values) => text.replaceAllMapped(
    RegExp(r'\{(\w+)\}'),
    (match) => Uri.encodeComponent('${values[match[1]] ?? ''}'),
  );

  /// Rejects a response body that does not carry the expected payload, so
  /// the next base URL is tried.
  void validate(String body) {}

  Future<(String, Uri)> request(
    Json step,
    Json values, {
    RequestCancellation? cancel,
  }) async {
    final bases = <String>{?_base, ...instance.baseUrls};
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
        validate(body);
        _base = base;
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

  /// Applies the rule's decode chain and checks for a direct media address.
  ResolvedStream stream(String address, StreamRef ref) {
    for (final decoder in array(config['decode'])) {
      address = switch ('$decoder') {
        'base64' => utf8.decode(base64.decode(address)),
        'unescape' => unescapeAddress(address),
        'url' => Uri.decodeComponent(address),
        'json' => '${jsonDecode(address)}',
        _ => throw FormatException('不支持的解码步骤：$decoder'),
      };
    }
    final uri = Uri.tryParse(address);
    if (uri == null || !['https', 'http'].contains(uri.scheme)) {
      throw StateError('站点没有返回直链，无法静态解析');
    }
    return ResolvedStream(
      url: address,
      format: uri.path.toLowerCase().contains('.m3u8')
          ? StreamFormat.hls
          : StreamFormat.file,
      headers: headers,
      sourceId: instance.id,
      line: ref.data['line'] as String?,
    );
  }

  List<Json> rows(String body, Json step, Uri uri) {
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

/// A title search that retries once with whitespace removed, which some
/// sites need for spaced names such as `FX 战士久留美`.
Future<List<SourceSubject>> searchWithCompactRetry(
  String name,
  Future<List<SourceSubject>> Function(String) query,
) async {
  final rows = await query(name);
  final compact = name.replaceAll(RegExp(r'\s+'), '');
  return rows.isEmpty && compact != name ? query(compact) : rows;
}

String unescapeAddress(String input) {
  final unicode = input.replaceAllMapped(
    RegExp(r'%u([a-fA-F0-9]{4})'),
    (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
  );
  return Uri.decodeComponent(unicode);
}
