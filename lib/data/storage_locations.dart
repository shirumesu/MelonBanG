import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'json.dart';
import 'store.dart';

/// The small bootstrap file stays in application support, outside movable data.
class StorageLocations {
  StorageLocations(this.bootstrap, this.defaultData);
  final File bootstrap;
  final String defaultData;
  Json _state = {};
  void Function(String)? onProgress;
  String get data => _state['data'] as String? ?? defaultData;
  String get media =>
      _state['media'] as String? ?? p.join(defaultData, 'downloads');
  String get credentialIdentity =>
      _state['credentialIdentity'] as String? ??
      p.join(defaultData, 'credentials');
  List<String> get previousMedia =>
      List<String>.from(_state['previousMedia'] ?? []);
  Json? get pending =>
      _state['pending'] == null ? null : object(_state['pending']);

  Future<void> load() async {
    if (await bootstrap.exists()) {
      _state = object(jsonDecode(await bootstrap.readAsString()));
    }
  }

  Future<void> _save(Json value) async {
    await bootstrap.parent.create(recursive: true);
    final temporary = File('${bootstrap.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(bootstrap.path);
    _state = value;
  }

  Future<void> schedule({String? dataPath, String? mediaPath}) async {
    final nextData = p.normalize(
      p.absolute(dataPath ?? pending?['data'] as String? ?? data),
    );
    final nextMedia = p.normalize(
      p.absolute(mediaPath ?? pending?['media'] as String? ?? media),
    );
    if (nextData == data && nextMedia == media) return;
    await Directory(media).create(recursive: true);
    for (final target in [
      if (nextData != data) nextData,
      if (nextMedia != media) nextMedia,
    ]) {
      for (final current in [data, media, bootstrap.parent.path]) {
        if (p.equals(target, current) ||
            p.isWithin(current, target) ||
            p.isWithin(target, current)) {
          throw StateError('请选择与现有数据目录分开的空文件夹');
        }
      }
      final folder = Directory(target);
      await folder.create(recursive: true);
      if (!await folder.list().isEmpty) throw StateError('目标文件夹必须为空，避免覆盖现有文件');
      final probe = File(p.join(target, '.melonbang-write-check'));
      await probe.writeAsString('');
      await probe.delete();
    }
    if (p.equals(nextData, nextMedia) ||
        p.isWithin(nextData, nextMedia) ||
        p.isWithin(nextMedia, nextData)) {
      // Existing installations may still keep downloads inside application data.
      if (nextData != data && nextMedia != media) {
        throw StateError('应用数据与媒体缓存需要使用独立目录');
      }
    }
    await _save({
      ..._state,
      'data': data,
      'media': media,
      'credentialIdentity': credentialIdentity,
      'pending': {'data': nextData, 'media': nextMedia, 'id': newId()},
    });
  }

  Future<void> cancel() => _save({..._state}..remove('pending'));

  /// Runs before any database, credentials or torrent handles have been opened.
  Future<void> migrate() async {
    final plan = pending;
    if (plan == null) return;
    final oldData = data, oldMedia = media;
    final nextData = '${plan['data']}', nextMedia = '${plan['media']}';
    if (nextData != oldData) {
      await _copyTree(oldData, nextData, '${plan['id']}', exclude: oldMedia);
    }
    if (nextMedia != oldMedia) {
      await _copyTree(oldMedia, nextMedia, '${plan['id']}');
      final database = File(p.join(nextData, 'melonbang.sqlite'));
      if (await database.exists()) {
        final store = await AppStore.open(database.path);
        try {
          await store.database.transaction((tx) async {
            final rows = await tx.query(
              'documents',
              where: 'scope IN (?, ?, ?)',
              whereArgs: ['downloads', 'episode_files', 'danmaku_matches'],
            );
            for (final row in rows) {
              final body = object(jsonDecode(row['body'] as String));
              void remap(Json value, String key) {
                final path = value[key];
                if (path is String &&
                    (p.equals(path, oldMedia) || p.isWithin(oldMedia, path))) {
                  value[key] = p.join(
                    nextMedia,
                    p.relative(path, from: oldMedia),
                  );
                }
              }

              for (final key in ['path', 'savePath', 'metadataPath', 'input']) {
                remap(body, key);
              }
              body['files'] = body['files'] == null
                  ? null
                  : objects(body['files']).map((file) {
                      remap(file, 'path');
                      return file;
                    }).toList();
              await tx.update(
                'documents',
                {
                  'body': jsonEncode(body),
                  if (row['scope'] == 'danmaku_matches' &&
                      p.isWithin(oldMedia, '${row['id']}'))
                    'id': p.join(
                      nextMedia,
                      p.relative('${row['id']}', from: oldMedia),
                    ),
                },
                where: 'scope=? AND id=?',
                whereArgs: [row['scope'], row['id']],
              );
            }
          });
        } finally {
          await store.close();
        }
      }
    }
    await _save(
      {
        ..._state,
        'data': nextData,
        'media': nextMedia,
        'previousMedia': {
          ...previousMedia,
          if (nextMedia != oldMedia) oldMedia,
        }.toList(),
      }..remove('pending'),
    );
    // Originals remain a recovery copy; never recursively delete a user-selected folder.
  }

  Future<void> _copyTree(
    String source,
    String target,
    String id, {
    String? exclude,
  }) async {
    final marker = File(p.join(target, '.melonbang-migration'));
    await Directory(target).create(recursive: true);
    if (await marker.exists()) {
      if (await marker.readAsString() != id) throw StateError('目标目录属于另一项迁移');
    } else {
      if (!await Directory(target).list().isEmpty) {
        throw StateError('目标目录已包含其他文件，迁移已停止');
      }
      await marker.writeAsString(id, flush: true);
    }
    if (!await Directory(source).exists()) {
      throw FileSystemException('原目录不可用，请连接磁盘后重新启动以继续迁移', source);
    }
    Future<void> copyDirectory(Directory directory) async {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity.path == exclude ||
            p.basename(entity.path) == '.melonbang-migration') {
          continue;
        }
        final destination = p.join(
          target,
          p.relative(entity.path, from: source),
        );
        if (entity is Directory) {
          await Directory(destination).create(recursive: true);
          await copyDirectory(entity);
        } else if (entity is File) {
          onProgress?.call('正在迁移：${p.basename(entity.path)}');
          final output = await entity.copy(destination);
          onProgress?.call('正在校验：${p.basename(entity.path)}');
          final before = await sha256.bind(entity.openRead()).first;
          final after = await sha256.bind(output.openRead()).first;
          if (before != after) {
            throw FileSystemException('文件迁移校验失败', entity.path);
          }
        } else {
          throw FileSystemException('数据目录中包含链接，请先移除链接再迁移', entity.path);
        }
      }
    }

    await copyDirectory(Directory(source));
  }
}
