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
  Future<dynamic> _cached(
    String key,
    String path, {
    Duration ttl = const Duration(minutes: 5),
  }) async {
    final cached = await store.get('catalog', key);
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - number(cached['savedAt']) <
            ttl.inMilliseconds) {
      return cached['value'];
    }
    return _requests.putIfAbsent(key, () async {
      try {
        final value = await api.json(Uri.parse('$origin$path'));
        await store.put('catalog', key, {
          'value': value,
          'savedAt': DateTime.now().millisecondsSinceEpoch,
        });
        return value;
      } catch (_) {
        if (cached != null) return cached['value'];
        rethrow;
      } finally {
        _requests.remove(key);
      }
    });
  }

  Json summary(Json value) => {
    ...value,
    'subjectId': value['subjectId'] ?? value['id'],
    'nameCn': value['nameCn'] ?? value['displayName'],
    'score': value['score'] ?? object(value['rating'])['score'],
  };
  Future<List<Json>> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return [];
    final response = object(
      await _cached(
        'search:${query.toLowerCase()}',
        '/v1/subjects/search?q=${Uri.encodeQueryComponent(query)}&limit=20&offset=0',
      ),
    );
    return objects(response['data']).map(summary).toList();
  }

  Future<List<Json>> trending() async {
    final items = <Json>[];
    for (var offset = 0; ; offset += 50) {
      final page = object(
        await _cached(
          'trending:$offset',
          '/v1/trending/current?limit=50&offset=$offset',
        ),
      );
      final values = objects(page['data']);
      items.addAll(values.map(summary));
      if (page['hasMore'] != true || values.isEmpty) break;
    }
    return items;
  }

  Future<Json> today() async {
    final response = object(await _cached('today', '/v1/schedule/today'));
    return {
      'date': response['date'],
      'items': objects(response['items']).map(summary).toList(),
    };
  }

  Future<List<Json>> calendar() async {
    final response = object(
      await _cached('week', '/v1/schedule/latest?days=7'),
    );
    final byDate = object(response['byDate']);
    final dates = byDate.keys.toList()..sort();
    const labels = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return dates.map((date) {
      final day = DateTime.parse(date).weekday;
      return {
        'date': date,
        'weekday': {'id': day, 'cn': labels[day - 1]},
        'items': objects(byDate[date]).map(summary).toList(),
      };
    }).toList();
  }

  Future<Json> subject(int id) async {
    if (id <= 0) throw const FormatException('番剧编号无效');
    // Detail and list caches have distinct keys; a search cannot erase detail.
    final response = object(
      await _cached(
        'detail:$id',
        '/v1/subjects/$id',
        ttl: const Duration(hours: 1),
      ),
    );
    final data = summary(object(response['data']));
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
}
