import 'dart:async';

import 'account.dart';
import 'catalog.dart';
import 'json.dart';
import 'store.dart';

class TrackingRepository {
  TrackingRepository(this.store, this.account, this.catalog);
  final AppStore store;
  final AccountRepository account;
  final CatalogRepository catalog;
  Future<void>? _flushing;
  Timer? _retry;
  bool _closed = false;
  String? lastSyncError;
  String? lastSyncedAt;
  final changes = StreamController<void>.broadcast();
  void start() {
    _retry = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(flush()),
    );
  }

  String _collection(String user) => 'collection:$user';
  String _episodes(String user) => 'episodes:$user';
  Future<List<Json>> collection() => store.list(_collection(account.userId));
  Future<Json> syncState() async => {
    'pendingMutationCount': (await store.pending(account.userId)).length,
    'lastSyncError': lastSyncError,
    'lastSyncedAt': lastSyncedAt,
  };
  Future<Json> subject(int id) async {
    final detail = await catalog.subject(id);
    try {
      await refreshEpisodes(id);
    } catch (e) {
      lastSyncError = e.toString();
    }
    final item = await store.get(_collection(account.userId), '$id');
    final progress = await store.list(_episodes(account.userId));
    final status = {for (final e in progress) '${e['episodeId']}': e['status']};
    return {
      ...detail,
      'collection': item == null
          ? null
          : {'status': item['status'], 'score': item['userScore']},
      'episodes': objects(detail['episodes'])
          .map(
            (e) => {...e, 'status': status['${e['episodeId']}'] ?? 'unwatched'},
          )
          .toList(),
    };
  }

  Future<void> setCollection(
    int subjectId, {
    CollectionStatus? status,
    int? score,
  }) async {
    if (subjectId <= 0 || (score != null && (score < 0 || score > 10))) {
      throw const FormatException('收藏信息无效');
    }
    final user = account.userId;
    final current =
        await store.get(_collection(user), '$subjectId') ??
        await catalog.subject(subjectId);
    final mutation = {
      'kind': 'subject',
      'subjectId': subjectId,
      'status': ?status?.key,
      'score': ?score,
    };
    await store.mutate(
      _collection(user),
      '$subjectId',
      {
        ...current,
        'subjectId': subjectId,
        'status': status?.key ?? current['status'] ?? 'wish',
        'userScore': score ?? current['userScore'],
      },
      user,
      'subject:$subjectId',
      mutation,
    );
    _changed();
    unawaited(flush());
  }

  Future<void> setEpisode(
    int subjectId,
    int episodeId,
    EpisodeStatus status,
  ) async {
    if (episodeId <= 0 || subjectId <= 0) throw const FormatException('章节编号无效');
    final user = account.userId;
    await store.mutate(
      _episodes(user),
      '$episodeId',
      {'subjectId': subjectId, 'episodeId': episodeId, 'status': status.key},
      user,
      'episode:$episodeId',
      {
        'kind': 'episode',
        'subjectId': subjectId,
        'episodeId': episodeId,
        'status': status.key,
      },
    );
    _changed();
    unawaited(flush());
  }

  Future<void> refresh() async {
    if (account.session == null) return;
    final requestedAt = DateTime.now().millisecondsSinceEpoch;
    final user = account.userId;
    final username = Uri.encodeComponent('${account.session!['username']}');
    final remote = <String, Json>{};
    try {
      for (var offset = 0; ; offset += 50) {
        final response = object(
          await account.request(
            '/v0/users/$username/collections?subject_type=2&limit=50&offset=$offset',
          ),
        );
        final rows = objects(response['data']);
        for (final row in rows) {
          final s = object(row['subject']);
          final id = row['subject_id'];
          remote['$id'] = {
            'subjectId': id,
            'name': s['name'],
            'nameCn': s['name_cn'],
            'summary': s['short_summary'],
            'coverUrl': object(s['images'])['common'],
            'episodeTotal': s['eps'] ?? s['total_episodes'],
            'score': object(s['rating'])['score'],
            'status': CollectionStatus.fromRemote(number(row['type']).toInt())
                .key,
            'userScore': row['rate'],
            'watchedEpisodes': row['ep_status'],
          };
        }
        if (rows.isEmpty || offset + rows.length >= number(response['total'])) {
          break;
        }
      }
      if (user != account.userId || _closed) return;
      await store.mergeRemote(
        _collection(user),
        remote,
        account: user,
        entityKind: 'subject',
        requestedAt: requestedAt,
        replace: true,
      );
      lastSyncedAt = DateTime.now().toIso8601String();
      lastSyncError = null;
      _changed();
      await flush();
    } catch (e) {
      lastSyncError = e.toString();
      _changed();
      rethrow;
    }
  }

  Future<void> refreshEpisodes(int subjectId) async {
    if (account.session == null) return;
    final requestedAt = DateTime.now().millisecondsSinceEpoch;
    final user = account.userId;
    for (var offset = 0; ; offset += 100) {
      final response = object(
        await account.request(
          '/v0/users/-/collections/$subjectId/episodes?limit=100&offset=$offset',
        ),
      );
      final rows = objects(response['data']);
      if (user != account.userId || _closed) return;
      final remote = <String, Json>{};
      for (final row in rows) {
        final id = object(row['episode'])['id'];
        final value = number(row['type']).toInt();
        final status =
            EpisodeStatus.values
                .where((s) => s.remoteValue == value)
                .firstOrNull ??
            EpisodeStatus.unwatched;
        remote['$id'] = {
          'subjectId': subjectId,
          'episodeId': id,
          'status': status.key,
        };
      }
      await store.mergeRemote(
        _episodes(user),
        remote,
        account: user,
        entityKind: 'episode',
        requestedAt: requestedAt,
      );
      if (rows.length < 100 ||
          offset + rows.length >= number(response['total'])) {
        break;
      }
    }
  }

  Future<void> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);
  Future<void> _flush() async {
    final user = account.userId;
    if (user == 'local' || _closed) return;
    try {
      for (final row in await store.pending(user)) {
        if (user != account.userId || _closed) return;
        final input = object(row['body']);
        if (input['kind'] == 'subject') {
          await account.request(
            '/v0/users/-/collections/${input['subjectId']}',
            method: 'POST',
            body: {
              'type': input['status'] == null
                  ? null
                  : CollectionStatus.parse('${input['status']}').remoteValue,
              'rate': input['score'],
            }..removeWhere((_, v) => v == null),
          );
        } else {
          await account.request(
            '/v0/users/-/collections/-/episodes/${input['episodeId']}',
            method: 'PUT',
            body: {
              'type': EpisodeStatus.parse('${input['status']}').remoteValue,
            },
          );
        }
        await store.acknowledge(row['sequence'] as int);
      }
      lastSyncError = null;
    } catch (e) {
      lastSyncError = e.toString();
    }
    _changed();
  }

  void _changed() {
    if (!_closed) changes.add(null);
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    await _flushing;
    await changes.close();
  }
}
