import 'dart:async';

import '../../core/error_message.dart';
import '../../domain/catalog.dart';
import '../../domain/collection_edit.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../../core/store.dart';

class _SyncStatus {
  String? error;
  String? syncedAt;
}

class TrackingRepository {
  TrackingRepository(this.store, this.account, this.catalog);
  final AppStore store;
  final Account account;
  final Catalog catalog;
  int? _sendingSequence;
  Future<void>? _flushing;
  Timer? _retry;
  bool _closed = false;
  final _syncStatus = <String, _SyncStatus>{};
  final _collectionRefreshes = <String, Future<void>>{};
  final _episodeRefreshes = <String, Future<void>>{};
  final _episodeRefreshedAt = <String, DateTime>{};

  /// Scores cleared on entering wish, keyed `user:subject`, restored on leaving it.
  final _heldScores = <String, int>{};
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
  Future<List<Subject>> collection() async {
    final user = account.userId;
    final items = await store.list(_collection(user));
    final watched = items.any((item) => item['watchedEpisodes'] == null)
        ? await store.watchedEpisodeCounts(_episodes(user))
        : const <int, int>{};
    return items.map((item) {
      item['watchedEpisodes'] ??= watched[item['subjectId']] ?? 0;
      return catalog.card(item);
    }).toList();
  }

  Future<SyncState> syncState() async => SyncState(
    pending: await store.pendingCount(account.userId),
    error: lastSyncError,
    syncedAt: lastSyncedAt,
  );
  Future<Subject> subject(
    int id, {
    void Function(Subject)? onAvailable,
    bool forPlayback = false,
  }) async {
    final user = account.userId;
    Future<void> publish(Subject detail) async {
      if (onAvailable != null) {
        onAvailable(await _withProgress(detail, user, id));
      }
    }

    // Public detail and personal progress are independent network requests.
    // A failed progress read keeps the saved progress and is retried on the
    // next visit; it is not an upload failure, so it leaves lastSyncError.
    final personal = refreshEpisodes(id, useCache: true).catchError((_) {});
    if (forPlayback) {
      unawaited(personal);
      return _withProgress(
        await catalog.subject(id, forPlayback: true),
        user,
        id,
      );
    }
    final values = await Future.wait<dynamic>([
      catalog.subject(id, onAvailable: publish).then((detail) async {
        await publish(detail);
        return detail;
      }),
      personal,
    ]);
    return _withProgress(values[0] as Subject, user, id);
  }

  Future<Subject> _withProgress(Subject detail, String user, int id) async {
    if (user != account.userId) throw StateError('账号已经切换');
    final item = await store.get(_collection(user), '$id');
    final progress = await store.list(_episodes(user), subjectId: id);
    if (user != account.userId) throw StateError('账号已经切换');
    final status = {for (final e in progress) e['episodeId']: e['status']};
    return detail.copyWith(
      collection: item == null ? null : Subject.fromJson(item).collection,
      clearCollection: item == null,
      episodes: [
        for (final episode in detail.episodes)
          episode.withStatus(
            status[episode.id] is String
                ? EpisodeStatus.parse(status[episode.id] as String)
                : EpisodeStatus.unwatched,
          ),
      ],
    );
  }

  /// A collection row in the shape Bangumi pulls are stored.
  static Json _row(Subject subject) => {
    'subjectId': subject.id,
    'name': subject.name,
    'nameCn': subject.nameCn,
    'summary': subject.summary,
    'coverUrl': subject.coverUrl,
    'episodeTotal': subject.episodeTotal,
    'score': subject.score,
    'airDate': subject.airDate,
    if (subject.collectionStats.isNotEmpty)
      'collectionTotal': subject.collectionStats.values.reduce((a, b) => a + b),
    'collectedAt': DateTime.now().toUtc().toIso8601String(),
  };

