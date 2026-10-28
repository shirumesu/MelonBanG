import 'dart:async';

import '../domain/catalog.dart';
import '../core/content_cache.dart';
import '../core/json.dart';
import '../core/network.dart';
import '../core/store.dart';
import 'bangumi/subjects.dart';
import 'melon_api/source_rules.dart' show melonApiOrigin;

/// The locally cached full or playback detail of a subject, without a request.
Future<Json?> cachedSubjectDetail(AppStore store, int id) async {
  final cached =
      await store.get('catalog', 'detail:$id') ??
      await store.get('catalog', 'playback-detail:$id');
  return cached == null ? null : object(object(cached['value'])['data']);
}

typedef _Load = Future<({dynamic value, String? etag})> Function(Json? cached);

/// Public catalogue reads with a local cache. Subject search, details and
/// covers come directly from Bangumi; Melon API supplies only the shared
/// season index, broadcast schedule and regional aliases.
class CatalogRepository implements Catalog {
  CatalogRepository(this.api, this.store, this.cache)
    : bangumi = BangumiSubjects(api);
  final ApiClient api;
  final AppStore store;
  final ContentCache cache;
  final BangumiSubjects bangumi;

  final _requests = <String, Future<dynamic>>{};
  bool _closed = false;
  final _coverChanges = StreamController<int>.broadcast();
  final _covers = <int, String>{};
  final _coverRequests = <int, Future<void>>{};
  @override
  String? coverFor(int id) => _covers[id];
  @override
  Stream<int> get coverUpdates => _coverChanges.stream;

  void _rememberCover(Json value) {
    final id = number(value['subjectId'] ?? value['id']).toInt();
    final cover = coverAddress(value['coverUrl']);
    if (_closed || id <= 0 || cover == null || _covers[id] == cover) return;
    _covers[id] = cover;
    _coverChanges.add(id);
  }

  // Reuse local detail artwork, then request only basic metadata for missing
  // covers instead of loading episodes, staff and other full-detail sections.
  @override
  Future<void> resolveCover(int id) {
    if (_closed || id <= 0 || _covers.containsKey(id)) return Future.value();
    return _coverRequests.putIfAbsent(id, () async {
      try {
        final cached = await cachedSubjectDetail(store, id);
        if (!_closed && cached != null && !_covers.containsKey(id)) {
          _rememberCover(cached);
        }
        if (!_closed && !_covers.containsKey(id)) {
          final response = await _cached(
            'basic-detail:$id',
            (_) async =>
                (value: {'data': await bangumi.subject(id)}, etag: null),
            refresh: true,
          );
          _rememberCover(object(object(response)['data']));
        }
      } finally {
        _coverRequests.remove(id);
      }
    });
  }

