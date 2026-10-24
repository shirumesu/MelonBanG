import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'error_message.dart';
import 'json.dart';
import 'store.dart';

/// How far the background copy of a pending move has got.
class MoveCopy {
  const MoveCopy({
    this.done = 0,
    this.total = 0,
    this.file = '',
    this.error,
    this.left,
  });

  /// Bytes read so far, copying and then verifying each file, of [total].
  final int done, total;
  final String file;
  final String? error;

  /// Files in use that the next start copies, once the copy has finished.
  final int? left;
}

/// The small bootstrap file stays in application support, outside movable data.
class StorageLocations {
  StorageLocations(this.bootstrap, this.defaultData);
  final File bootstrap;
  final String defaultData;
  Json _state = {};
  void Function(String)? onProgress;

  /// The background copy of the pending move.
  final copy = ValueNotifier<MoveCopy?>(null);
  Future<void>? _copying;
  String get data => _state['data'] as String? ?? defaultData;
  String get media =>
      _state['media'] as String? ?? p.join(defaultData, 'downloads');
  String get credentialIdentity =>
      _state['credentialIdentity'] as String? ??
      p.join(defaultData, 'credentials');
  Json? get pending =>
      _state['pending'] == null ? null : object(_state['pending']);

  Future<void> load() async {
    if (await bootstrap.exists()) {
      _state = object(jsonDecode(await bootstrap.readAsString()));
    }
  }

  /// Nothing has been stored yet, so the first locations can be chosen freely.
  Future<bool> get fresh async =>
      !await bootstrap.exists() && !await Directory(defaultData).exists();

  /// Where a fresh installation keeps its media, before anything is stored.
  Future<void> choose(String mediaPath) async {
    final folder = Directory(mediaPath);
    await folder.create(recursive: true);
    if (!await folder.list().isEmpty) throw StateError('目标文件夹必须为空，避免覆盖现有文件');
    final probe = File(p.join(mediaPath, '.melonbang-write-check'));
    await probe.writeAsString('');
    await probe.delete();
    await _save({'media': p.normalize(p.absolute(mediaPath))});
  }

  Future<void> _save(Json value) async {
    await bootstrap.parent.create(recursive: true);
    final temporary = File('${bootstrap.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(bootstrap.path);
    _state = value;
  }

  /// The data and media folders after moving to [dataPath] or [mediaPath],
  /// once each new one is known to be separate, empty and writable. Folders
  /// created only to check are removed again.
  Future<(String, String)> check({String? dataPath, String? mediaPath}) async {
    final nextData = p.normalize(p.absolute(dataPath ?? data));
    final nextMedia = p.normalize(p.absolute(mediaPath ?? media));
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
      final created = !await folder.exists();
      try {
        await folder.create(recursive: true);
        if (!await folder.list().isEmpty) {
          throw StateError('目标文件夹必须为空，避免覆盖现有文件');
        }
        final probe = File(p.join(target, '.melonbang-write-check'));
        await probe.writeAsString('');
        await probe.delete();
        if (created) await folder.delete();
      } on FileSystemException {
        throw StateError('没有权限写入这个文件夹，请选择其他位置');
      }
    }
    if (p.equals(nextData, nextMedia) ||
        p.isWithin(nextData, nextMedia) ||
        p.isWithin(nextMedia, nextData)) {
      // Existing installations may still keep downloads inside application data.
      if (nextData != data && nextMedia != media) {
        throw StateError('应用数据与媒体缓存需要使用独立目录');
      }
    }
    return (nextData, nextMedia);
  }

  /// Plans a move and starts copying it in the background.
  Future<void> schedule({String? dataPath, String? mediaPath}) async {
    final (nextData, nextMedia) = await check(
      dataPath: dataPath,
      mediaPath: mediaPath,
    );
    if (nextData == data && nextMedia == media) return;
    await Directory(media).create(recursive: true);
    await _save({
      ..._state,
      'data': data,
      'media': media,
      'credentialIdentity': credentialIdentity,
      'pending': {'data': nextData, 'media': nextMedia, 'id': newId()},
    });
    unawaited(prepare());
  }

  /// Copies the pending move while the app keeps using the current folders,
  /// so the next start only copies what has changed since.
  Future<void> prepare() =>
      _copying ??= _prepare().whenComplete(() => _copying = null);

