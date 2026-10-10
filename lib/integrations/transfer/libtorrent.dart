import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:libtorrent_flutter/libtorrent_flutter.dart' as lt;
import 'package:path/path.dart' as p;

import '../../data/json.dart';
import '../../data/store.dart';
import '../../data/torrent_identity.dart';
import '../../domain/bittorrent_settings.dart';
import '../../domain/transfer.dart';
import 'records.dart';

/// BT through libtorrent: queueing, seeding policy and streaming of
/// incomplete files.
class LibtorrentTransfer implements Transfer {
  LibtorrentTransfer(this.store, String directory)
    : directory = p.normalize(p.absolute(directory));
  final AppStore store;
  final String directory;
  @override
  CacheMethod get method => CacheMethod.bt;
  final _changes = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => _changes.stream;
  final _tasks = <String, Json>{};
  final _handles = <String, int>{};
  final _files = <String, List<Json>>{};
  final _adding = <String, Future<Json>>{};
  final _removing = <String, Future<void>>{};
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _initializing;
  Future<void>? _restoring;
  Future<void>? _loadingPreferences;
  Future<void> get ready => _restoring ?? initialize();
  final _fileReadAt = <String, int>{};
  final _pendingWrites = <String, Json>{};
  final _writeWaiters = <Completer<void>>[];
  Future<void>? _writes;
  Future<void>? _closing;
  bool _closed = false;
  BitTorrentSettings settings = const BitTorrentSettings();
  final _verifying = <String>{};
  final _checkingFiles = <String>{};
  final _running = <String>{};
  final _uploaded = <String, int>{};
  final _streams = <int, String>{};
  final _clock = Stopwatch()..start();
  int _lastTick = 0, _lastSaved = 0;

  Future<void> saveSettings(BitTorrentSettings value) async {
    await ready;
    _requireOpen();
    value.validate();
    await store.put('settings', 'bittorrent', value.toJson());
    settings = value;
    if (_initializing != null) {
      await _initializing;
      lt.LibtorrentFlutter.instance.configureSession(_engineConfig(settings));
      _schedule();
    }
    for (final task in _tasks.values) {
      await _persist('${task['id']}', task);
    }
    _emit();
  }

  @override
  Future<void> initialize() => _restoring ??= _restore();

  Future<void> loadPreferences() => _loadingPreferences ??= _loadPreferences();

  Future<void> _loadPreferences() async {
    _requireOpen();
    settings = BitTorrentSettings.fromStoredJson(
      await store.get('settings', 'bittorrent') ?? {},
    );
    settings.validate();
  }

