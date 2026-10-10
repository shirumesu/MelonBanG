import 'dart:async';

import '../../domain/catalog.dart';
import '../../core/content_cache.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../../core/store.dart';

/// The locally cached full or playback detail of a subject, without a request.
Future<Json?> cachedSubjectDetail(AppStore store, int id) async {
  final cached =
      await store.get('catalog', 'detail:$id') ??
      await store.get('catalog', 'playback-detail:$id');
  return cached == null ? null : object(object(cached['value'])['data']);
}

class CatalogRepository implements Catalog {
  CatalogRepository(
    this.api,
    this.store,
    this.cache, {
    this.origin = 'https://melonapi.konataizumi.com',
  });
  final ApiClient api;
  final AppStore store;
  final ContentCache cache;
  final String origin;
  final _requests = <String, Future<dynamic>>{};
  bool _closed = false;
  final coverChanges = StreamController<int>.broadcast();
  final _covers = <int, String>{};
  final _coverRequests = <int, Future<void>>{};
  @override
  String? coverFor(int id) => _covers[id];
  @override
  Stream<int> get coverUpdates => coverChanges.stream;

  void _rememberCover(Json value) {
    final id = number(value['subjectId'] ?? value['id']).toInt();
    final cover = coverAddress(value['coverUrl']);
    if (_closed || id <= 0 || cover == null || _covers[id] == cover) return;
    _covers[id] = cover;
    coverChanges.add(id);
  }

  // Reuse local detail artwork without making a full-detail request per card.
  @override
  Future<void> resolveCover(int id) {
    if (_closed || id <= 0 || _covers.containsKey(id)) return Future.value();
    return _coverRequests.putIfAbsent(id, () async {
      try {
        final cached = await cachedSubjectDetail(store, id);
        if (!_closed && cached != null && !_covers.containsKey(id)) {
          _rememberCover(cached);
        }
      } finally {
        _coverRequests.remove(id);
      }
    });
  }

