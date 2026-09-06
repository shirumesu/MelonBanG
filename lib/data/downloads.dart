import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart' as lt;
import 'package:path/path.dart' as p;

import 'json.dart';
import 'store.dart';

class DownloadRepository {
  DownloadRepository(this.store, String directory)
    : directory = p.normalize(p.absolute(directory));
  final AppStore store;
  final String directory;
  final changes = StreamController<Json>.broadcast();
  final _tasks = <String, Json>{};
  final _handles = <String, int>{};
  final _files = <String, List<Json>>{};
  final _adding = <String, Future<Json>>{};
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  bool _closed = false;
  Future<void> initialize() async {
    for (final task in await store.list('downloads')) {
      _tasks['${task['id']}'] = task;
    }
    if (_tasks.isNotEmpty) await _engine();
    for (final task in _tasks.values.toList()) {
      try {
        _attach(task);
      } catch (e) {
        task['status'] = 'failed';
        task['errorMessage'] = e.toString();
      }
    }
    _emit();
  }

  Future<void> _engine() => _initializing ??= () async {
    await Directory(directory).create(recursive: true);
    await lt.LibtorrentFlutter.init(
      defaultSavePath: directory,
      fetchTrackers: false,
    );
    _subscription = lt.LibtorrentFlutter.instance.torrentUpdates.listen((
      snapshot,
    ) {
      for (final entry in _handles.entries.toList()) {
        final info = snapshot[entry.value];
        final task = _tasks[entry.key];
        if (info == null || task == null) continue;
        task.addAll({
          'title': info.name.isEmpty ? task['title'] : info.name,
          'status': info.errorMsg.isNotEmpty
              ? 'failed'
              : info.isPaused
              ? 'paused'
              : info.isFinished
              ? 'completed'
              : info.hasMetadata
              ? 'downloading'
              : 'metadata',
          'progress': info.progress,
          'downloadSpeedBytesPerSecond': info.downloadRate,
          'peerCount': info.numPeers,
          'errorMessage': info.errorMsg.isEmpty ? null : info.errorMsg,
          'totalBytes': info.totalWanted,
          'downloadedBytes': info.totalDone,
        });
        if (info.hasMetadata) {
          _files[entry.key] = lt.LibtorrentFlutter.instance
              .getFiles(entry.value)
              .map(
                (file) => {
                  'id': '${file.index}',
                  'downloadId': entry.key,
                  'name': file.name,
                  'path': p.join('${task['savePath']}', file.path),
                  'size': file.size,
                  'progress': info.isFinished ? 1.0 : 0.0,
                  'mediaKind': file.isStreamable ? 'video' : 'other',
                },
              )
              .toList();
        }
        final saved = Map<String, dynamic>.from(task);
        _writes = _writes.then((_) => store.put('downloads', entry.key, saved));
      }
      _emit();
    });
  }();
  void _attach(Json task) {
    final id = '${task['id']}';
    final engine = lt.LibtorrentFlutter.instance;
    final handle = task['kind'] == 'magnet'
        ? engine.addMagnet('${task['input']}', '${task['savePath']}')
        : engine.addTorrentFile('${task['input']}', '${task['savePath']}');
    _handles[id] = handle;
    if (task['status'] == 'paused') engine.pauseTorrent(handle);
  }

  Json snapshot() => {
    'tasks': _tasks.values.map((t) => Map<String, dynamic>.from(t)).toList(),
    'files': _files.values.expand((v) => v).toList(),
  };
  Future<Json> addMagnet(String input, {int? subjectId, int? episodeId}) async {
    final uri = Uri.tryParse(input.trim());
    final hashes = uri?.queryParametersAll['xt'] ?? [];
    if (uri?.scheme != 'magnet' ||
        !hashes.any(
          (v) =>
              RegExp(r'^urn:btih:([a-fA-F0-9]{40}|[A-Z2-7a-z]{32})$')
                  .hasMatch(v),
        )) {
      throw const FormatException('磁力链接缺少有效的 BT info hash');
    }
    return _add(
      'magnet',
      uri.toString(),
      hashes.first.toLowerCase(),
      uri?.queryParameters['dn'] ?? '正在获取种子信息',
      subjectId,
      episodeId,
    );
  }

