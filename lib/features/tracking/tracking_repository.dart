import 'dart:async';
import 'dart:convert';

import '../../core/error_message.dart';
import '../../domain/catalog.dart';
import '../../domain/collection_edit.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../../core/store.dart';

class TrackingRepository {
  TrackingRepository(this.store, this.account, this.catalog);
  final AppStore store;
  final Account account;
  final Catalog catalog;
  bool _closed = false;

  /// The running edit or upload of each `user:subject`; the next one waits.
  final _subjectQueues = <String, Future<void>>{};
  final _collectionRefreshes = <String, Future<void>>{};
  final _entryRefreshes = <String, Future<void>>{};
  final _entryRefreshedAt = <String, DateTime>{};

  /// Scores cleared on entering wish, keyed `user:subject`, restored on leaving it.
  final _heldScores = <String, int>{};
  final changes = StreamController<void>.broadcast();

  /// Uploads the edits a previous run left queued.
  void start() {
    if (!_closed) unawaited(_uploadQueued().catchError((Object _) {}));
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
    // next visit.
    final personal = refreshEntry(id, useCache: true).catchError((_) {});
    if (forPlayback) {
      unawaited(personal);
      return _withProgress(
        await catalog.subject(id, forPlayback: true),
        user,
        id,
      );
    }
    final detail = await catalog.subject(id, onAvailable: publish);
    await publish(detail);
    await personal;
    return _withProgress(detail, user, id);
  }