  Future<dynamic> _cached(
    String key,
    String path, {
    Duration ttl = const Duration(minutes: 5),
    bool refresh = false,
    FutureOr<void> Function(dynamic)? onCached,
    Future<({dynamic value, String? etag})> Function(Json? cached)? load,
  }) async {
    if (_closed) throw StateError('番剧服务已关闭');
    final generation = cache.generation;
    final cached = await store.get('catalog', key);
    if (_closed) throw StateError('番剧服务已关闭');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cached != null && onCached != null) await onCached(cached['value']);
    if (!refresh &&
        cached != null &&
        now - number(cached['savedAt']) < ttl.inMilliseconds &&
        _serverFresh(cached['value'], now)) {
      return cached['value'];
    }
    try {
      return await _requests.putIfAbsent(key, () async {
        try {
          final result = await (load == null
              ? _read(Uri.parse('$origin$path'), cached)
              : load(cached));
          if (_closed) throw StateError('番剧服务已关闭');
          if (generation == cache.generation) {
            await store.put('catalog', key, {
              'value': result.value,
              'etag': result.etag,
              'savedAt': DateTime.now().millisecondsSinceEpoch,
            });
          }
          return result.value;
        } finally {
          _requests.remove(key);
        }
      });
    } catch (_) {
      if (!refresh && cached != null) return cached['value'];
      rethrow;
    }
  }

  Future<({dynamic value, String? etag})> _read(Uri uri, Json? cached) async {
    final response = await api.send(
      uri,
      headers: {'If-None-Match': ?cached?['etag'] as String?},
      acceptedStatuses: const {304},
    );
    return (
      value: response.statusCode == 304
          ? _revalidated(cached, response.headers)
          : await decodeJsonBytes(response.bodyBytes),
      etag: response.headers['etag'] ?? cached?['etag'] as String?,
    );
  }

  dynamic _revalidated(Json? cached, Map<String, String> headers) {
    if (cached == null) throw const FormatException('缓存响应缺少本地内容');
    final value = object(cached['value']);
    return {
      ...value,
      'cache': {
        ...object(value['cache']),
        'expiresAt': ?headers['x-cache-expires-at'],
        'stale': headers['x-cache-stale'] == 'true',
      },
    };
  }

  bool _serverFresh(dynamic value, int now) {
    if (object(object(object(value)['data'])['source'])['notes']
        case final List notes when notes.isNotEmpty) {
      return false;
    }
    final cache = object(object(value)['cache']);
    if (cache['stale'] == true) return false;
    final expiresAt = DateTime.tryParse('${cache['expiresAt'] ?? ''}');
    return expiresAt == null || expiresAt.millisecondsSinceEpoch > now;
  }

  Json _summary(Json value) {
    final result = <String, dynamic>{
      ...value,
      'subjectId': value['subjectId'] ?? value['id'],
      'nameCn': value['nameCn'] ?? value['displayName'],
      'score': value['score'] ?? object(value['rating'])['score'],
    };
    _rememberCover(result);
    return result;
  }

  @override
  Subject card(Json value) => Subject.fromJson(_summary(value));

  @override
  Future<Subject?> cached(int id) async {
    final detail = await cachedSubjectDetail(store, id);
    return detail == null ? null : card(detail);
  }

  @override
  Future<SubjectResults> search(
    String keyword, {
    int offset = 0,
    void Function(SubjectResults)? onCached,
  }) async {
    final query = keyword.trim();
    SubjectResults page(dynamic value) {
      final response = object(value);
      final items = objects(response['data']).map(card).toList();
      return SubjectResults(
        items: items,
        offset: (response['offset'] as num).toInt() + items.length,
        total: (response['total'] as num).toInt(),
        hasMore: response['hasMore'] as bool,
      );
    }

    final response = object(
      await _cached(
        'search:${query.toLowerCase()}:10:$offset',
        '/v1/subjects/search?q=${Uri.encodeQueryComponent(query)}&limit=10&offset=$offset',
        onCached: onCached == null ? null : (value) => onCached(page(value)),
      ),
    );
    return page(response);
  }

  @override
  Future<List<Subject>> trending({
    bool refresh = false,
    int? limit,
    void Function(List<Subject>)? onCached,
  }) async {
    if (limit != null && limit <= 0) return [];
    final pageSize = limit == null ? 50 : limit.clamp(1, 50);
    List<Subject> valuesFrom(dynamic value) {
      final values = objects(object(value)['data']).map(card);
      return (limit == null ? values : values.take(limit)).toList();
    }

    final items = <Subject>[];
    for (var offset = 0; ;) {
      final page = object(
        await _cached(
          'trending:$pageSize:$offset',
          '/v1/trending/current?limit=$pageSize&offset=$offset',
          refresh: refresh,
          ttl: const Duration(hours: 1),
          onCached: offset == 0 && onCached != null
              ? (value) => onCached(valuesFrom(value))
              : null,
        ),
      );
      final values = objects(page['data']);
      items.addAll(values.map(card));
      if (limit != null && items.length >= limit) {
        return items.take(limit).toList();
      }
      if (page['hasMore'] != true || values.isEmpty) break;
      offset += values.length;
    }
    return items;
  }

  // The schedule API defines its day in Asia/Shanghai, independent of the host.
  @override
  String get scheduleDate => DateTime.now()
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .substring(0, 10);

  SchedulePage _today(dynamic value) {
    final response = object(value);
    return SchedulePage(
      date: response['date'] as String?,
      items: objects(response['items'])
          .where((item) => number(item['subjectId']) > 0)
          .map(card)
          .toList(),
    );
  }

  @override
  Future<SchedulePage> today({
    bool refresh = false,
    void Function(SchedulePage)? onCached,
  }) async {
    final response = object(
      await _cached(
        'today:$scheduleDate',
        '/v1/schedule/today',
        refresh: refresh,
        ttl: const Duration(minutes: 15),
        onCached: onCached == null ? null : (value) => onCached(_today(value)),
      ),
    );
    return _today(response);
  }

  @override
  Future<List<ScheduleDay>> calendar({
    void Function(List<ScheduleDay>)? onCached,
  }) async {
    final response = object(
      await _cached(
        'week-forward:$scheduleDate',
        '/v1/schedule/latest?startDate=$scheduleDate&dayCount=7&view=byDate',
        ttl: const Duration(hours: 1),
        onCached: onCached == null
            ? null
            : (value) => onCached(_calendar(value)),
      ),
    );
    return _calendar(response);
  }

  List<ScheduleDay> _calendar(dynamic value) {
    final response = object(value);
    final byDate = object(response['byDate']);
    final start = DateTime.parse('${scheduleDate}T00:00:00Z');
    final dates = List.generate(
      7,
      (index) =>
          start.add(Duration(days: index)).toIso8601String().substring(0, 10),
    );
    const labels = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return dates.map((date) {
      final day = DateTime.parse(date).weekday;
      return ScheduleDay(
        date: date,
        weekday: labels[day - 1],
        items: objects(byDate[date])
            .where((item) => number(item['subjectId']) > 0)
            .map(card)
            .toList(),
      );
    }).toList();
  }

  @override
  Future<Subject> subject(
    int id, {
    FutureOr<void> Function(Subject)? onAvailable,
    bool forPlayback = false,
  }) async {
    if (id <= 0) throw const FormatException('番剧编号无效');
    // Detail and list caches have distinct keys; a search cannot erase detail.
    Json? available;
    final path =
        '/v1/subjects/$id?includeHtml=false&streamVersion=2'
        '&view=${forPlayback ? 'playback' : 'full'}';
    final uri = Uri.parse('$origin$path');
    final response = object(
      await _cached(
        forPlayback ? 'playback-detail:$id' : 'detail:$id',
        path,
        ttl: const Duration(hours: 1),
        onCached: onAvailable == null
            ? null
            : (value) async {
                available = object(object(value)['data']);
                await onAvailable(_subject(id, value));
              },
        load: (cached) async {
          var headers = <String, String>{};
          await for (final message in api.ndjson(
            uri,
            headers: {'If-None-Match': ?cached?['etag'] as String?},
            onHeaders: (value) => headers = value,
          )) {
            switch (message['type']) {
              case 'snapshot':
              case 'patch':
                final pending = message['pending'] as List<dynamic>? ?? [];
                final append = (message['append'] as List?) ?? const [];
                available = message['type'] == 'snapshot'
                    ? {...object(message['data'])}
                    : {...?available};
                for (final entry in object(message['data']).entries) {
                  if (append.contains(entry.key)) {
                    final previous = available![entry.key] as List? ?? const [];
                    available![entry.key] = [
                      ...previous,
                      ...entry.value as List,
                    ];
                  } else if (!pending.contains(entry.key)) {
                    available![entry.key] = entry.value;
                  }
                }
                if (onAvailable != null) {
                  await onAvailable(
                    Subject.fromJson({
                      ..._subjectJson(id, {'data': available}),
                      '_pending': pending,
                    }),
                  );
                }
              case 'complete':
                final data = message['data'] ?? available;
                if (data == null) throw const FormatException('番剧详情响应缺少内容');
                return (
                  value: {'data': data, 'cache': message['cache']},
                  etag:
                      headers['etag'] ??
                      object(message['cache'])['etag'] as String?,
                );
              case 'notModified':
                return (
                  value: _revalidated(cached, headers),
                  etag: headers['etag'] ?? cached?['etag'] as String?,
                );
              case 'error':
                throw StateError(
                  '番剧详情加载失败：${object(message['error'])['message']}',
                );
            }
          }
          throw const FormatException('番剧详情响应未完整接收');
        },
      ),
    );
    return _subject(id, response);
  }

  Subject _subject(int id, dynamic value) =>
      Subject.fromJson(_subjectJson(id, value));

  Json _subjectJson(int id, dynamic value) {
    final data = _summary(object(object(value)['data']));
    data['episodes'] = objects(data['episodes'])
        .where((e) => e['type'] == null || e['type'] == 'main')
        .map(
          (e) => {
            ...e,
            'subjectId': id,
            'nameCn': e['nameCn'] ?? e['displayName'],
            'sort': e['ep'] ?? e['sort'],
            'status': 'unwatched',
          },
        )
        .toList();
    return data;
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(_coverRequests.values.toList());
    await Future.wait(
      _requests.values.toList().map((request) async {
        try {
          await request;
        } catch (_) {
          /* Request callers receive failures. */
        }
      }),
    );
    await coverChanges.close();
  }
}