  Future<Json> addTorrent(
    Uint8List bytes,
    String name, {
    int? subjectId,
    int? episodeId,
  }) async {
    if (bytes.isEmpty) throw const FormatException('种子文件为空');
    final fingerprint = sha1.convert(bytes).toString();
    final metadata = p.join(directory, 'metadata');
    await Directory(metadata).create(recursive: true);
    final file = File(p.join(metadata, '$fingerprint.torrent'));
    await file.writeAsBytes(bytes, flush: true);
    return _add('torrent', file.path, fingerprint, name, subjectId, episodeId);
  }

  Future<Json> _add(
    String kind,
    String input,
    String fingerprint,
    String title,
    int? subjectId,
    int? episodeId,
  ) => _adding.putIfAbsent(
    fingerprint,
    () => _create(kind, input, fingerprint, title, subjectId, episodeId)
        .whenComplete(() {
          _adding.remove(fingerprint);
        }),
  );

  Future<Json> _create(
    String kind,
    String input,
    String fingerprint,
    String title,
    int? subjectId,
    int? episodeId,
  ) async {
    final existing = _tasks.values
        .where((t) => t['fingerprint'] == fingerprint)
        .firstOrNull;
    if (existing != null) return existing;
    await _engine();
    if (_closed) throw StateError('下载器已关闭');
    final id = newId();
    final savePath = p.join(directory, id);
    await Directory(savePath).create(recursive: true);
    final task = <String, dynamic>{
      'id': id,
      'kind': kind,
      'input': input,
      'fingerprint': fingerprint,
      'title': title,
      'savePath': savePath,
      'subjectId': subjectId,
      'episodeId': episodeId,
      'status': 'metadata',
      'progress': 0.0,
      'peerCount': 0,
      'downloadSpeedBytesPerSecond': 0,
    };
    _attach(task);
    _tasks[id] = task;
    await store.put('downloads', id, task);
    _emit();
    return task;
  }

  Future<void> pause(String id) async {
    lt.LibtorrentFlutter.instance.pauseTorrent(_handles[id]!);
    _tasks[id]!['status'] = 'paused';
    await store.put('downloads', id, _tasks[id]!);
    _emit();
  }

  Future<void> resume(String id) async {
    if (!_handles.containsKey(id)) _attach(_tasks[id]!);
    lt.LibtorrentFlutter.instance.resumeTorrent(_handles[id]!);
    _tasks[id]!['status'] = 'downloading';
    await store.put('downloads', id, _tasks[id]!);
    _emit();
  }

  Future<void> remove(String id) async {
    final task = _tasks.remove(id);
    if (task == null) return;
    final handle = _handles.remove(id);
    if (handle != null) {
      lt.LibtorrentFlutter.instance.removeTorrent(handle, deleteFiles: true);
    }
    _files.remove(id);
    await _writes;
    await store.remove('downloads', id);
    _emit();
  }

  Json media(String id, {String? fileId}) {
    final task = _tasks[id];
    if (task == null) throw StateError('下载任务不存在');
    final files =
        (_files[id] ?? [])
            .where(
              (f) =>
                  f['mediaKind'] == 'video' &&
                  (fileId == null || f['id'] == fileId),
            )
            .toList()
          ..sort((a, b) => number(b['size']).compareTo(number(a['size'])));
    if (files.isEmpty) throw StateError('尚未获取到视频文件');
    if (number(task['progress']) < 1) throw StateError('请等待下载完成后播放');
    final file = files.first;
    return {
      ...file,
      'subjectId': task['subjectId'],
      'episodeId': task['episodeId'],
    };
  }

  Json episodeMedia(int subjectId, int episodeId) {
    final task = _tasks.values
        .where(
          (t) =>
              t['subjectId'] == subjectId &&
              t['episodeId'] == episodeId &&
              number(t['progress']) >= 1,
        )
        .firstOrNull;
    if (task == null) throw StateError('该章节尚无完成的下载，请先选择资源或打开本地文件');
    return media('${task['id']}');
  }

  void _emit() {
    if (!_closed) changes.add(snapshot());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _writes;
    if (_initializing != null) {
      await _initializing;
      final engine = lt.LibtorrentFlutter.instance;
      // The upstream disposeAll deletes files. Detach all handles without
      // deleting data first, so closing the app preserves downloaded episodes.
      for (final handle in _handles.values.toSet()) {
        engine.removeTorrent(handle, deleteFiles: false);
      }
      _handles.clear();
      await engine.dispose();
    }
    await changes.close();
  }
}
