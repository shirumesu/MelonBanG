import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pinyin/pinyin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../json.dart';
import '../network.dart';
import '../resource_title.dart';
import '../resource_metadata.dart';
import 'builtin.dart';
import 'engine.dart';
export 'engine.dart' show onlineEngineVersion, SourceVerificationRequired;

class _SourceRead {
  final cancel = RequestCancellation();
  late Future<List<Json>> value;
  int users = 0;
}

class OnlineSourceRepository extends ChangeNotifier {
  OnlineSourceRepository(
    this.api,
    this.preferences, {
    this.origin = 'https://melonapi.konataizumi.com',
  });
  final ApiClient api;
  final SharedPreferences preferences;
  final String origin;
  final health = <String, String>{};
  final errors = <String, String>{};
  final results = <String, List<Json>>{};
  final _engines = <String, RuleOnlineSource>{};
  final _reads = <String, _SourceRead>{};
  final _cache = <String, ({DateTime expires, List<Json> rows})>{};
  Json snapshot = object(jsonDecode(builtinSourceRules));
  String ruleOrigin = '安装包内置';
  String? updateIssue;
  DateTime? checkedAt;
  bool _closed = false;
  Future<void>? _refreshing;
  List<Json> get rules => objects(snapshot['rules']);
  String get version => '${snapshot['version']}';
  bool get warning => health.entries.any(
    (e) =>
        isEnabled(e.key) &&
        ['error', 'verification', 'partial'].contains(e.value),
  );
  bool isEnabled(String id) =>
      preferences.getBool('source-enabled-$id') ?? true;
  bool usable(Json rule) =>
      isEnabled('${rule['id']}') &&
      rule['disabled'] != true &&
      number(rule['minEngine']) <= onlineEngineVersion &&
      health['${rule['id']}'] != 'verification';
  String status(String id) {
    final rule = rules.where((e) => e['id'] == id).firstOrNull;
    if (!isEnabled(id) || rule?['disabled'] == true) return 'disabled';
    if (rule != null && number(rule['minEngine']) > onlineEngineVersion) {
      return 'update';
    }
    return health[id] ?? 'unknown';
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await preferences.setBool('source-enabled-$id', enabled);
    if (enabled && health[id] == 'verification') health.remove(id);
    _clearReads();
    _notify();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  RuleOnlineSource source(String id) => _engines.putIfAbsent(
    id,
    () => RuleOnlineSource(api, rules.firstWhere((e) => e['id'] == id)),
  );
  String currentDomain(String id) =>
      _engines[id]?.currentBase ??
      '${array(rules.where((r) => r['id'] == id).firstOrNull?['baseUrls']).firstOrNull ?? ''}';

  Future<void> initialize() async {
    final cached = preferences.getString('online-source-rules');
    if (cached != null) {
      try {
        snapshot = _validate(jsonDecode(cached));
        ruleOrigin = '本地缓存';
      } catch (_) {
        /* Keep the bundled snapshot if the cache cannot be read. */
      }
    }
    unawaited(refreshRules().catchError((Object _) {}));
  }

  Json _validate(dynamic data) {
    final value = object(data);
    final rows = objects(value['rules']);
    if (value['version'] is! String || value['rules'] is! List) {
      throw const FormatException('规则格式无效');
    }
    for (final row in rows) {
      if (row['id'] is! String ||
          row['name'] is! String ||
          row['baseUrls'] is! List ||
          row['engine'] is! String) {
        throw const FormatException('来源规则不完整');
      }
    }
    return value;
  }

  Future<void> refreshRules() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<void> _refresh() async {
    try {
      final response = await api.send(
        Uri.parse('$origin/sources/rules?engine=$onlineEngineVersion'),
        headers: {
          'If-None-Match': ?preferences.getString('online-source-etag'),
        },
        acceptedStatuses: const {304},
      );
      if (_closed) return;
      if (response.statusCode == 304) {
        checkedAt = DateTime.now();
        updateIssue = null;
        _notify();
        return;
      }
      if (response.statusCode != 200) {
        throw ApiException(response.statusCode, Uri.parse(origin).host);
      }
      final value = _validate(jsonDecode(utf8.decode(response.bodyBytes)));
      await preferences.setString('online-source-rules', jsonEncode(value));
      final etag = response.headers['etag'];
      if (etag != null) {
        await preferences.setString('online-source-etag', etag);
      } else {
        await preferences.remove('online-source-etag');
      }
      snapshot = value;
      ruleOrigin = 'Melon API';
      checkedAt = DateTime.now();
      updateIssue = null;
      _engines.clear();
      _clearReads();
      _notify();
    } catch (error) {
      updateIssue = '规则更新失败，继续使用$ruleOrigin：$error';
      _notify();
      rethrow;
    }
  }

  Future<List<Json>> search(
    String id,
    Iterable<String> names, {
    bool refresh = false,
    RequestCancellation? cancel,
    bool Function(List<Json>)? enough,
  }) async {
    try {
      final rows = <String, Json>{};
      Object? failure;
      var succeeded = false;
      for (final name
          in names.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()) {
        cancel?.throwIfCancelled();
        final key = '$version:search:$id:$name';
        if (refresh) _cache.remove(key);
        try {
          final values = await _cachedRead(
            key,
            (token) => source(id).searchSubjects([name], cancel: token),
            cancel: cancel,
          );
          succeeded = true;
          for (final row in values) {
            rows['${row['id'] ?? row['url']}'] = row;
          }
          if (enough?.call(rows.values.toList()) == true) break;
        } on SourceVerificationRequired {
          rethrow;
        } catch (error) {
          cancel?.throwIfCancelled();
          failure = error;
        }
      }
      if (!succeeded && failure != null) throw failure;
      health[id] = 'ready';
      errors.remove(id);
      _notify();
      return rows.values.toList();
    } catch (error) {
      cancel?.throwIfCancelled();
      failed(id, error);
      rethrow;
    }
  }

  Future<List<Json>> episodes(
    String id,
    Json subject, {
    RequestCancellation? cancel,
  }) async {
    try {
      return await _cachedRead(
        '$version:episodes:$id:${subject['id'] ?? subject['url']}',
        (token) => source(id).episodes(subject, cancel: token),
        cancel: cancel,
      );
    } catch (error) {
      cancel?.throwIfCancelled();
      failed(id, error);
      rethrow;
    }
  }

  Future<List<Json>> _cachedRead(
    String key,
    Future<List<Json>> Function(RequestCancellation) load, {
    RequestCancellation? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final cached = _cache.remove(key);
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      _cache[key] = cached;
      return cached.rows;
    }
    var read = _reads[key];
    if (read == null || read.cancel.isCancelled) {
      final created = _SourceRead();
      read = created;
      _reads[key] = created;
      created.value = load(created.cancel)
          .then((rows) {
            created.cancel.throwIfCancelled();
            _cache[key] = (
              expires: DateTime.now().add(const Duration(minutes: 5)),
              rows: rows,
            );
            while (_cache.length > 64) {
              _cache.remove(_cache.keys.first);
            }
            return rows;
          })
          .whenComplete(() {
            if (identical(_reads[key], created)) _reads.remove(key);
          });
    }
    final active = read;
    active.users++;
    final cancelled = Completer<List<Json>>();
    final stop = cancel?.listen(() {
      if (!cancelled.isCompleted) {
        cancelled.completeError(const RequestCancelled());
      }
    });
    try {
      return await Future.any([
        active.value,
        if (cancel != null) cancelled.future,
      ]);
    } finally {
      stop?.call();
      active.users--;
      if (active.users == 0 && identical(_reads[key], active)) {
        active.cancel.cancel();
      }
    }
  }

  void _clearReads() {
    for (final read in _reads.values) {
      read.cancel.cancel();
    }
    _reads.clear();
    _cache.clear();
  }

  void failed(String id, Object error) {
    health[id] = error is SourceVerificationRequired ? 'verification' : 'error';
    errors[id] = '$error';
    _notify();
  }

  Future<List<Json>> candidates(
    Json subject,
    Json episode, {
    RequestCancellation? cancel,
    bool firstReady = false,
  }) async {
    final names = resourceNames(subject);
    final result = <Json>[];
    final operation = RequestCancellation();
    final stop = cancel?.listen(operation.cancel);
    final ready = Completer<List<Json>>();
    final all = Future.wait(
      rules.where(usable).map((rule) async {
        final id = '${rule['id']}';
        try {
          final matches = await search(
            id,
            names,
            cancel: operation,
            enough: firstReady
                ? (rows) => rows.any(
                    (site) => onlineMatchScore(subject, site, names) >= .84,
                  )
                : null,
          );
          for (final site in matches) {
            final score = onlineMatchScore(subject, site, names);
            if (score < .55) continue;
            final rows = await episodes(id, site, cancel: operation);
            for (final row in rows.where(
              (row) => onlineEpisodeMatches('${row['label']}', episode),
            )) {
              final title = '${site['title']} · ${row['label']}';
              final info = describeResource({'title': title});
              result.add({
                'kind': 'online',
                'sourceId': id,
                'provider': id,
                'providerId': id,
                'providerName': rule['name'],
                'line': row['line'],
                'title': title,
                'candidateId':
                    '$id:${site['id']}:${row['line']}:${row['label']}',
                'instant': true,
                'ref': row['ref'],
                'matchScore': score,
                'possibleMatch': score < .84,
                'languages': info.languages.toList(),
                'quality': info.quality,
                'health': status(id),
              });
            }
          }
          if (firstReady &&
              !ready.isCompleted &&
              result.any((row) => row['possibleMatch'] != true)) {
            ready.complete(List<Json>.of(result));
          }
        } catch (_) {
          /* Failed providers retain their health while others remain usable. */
        }
      }),
    ).then((_) => List<Json>.of(result));
    try {
      final rows = await (firstReady ? Future.any([ready.future, all]) : all);
      cancel?.throwIfCancelled();
      if (firstReady && !rows.any((row) => row['possibleMatch'] != true)) {
        return await candidates(subject, episode, cancel: cancel);
      }
      return rows;
    } finally {
      stop?.call();
      operation.cancel();
    }
  }

  Future<Json> resolve(Json candidate, {RequestCancellation? cancel}) async {
    cancel?.throwIfCancelled();
    final ref = object(candidate['ref']).isEmpty
        ? candidate
        : object(candidate['ref']);
    final id =
        '${ref['sourceId'] ?? candidate['sourceId'] ?? candidate['provider']}';
    if (!isEnabled(id)) throw StateError('视频源已停用');
    final rule = rules.firstWhere((e) => e['id'] == id);
    if (rule['disabled'] == true) throw StateError('维护者已停用该视频源');
    if (number(rule['minEngine']) > onlineEngineVersion) {
      throw StateError('该视频源需要更新应用');
    }
    try {
      final resolved = await source(id).resolve(ref, cancel: cancel);
      if (resolved['kind'] == 'hls' &&
          object(rule['playlistFilter'])['foreignPathBlocks'] == true) {
        final manifest = await playlist(
          Uri.parse('${resolved['url']}'),
          object(resolved['headers']).map((k, v) => MapEntry(k, '$v')),
          filter: true,
          cancel: cancel,
        );
        resolved['playlist'] = manifest.$1;
      }
      health[id] = 'ready';
      errors.remove(id);
      _notify();
      return resolved;
    } catch (error) {
      if (cancel?.isCancelled != true) failed(id, error);
      rethrow;
    }
  }

  Future<(String, Uri)> playlist(
    Uri uri,
    Map<String, String> headers, {
    bool filter = false,
    RequestCancellation? cancel,
  }) async {
    for (var depth = 0; depth < 4; depth++) {
      final response = await api.send(uri, headers: headers, cancel: cancel);
      final text = utf8.decode(response.bodyBytes);
      if (!text.trimLeft().startsWith('#EXTM3U')) {
        throw StateError('站点没有返回有效 m3u8');
      }
      final lines = text.split(RegExp(r'\r?\n'));
      if (lines.any((line) => line.startsWith('#EXT-X-STREAM-INF'))) {
        final next = lines
            .where((line) => line.trim().isNotEmpty && !line.startsWith('#'))
            .firstOrNull;
        if (next == null) throw StateError('主清单没有播放线路');
        uri = uri.resolve(next.trim());
        continue;
      }
      final rendered = filter
          ? filterPlaylist(text, uri)
          : absolutePlaylist(text, uri);
      return (rendered, uri);
    }
    throw StateError('m3u8 清单嵌套层数过多');
  }

  Future<void> probe(String id, {Future<void> Function()? external}) async {
    final steps = <Json>[];
    results[id] = steps;
    _notify();
    Future<T> step<T>(
      String label,
      Future<T> Function() action, {
      String? url,
    }) async {
      final clock = Stopwatch()..start();
      final row = <String, dynamic>{
        'label': label,
        'status': 'loading',
        'url': url,
      };
      steps.add(row);
      _notify();
      try {
        final value = await action();
        row.addAll({
          'status': 'ready',
          'milliseconds': clock.elapsedMilliseconds,
          if (external == null && ['搜索', '取集数', '解析地址'].contains(label))
            'url': source(id).lastRequest?.toString(),
          if (external == null && ['搜索', '取集数', '解析地址'].contains(label))
            'statusCode': source(id).lastStatus,
        });
        _notify();
        return value;
      } catch (error) {
        row.addAll({
          'status': 'error',
          'milliseconds': clock.elapsedMilliseconds,
          'error': '$error',
          if (external == null && ['搜索', '取集数', '解析地址'].contains(label))
            'url': source(id).lastRequest?.toString(),
          if (external == null && source(id).lastStatus != null)
            'statusCode': source(id).lastStatus,
          if (error is ApiException) 'statusCode': error.status,
        });
        _notify();
        rethrow;
      }
    }

    try {
      if (external != null) {
        await step(id == 'pikpak' ? '读取网盘' : '搜索 RSS', external);
      } else {
        final rule = rules.firstWhere((e) => e['id'] == id);
        if (number(rule['minEngine']) > onlineEngineVersion) {
          throw StateError('需要更新应用');
        }
        final rows = await step(
          '搜索',
          () =>
              search(id, ['${object(rule['test'])['subject']}'], refresh: true),
          url: '${currentDomain(id)}${object(rule['search'])['url']}',
        );
        if (rows.isEmpty) throw StateError('搜索没有结果');
        var site = rows.first;
        final expected = '${object(rule['test'])['subject']}';
        site =
            rows
                .where(
                  (r) =>
                      normalizeOnlineTitle('${r['title']}').$1 ==
                          normalizeOnlineTitle(expected).$1 &&
                      normalizeOnlineTitle('${r['title']}').$2 ==
                          normalizeOnlineTitle(expected).$2,
                )
                .firstOrNull ??
            site;
        final entries = await step('取集数', () async {
          final entries = await episodes(id, site);
          if (entries.length < number(object(rule['test'])['minEpisodes'])) {
            throw StateError('返回集数少于规则预期');
          }
          return entries;
        }, url: '${currentDomain(id)}${object(rule['detail'])['url']}');
        final resolved = await step(
          '解析地址',
          () => source(id).resolve(object(entries.first['ref'])),
        );
        steps.last['url'] = resolved['url'];
        if (resolved['kind'] == 'hls') {
          final headers = object(resolved['headers'])
              .map((k, v) => MapEntry(k, '$v'));
          final manifest = await step(
            '拉取 m3u8',
            () => playlist(
              Uri.parse('${resolved['url']}'),
              headers,
              filter:
                  object(rule['playlistFilter'])['foreignPathBlocks'] == true,
            ),
            url: '${resolved['url']}',
          );
          final segment = manifest.$1
              .split('\n')
              .where((line) => line.isNotEmpty && !line.startsWith('#'))
              .firstOrNull;
          if (segment == null) throw StateError('播放清单没有分片');
          await step('拉取第一个分片', () async {
            final response = await api.send(
              Uri.parse(segment),
              headers: headers,
            );
            if (response.bodyBytes.isEmpty) throw StateError('分片为空');
          }, url: segment);
        } else {
          await step(
            '读取视频',
            () => api.send(
              Uri.parse('${resolved['url']}'),
              headers: {'Range': 'bytes=0-4095'},
            ),
            url: '${resolved['url']}',
          );
        }
      }
      health[id] = 'ready';
      errors.remove(id);
    } catch (error) {
      errors[id] = '$error';
      health[id] = error is SourceVerificationRequired
          ? 'verification'
          : steps.any((row) => row['status'] == 'ready')
          ? 'partial'
          : 'error';
      if (steps.isEmpty || steps.last['status'] == 'ready') {
        steps.add({'label': '验证结果', 'status': 'error', 'error': '$error'});
      }
    }
    _notify();
  }

  @override
  void dispose() {
    _clearReads();
    _closed = true;
    super.dispose();
  }
}

(String, int) normalizeOnlineTitle(String input) {
  var title = ChineseHelper.convertToSimplifiedChinese(
    String.fromCharCodes(
      input.runes.map(
        (c) => c == 0x3000
            ? 32
            : c >= 0xff01 && c <= 0xff5e
            ? c - 0xfee0
            : c,
      ),
    ),
  ).toLowerCase();
  final season = RegExp(
    r'第\s*([一二三四五六七八九十\d]+)\s*[季期]|season\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(title);
  final raw = season?[1] ?? season?[2] ?? '1';
  final number =
      int.tryParse(raw) ??
      ({
            '一': 1,
            '二': 2,
            '三': 3,
            '四': 4,
            '五': 5,
            '六': 6,
            '七': 7,
            '八': 8,
            '九': 9,
            '十': 10,
          }[raw] ??
          1);
  if (season != null) title = title.replaceRange(season.start, season.end, '');
  return (
    title.replaceAll(RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff]'), ''),
    number,
  );
}

double onlineMatchScore(Json subject, Json site, Iterable<String> names) {
  final target = normalizeOnlineTitle('${site['title']}');
  var best = 0.0;
  for (final name in names) {
    final expected = normalizeOnlineTitle(name);
    double dice(String a, String b) {
      if (a == b) return 1;
      if (a.length < 2 || b.length < 2) return 0;
      final left = <String>{
        for (var i = 0; i < a.length - 1; i++) a.substring(i, i + 2),
      };
      final right = <String>{
        for (var i = 0; i < b.length - 1; i++) b.substring(i, i + 2),
      };
      return 2 * left.intersection(right).length / (left.length + right.length);
    }

    final score =
        dice(expected.$1, target.$1) - (expected.$2 != target.$2 ? .4 : 0);
    if (score > best) best = score;
  }
  final year = int.tryParse('${subject['airDate'] ?? ''}'.split('-').first);
  if (year != null && site['year'] != null) {
    best += year == site['year'] ? .03 : -.12;
  }
  final count = int.tryParse('${site['episodeTotal'] ?? ''}');
  if (count != null && (count - number(subject['episodeTotal'])).abs() <= 2) {
    best += .02;
  }
  return best.clamp(0, 1);
}

bool onlineEpisodeMatches(String label, Json episode) {
  final normalized = ChineseHelper.convertToSimplifiedChinese(label)
      .toUpperCase();
  final special = RegExp(r'SP|OVA|OAD|特别').hasMatch(normalized);
  final main =
      episode['type'] == 'main' ||
      episode['type'] == 0 ||
      episode['type'] == null;
  if (special == main) return false;
  final parsed = describeResource({'title': '[$normalized]'}).episodeLabel;
  final match = RegExp(r'(?:第|EP\s*|SP\s*|OVA\s*|OAD\s*)?(\d+(?:\.\d+)?)')
      .firstMatch(normalized);
  if (match == null) {
    return !main && number(episode['sort']) == 1 && parsed != null;
  }
  return double.tryParse(match[1]!) == number(episode['sort']);
}

String absolutePlaylist(String text, Uri base) => text
    .split(RegExp(r'\r?\n'))
    .map((line) {
      if (line.isNotEmpty && !line.startsWith('#')) {
        return base.resolve(line.trim()).toString();
      }
      return line.replaceAllMapped(
        RegExp('URI="([^"]+)"'),
        (match) => 'URI="${base.resolve(match[1]!)}"',
      );
    })
    .join('\n');
String filterPlaylist(String text, Uri base) {
  final blocks = text.split('#EXT-X-DISCONTINUITY');
  final directory = base.resolve('.').path;
  final kept = <String>[];
  for (final block in blocks) {
    final segments = block
        .split(RegExp(r'\r?\n'))
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .map((line) => base.resolve(line.trim()))
        .toList();
    // Content segments may use a separate CDN host from the playlist.
    if (segments.isEmpty ||
        segments.every((segment) => segment.path.startsWith(directory))) {
      kept.add(block.replaceAll('#EXT-X-ENDLIST', '').trim());
    }
  }
  final result = kept.join('\n#EXT-X-DISCONTINUITY\n');
  if (!result.contains('#EXTM3U')) throw StateError('过滤后没有正片清单');
  return absolutePlaylist(
    '$result\n${text.contains('#EXT-X-ENDLIST') ? '#EXT-X-ENDLIST\n' : ''}',
    base,
  );
}