  Future<void> _prepare() async {
    final plan = pending;
    if (plan == null || plan['copied'] == true) return;
    bool current() => pending?['id'] == plan['id'];
    copy.value = const MoveCopy();
    try {
      final left = await _pass(plan, strict: false, (done, total, file) {
        if (current()) {
          copy.value = MoveCopy(done: done, total: total, file: file);
        }
      });
      if (!current()) return;
      await _save({
        ..._state,
        'pending': {...plan, 'copied': true},
      });
      copy.value = MoveCopy(
        done: copy.value!.total,
        total: copy.value!.total,
        left: left,
      );
    } catch (e) {
      if (current()) copy.value = MoveCopy(error: errorMessage(e));
    }
  }

  /// Drops the pending move and the files copied for it so far.
  Future<void> cancel() async {
    final plan = pending!;
    await _save({..._state}..remove('pending'));
    copy.value = null;
    await _copying;
    for (final (source, target, _) in _trees(plan)) {
      await _discard(source, target, '${plan['id']}');
    }
  }

  /// Each (source, target, excluded) folder [plan] moves.
  List<(String, String, String?)> _trees(Json plan) => [
    if (plan['data'] != data) (data, '${plan['data']}', media),
    if (plan['media'] != media) (media, '${plan['media']}', null),
  ];

  /// Copies the folders [plan] moves in an isolate, reporting progress, and
  /// returns how many files were left for a later pass.
  Future<int> _pass(
    Json plan,
    void Function(int done, int total, String file) report, {
    required bool strict,
  }) async {
    final trees = _trees(plan);
    final id = '${plan['id']}', bootstrap = this.bootstrap.path;
    final progress = ReceivePort()
      ..listen((message) {
        final (done, total, file) = message as (int, int, String);
        report(done, total, file);
      });
    try {
      return await _copyInIsolate(
        trees,
        id,
        bootstrap,
        strict,
        progress.sendPort,
      );
    } finally {
      progress.close();
    }
  }

