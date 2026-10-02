import 'account.dart';
import 'json.dart';
import 'network.dart';

class BangumiPrivateClient {
  BangumiPrivateClient(this.account);
  final AccountRepository account;
  final _cache = <String, Json>{};

  Future<dynamic> _request(String path) async {
    final user = account.userId;
    final headers = <String, String>{};
    if (account.session != null && !account.needsAuthorization) {
      try {
        headers['Authorization'] = 'Bearer ${await account.accessToken()}';
      } catch (_) {
        if (user != account.userId) rethrow;
      }
    }
    try {
      final result = await account.api.json(
        Uri.parse('https://next.bgm.tv$path'),
        headers: headers,
      );
      if (user != account.userId) throw StateError('账号已经切换');
      return result;
    } on ApiException catch (error) {
      if (headers.isEmpty || (error.status != 401 && error.status != 403)) {
        rethrow;
      }
      final result = await account.api.json(
        Uri.parse('https://next.bgm.tv$path'),
      );
      if (user != account.userId) throw StateError('账号已经切换');
      return result;
    }
  }

  Future<Json> page(
    int subjectId,
    String segment, {
    int offset = 0,
    bool refresh = false,
  }) async {
    if (!const {
      'comments',
      'reviews',
      'topics',
      'relations',
    }.contains(segment)) {
      throw const FormatException('未知社区分段');
    }
    final key = '${account.userId}:$subjectId:$segment:$offset';
    if (!refresh) {
      if (_cache[key] case final cached?) return cached;
    }
    final response = object(
      await _request(
        '/p1/subjects/$subjectId/$segment?limit=20&offset=$offset',
      ),
    );
    final data = objects(response['data']);
    return _cache[key] = {
      'subjectId': subjectId,
      'data': data,
      'total': response['total'] is num
          ? number(response['total']).toInt()
          : offset + data.length,
    };
  }

  Future<List<Json>> relations(int subjectId, {bool refresh = false}) async {
    final values = <Json>[];
    try {
      for (var offset = 0; ;) {
        final response = await page(
          subjectId,
          'relations',
          offset: offset,
          refresh: refresh,
        );
        final data = objects(response['data']);
        values.addAll(data.map((row) => _relation(row, private: true)));
        offset += data.length;
        if (data.isEmpty || offset >= number(response['total'])) break;
      }
      return values.where((row) => number(row['subjectId']) > 0).toList();
    } catch (_) {
      final data = await account.api.json(
        Uri.https('api.bgm.tv', '/v0/subjects/$subjectId/subjects'),
      );
      return objects(data)
          .map((row) => _relation(row, private: false))
          .where((row) => number(row['subjectId']) > 0)
          .toList();
    }
  }

  Json _relation(Json row, {required bool private}) {
    final subject = private ? object(row['subject']) : row;
    final images = object(subject['images']);
    final info = '${subject['info'] ?? subject['air_date'] ?? ''}';
    final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(info)?.group(0);
    return {
      'subjectId': number(subject['id']).toInt(),
      'name': subject['name'],
      'nameCn': subject['nameCN'] ?? subject['name_cn'],
      'coverUrl': images['common'] ?? images['large'] ?? images['medium'],
      'relation': private
          ? object(row['relation'])['cn'] ?? '其他'
          : row['relation'] ?? '其他',
      'season': {'year': year},
      'score': object(subject['rating'])['score'],
      'platform':
          const {1: '书籍', 2: '动画', 3: '音乐', 4: '游戏', 6: '三次元'}[number(
            subject['type'],
          ).toInt()] ??
          '其他',
    };
  }
}