  Future<void> setCollection(int subjectId, CollectionChange change) async {
    final status = change.status, comment = change.comment, tags = change.tags;
    var score = change.score;
    final completeEpisodes = change.completeEpisodes;
    final user = account.userId;
    final current =
        await store.get(_collection(user), '$subjectId') ??
        _row(await catalog.subject(subjectId));
    if (_closed || user != account.userId) throw StateError('账号已经切换');
    if ((status?.key ?? current['status'] ?? 'wish') == 'wish') {
      if (status == CollectionStatus.wish && number(current['userScore']) > 0) {
        _heldScores['$user:$subjectId'] = number(current['userScore']).toInt();
        score = 0;
      }
    } else if (score != null) {
      _heldScores.remove('$user:$subjectId');
    } else if (current['status'] == 'wish') {
      // Leaving wish restores the score Bangumi made us clear on entering it.
      score = _heldScores.remove('$user:$subjectId');
    }
    final fields = {
      'type': ?status?.remoteValue,
      'rate': ?score,
      'tags': ?tags,
      'comment': ?comment,
    };
    List<int> episodeIds = [];
    if (completeEpisodes) {
      final detail = await catalog.subject(subjectId);
      episodeIds = detail.episodes
          .where((episode) => episode.main && episode.id > 0)
          .map((episode) => episode.id)
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

  /// Marks several episodes at once; watched uses Bangumi's batch endpoint.
  Future<void> setEpisodes(
    int subjectId,
    List<int> episodeIds,
    EpisodeStatus status,
  ) async {
    if (status != EpisodeStatus.watched || episodeIds.length == 1) {
      for (final id in episodeIds) {
        await setEpisode(subjectId, id, status);
      }
      return;
    }
    if (_closed) throw StateError('收藏服务已关闭');
    final user = account.userId;
    await store.markEpisodes(
      _episodes(user),
      _collection(user),
      user,
      subjectId,
      episodeIds,
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
    if (account.profile == null) return;
    final requestedAt = DateTime.now().millisecondsSinceEpoch;
    final user = account.userId;
    final username = Uri.encodeComponent('${account.profile!.username}');
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
            'airDate': s['date'],
            'collectionTotal': s['collection_total'],
            'collectedAt': row['updated_at'],
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
      if (user == account.userId) lastSyncError = errorMessage(e);
      _changed();
      rethrow;
    }
  }

  Future<void> refreshEpisodes(int subjectId, {bool useCache = false}) async {
    if (account.profile == null || account.needsAuthorization) return;
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

  /// Pulls the episode progress of those [subjectIds] in the collection.
  Future<void> refreshProgress(Iterable<int> subjectIds) async {
    final user = account.userId;
    await Future.wait([
      for (final id in subjectIds)
        if (await store.get(_collection(user), '$id') != null)
          refreshEpisodes(id, useCache: true),
    ]);
  }

  /// Whether the recorded progress still leaves [episodeId] of [subject] to
  /// watch: the subject is collected, neither completed nor dropped, and no
  /// main episode from it on is watched, by episode record or watched count.
  Future<bool> leavesUnwatched(Subject subject, int episodeId) async {
    final user = account.userId;
    final row = await store.get(_collection(user), '${subject.id}');
    if (row == null) return false;
    final status = CollectionStatus.tryParse(row['status']);
    if (status == CollectionStatus.completed ||
        status == CollectionStatus.dropped) {
      return false;
    }
    final episodes = subject.episodes.where((e) => e.main).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    final index = episodes.indexWhere((e) => e.id == episodeId);
    if (index < 0 || number(row['watchedEpisodes']) > index) return false;
    final watched = {
      for (final e in await store.list(_episodes(user), subjectId: subject.id))
        if (e['status'] == EpisodeStatus.watched.key) e['episodeId'],
    };
    return !episodes.skip(index).any((e) => watched.contains(e.id));
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
    final previousError = lastSyncError;
    var changed = false;
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
            changed = true;
          } on ApiException catch (e) {
            // A rejected item must not prevent unrelated valid edits syncing.
            // Stop on connection/server/account failures until the next retry.
            if (e.status != 400 && e.status != 404) rethrow;
            blocked.add(entity);
            error ??= input['kind'] == 'episode' && e.status == 400
                ? '章节 ${input['episodeId']} 同步失败，请先收藏对应番剧后重试。'
                : errorMessage(e);
          } finally {
            _sendingSequence = null;
          }
        }
      }
      if (user == account.userId) lastSyncError = error;
    } catch (e) {
      if (user == account.userId) lastSyncError = errorMessage(e);
    }
    if (changed || previousError != lastSyncError) _changed();
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