  /// Runs before any database, credentials or torrent handles have been
  /// opened, once the background copy has finished: copies what has changed
  /// since, then switches to the new folders.
  Future<void> migrate() async {
    final plan = pending;
    if (plan == null || plan['copied'] != true) return;
    final oldMedia = media;
    final nextData = '${plan['data']}', nextMedia = '${plan['media']}';
    await _pass(
      plan,
      strict: true,
      (done, total, file) => onProgress?.call(
        file.isEmpty || total == 0
            ? '正在检查迁移的文件…'
            : '正在完成迁移 ${done * 100 ~/ total}%：$file',
      ),
    );
    if (nextMedia != oldMedia) {
      final database = File(p.join(nextData, 'melonbang.sqlite'));
      if (await database.exists()) {
        final store = await AppStore.open(database.path);
        try {
          await store.database.transaction((tx) async {
            final rows = await tx.query(
              'documents',
              where: 'scope IN (?, ?, ?)',
              whereArgs: ['downloads', 'pikpak_downloads', 'danmaku_matches'],
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
      {..._state, 'data': nextData, 'media': nextMedia}..remove('pending'),
    );
    for (final (_, target, _) in _trees(plan)) {
      await File(p.join(target, _manifest)).delete();
    }
    // Originals remain a recovery copy; never recursively delete a user-selected folder.
  }
}

const _marker = '.melonbang-migration';

/// What each copied file was copied from: relative path → [size, modified].
const _manifest = '.melonbang-migration-files';

/// Runs [_copyTrees] in its own isolate; top level, so the closure sent there
/// holds nothing but these arguments.
Future<int> _copyInIsolate(
  List<(String, String, String?)> trees,
  String id,
  String bootstrap,
  bool strict,
  SendPort progress,
) => Isolate.run(() => _copyTrees(trees, id, bootstrap, strict, progress));

/// Copies each (source, target, excluded) tree of move [id], verifying every
/// file and skipping those an earlier pass copied that have not changed
/// since. With [strict], at the switch, every file must copy and files since
/// removed from a source are removed from its target; otherwise a file that
/// cannot be copied now, such as one being written, is left for later, and
/// the pass stops once the move is no longer pending in [bootstrap]. Sends
/// (done, total, file) progress and returns how many files were left.
Future<int> _copyTrees(
  List<(String, String, String?)> trees,
  String id,
  String bootstrap,
  bool strict,
  SendPort progress,
) async {
  final files = <(String, String, File, FileStat)>[];
  final manifests = <String, Json>{};
  var total = 0;
  for (final (source, target, excluded) in trees) {
    final marker = File(p.join(target, _marker));
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
    final manifest = File(p.join(target, _manifest));
    manifests[target] = await manifest.exists()
        ? object(jsonDecode(await manifest.readAsString()))
        : {};
    final kept = {_marker, _manifest};
    await for (final entity in Directory(
      source,
    ).list(recursive: true, followLinks: false)) {
      if (excluded != null &&
          (p.equals(entity.path, excluded) ||
              p.isWithin(excluded, entity.path))) {
        continue;
      }
      final relative = p.relative(entity.path, from: source);
      kept.add(relative);
      if (entity is Directory) {
        await Directory(p.join(target, relative)).create(recursive: true);
      } else if (entity is File) {
        final stat = await entity.stat();
        files.add((target, relative, entity, stat));
        total += stat.size * 2;
      } else {
        throw FileSystemException('数据目录中包含链接，请先移除链接再迁移', entity.path);
      }
    }
    if (strict) {
      // Gone from the source since an earlier pass, like a database journal.
      final stale = await Directory(target)
          .list(recursive: true, followLinks: false)
          .where(
            (entity) => !kept.contains(p.relative(entity.path, from: target)),
          )
          .toList();
      for (final entity in stale) {
        if (await entity.exists()) await entity.delete(recursive: true);
      }
    }
  }

  var done = 0, reported = 0, left = 0;
  var saved = DateTime.now();
  Future<void> save() async {
    for (final MapEntry(key: target, value: manifest) in manifests.entries) {
      await File(p.join(target, _manifest)).writeAsString(jsonEncode(manifest));
    }
    saved = DateTime.now();
  }

  void report(String file, {bool now = false}) {
    if (!now && done - reported < 32 << 20) return;
    reported = done;
    if (!strict) {
      final pending = object(
        jsonDecode(File(bootstrap).readAsStringSync()),
      )['pending'];
      if (pending is! Map || pending['id'] != id) throw StateError('迁移已取消');
    }
    progress.send((done, total, file));
  }

  report('', now: true);
  try {
    for (final (target, relative, file, stat) in files) {
      final manifest = manifests[target]!;
      final output = File(p.join(target, relative));
      final record = [stat.size, stat.modified.microsecondsSinceEpoch];
      final start = done;
      if (listEquals(manifest[relative] as List?, record) &&
          await output.exists()) {
        done += stat.size * 2;
        continue;
      }
      final name = p.basename(file.path);
      report(name, now: true);
      try {
        await _copyFile(file, output, (bytes) {
          done += bytes;
          report(name);
        });
        await output.setLastModified(stat.modified);
        // Written to while copying; the next pass copies it again.
        final after = await file.stat();
        if (after.size == stat.size && after.modified == stat.modified) {
          manifest[relative] = record;
        } else if (strict) {
          throw FileSystemException('文件在迁移时被修改', file.path);
        } else {
          left++;
        }
      } on FileSystemException {
        if (strict) rethrow;
        left++;
      }
      done = start + stat.size * 2;
      if (DateTime.now().difference(saved).inSeconds >= 2) await save();
    }
  } finally {
    await save();
  }
  return left;
}

/// Copies [source] to [target] while hashing it, then checks the copy reads
/// back the same; [read] receives the bytes read along the way.
Future<void> _copyFile(
  File source,
  File target,
  void Function(int bytes) read,
) async {
  late Digest digest;
  final hash = sha256.startChunkedConversion(
    ChunkedConversionSink<Digest>.withCallback(
      (digests) => digest = digests.single,
    ),
  );
  final output = await target.open(mode: FileMode.write);
  try {
    await for (final chunk in source.openRead()) {
      hash.add(chunk);
      read(chunk.length);
      await output.writeFrom(chunk);
    }
  } finally {
    await output.close();
  }
  hash.close();
  final copied = await sha256
      .bind(
        target.openRead().map((chunk) {
          read(chunk.length);
          return chunk;
        }),
      )
      .first;
  if (copied != digest) throw FileSystemException('文件迁移校验失败', source.path);
}

/// Removes what move [id] copied from [source] into [target]: files at the
/// same place in the source, and folders left empty.
Future<void> _discard(String source, String target, String id) async {
  final marker = File(p.join(target, _marker));
  if (!await marker.exists() || await marker.readAsString() != id) return;
  final folders = <Directory>[];
  await for (final entity in Directory(
    target,
  ).list(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: target);
    if (entity is Directory) {
      folders.add(entity);
    } else if (entity is File &&
        (relative == _marker ||
            relative == _manifest ||
            await File(p.join(source, relative)).exists())) {
      await entity.delete();
    }
  }
  for (final folder in folders.reversed) {
    if (await folder.list().isEmpty) await folder.delete();
  }
}
