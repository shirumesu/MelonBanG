import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE documents (scope TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, updated INTEGER NOT NULL, PRIMARY KEY(scope,id))',
            );
            await db.execute(
              'CREATE TABLE mutations (sequence INTEGER PRIMARY KEY AUTOINCREMENT, account TEXT NOT NULL, entity TEXT NOT NULL, body TEXT NOT NULL)',
            );
          },
        ),
      ),
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

  Future<List<Json>> list(String scope) async => (await database.query(
    'documents',
    where: 'scope=?',
    whereArgs: [scope],
    orderBy: 'updated DESC',
  )).map((r) => object(jsonDecode(r['body'] as String))).toList();

  Future<Map<String, Json>> entries(String scope) async => {
    for (final row in await database.query(
      'documents',
      where: 'scope=?',
      whereArgs: [scope],
      orderBy: 'updated DESC, id ASC',
    ))
      row['id'] as String: object(jsonDecode(row['body'] as String)),
  };
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

  Future<void> replace(String scope, Map<String, Json> values) async {
    await database.transaction((tx) async {
      await tx.delete('documents', where: 'scope=?', whereArgs: [scope]);
      for (final entry in values.entries) {
        await tx.insert('documents', {
          'scope': scope,
          'id': entry.key,
          'body': jsonEncode(entry.value),
          'updated': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
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
      final local = await tx.query(
        'documents',
        where: 'scope=?',
        whereArgs: [scope],
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
          for (final mutation in pendingRows) {
            if (mutation['entity'] == 'subject:$id') {
              fields.addAll(
                collectionMutationFields(
                  object(jsonDecode(mutation['body'] as String)),
                ).keys,
              );
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
            final pendingEpisodes = pendingRows.any((mutation) {
              final input = object(jsonDecode(mutation['body'] as String));
              return input['kind'] != 'subject' &&
                  '${input['subjectId']}' == id;
            });
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
        final collection = await tx.query(
          'documents',
          where: 'scope=? AND id=?',
          whereArgs: [episodeCollectionScope, '$episodeSubjectId'],
        );
        if (collection.isNotEmpty) {
          final body = object(jsonDecode(collection.single['body'] as String));
          body['watchedEpisodes'] = merged.values
              .where(
                (episode) =>
                    episode['subjectId'] == episodeSubjectId &&
                    episode['status'] == 'watched',
              )
              .length;
          body['_episodeCountUpdated'] = DateTime.now().millisecondsSinceEpoch;
          await tx.update(
            'documents',
            {
              'body': jsonEncode(body),
              'updated': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'scope=? AND id=?',
            whereArgs: [episodeCollectionScope, '$episodeSubjectId'],
          );
        }
      }
    });
  }

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
        final collection = await tx.query(
          'documents',
          where: 'scope=? AND id=?',
          whereArgs: [episodeCollectionScope, '${value['subjectId']}'],
        );
        if (collection.isNotEmpty) {
          final body = object(jsonDecode(collection.single['body'] as String));
          final previous = rows.isEmpty
              ? null
              : object(jsonDecode(rows.single['body'] as String));
          // Retain the remote total when only some episode records are cached.
          final watched = body['watchedEpisodes'] == null
              ? (await tx.query(
                      'documents',
                      where: 'scope=?',
                      whereArgs: [scope],
                    ))
                    .map((row) => object(jsonDecode(row['body'] as String)))
                    .where(
                      (episode) =>
                          episode['subjectId'] == value['subjectId'] &&
                          episode['status'] == 'watched',
                    )
                    .length
              : number(body['watchedEpisodes']).toInt() +
                    (value['status'] == 'watched' ? 1 : 0) -
                    (previous?['status'] == 'watched' ? 1 : 0);
          body['watchedEpisodes'] = watched < 0 ? 0 : watched;
          body['_episodeCountUpdated'] = DateTime.now().millisecondsSinceEpoch;
          await tx.update(
            'documents',
            {
              'body': jsonEncode(body),
              'updated': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'scope=? AND id=?',
            whereArgs: [episodeCollectionScope, '${value['subjectId']}'],
          );
        }
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
      final collection = await tx.query(
        'documents',
        where: 'scope=? AND id=?',
        whereArgs: [collectionScope, '$subjectId'],
      );
      if (collection.isNotEmpty) {
        final body = object(jsonDecode(collection.single['body'] as String));
        body['watchedEpisodes'] =
            (await tx.query('documents', where: 'scope=?', whereArgs: [scope]))
                .map((row) => object(jsonDecode(row['body'] as String)))
                .where(
                  (episode) =>
                      episode['subjectId'] == subjectId &&
                      episode['status'] == 'watched',
                )
                .length;
        body['_episodeCountUpdated'] = now;
        await tx.update(
          'documents',
          {'body': jsonEncode(body), 'updated': now},
          where: 'scope=? AND id=?',
          whereArgs: [collectionScope, '$subjectId'],
        );
      }
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
