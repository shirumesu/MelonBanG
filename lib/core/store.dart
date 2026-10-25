import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/collection_edit.dart';
import 'json.dart';

/// The Dart application owns a fresh database, separate from earlier runtimes.
class AppStore {
  AppStore._(this.database);
  final Database database;
  static Future<AppStore> open(String path) async {
    sqfliteFfiInit();
    return AppStore._(
      await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 5,
          onUpgrade: (db, oldVersion, _) async {
            if (oldVersion < 2) await _createIndexes(db);
            if (oldVersion < 3) {
              await _createImageCache(db);
            } else if (oldVersion < 4) {
              await db.execute(
                'ALTER TABLE cached_images ADD COLUMN accessed INTEGER NOT NULL DEFAULT 0',
              );
              await db.execute('UPDATE cached_images SET accessed=saved');
              await _createImageAccessIndex(db);
            }
            // Danmaku source offsets were removed with their controls.
            if (oldVersion < 5) {
              await db.execute('DROP TABLE IF EXISTS danmaku_offsets');
            }
          },
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE documents (scope TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, updated INTEGER NOT NULL, PRIMARY KEY(scope,id))',
            );
            await db.execute(
              'CREATE TABLE mutations (sequence INTEGER PRIMARY KEY AUTOINCREMENT, account TEXT NOT NULL, entity TEXT NOT NULL, body TEXT NOT NULL)',
            );
            await _createIndexes(db);
            await _createImageCache(db);
          },
        ),
      ),
    );
  }

  static Future<void> _createImageCache(Database db) async {
    await db.execute(
      'CREATE TABLE cached_images (url TEXT PRIMARY KEY, bytes BLOB NOT NULL, saved INTEGER NOT NULL, accessed INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX cached_images_saved ON cached_images(saved)',
    );
    await _createImageAccessIndex(db);
  }

  static Future<void> _createImageAccessIndex(Database db) => db.execute(
    'CREATE INDEX cached_images_accessed ON cached_images(accessed DESC, url)',
  );

  static Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX documents_recent ON documents(scope, updated DESC, id ASC)',
    );
    await db.execute(
      "CREATE INDEX documents_subject ON documents(scope, json_extract(body, '\$.subjectId'))",
    );
    await db.execute(
      'CREATE INDEX mutations_account ON mutations(account, sequence)',
    );
    await db.execute(
      'CREATE INDEX mutations_entity ON mutations(account, entity, sequence)',
    );
  }

  Future<Json?> get(String scope, String id) async {
    final rows = await database.query(
      'documents',
      where: 'scope=? AND id=?',
      whereArgs: [scope, id],
    );
    return rows.isEmpty
        ? null
        : object(jsonDecode(rows.first['body'] as String));
  }

  Future<List<Json>> list(
    String scope, {
    int? subjectId,
    String? idPrefix,
    int? limit,
    int offset = 0,
  }) async => (await entries(
    scope,
    subjectId: subjectId,
    idPrefix: idPrefix,
    limit: limit,
    offset: offset,
  )).values.toList();

  Future<Map<String, Json>> entries(
    String scope, {
    int? subjectId,
    String? idPrefix,
    int? limit,
    int offset = 0,
  }) async {
    final clauses = ['scope=?'];
    final arguments = <Object?>[scope];
    if (subjectId != null) {
      clauses.add("json_extract(body, '\$.subjectId')=?");
      arguments.add(subjectId);
    }
    if (idPrefix != null) {
      clauses.add('id>=? AND id<?');
      arguments.addAll([idPrefix, '$idPrefix\uffff']);
    }
    return {
      for (final row in await database.query(
        'documents',
        columns: ['id', 'body'],
        where: clauses.join(' AND '),
        whereArgs: arguments,
        orderBy: 'updated DESC, id ASC',
        limit: limit,
        offset: offset,
      ))
        row['id'] as String: object(jsonDecode(row['body'] as String)),
    };
  }

  Future<int> pendingCount(String account) async =>
      (await database.rawQuery(
            'SELECT COUNT(*) AS count FROM mutations WHERE account=?',
            [account],
          )).single['count']
          as int;

  Future<Map<int, int>> watchedEpisodeCounts(String scope) async => {
    for (final row in await database.rawQuery(
      "SELECT json_extract(body, '\$.subjectId') AS subject, COUNT(*) AS count "
      "FROM documents WHERE scope=? AND json_extract(body, '\$.status')='watched' "
      "GROUP BY json_extract(body, '\$.subjectId')",
      [scope],
    ))
      if (row['subject'] is int) row['subject'] as int: row['count'] as int,
  };

  Future<void> putAll(String scope, Map<String, Json> values) async {
    if (values.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.transaction((tx) async {
      final batch = tx.batch();
      for (final entry in values.entries) {
        batch.insert('documents', {
          'scope': scope,
          'id': entry.key,
          'body': jsonEncode(entry.value),
          'updated': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> put(String scope, String id, Json body) async {
    await database.insert('documents', {
      'scope': scope,
      'id': id,
      'body': jsonEncode(body),
      'updated': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(String scope, String id) async {
    await database.delete(
      'documents',
      where: 'scope=? AND id=?',
      whereArgs: [scope, id],
    );
  }

  Future<void> clear(String scope) async {
    await database.delete('documents', where: 'scope=?', whereArgs: [scope]);
  }

  Future<void> enqueue(String account, String entity, Json body) async {
    await database.insert('mutations', {
      'account': account,
      'entity': entity,
      'body': jsonEncode(body),
    });
  }

  Future<void> mergeRemote(
    String scope,
    Map<String, Json> values, {
    required String account,
    required String entityKind,
    required int requestedAt,
    bool replace = false,
    Set<String> preserveEpisodeCounts = const {},
    Set<String> preserveEntities = const {},
    Map<String, Set<String>> preserveFields = const {},
    String? episodeCollectionScope,
    int? episodeSubjectId,
  }) async {
    await database.transaction((tx) async {
      final pendingRows = (await tx.query(
        'mutations',
        where: 'account=?',
        whereArgs: [account],
      ));
      final pending = pendingRows.map((row) => row['entity']).toSet();
      final pendingBodies = [
        for (final row in pendingRows)
          (
            entity: row['entity'],
            body: object(jsonDecode(row['body'] as String)),
          ),
      ];
      final local = await tx.query(
        'documents',
        where: episodeSubjectId == null
            ? 'scope=?'
            : "scope=? AND json_extract(body, '\$.subjectId')=?",
        whereArgs: [scope, ?episodeSubjectId],
      );
      final merged = Map<String, Json>.from(values);
      final updated = <String, int>{};
      // Preserve edits made while the request was in flight, even if their
      // queued writes were already acknowledged before the response arrived.
      for (final row in local) {
        final id = row['id'] as String;
        final body = object(jsonDecode(row['body'] as String));
        if (entityKind == 'subject') {
          final fields = {...?preserveFields[id]};
          for (final mutation in pendingBodies) {
            if (mutation.entity == 'subject:$id') {
              fields.addAll(collectionMutationFields(mutation.body).keys);
            }
          }
          final fieldTimes = object(body['_collectionFieldUpdated']);
          fields.addAll(
            fieldTimes.keys.where(
              (field) => number(fieldTimes[field]) >= requestedAt,
            ),
          );
          if (fields.isNotEmpty) {
            merged[id] ??= {...body};
            for (final field in fields) {
              final localField = collectionFieldNames[field];
              if (localField != null) {
                merged[id]![localField] = body[localField];
              }
            }
          }
          if (merged[id] != null) {
            merged[id]!['_collectionFieldUpdated'] = fieldTimes;
            final pendingEpisodes = pendingBodies.any(
              (mutation) =>
                  mutation.body['kind'] != 'subject' &&
                  '${mutation.body['subjectId']}' == id,
            );
            if (preserveEpisodeCounts.contains(id) ||
                pendingEpisodes ||
                number(body['_episodeCountUpdated']) >= requestedAt) {
              merged[id]!['watchedEpisodes'] = body['watchedEpisodes'];
            }
            merged[id]!['_episodeCountUpdated'] = body['_episodeCountUpdated'];
          }
          continue;
        }
        if (pending.contains('$entityKind:$id') ||
            preserveEntities.contains('$entityKind:$id') ||
            (row['updated'] as int) >= requestedAt) {
          merged[id] = body;
          updated[id] = row['updated'] as int;
        } else if (preserveEpisodeCounts.contains(id) &&
            merged.containsKey(id)) {
          if (body['watchedEpisodes'] != null) {
            merged[id] = {
              ...merged[id]!,
              'watchedEpisodes': body['watchedEpisodes'],
            };
          }
        }
      }
      if (replace) {
        await tx.delete('documents', where: 'scope=?', whereArgs: [scope]);
      }
      for (final entry in merged.entries) {
        await tx.insert('documents', {
          'scope': scope,
          'id': entry.key,
          'body': jsonEncode(entry.value),
          'updated': updated[entry.key] ?? requestedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (episodeCollectionScope != null && episodeSubjectId != null) {
        await _updateWatchedCount(
          tx,
          episodeCollectionScope,
          episodeSubjectId,
          (_) async => merged.values
              .where(
                (episode) =>
                    episode['subjectId'] == episodeSubjectId &&
                    episode['status'] == 'watched',
              )
              .length,
        );
      }
    });
  }

  /// Sets the collection row of [subjectId] to [count] watched episodes,
  /// given its current body, when the subject is collected.
  static Future<void> _updateWatchedCount(
    Transaction tx,
    String collectionScope,
    Object? subjectId,
    Future<int> Function(Json body) count,
  ) async {
    const where = 'scope=? AND id=?';
    final args = [collectionScope, '$subjectId'];
    final collection = await tx.query(
      'documents',
      where: where,
      whereArgs: args,
    );
    if (collection.isEmpty) return;
    final body = object(jsonDecode(collection.single['body'] as String));
    body['watchedEpisodes'] = await count(body);
    final now = DateTime.now().millisecondsSinceEpoch;
    body['_episodeCountUpdated'] = now;
    await tx.update(
      'documents',
      {'body': jsonEncode(body), 'updated': now},
      where: where,
      whereArgs: args,
    );
  }

  /// The episodes of [subjectId] in [scope] marked watched.
  static Future<int> _watchedCount(
    Transaction tx,
    String scope,
    Object? subjectId,
  ) async =>
      (await tx.rawQuery(
            'SELECT COUNT(*) AS count FROM documents '
            "WHERE scope=? AND json_extract(body, '\$.subjectId')=? "
            "AND json_extract(body, '\$.status')='watched'",
            [scope, subjectId],
          )).single['count']
          as int;

  Future<void> mutate(
    String scope,
    String id,
    Json value,
    String account,
    String entity,
    Json mutation, {
    Json? defaults,
    Json? initialMutation,
    String? episodeCollectionScope,
    int? excludePendingSequence,
  }) async {
    await database.transaction((tx) async {
      final rows = defaults != null || episodeCollectionScope != null
          ? await tx.query(
              'documents',
              where: 'scope=? AND id=?',
              whereArgs: [scope, id],
            )
          : <Map<String, Object?>>[];
      if (defaults != null) {
        if (rows.isEmpty && initialMutation != null) {
          mutation = {
            ...mutation,
            'fields': {
              ...collectionMutationFields(initialMutation),
              ...collectionMutationFields(mutation),
            },
          };
        }
        value = {
          ...defaults,
          if (rows.isNotEmpty)
            ...object(jsonDecode(rows.single['body'] as String)),
          ...value,
        };
      }
      if (mutation['kind'] == 'subject') {
        value['_collectionFieldUpdated'] = {
          ...object(value['_collectionFieldUpdated']),
          for (final field in collectionMutationFields(mutation).keys)
            field: DateTime.now().millisecondsSinceEpoch,
        };
      }
      await tx.insert('documents', {
        'scope': scope,
        'id': id,
        'body': jsonEncode(value),
        'updated': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (episodeCollectionScope != null) {
        final previous = rows.isEmpty
            ? null
            : object(jsonDecode(rows.single['body'] as String));
        await _updateWatchedCount(
          tx,
          episodeCollectionScope,
          value['subjectId'],
          (body) async {
            // Retain the remote total when only some episode records are
            // cached.
            if (body['watchedEpisodes'] == null) {
              return _watchedCount(tx, scope, value['subjectId']);
            }
            final watched =
                number(body['watchedEpisodes']).toInt() +
                (value['status'] == 'watched' ? 1 : 0) -
                (previous?['status'] == 'watched' ? 1 : 0);
            return watched < 0 ? 0 : watched;
          },
        );
      }
      if (account != 'local') {
        if (mutation['kind'] == 'subject') {
          final pending = await tx.query(
            'mutations',
            where: 'account=? AND entity=?',
            whereArgs: [account, entity],
            orderBy: 'sequence',
          );
          final editable = pending
              .where((row) => row['sequence'] != excludePendingSequence)
              .toList();
          if (editable.isNotEmpty) {
            final fields = <String, dynamic>{};
            for (final row in editable) {
              fields.addAll(
                collectionMutationFields(
                  object(jsonDecode(row['body'] as String)),
                ),
              );
              await tx.delete(
                'mutations',
                where: 'sequence=?',
                whereArgs: [row['sequence']],
              );
            }
            mutation = {
              ...mutation,
              'fields': {...fields, ...collectionMutationFields(mutation)},
            };
          }
        }
        await tx.insert('mutations', {
          'account': account,
          'entity': entity,
          'body': jsonEncode(mutation),
        });
      }
    });
  }

  Future<void> markEpisodes(
    String scope,
    String collectionScope,
    String account,
    int subjectId,
    List<int> episodeIds,
  ) async {
    await database.transaction((tx) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final id in episodeIds) {
        await tx.insert('documents', {
          'scope': scope,
          'id': '$id',
          'body': jsonEncode({
            'subjectId': subjectId,
            'episodeId': id,
            'status': 'watched',
          }),
          'updated': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _updateWatchedCount(
        tx,
        collectionScope,
        subjectId,
        (_) => _watchedCount(tx, scope, subjectId),
      );
      if (account != 'local') {
        await tx.insert('mutations', {
          'account': account,
          'entity': 'episodes:$subjectId',
          'body': jsonEncode({
            'kind': 'episodes',
            'subjectId': subjectId,
            'episodeIds': episodeIds,
            'status': 'watched',
          }),
        });
      }
    });
  }

  Future<List<Json>> pending(String account) async =>
      (await database.query(
            'mutations',
            where: 'account=?',
            whereArgs: [account],
            orderBy: 'sequence',
          ))
          .map((r) => {...r, 'body': object(jsonDecode(r['body'] as String))})
          .toList();
  Future<void> acknowledge(int sequence) async {
    await database.delete(
      'mutations',
      where: 'sequence=?',
      whereArgs: [sequence],
    );
  }

  Future<void> close() => database.close();
}