  Future<dynamic> _cached(
    String key,
    _Load load, {
    Duration ttl = const Duration(minutes: 5),
    bool refresh = false,
    FutureOr<void> Function(dynamic)? onCached,
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
          final result = await load(cached);
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

  /// A conditional Melon API read.
  _Load _melon(String path) => (cached) async {
    final response = await api.send(
      Uri.parse('$melonApiOrigin$path'),
      headers: {'If-None-Match': ?cached?['etag'] as String?},
      acceptedStatuses: const {304},
    );
    return (
      value: response.statusCode == 304
          ? _revalidated(cached, response.headers)
          : await decodeJsonBytes(response.bodyBytes),
      etag: response.headers['etag'] ?? cached?['etag'] as String?,
    );
  };

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
    final cache = object(object(value)['cache']);
    if (cache['stale'] == true) return false;
    final expiresAt = DateTime.tryParse('${cache['expiresAt'] ?? ''}');
    return expiresAt == null || expiresAt.millisecondsSinceEpoch > now;
  }

  @override
  Subject card(Json value) {
    _rememberCover(value);
    return Subject.fromJson(value);
  }

  @override
  Future<Subject?> cached(int id) async {
    final detail = await cachedSubjectDetail(store, id);
    return detail == null ? null : card(detail);
  }

  @override
  Future<SubjectResults> search(
    SubjectQuery query, {
    int offset = 0,
    void Function(SubjectResults)? onCached,
  }) async {
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
        'search:${query.key}:10:$offset',
        (_) async => (
          value: await bangumi.search(query, limit: 10, offset: offset),
          etag: null,
        ),
        onCached: onCached == null ? null : (value) => onCached(page(value)),
      ),
    );
    return page(response);
  }

  @override
  Future<List<Subject>> trending({
    required int limit,
    bool refresh = false,
    void Function(List<Subject>)? onCached,
  }) async {
    List<Subject> valuesFrom(dynamic value) =>
        objects(object(value)['data']).map(card).take(limit).toList();
    return valuesFrom(
      await _cached(
        'trending:$limit:0',
        _melon('/v1/trending/current?limit=$limit&offset=0'),
        refresh: refresh,
        ttl: const Duration(hours: 1),
        onCached: onCached == null
            ? null
            : (value) => onCached(valuesFrom(value)),
      ),
    );
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
        _melon('/v1/schedule/today'),
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
        _melon(
          '/v1/schedule/latest?startDate=$scheduleDate&dayCount=7&view=byDate',
        ),
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
  Future<CreditProfile> credit(int id, {required bool character}) =>
      bangumi.credit(id, character: character);

  @override
  Future<Subject> subject(
    int id, {
    FutureOr<void> Function(Subject)? onAvailable,
    bool forPlayback = false,
  }) async {
    // Detail and list caches have distinct keys; a search cannot erase detail.
    // A saved detail stays shown while it refreshes and is replaced whole,
    // rather than by a partial one whose sections load again.
    final response = object(
      await _cached(
        forPlayback ? 'playback-detail:$id' : 'detail:$id',
        (cached) async => (
          value: {
            'data': await _detail(
              id,
              forPlayback,
              cached == null ? onAvailable : null,
            ),
          },
          etag: null,
        ),
        ttl: const Duration(hours: 1),
        onCached: onAvailable == null
            ? null
            : (value) => onAvailable(_subject(id, value)),
      ),
    );
    return _subject(id, response);
  }

  /// Requests the detail parts concurrently and publishes each one as it
  /// arrives; until the base metadata does, `base` stays pending and the
  /// page shows the parts on the card it opened from. A failed part fails
  /// the detail after the others settle and stays pending in the last
  /// published value.
  Future<Json> _detail(
    int id,
    bool forPlayback,
    FutureOr<void> Function(Subject)? onAvailable,
  ) async {
    Json? base;
    final parts = <String, dynamic>{};
    final pending = {
      'episodes',
      'aliases',
      if (!forPlayback) ...['characters', 'staff'],
    };
    var published = Future<void>.value();
    void publish() {
      if (onAvailable == null) return;
      final value = Subject.fromJson({
        ..._subjectJson(id, {
          'data': {...?base, ...parts},
        }),
        'subjectId': id,
        '_pending': [...pending, if (base == null) 'base'],
      });
      published = published.then((_) => onAvailable(value));
    }

    Future<void> part(String name, Future<void> Function() load) async {
      await load();
      pending.remove(name);
      publish();
    }

    try {
      await Future.wait([
        bangumi.subject(id).then((value) {
          base = value;
          publish();
        }),
        part('episodes', () async {
          await for (final page in bangumi.episodes(id)) {
            // Specials arrive last and take their place in broadcast order;
            // undated ones follow the run, all by Bangumi's number.
            double order(Object? value) {
              final e = object(value);
              return e['type'] != 'special'
                  ? number(e['absolute']).toDouble()
                  : e['order'] == null
                  ? double.infinity
                  : number(e['order']).toDouble();
            }

            parts['episodes'] = [...?parts['episodes'] as List?, ...page]
              ..sort((a, b) {
                final placed = order(a).compareTo(order(b));
                return placed != 0
                    ? placed
                    : number(object(a)['absolute'])
                          .compareTo(number(object(b)['absolute']));
              });
            publish();
          }
        }),
        part('aliases', () async {
          final response = await api.json(
            Uri.parse('$melonApiOrigin/v1/subjects/$id/aliases'),
          );
          parts['aliases'] = object(response)['data'];
        }),
        if (!forPlayback) ...[
          part('characters', () async {
            parts['characters'] = await bangumi.characters(id);
          }),
          part('staff', () async {
            parts['staff'] = await bangumi.persons(id);
          }),
        ],
      ]);
    } finally {
      await published;
    }
    return {...base!, ...parts};
  }

  Subject _subject(int id, dynamic value) =>
      Subject.fromJson(_subjectJson(id, value));

  Json _subjectJson(int id, dynamic value) {
    final data = object(object(value)['data']);
    _rememberCover(data);
    data['episodes'] = objects(data['episodes'])
        .where((e) => const [null, 'main', 'special'].contains(e['type']))
        .map((e) => {...e, 'subjectId': id, 'status': 'unwatched'})
        .toList();
    return data;
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(
      [..._coverRequests.values, ..._requests.values].map((request) async {
        try {
          await request;
        } catch (_) {
          /* Request callers receive failures. */
        }
      }),
    );
    await _coverChanges.close();
  }
}
