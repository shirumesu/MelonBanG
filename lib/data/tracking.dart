import 'dart:async';

import 'account.dart';
import 'bangumi_private.dart';
import 'catalog.dart';
import 'collection_edit.dart';
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
  late final community = BangumiPrivateClient(account);
  int? _sendingSequence;
  Future<void>? _flushing;
  Timer? _retry;
  bool _closed = false;
  final _syncStatus = <String, _SyncStatus>{};
  final _collectionRefreshes = <String, Future<void>>{};
  final _episodeRefreshes = <String, Future<void>>{};
  final _episodeRefreshedAt = <String, DateTime>{};
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
  Future<List<Json>> collection() async {
    final user = account.userId;
    final items = await store.list(_collection(user));
    final progress = await store.list(_episodes(user));
    return items.map((item) {
      item['watchedEpisodes'] ??= progress
          .where(
            (episode) =>
                episode['subjectId'] == item['subjectId'] &&
                episode['status'] == 'watched',
          )
          .length;
      return catalog.summary(item);
    }).toList();
  }

  Future<Json> syncState() async => {
    'pendingMutationCount': (await store.pending(account.userId)).length,
    'lastSyncError': lastSyncError,
    'lastSyncedAt': lastSyncedAt,
  };
  Future<Json> subject(int id, {void Function(Json)? onAvailable}) async {
    final user = account.userId;
    Future<void> publish(Json detail) async {
      if (onAvailable != null) {
        onAvailable(await _withProgress(detail, user, id));
      }
    }

    // Public detail and personal progress are independent network requests.
    final values = await Future.wait<dynamic>([
      catalog.subject(id, onAvailable: publish).then((detail) async {
        await publish(detail);
        return detail;
      }),
      refreshEpisodes(id, useCache: true).catchError((Object e) {
        if (user == account.userId) lastSyncError = e.toString();
      }),
    ]);
    return _withProgress(object(values[0]), user, id);
  }

  Future<Json> _withProgress(Json detail, String user, int id) async {
    if (user != account.userId) throw StateError('账号已经切换');
    final item = await store.get(_collection(user), '$id');
    final progress = await store.list(_episodes(user));
    if (user != account.userId) throw StateError('账号已经切换');
    final status = {for (final e in progress) '${e['episodeId']}': e['status']};
    return {
      ...detail,
      'collection': item == null
          ? null
          : {
              'status': item['status'],
              'score': item['userScore'],
              'tags': item['collectionTags'] ?? [],
              'comment': item['comment'] ?? '',
            },
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
    List<String>? tags,
    String? comment,
    bool completeEpisodes = false,
  }) async {
    if (subjectId <= 0 || (score != null && (score < 0 || score > 10))) {
      throw const FormatException('收藏信息无效');
    }
    tags = tags == null ? null : normalizeCollectionTags(tags);
    if (comment != null && comment.runes.length > collectionCommentLimit) {
      throw const FormatException('吐槽最多 $collectionCommentLimit 字');
    }
    final user = account.userId;
    final current =
        await store.get(_collection(user), '$subjectId') ??
        await catalog.subject(subjectId);
    if (_closed || user != account.userId) throw StateError('账号已经切换');
    if ((status?.key ?? current['status'] ?? 'wish') == 'wish') {
      if (score != null && score > 0) {
        throw const FormatException('想看状态不能评分，请先选择其他收藏状态');
      }
      if (status == CollectionStatus.wish && number(current['userScore']) > 0) {
        score = 0;
      }
    }
    final fields = {
      'type': ?status?.remoteValue,
      'rate': ?score,
      'tags': ?tags,
      'comment': ?comment,
    };
    List<int> episodeIds = [];
    if (completeEpisodes) {
      if ((status?.key ?? current['status']) != 'completed') {
        throw const FormatException('仅在标为看过时完成全部正片');
      }
      final detail = await catalog.subject(subjectId);
      episodeIds = objects(detail['episodes'])
          .where(
            (episode) =>
                episode['type'] == null ||
                episode['type'] == 0 ||
                episode['type'] == 'main',
          )
          .map((episode) => number(episode['episodeId']).toInt())
          .where((id) => id > 0)
          .toSet()
          .toList();
      if (_closed || user != account.userId) throw StateError('账号已经切换');
    }
    if (fields.isEmpty && !completeEpisodes) return;
    final mutation = {
      'kind': 'subject',
      'subjectId': subjectId,
      'fields': fields,
    };
    if (fields.isNotEmpty) {
      await store.mutate(
        _collection(user),
        '$subjectId',
        {
          'subjectId': subjectId,
          'status': ?status?.key,
          'userScore': ?score,
          'collectionTags': ?tags,
          'comment': ?comment,
        },
        user,
        'subject:$subjectId',
        mutation,
        defaults: {...current, 'status': current['status'] ?? 'wish'},
        initialMutation: const {
          'fields': {'type': 1},
        },
        excludePendingSequence: _sendingSequence,
      );
    }
    if (episodeIds.isNotEmpty) {
      await store.markEpisodes(
        _episodes(user),
        _collection(user),
        user,
        subjectId,
        episodeIds,
      );
    }
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
      episodeCollectionScope: _collection(user),
    );
    _changed();
    unawaited(flush());
  }

  Future<void> refresh() {
    final user = account.userId;
    return _collectionRefreshes.putIfAbsent(user, () async {
      try {
        await _refreshCollection();
      } finally {
        _collectionRefreshes.remove(user);
      }
    });
  }

  Future<void> _refreshCollection() async {
    if (account.session == null) return;
    final requestedAt = DateTime.now().millisecondsSinceEpoch;
    final user = account.userId;
    final username = Uri.encodeComponent('${account.session!['username']}');
    final remote = <String, Json>{};
    try {
      // Keep pending episode counts even if the outbox finishes during the pull.
      final requestMutations = await store.pending(user);
      final pendingFields = <String, Set<String>>{};
      for (final row in requestMutations) {
        final body = object(row['body']);
        if (body['kind'] == 'subject') {
          pendingFields
              .putIfAbsent('${body['subjectId']}', () => {})
              .addAll(collectionMutationFields(body).keys);
        }
      }
      final pendingEpisodeSubjects = requestMutations
          .map((row) => object(row['body']))
          .where(
            (body) => body['kind'] == 'episode' || body['kind'] == 'episodes',
          )
          .map((body) => '${body['subjectId']}')
          .toSet();
      for (var offset = 0; ; offset += 50) {
        if (user != account.userId || _closed) return;
        final response = object(
          await account.request(
            '/v0/users/$username/collections?subject_type=2&limit=50&offset=$offset',
          ),
        );
        final rows = objects(response['data']);
        for (final row in rows) {
          if (number(row['type']) == 0) continue;
          final s = object(row['subject']);
          final id = row['subject_id'];
          remote['$id'] = {
            'subjectId': id,
            'name': s['name'],
            'nameCn': s['name_cn'],
            'summary': s['short_summary'],
            'coverUrl': [
              for (final size in ['common', 'large', 'medium', 'small'])
                coverAddress(object(s['images'])[size]),
            ].whereType<String>().firstOrNull,
            'episodeTotal': s['eps'] ?? s['total_episodes'],
            'score': s['score'],
            'status': CollectionStatus.fromRemote(number(row['type']).toInt())
                .key,
            'userScore': row['rate'],
            'collectionTags': row['tags'] is List ? row['tags'] : [],
            'comment': row['comment'] ?? '',
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
        preserveEpisodeCounts: pendingEpisodeSubjects,
        preserveFields: pendingFields,
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

  Future<void> refreshEpisodes(int subjectId, {bool useCache = false}) async {
    if (account.session == null || account.needsAuthorization) return;
    final user = account.userId;
    final key = '$user:$subjectId';
    final active = _episodeRefreshes[key];
    if (active != null) return active;
    final refreshedAt = _episodeRefreshedAt[key];
    if (useCache &&
        refreshedAt != null &&
        DateTime.now().difference(refreshedAt) < const Duration(minutes: 1)) {
      return;
    }
    final request = _refreshEpisodes(subjectId, user);
    _episodeRefreshes[key] = request;
    try {
      await request;
      if (!_closed && user == account.userId) {
        _episodeRefreshedAt[key] = DateTime.now();
      }
    } finally {
      _episodeRefreshes.remove(key);
    }
  }

  Future<void> _refreshEpisodes(int subjectId, String user) async {
    final requestedAt = DateTime.now().millisecondsSinceEpoch;
    final preserveEntities = <String>{};
    for (final row in await store.pending(user)) {
      final body = object(row['body']);
      if (body['subjectId'] != subjectId) continue;
      if (body['kind'] == 'episode') {
        preserveEntities.add('episode:${body['episodeId']}');
      } else if (body['kind'] == 'episodes') {
        for (final id in body['episodeIds'] as List? ?? []) {
          preserveEntities.add('episode:$id');
        }
      }
    }
    final remote = <String, Json>{};
    int? total;
    for (var offset = 0; ;) {
      final response = object(
        await account.request(
          '/v0/users/-/collections/$subjectId/episodes?limit=100&offset=$offset',
        ),
      );
      final rows = objects(response['data']);
      if (user != account.userId || _closed) return;
      final count = response['total'];
      if (count is! int || count < 0 || (total != null && total != count)) {
        throw const FormatException('章节列表未完整接收，请重新同步');
      }
      total = count;
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
      offset += rows.length;
      if (offset == total && remote.length == total) break;
      if (rows.isEmpty || offset >= total) {
        throw const FormatException('章节列表未完整接收，请重新同步');
      }
    }
    await store.mergeRemote(
      _episodes(user),
      remote,
      account: user,
      entityKind: 'episode',
      requestedAt: requestedAt,
      preserveEntities: preserveEntities,
      episodeCollectionScope: _collection(user),
      episodeSubjectId: subjectId,
    );
    _changed();
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
          final aEpisode = object(a['body'])['kind'] == 'subject' ? 0 : 1;
          final bEpisode = object(b['body'])['kind'] == 'subject' ? 0 : 1;
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
              (input['kind'] != 'subject' &&
                  blocked.contains('subject:${input['subjectId']}'))) {
            continue;
          }
          try {
            _sendingSequence = sequence;
            if (input['kind'] == 'subject') {
              await account.request(
                '/v0/users/-/collections/${input['subjectId']}',
                method: 'POST',
                body: collectionMutationFields(input),
              );
            } else if (input['kind'] == 'episodes') {
              await account.request(
                '/v0/users/-/collections/${input['subjectId']}/episodes',
                method: 'PATCH',
                body: {'episode_id': input['episodeIds'], 'type': 2},
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
          } finally {
            _sendingSequence = null;
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
    await Future.wait(
      [..._collectionRefreshes.values, ..._episodeRefreshes.values].map((
        request,
      ) async {
        try {
          await request;
        } catch (_) {
          // The refresh caller owns error reporting.
        }
      }),
    );
    await changes.close();
  }
}