  /// [detail] with the saved collection entry and episode progress.
  Future<Subject> withProgress(Subject detail) =>
      _withProgress(detail, account.userId, detail.id);

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
    await _commit(
      user,
      subjectId,
      [
        (_collection(user), '$subjectId'),
        for (final id in episodeIds) (_episodes(user), '$id'),
      ],
      () async => [
        if (fields.isNotEmpty)
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
            {'kind': 'subject', 'subjectId': subjectId, 'fields': fields},
            defaults: {...current, 'status': current['status'] ?? 'wish'},
            initialMutation: const {
              'fields': {'type': 1},
            },
          ),
        if (episodeIds.isNotEmpty)
          await store.markEpisodes(
            _episodes(user),
            _collection(user),
            user,
            subjectId,
            episodeIds,
          ),
      ],
    );
  }

  Future<void> setEpisode(
    int subjectId,
    int episodeId,
    EpisodeStatus status,
  ) async {
    if (_closed) throw StateError('收藏服务已关闭');
    final user = account.userId;
    await _commit(
      user,
      subjectId,
      [(_episodes(user), '$episodeId'), (_collection(user), '$subjectId')],
      () async => [
        await store.mutate(
          _episodes(user),
          '$episodeId',
          {
            'subjectId': subjectId,
            'episodeId': episodeId,
            'status': status.key,
          },
          user,
          'episode:$episodeId',
          {
            'kind': 'episode',
            'subjectId': subjectId,
            'episodeId': episodeId,
            'status': status.key,
          },
          episodeCollectionScope: _collection(user),
        ),
      ],
    );
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
    await _commit(
      user,
      subjectId,
      [
        for (final id in episodeIds) (_episodes(user), '$id'),
        (_collection(user), '$subjectId'),
      ],
      () async => [
        await store.markEpisodes(
          _episodes(user),
          _collection(user),
          user,
          subjectId,
          episodeIds,
        ),
      ],
    );
  }

  /// Runs [task] after the earlier edits and uploads of [subjectId].
  Future<T> _inOrder<T>(String user, int subjectId, Future<T> Function() task) {
    final key = '$user:$subjectId';
    final result = (_subjectQueues[key] ?? Future.value()).then((_) => task());
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _subjectQueues[key] = settled;
    settled.then((_) {
      if (identical(_subjectQueues[key], settled)) _subjectQueues.remove(key);
    });
    return result;
  }

  /// Writes an edit locally so it shows at once, then sends it to Bangumi.
  /// When sending fails the [touched] rows go back to how they were and the
  /// error names why. [write] returns the queued sequences.
  Future<void> _commit(
    String user,
    int subjectId,
    List<(String, String)> touched,
    Future<List<int?>> Function() write,
  ) => _inOrder(user, subjectId, () async {
    if (_closed || user != account.userId) throw StateError('账号已经切换');
    if (user == 'local') {
      await write();
      _changed();
      return;
    }
    DocumentSnapshot? before;
    var sequences = <int>[];
    try {
      // The edit is the user's own: ask the keychain even if it was refused.
      if (account.needsAuthorization) await account.unlock();
      // Older edits of this subject go first, or they would undo this one.
      await _upload(user, subjectId);
      before = await store.snapshot(touched);
      sequences = (await write()).nonNulls.toList();
      _changed();
      for (final row in await store.pending(user)) {
        final sequence = row['sequence'] as int;
        if (!sequences.contains(sequence)) continue;
        await _send(object(row['body']));
        await store.acknowledge(sequence);
      }
    } catch (e) {
      if (before != null) {
        await store.restore(before, sequences);
        // A partly sent edit leaves Bangumi ahead of the restored rows.
        unawaited(refreshEntry(subjectId).catchError((Object _) {}));
      }
      // The account may have just turned out locked or expired.
      _changed();
      throw StateError(
        before == null ? _failure(e) : '同步到 Bangumi 失败，修改已撤销：${_failure(e)}',
      );
    }
  });

  String _failure(Object error) => error is ApiException && error.status == 400
      ? 'Bangumi 拒绝了这次修改（${error.reason ?? 'HTTP 400'}）'
      : errorMessage(error);

  /// Sends one queued edit to Bangumi.
  Future<void> _send(Json input) async {
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
        body: {'type': EpisodeStatus.parse('${input['status']}').remoteValue},
      );
    }
  }

  /// Sends the queued edits of [subjectId], left by a run that closed or
  /// lost its connection mid-send. Bangumi rejecting one drops it and pulls
  /// the subject back; other failures keep them queued.
  Future<void> _upload(String user, int subjectId) async {
    final rows = [
      for (final row in await store.pending(user))
        if (object(row['body'])['subjectId'] == subjectId) row,
    ];
    if (rows.isEmpty) return;
    // Bangumi requires a subject collection before accepting episode edits.
    rows.sort((a, b) {
      final aEpisode = object(a['body'])['kind'] == 'subject' ? 0 : 1;
      final bEpisode = object(b['body'])['kind'] == 'subject' ? 0 : 1;
      final kind = aEpisode.compareTo(bEpisode);
      return kind != 0
          ? kind
          : (a['sequence'] as int).compareTo(b['sequence'] as int);
    });
    var rejected = false;
    for (final row in rows) {
      if (_closed || user != account.userId) throw StateError('账号已经切换');
      try {
        await _send(object(row['body']));
      } on ApiException catch (e) {
        if (e.status != 400 && e.status != 404) rethrow;
        rejected = true;
      }
      await store.acknowledge(row['sequence'] as int);
    }
    if (rejected) await refreshEntry(subjectId);
  }

  /// Uploads every queued edit of the current account, subject by subject.
  Future<void> _uploadQueued() async {
    final user = account.userId;
    if (user == 'local' || _closed) return;
    final subjects = {
      for (final row in await store.pending(user))
        number(object(row['body'])['subjectId']).toInt(),
    };
    for (final id in subjects) {
      await _inOrder(user, id, () => _upload(user, id));
    }
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

  /// A Bangumi collection entry in the shape the collection is stored.
  static Json _remoteRow(Json row) {
    final s = object(row['subject']);
    return {
      'subjectId': row['subject_id'],
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
      'status': CollectionStatus.fromRemote(number(row['type']).toInt()).key,
      'userScore': row['rate'],
      'collectionTags': row['tags'] is List ? row['tags'] : [],
      'comment': row['comment'] ?? '',
      'watchedEpisodes': row['ep_status'],
    };
  }

  Future<void> _refreshCollection() async {
    if (account.profile == null) return;
    final requestedAt = DateTime.now().millisecondsSinceEpoch;
    final user = account.userId;
    final username = Uri.encodeComponent('${account.profile!.username}');
    final remote = <String, Json>{};
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
        remote['${row['subject_id']}'] = _remoteRow(row);
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
    _changed();
    // Edits left queued by an earlier run go up once Bangumi answers again.
    await _uploadQueued().catchError((Object _) {});
  }

  /// Pulls the collection entry and episode progress of [subjectId]; with
  /// [useCache], not again within a minute.
  Future<void> refreshEntry(int subjectId, {bool useCache = false}) async {
    if (account.profile == null) return;
    final user = account.userId;
    final key = '$user:$subjectId';
    final active = _entryRefreshes[key];
    if (active != null) return active;
    final refreshedAt = _entryRefreshedAt[key];
    if (useCache &&
        refreshedAt != null &&
        DateTime.now().difference(refreshedAt) < const Duration(minutes: 1)) {
      return;
    }
    final request = Future.wait([
      _refreshEpisodes(subjectId, user),
      _refreshCollected(subjectId, user),
    ]);
    _entryRefreshes[key] = request;
    try {
      await request;
      if (!_closed && user == account.userId) {
        _entryRefreshedAt[key] = DateTime.now();
      }
    } finally {
      _entryRefreshes.remove(key);
    }
  }

  /// Pulls the progress of those [subjectIds] in the collection.
  Future<void> refreshProgress(Iterable<int> subjectIds) async {
    final user = account.userId;
    await Future.wait([
      for (final id in subjectIds)
        () async {
          if (await store.get(_collection(user), '$id') != null) {
            await refreshEntry(id, useCache: true);
          }
        }(),
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

  /// Pulls whether and how [subjectId] is collected; an unchanged entry
  /// writes nothing.
  Future<void> _refreshCollected(int subjectId, String user) async {
    final requestedAt = DateTime.now().millisecondsSinceEpoch;
    final username = Uri.encodeComponent('${account.profile!.username}');
    Json? row;
    try {
      row = object(
        await account.request('/v0/users/$username/collections/$subjectId'),
      );
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
    if (user != account.userId || _closed) return;
    final local = await store.get(_collection(user), '$subjectId');
    if (row == null || number(row['type']) == 0) {
      if (local == null) return;
      await store.removeUnchanged(
        _collection(user),
        '$subjectId',
        account: user,
        entity: 'subject:$subjectId',
        requestedAt: requestedAt,
      );
    } else {
      final remote = _remoteRow(row);
      if (local != null &&
          remote.entries.every(
            (e) => jsonEncode(e.value) == jsonEncode(local[e.key]),
          )) {
        return;
      }
      await store.mergeRemote(
        _collection(user),
        {'$subjectId': remote},
        account: user,
        entityKind: 'subject',
        requestedAt: requestedAt,
      );
    }
    _changed();
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
        throw const FormatException('章节列表未完整接收，请稍后再试');
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
        throw const FormatException('章节列表未完整接收，请稍后再试');
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

  void _changed() {
    if (!_closed) changes.add(null);
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(
      [
        ..._subjectQueues.values,
        ..._collectionRefreshes.values,
        ..._entryRefreshes.values,
      ].map((request) async {
        try {
          await request;
        } catch (_) {
          // The caller owns error reporting.
        }
      }),
    );
    await changes.close();
  }
}
