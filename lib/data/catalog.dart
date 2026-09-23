import 'dart:async';

import 'json.dart';
import 'network.dart';
import 'store.dart';

class CatalogRepository {
  CatalogRepository(
    this.api,
    this.store, {
    this.origin = 'https://melonapi.konataizumi.com',
  });
  final ApiClient api;
  final AppStore store;
  final String origin;
  final _requests = <String, Future<dynamic>>{};
  bool _closed = false;
  final coverChanges = StreamController<int>.broadcast();
  final _covers = <int, String>{};
  final _coverRequests = <int, Future<void>>{};
  String? coverFor(int id) => _covers[id];

  void _rememberCover(Json value) {
    final id = number(value['subjectId'] ?? value['id']).toInt();
    final cover = coverAddress(value['coverUrl']);
    if (_closed || id <= 0 || cover == null || _covers[id] == cover) return;
    _covers[id] = cover;
    coverChanges.add(id);
  }

  // Reuse local detail artwork without making a full-detail request per card.
  Future<void> resolveCover(int id) {
    if (_closed || id <= 0 || _covers.containsKey(id)) return Future.value();
    return _coverRequests.putIfAbsent(id, () async {
      try {
        final cached = await store.get('catalog', 'detail:$id');
        if (!_closed && cached != null && !_covers.containsKey(id)) {
          _rememberCover(object(object(cached['value'])['data']));
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
  }) async {
    if (_closed) throw StateError('番剧服务已关闭');
    final cached = await store.get('catalog', key);
    if (_closed) throw StateError('番剧服务已关闭');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!refresh &&
        onCached == null &&
        cached != null &&
        now - number(cached['savedAt']) < ttl.inMilliseconds &&
        _serverFresh(cached['value'], now)) {
      return cached['value'];
    }
    if (cached != null && onCached != null) await onCached(cached['value']);
    try {
      return await _requests.putIfAbsent(key, () async {
        try {
          final value = await api.json(Uri.parse('$origin$path'));
          if (_closed) throw StateError('番剧服务已关闭');
          await store.put('catalog', key, {
            'value': value,
            'savedAt': DateTime.now().millisecondsSinceEpoch,
          });
          return value;
        } finally {
          _requests.remove(key);
        }
      });
    } catch (_) {
      if (!refresh && cached != null) return cached['value'];
      rethrow;
    }
  }

  bool _serverFresh(dynamic value, int now) {
    final cache = object(object(value)['cache']);
    if (cache['stale'] == true) return false;
    final expiresAt = DateTime.tryParse('${cache['expiresAt'] ?? ''}');
    return expiresAt == null || expiresAt.millisecondsSinceEpoch > now;
  }

  Json summary(Json value) {
    final result = <String, dynamic>{
      ...value,
      'subjectId': value['subjectId'] ?? value['id'],
      'nameCn': value['nameCn'] ?? value['displayName'],
      'score': value['score'] ?? object(value['rating'])['score'],
    };
    _rememberCover(result);
    return result;
  }

  Future<List<Json>> search(
    String keyword, {
    void Function(List<Json>)? onCached,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) return [];
    final response = object(
      await _cached(
        'search:${query.toLowerCase()}',
        '/v1/subjects/search?q=${Uri.encodeQueryComponent(query)}&limit=20&offset=0',
        onCached: onCached == null
            ? null
            : (value) => onCached(
                objects(object(value)['data']).map(summary).toList(),
              ),
      ),
    );
    return objects(response['data']).map(summary).toList();
  }

  Future<List<Json>> trending({
    bool refresh = false,
    int? limit,
    void Function(List<Json>)? onCached,
  }) async {
    if (limit != null && limit <= 0) return [];
    final pageSize = limit == null ? 50 : limit.clamp(1, 50);
    List<Json> valuesFrom(dynamic value) {
      final values = objects(object(value)['data']).map(summary);
      return (limit == null ? values : values.take(limit)).toList();
    }

    final items = <Json>[];
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
      items.addAll(values.map(summary));
      if (limit != null && items.length >= limit) {
        return items.take(limit).toList();
      }
      if (page['hasMore'] != true || values.isEmpty) break;
      offset += values.length;
    }
    return items;
  }

  // The schedule API defines its day in Asia/Shanghai, independent of the host.
  String get scheduleDate => DateTime.now()
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .substring(0, 10);

  Json _today(dynamic value) {
    final response = object(value);
    return {
      'date': response['date'],
      'items': objects(response['items'])
          .where((item) => number(item['subjectId']) > 0)
          .map(summary)
          .toList(),
    };
  }

  Future<Json> today({
    bool refresh = false,
    void Function(Json)? onCached,
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

  Future<List<Json>> calendar({void Function(List<Json>)? onCached}) async {
    final response = object(
      await _cached(
        'week:$scheduleDate',
        '/v1/schedule/latest?days=7',
        ttl: const Duration(hours: 1),
        onCached: onCached == null
            ? null
            : (value) => onCached(_calendar(value)),
      ),
    );
    return _calendar(response);
  }

  List<Json> _calendar(dynamic value) {
    final response = object(value);
    final byDate = object(response['byDate']);
    final dates = byDate.keys.toList()..sort();
    const labels = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return dates.map((date) {
      final day = DateTime.parse(date).weekday;
      return {
        'date': date,
        'weekday': {'id': day, 'cn': labels[day - 1]},
        'items': objects(byDate[date])
            .where((item) => number(item['subjectId']) > 0)
            .map(summary)
            .toList(),
      };
    }).toList();
  }

  Future<Json> subject(
    int id, {
    FutureOr<void> Function(Json)? onCached,
  }) async {
    if (id <= 0) throw const FormatException('番剧编号无效');
    // Detail and list caches have distinct keys; a search cannot erase detail.
    final response = object(
      await _cached(
        'detail:$id',
        '/v1/subjects/$id?includeHtml=false',
        ttl: const Duration(hours: 1),
        onCached: onCached == null
            ? null
            : (value) => onCached(_subject(id, value)),
      ),
    );
    return _subject(id, response);
  }

  Json _subject(int id, dynamic value) {
    final data = summary(object(object(value)['data']));
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
