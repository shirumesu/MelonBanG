import 'dart:async';

import 'account.dart';
import 'catalog.dart';
import 'json.dart';
import 'network.dart';
import 'store.dart';

class _SyncStatus {
  String? error;
  String? syncedAt;
}

class TrackingRepository {
  TrackingRepository(this.store, this.account, this.catalog);
  final AppStore store;
  final AccountRepository account;
  final CatalogRepository catalog;
  Future<void>? _flushing;
  Timer? _retry;
  bool _closed = false;
  final _syncStatus = <String, _SyncStatus>{};
  _SyncStatus get _currentSync =>
      _syncStatus.putIfAbsent(account.userId, _SyncStatus.new);
  String? get lastSyncError => _currentSync.error;
  set lastSyncError(String? value) => _currentSync.error = value;
  String? get lastSyncedAt => _currentSync.syncedAt;
  set lastSyncedAt(String? value) => _currentSync.syncedAt = value;
  final changes = StreamController<void>.broadcast();
  void start() {
    if (_closed || _retry != null) return;
    unawaited(flush());
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
    final user = account.userId;
    final detail = await catalog.subject(id);
    if (user != account.userId) throw StateError('账号已经切换');
    try {
      await refreshEpisodes(id);
    } catch (e) {
      if (user == account.userId) lastSyncError = e.toString();
    }
    if (user != account.userId) throw StateError('账号已经切换');
    final item = await store.get(_collection(user), '$id');
    final progress = await store.list(_episodes(user));
    if (user != account.userId) throw StateError('账号已经切换');
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
    if (_closed || user != account.userId) throw StateError('账号已经切换');
    final mutation = {
      'kind': 'subject',
      'subjectId': subjectId,
      'status': ?status?.key,
      'score': ?score,
    };
    await store.mutate(
      _collection(user),
      '$subjectId',
      {'subjectId': subjectId, 'status': ?status?.key, 'userScore': ?score},
      user,
      'subject:$subjectId',
      mutation,
      defaults: {...current, 'status': current['status'] ?? 'wish'},
      initialMutation: const {'status': 'wish'},
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
    if (_closed) throw StateError('收藏服务已关闭');
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
        if (user != account.userId || _closed) return;
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
            'score': s['score'],
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
      if (user == account.userId) lastSyncError = e.toString();
      _changed();
      rethrow;
    }
  }

  Future<void> refreshEpisodes(int subjectId) async {
    if (account.session == null || account.needsAuthorization) return;
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
    if (user == 'local' || _closed || account.needsAuthorization) return;
    final attempted = <int>{};
    final blocked = <String>{};
    String? error;
    try {
      while (!_closed && user == account.userId) {
        final rows = (await store.pending(user))
            .where((row) => !attempted.contains(row['sequence']))
            .toList();
        if (rows.isEmpty) break;
        // Bangumi requires a subject collection before accepting episode edits.
        // Preserve order within each entity, but send collection edits first.
        rows.sort((a, b) {
          final aEpisode = object(a['body'])['kind'] == 'episode' ? 1 : 0;
          final bEpisode = object(b['body'])['kind'] == 'episode' ? 1 : 0;
          final kind = aEpisode.compareTo(bEpisode);
          return kind != 0
              ? kind
              : (a['sequence'] as int).compareTo(b['sequence'] as int);
        });
        for (final row in rows) {
          if (user != account.userId || _closed) return;
          final sequence = row['sequence'] as int;
          attempted.add(sequence);
          final entity = '${row['entity']}';
          final input = object(row['body']);
          if (blocked.contains(entity) ||
              (input['kind'] == 'episode' &&
                  blocked.contains('subject:${input['subjectId']}'))) {
            continue;
          }
          try {
            if (input['kind'] == 'subject') {
              await account.request(
                '/v0/users/-/collections/${input['subjectId']}',
                method: 'POST',
                body: {
                  'type': input['status'] == null
                      ? null
                      : CollectionStatus.parse('${input['status']}')
                            .remoteValue,
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
            await store.acknowledge(sequence);
          } on ApiException catch (e) {
            // A rejected item must not prevent unrelated valid edits syncing.
            // Stop on connection/server/account failures until the next retry.
            if (e.status != 400 && e.status != 404) rethrow;
            blocked.add(entity);
            error ??= input['kind'] == 'episode' && e.status == 400
                ? '章节 ${input['episodeId']} 同步失败，请先收藏对应番剧后重试。'
                : e.toString();
          }
        }
      }
      if (user == account.userId) lastSyncError = error;
    } catch (e) {
      if (user == account.userId) lastSyncError = e.toString();
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
