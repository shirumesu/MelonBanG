import '../../domain/catalog.dart';
import 'account.dart';
import '../../core/json.dart';
import '../../core/network.dart';

class BangumiPrivateClient implements SubjectCommunitySource {
  BangumiPrivateClient(this.account);
  final AccountRepository account;

  @override
  String get userId => account.userId;
  @override
  AccountProfile? get profile => account.profile;
  final _rows = <String, ({DateTime savedAt, List<Json> rows, int total})>{};

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

  @override
  Future<CommunityPage> page(
    int subjectId,
    String segment, {
    int offset = 0,
    bool refresh = false,
  }) async {
    if (!const {'comments', 'reviews', 'topics'}.contains(segment)) {
      throw const FormatException('未知社区分段');
    }
    final page = await _page(
      subjectId,
      segment,
      offset: offset,
      refresh: refresh,
    );
    return CommunityPage(
      entries: [for (final row in page.rows) _entry(row, segment)],
      total: page.total,
    );
  }

  CommunityEntry _entry(Json row, String segment) {
    final entry = segment == 'reviews' ? object(row['entry']) : row;
    final user = object(row[segment == 'topics' ? 'creator' : 'user']);
    final comments = segment == 'comments';
    return CommunityEntry(
      id: number(entry['id']).toInt(),
      userId: '${user['id']}',
      author: '${user['nickname'] ?? user['username'] ?? '未知用户'}',
      avatarUrl: coverAddress(object(user['avatar'])['medium']),
      score: comments ? number(row['rate']).toInt() : 0,
      status: comments
          ? CollectionStatus.values
                .where((status) => status.remoteValue == number(row['type']))
                .firstOrNull
          : null,
      replies: number(row['replyCount']).toInt(),
      title: entry['title'] as String?,
      text: '${comments ? row['comment'] ?? '' : entry['summary'] ?? ''}',
      time: number(
        segment == 'topics'
            ? row['updatedAt']
            : entry['createdAt'] ?? entry['updatedAt'],
      ).toInt(),
    );
  }

  Future<({List<Json> rows, int total})> _page(
    int subjectId,
    String segment, {
    int offset = 0,
    bool refresh = false,
  }) async {
    final prefix = '${account.userId}:$subjectId:$segment:';
    final key = '$prefix$offset';
    final cached = _rows[key];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.savedAt) <
            const Duration(minutes: 5)) {
      return (rows: cached.rows, total: cached.total);
    }
    final response = object(
      await _request(
        '/p1/subjects/$subjectId/$segment?limit=20&offset=$offset',
      ),
    );
    final data = objects(response['data']);
    final total = response['total'] is num
        ? number(response['total']).toInt()
        : offset + data.length;
    if (offset == 0) _rows.removeWhere((key, _) => key.startsWith(prefix));
    _rows[key] = (savedAt: DateTime.now(), rows: data, total: total);
    return (rows: data, total: total);
  }

  @override
  Future<List<TopicPost>> topic(int topicId) async {
    final response = object(await _request('/p1/subjects/-/topics/$topicId'));
    return objects(response['replies']).map(_post).toList();
  }

  @override
  Future<String> blog(int entryId) async =>
      '${object(await _request('/p1/blogs/$entryId'))['content'] ?? ''}';

  TopicPost _post(Json row) {
    final user = object(row['creator']);
    return TopicPost(
      id: number(row['id']).toInt(),
      author: '${user['nickname'] ?? user['username'] ?? '未知用户'}',
      avatarUrl: coverAddress(object(user['avatar'])['medium']),
      time: number(row['createdAt']).toInt(),
      content: '${row['content'] ?? ''}',
      replies: objects(row['replies']).map(_post).toList(),
    );
  }

  @override
  Future<List<Subject>> relations(int subjectId, {bool refresh = false}) async {
    final values = <Json>[];
    try {
      for (var offset = 0; ;) {
        final response = await _page(
          subjectId,
          'relations',
          offset: offset,
          refresh: refresh,
        );
        final data = response.rows;
        values.addAll(data.map((row) => _relation(row, private: true)));
        offset += data.length;
        if (data.isEmpty || offset >= response.total) break;
      }
    } catch (_) {
      final data = await account.api.json(
        Uri.https('api.bgm.tv', '/v0/subjects/$subjectId/subjects'),
      );
      values
        ..clear()
        ..addAll(objects(data).map((row) => _relation(row, private: false)));
    }
    return values
        .where((row) => number(row['subjectId']) > 0)
        .map(Subject.fromJson)
        .toList();
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
