import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:libtorrent_flutter/libtorrent_flutter.dart' as lt;
import 'package:path/path.dart' as p;

import 'json.dart';
import 'bittorrent_settings.dart';
import 'store.dart';
import 'torrent_identity.dart';

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
  Future<void>? _closing;
  bool _closed = false;
  BitTorrentSettings settings = const BitTorrentSettings();
  final _verifying = <String>{};
  final _running = <String>{};
  final _uploaded = <String, int>{};
  final _clock = Stopwatch()..start();
  int _lastTick = 0, _lastSaved = 0;

  Future<void> saveSettings(BitTorrentSettings value) async {
    value.validate();
    await store.put('settings', 'bittorrent', value.toJson());
    settings = value;
    if (_initializing != null) {
      await _initializing;
      lt.LibtorrentFlutter.instance.configureSession(settings.engineConfig);
      _schedule();
    }
    for (final task in _tasks.values) {
      await _persist('${task['id']}', task);
    }
    _emit();
  }

  Future<void> initialize() async {
    settings = BitTorrentSettings.fromJson(
      await store.get('settings', 'bittorrent') ?? {},
    );
    settings.validate();
    final restored = await store.list('downloads');
    restored.sort(
      (a, b) => number(a['createdAt']).compareTo(number(b['createdAt'])),
    );
    for (final task in restored) {
      task['manualPaused'] ??= task['status'] == 'paused';
      if (!settings.resumeOnStartup) task['manualPaused'] = true;
      task['peerCount'] = 0;
      task['downloadSpeedBytesPerSecond'] = 0;
      task['uploadSpeedBytesPerSecond'] = 0;
      _files['${task['id']}'] = objects(task['files']);
      try {
        task['fingerprint'] = task['kind'] == 'magnet'
            ? magnetInfoHash(Uri.parse('${task['input']}'))
            : torrentInfoHash(await File('${task['input']}').readAsBytes());
      } catch (_) {
        // Attachment below reports unavailable or invalid metadata per task.
      }
      _tasks['${task['id']}'] = task;
    }
    if (_tasks.isNotEmpty) await _engine();
    for (final task in _tasks.values.toList()) {
      try {
        _attach(task, restoring: true);
      } catch (e) {
        task['status'] = 'failed';
        task['errorMessage'] = e.toString();
      }
    }
    _schedule();
    _emit();
  }

  Future<void> _engine() => _initializing ??= () async {
    await Directory(directory).create(recursive: true);
    await Directory(p.join(directory, 'metadata')).create(recursive: true);
    await lt.LibtorrentFlutter.init(
      defaultSavePath: directory,
      fetchTrackers: false,
    );
    lt.LibtorrentFlutter.instance.configureSession(settings.engineConfig);
    _lastTick = _clock.elapsedMilliseconds;
    _subscription = lt.LibtorrentFlutter.instance.torrentUpdates.listen(
      _update,
    );
  }();

  void _update(Map<int, lt.TorrentInfo> snapshot) {
    if (_closed) return;
    final now = _clock.elapsedMilliseconds;
    final elapsed = (now - _lastTick) / 1000;
    _lastTick = now;
    final before = {for (final t in _tasks.values) t['id']: t['status']};
    for (final entry in _handles.entries.toList()) {
      final id = entry.key, info = snapshot[entry.value];
      final task = _tasks[id];
      if (info == null || task == null) continue;
      final checking =
          info.state == lt.TorrentState.checkingFiles ||
          info.state == lt.TorrentState.checkingResume;
      if (task['status'] == 'seeding' && info.isFinished && !info.isPaused) {
        task['seedSeconds'] = number(task['seedSeconds']) + elapsed;
      }
      final previousUpload = _uploaded[id] ?? 0;
      task['uploadedBytes'] =
          number(task['uploadedBytes']).toInt() +
          (info.totalUploaded - previousUpload).clamp(0, info.totalUploaded);
      _uploaded[id] = info.totalUploaded;
      task.addAll({
        'title': info.name.isEmpty ? task['title'] : info.name,
        'progress': checking ? 0.0 : info.progress,
        'downloadSpeedBytesPerSecond': info.downloadRate,
        'uploadSpeedBytesPerSecond': info.uploadRate,
        'peerCount': info.numPeers,
        'seedCount': info.numSeeds,
        'errorMessage': info.errorMsg.isEmpty ? null : info.errorMsg,
        'totalBytes': info.totalWanted,
        'downloadedBytes': info.totalDone,
        'complete': !checking && info.isFinished,
      });
      if (info.errorMsg.isNotEmpty) {
        task['status'] = 'failed';
        _verifying.remove(id);
        task['manualPaused'] = true;
      } else if (checking || (_verifying.contains(id) && !info.hasMetadata)) {
        task['status'] = 'checking';
      } else {
        _verifying.remove(id);
        task['status'] = info.isFinished
            ? 'seeding'
            : info.hasMetadata
            ? 'downloading'
            : 'metadata';
      }
      if (info.hasMetadata) {
        _files[id] = lt.LibtorrentFlutter.instance
            .getFiles(entry.value)
            .map(
              (file) => <String, dynamic>{
                'id': '${file.index}',
                'downloadId': id,
                'name': file.name,
                'path': p.join('${task['savePath']}', file.path),
                'size': file.size,
                'progress': !checking && info.isFinished ? 1.0 : 0.0,
                'mediaKind': file.isStreamable ? 'video' : 'other',
              },
            )
            .toList();
        task['files'] = _files[id];
        if (task['kind'] == 'magnet' && task['metadataPath'] == null) {
          final path = p.join(
            directory,
            'metadata',
            '${task['fingerprint']}.torrent',
          );
          if (lt.LibtorrentFlutter.instance.saveMetadata(entry.value, path)) {
            task['metadataPath'] = path;
          }
        }
      }
    }
    _schedule();
    final periodic = now - _lastSaved >= 5000;
    for (final task in _tasks.values) {
      if (periodic || before[task['id']] != task['status']) {
        unawaited(_persist('${task['id']}', task));
      }
    }
    if (periodic) _lastSaved = now;
    _emit();
  }

  void _schedule() {
    if (_handles.isEmpty) return;
    final engine = lt.LibtorrentFlutter.instance;
    var downloading = 0, seeding = 0;
    for (final task in _tasks.values) {
      final id = '${task['id']}', handle = _handles[id];
      if (handle == null || _verifying.contains(id)) continue;
      var run = false;
      if (task['errorMessage'] != null) {
        task['status'] = 'failed';
      } else if (task['seedingStopped'] == true && task['complete'] == true) {
        task['status'] = 'completed';
        task['seedStopReason'] = 'manual';
      } else if (task['manualPaused'] == true) {
        task['status'] = 'paused';
      } else if (task['complete'] == true) {
        final reason = settings.stopReason(task);
        task['seedStopReason'] = reason;
        if (reason != null) {
          task['status'] = 'completed';
        } else {
          run = seeding++ < settings.activeSeeds;
          task['status'] = run ? 'seeding' : 'queued';
        }
      } else {
        task['seedStopReason'] = null;
        run = downloading++ < settings.activeDownloads;
        if (!run) {
          task['status'] = 'queued';
        } else if ([
          'queued',
          'paused',
          'failed',
          'completed',
        ].contains(task['status'])) {
          task['status'] = 'metadata';
        }
      }
      if (run && !_running.contains(id)) {
        engine.resumeTorrent(handle);
        _running.add(id);
      } else if (!run && _running.remove(id)) {
        engine.pauseTorrent(handle);
      }
      if (!run) {
        task['downloadSpeedBytesPerSecond'] = 0;
        task['uploadSpeedBytesPerSecond'] = 0;
        task['peerCount'] = 0;
      }
    }
  }

  void _attach(Json task, {bool restoring = false}) {
    final id = '${task['id']}';
    final engine = lt.LibtorrentFlutter.instance;
    final metadata = task['metadataPath'];
    final localMetadata = metadata != null && File('$metadata').existsSync();
    // Verify restored local data without entering a network transfer state.
    final verify = restoring && (task['kind'] == 'torrent' || localMetadata);
    final handle = task['kind'] == 'magnet' && !localMetadata
        ? engine.addMagnet(
            '${task['input']}',
            '${task['savePath']}',
            false,
            !verify,
            verify,
          )
        : engine.addTorrentFile(
            localMetadata ? '$metadata' : '${task['input']}',
            '${task['savePath']}',
            false,
            !verify,
            verify,
          );
    _handles[id] = handle;
    if (verify) {
      _verifying.add(id);
      task['status'] = 'checking';
      task['progress'] = 0.0;
      for (final file in _files[id] ?? <Json>[]) {
        file['progress'] = 0.0;
      }
    }
  }

  Json snapshot() => {
    'tasks': _tasks.values.map((t) => Map<String, dynamic>.from(t)).toList(),
    'files': _files.values.expand((v) => v).toList(),
  };
  Future<Json> addMagnet(String input, {int? subjectId, int? episodeId}) async {
    if (_closed) throw StateError('下载器已关闭');
    final uri = Uri.tryParse(input.trim());
    if (uri?.scheme != 'magnet') {
      throw const FormatException('磁力链接缺少有效的 BT info hash');
    }
    return _add(
      'magnet',
      uri.toString(),
      magnetInfoHash(uri!),
      uri.queryParameters['dn'] ?? '正在获取种子信息',
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
    if (_closed) throw StateError('下载器已关闭');
    if (bytes.isEmpty) throw const FormatException('种子文件为空');
    final fingerprint = torrentInfoHash(bytes);
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
    if (_closed) throw StateError('下载器已关闭');
    final existing = _tasks.values
        .where((t) => t['fingerprint'] == fingerprint)
        .firstOrNull;
    if (existing != null) return existing;
    await _engine();
    if (_closed) throw StateError('下载器已关闭');
    final id = newId();
    final savePath = p.join(directory, id);
    await Directory(savePath).create(recursive: true);
    if (_closed) throw StateError('下载器已关闭');
    final task = <String, dynamic>{
      'id': id,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
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
    _schedule();
    await _persist(id, task);
    _emit();
    return task;
  }

  Future<void> stopSeeding(String id) async {
    final task = _tasks[id];
    if (task == null) throw StateError('下载任务不存在');
    if (task['complete'] != true) throw StateError('文件尚未下载完成');
    task['seedingStopped'] = true;
    task['manualPaused'] = false;
    _schedule();
    await _persist(id, task);
    _emit();
  }

  Future<void> pause(String id) async {
    final task = _tasks[id];
    if (task == null) throw StateError('下载任务不存在');
    task['manualPaused'] = true;
    _schedule();
    await _persist(id, task);
    _emit();
  }

  Future<void> resume(String id) async {
    final task = _tasks[id];
    if (task == null) throw StateError('下载任务不存在');
    await _engine();
    if (!_handles.containsKey(id)) _attach(task, restoring: true);
    task['manualPaused'] = false;
    task['seedingStopped'] = false;
    task['errorMessage'] = null;
    _schedule();
    await _persist(id, task);
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
    _running.remove(id);
    _verifying.remove(id);
    _uploaded.remove(id);
    _schedule();
    await _writes;
    await store.remove('downloads', id);
    final metadata =
        task['metadataPath'] ??
        (task['kind'] == 'torrent' ? task['input'] : null);
    if (metadata != null && await File('$metadata').exists()) {
      await File('$metadata').delete();
    }
    _emit();
  }

  Json media(String id, {String? fileId}) {
    final task = _tasks[id];
    if (task == null) throw StateError('下载任务不存在');
    final videos = (_files[id] ?? [])
        .where((f) => f['mediaKind'] == 'video')
        .toList();
    if (fileId == null && videos.length > 1) {
      throw StateError('资源包含多个视频，请在缓存列表中选择具体文件');
    }
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
      'episodeId': videos.length == 1 ? task['episodeId'] : null,
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

  Future<void> _persist(String id, Json task) {
    final saved = Map<String, dynamic>.from(task);
    return _writes = _writes.then((_) => store.put('downloads', id, saved));
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await Future.wait(
      _adding.values.toList().map((operation) async {
        try {
          await operation;
        } catch (_) {
          /* The caller receives add failures. */
        }
      }),
    );
    if (_initializing != null) {
      await _initializing;
      await _subscription?.cancel();
      for (final task in _tasks.values) {
        await _persist('${task['id']}', task);
      }
      await _writes;
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