  Future<void> _restore() async {
    _requireOpen();
    await loadPreferences();
    final restored = await store.list('downloads');
    restored.sort(
      (a, b) => number(a['createdAt']).compareTo(number(b['createdAt'])),
    );
    for (final task in restored) {
      task['coverUrl'] ??= await cachedCover(store, task['subjectId'] as int?);
      task['manualPaused'] ??= task['status'] == 'paused';
      if (!settings.resumeOnStartup) task['manualPaused'] = true;
      task['peerCount'] = 0;
      for (final key in [
        'knownPeerCount',
        'trackerCount',
        'workingTrackers',
        'failedTrackers',
        'dhtNodes',
      ]) {
        task.remove(key);
      }
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
    var attached = 0;
    for (final task in _tasks.values.toList()) {
      if (attached++ % 8 == 0) await Future<void>.delayed(Duration.zero);
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
    lt.LibtorrentFlutter.instance.configureSession(_engineConfig(settings));
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
      final wasComplete = task['complete'] == true;
      final checking =
          info.state == lt.TorrentState.checkingFiles ||
          info.state == lt.TorrentState.checkingResume;
      final wasChecking = _checkingFiles.contains(id);
      if (checking) {
        _checkingFiles.add(id);
      } else {
        _checkingFiles.remove(id);
      }
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
        'knownPeerCount': info.knownPeers,
        'trackerCount': info.trackerCount,
        'workingTrackers': info.workingTrackers,
        'failedTrackers': info.failedTrackers,
        'dhtNodes': info.dhtNodes,
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
      final refreshFiles =
          !_fileReadAt.containsKey(id) ||
          wasChecking != checking ||
          !_files.containsKey(id) ||
          _files[id]!.isEmpty ||
          wasComplete != (!checking && info.isFinished) ||
          (!info.isPaused &&
              !info.isFinished &&
              !checking &&
              now - (_fileReadAt[id] ?? 0) >= 3000);
      if (info.hasMetadata && refreshFiles) {
        _fileReadAt[id] = now;
        _files[id] = lt.LibtorrentFlutter.instance
            .getFiles(entry.value)
            .map(
              (file) => <String, dynamic>{
                'id': '${file.index}',
                'downloadId': id,
                'name': file.name,
                'path': p.join('${task['savePath']}', file.path),
                'size': file.size,
                'progress': checking
                    ? 0.0
                    : file.size == 0
                    ? 1.0
                    : (file.downloadedBytes / file.size).clamp(0.0, 1.0),
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
      final changing = const {
        'downloading',
        'metadata',
        'seeding',
        'checking',
      }.contains(task['status']);
      if ((periodic && (changing || task['persistenceError'] != null)) ||
          before[task['id']] != task['status']) {
        unawaited(
          _persist('${task['id']}', task).catchError((Object _) {
            // The error is visible on the task; the next snapshot retries saving.
            _emit();
          }),
        );
      }
    }
    if (periodic) _lastSaved = now;
    _emit();
  }

  void _schedule() {
    if (_handles.isEmpty) return;
    final engine = lt.LibtorrentFlutter.instance;
    var downloading = 0, seeding = 0;
    final ordered = [
      ..._tasks.values.where((task) => _streams.containsValue(task['id'])),
      ..._tasks.values.where((task) => !_streams.containsValue(task['id'])),
    ];
    for (final task in ordered) {
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
        final reason = settings.stopReason(
          number(task['totalBytes']).toInt(),
          number(task['uploadedBytes']).toInt(),
          number(task['seedSeconds']),
        );
        task['seedStopReason'] = reason?.name;
        if (reason != null) {
          task['status'] = 'completed';
        } else {
          run = settings.activeSeeds == 0 || seeding++ < settings.activeSeeds;
          task['status'] = run ? 'seeding' : 'queued';
        }
      } else {
        task['seedStopReason'] = null;
        run =
            settings.activeDownloads == 0 ||
            downloading++ < settings.activeDownloads;
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

  @override
  List<DownloadTask> tasks() => [
    for (final task in _tasks.values)
      downloadTask({
        ...task,
        'files': _files[task['id']] ?? const <Json>[],
      }, CacheMethod.bt),
  ];

  @override
  Future<DownloadTask> addMagnet(
    Uri magnet, {
    String? title,
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    List<String> releaseGroups = const [],
  }) async {
    await ready;
    if (_closed) throw StateError('下载器已关闭');
    return downloadTask(
      await _add(
        'magnet',
        magnet.toString(),
        magnetInfoHash(magnet),
        title ?? magnet.queryParameters['dn'] ?? '正在获取种子信息',
        subjectId,
        episodeId,
        coverUrl: coverUrl,
        releaseGroups: releaseGroups,
      ),
      CacheMethod.bt,
    );
  }

  @override
  Future<DownloadTask> addTorrent(
    Uint8List bytes,
    String name, {
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    List<String> releaseGroups = const [],
  }) async {
    await ready;
    if (_closed) throw StateError('下载器已关闭');
    final fingerprint = torrentInfoHash(bytes);
    return downloadTask(
      await _add(
        'torrent',
        p.join(directory, 'metadata', '$fingerprint.torrent'),
        fingerprint,
        name,
        subjectId,
        episodeId,
        metadataBytes: bytes,
        coverUrl: coverUrl,
        releaseGroups: releaseGroups,
      ),
      CacheMethod.bt,
    );
  }

  Future<Json> _add(
    String kind,
    String input,
    String fingerprint,
    String title,
    int? subjectId,
    int? episodeId, {
    Uint8List? metadataBytes,
    String? coverUrl,
    List<String> releaseGroups = const [],
  }) => _adding.putIfAbsent(
    fingerprint,
    () =>
        _create(
          kind,
          input,
          fingerprint,
          title,
          subjectId,
          episodeId,
          metadataBytes: metadataBytes,
          coverUrl: coverUrl,
          releaseGroups: releaseGroups,
        ).whenComplete(() {
          _adding.remove(fingerprint);
        }),
  );

  Future<Json> _create(
    String kind,
    String input,
    String fingerprint,
    String title,
    int? subjectId,
    int? episodeId, {
    Uint8List? metadataBytes,
    String? coverUrl,
    List<String> releaseGroups = const [],
  }) async {
    await ready;
    if (_closed) throw StateError('下载器已关闭');
    await _removing[fingerprint];
    if (_closed) throw StateError('下载器已关闭');
    final existing = _tasks.values
        .where((t) => t['fingerprint'] == fingerprint)
        .firstOrNull;
    if (existing != null) {
      if (releaseGroups.isNotEmpty &&
          ((existing['releaseGroups'] as List?)?.isEmpty ?? true)) {
        existing['releaseGroups'] = List<String>.of(releaseGroups);
        await _persist('${existing['id']}', existing);
        _emit();
      }
      return existing;
    }
    final resolvedCover = coverUrl ?? await cachedCover(store, subjectId);
    if (_closed) throw StateError('下载器已关闭');
    await _engine();
    if (_closed) throw StateError('下载器已关闭');
    if (metadataBytes != null) {
      final pending = File('$input.pending');
      await pending.writeAsBytes(metadataBytes, flush: true);
      await pending.rename(input);
    }
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
      if (releaseGroups.isNotEmpty)
        'releaseGroups': List<String>.of(releaseGroups),
      'savePath': savePath,
      'subjectId': subjectId,
      'episodeId': episodeId,
      'coverUrl': resolvedCover,
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
    await ready;
    _requireOpen();
    final task = _tasks[id];
    if (task == null) throw StateError('下载任务不存在');
    if (task['complete'] != true) throw StateError('文件尚未下载完成');
    task['seedingStopped'] = true;
    task['manualPaused'] = false;
    _schedule();
    await _persist(id, task);
    _emit();
  }

  @override
  Future<void> pause(String id) async {
    await ready;
    _requireOpen();
    final task = _tasks[id];
    if (task == null) throw StateError('下载任务不存在');
    task['manualPaused'] = true;
    _schedule();
    await _persist(id, task);
    _emit();
  }

  @override
  Future<void> resume(String id) async {
    await ready;
    _requireOpen();
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

  @override
  Future<void> remove(String id) async {
    await ready;
    _requireOpen();
    final task = _tasks[id];
    if (task == null) return Future.value();
    final fingerprint = '${task['fingerprint']}';
    return _removing.putIfAbsent(
      fingerprint,
      () => _remove(id).whenComplete(() {
        _removing.remove(fingerprint);
      }),
    );
  }

  Future<void> _remove(String id) async {
    final task = _tasks.remove(id);
    if (task == null) return;
    for (final stream
        in _streams.entries.where((entry) => entry.value == id).toList()) {
      lt.LibtorrentFlutter.instance.stopStream(stream.key);
      _streams.remove(stream.key);
    }
    final handle = _handles.remove(id);
    if (handle != null) {
      lt.LibtorrentFlutter.instance.removeTorrent(handle, deleteFiles: true);
    }
    _files.remove(id);
    _running.remove(id);
    _verifying.remove(id);
    _checkingFiles.remove(id);
    _uploaded.remove(id);
    _fileReadAt.remove(id);
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

  void _requireOpen() {
    if (_closed) throw StateError('下载器已关闭');
  }

  @override
  bool contains(String id) => _tasks.containsKey(id);

  @override
  TransferMedia media(String id, {String? fileId}) {
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
    if (task['status'] == 'checking') throw StateError('正在校验文件，请稍后播放');
    if (task['status'] == 'failed') throw StateError('下载任务异常，请先重试');
    final file = downloadFile(files.first);
    return TransferMedia(
      file: file,
      incomplete: file.progress < 1,
      subjectId: task['subjectId'] as int?,
      episodeId: videos.length == 1 ? task['episodeId'] as int? : null,
    );
  }

  @override
  Future<TransferMedia> openMedia(String id, {String? fileId}) async {
    await ready;
    final selected = media(id, fileId: fileId);
    if (!selected.incomplete) return selected;
    await resume(id);
    final stream = lt.LibtorrentFlutter.instance.startStream(
      _handles[id]!,
      fileIndex: int.parse(selected.file.id),
    );
    _streams[stream.id] = id;
    _schedule();
    return selected.streaming(stream.url, id: stream.id);
  }

  @override
  void releaseStreamsExcept(int? keep) {
    for (final id in _streams.keys.toList()) {
      if (id == keep) continue;
      lt.LibtorrentFlutter.instance.stopStream(id);
      _streams.remove(id);
    }
    _schedule();
  }

  void _emit() {
    if (!_closed) _changes.add(null);
  }

  Future<void> _persist(String id, Json task) {
    _pendingWrites[id] = {
      ...task,
      if (task['files'] is List)
        'files': [
          for (final file in objects(task['files'])) {...file},
        ],
    }..remove('persistenceError');
    final completion = Completer<void>();
    _writeWaiters.add(completion);
    _writes ??= Future<void>.microtask(_flushWrites);
    return completion.future;
  }

  Future<void> _flushWrites() async {
    try {
      while (_pendingWrites.isNotEmpty) {
        final values = Map<String, Json>.of(_pendingWrites);
        final waiters = List<Completer<void>>.of(_writeWaiters);
        _pendingWrites.clear();
        _writeWaiters.clear();
        try {
          await store.putAll('downloads', values);
          for (final id in values.keys) {
            _tasks[id]?.remove('persistenceError');
          }
          for (final waiter in waiters) {
            waiter.complete();
          }
        } catch (error, stack) {
          for (final id in values.keys) {
            _tasks[id]?['persistenceError'] = '下载记录保存失败，将自动重试：$error';
          }
          for (final waiter in waiters) {
            waiter.completeError(error, stack);
          }
        }
      }
    } finally {
      _writes = null;
    }
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    try {
      await _loadingPreferences;
      await _restoring;
    } catch (_) {
      // Dispose any engine created before recovery failed.
    }
    await Future.wait(
      _adding.values.toList().map((operation) async {
        try {
          await operation;
        } catch (_) {
          /* The caller receives add failures. */
        }
      }),
    );
    await Future.wait(
      _removing.values.toList().map((operation) async {
        try {
          await operation;
        } catch (_) {
          /* The caller receives removal failures. */
        }
      }),
    );
    try {
      if (_initializing != null) {
        await _initializing;
        await _subscription?.cancel();
        await Future.wait([
          for (final task in _tasks.values) _persist('${task['id']}', task),
        ]);
      }
      await _writes;
    } finally {
      await _subscription?.cancel();
      if (_initializing != null && lt.LibtorrentFlutter.isInitialized) {
        _handles.clear();
        await lt.LibtorrentFlutter.instance.dispose();
      }
      await _changes.close();
    }
  }
}

lt.BtConfig _engineConfig(BitTorrentSettings settings) => lt.BtConfig(
  downloadRateLimit: settings.downloadKiB,
  uploadRateLimit: settings.uploadKiB,
  connectionsLimit: settings.connectionsPerTask,
  peersListenPort: settings.listenPort,
  disableDht: !settings.dht,
  disableUpnp: !settings.upnp,
  enableIpv6: settings.ipv6,
  forceEncrypt: settings.forceEncryption,
);
