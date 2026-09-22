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
  }) async {
    await database.transaction((tx) async {
      final pending = (await tx.query(
        'mutations',
        where: 'account=?',
        whereArgs: [account],
      )).map((row) => row['entity']).toSet();
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
        if (pending.contains('$entityKind:$id') ||
            (row['updated'] as int) >= requestedAt) {
          merged[id] = object(jsonDecode(row['body'] as String));
          updated[id] = row['updated'] as int;
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
  }) async {
    await database.transaction((tx) async {
      if (defaults != null) {
        final rows = await tx.query(
          'documents',
          where: 'scope=? AND id=?',
          whereArgs: [scope, id],
        );
        if (rows.isEmpty) mutation = {...?initialMutation, ...mutation};
        value = {
          ...defaults,
          if (rows.isNotEmpty)
            ...object(jsonDecode(rows.single['body'] as String)),
          ...value,
        };
      }
      await tx.insert('documents', {
        'scope': scope,
        'id': id,
        'body': jsonEncode(value),
        'updated': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (account != 'local') {
        await tx.insert('mutations', {
          'account': account,
          'entity': entity,
          'body': jsonEncode(mutation),
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
