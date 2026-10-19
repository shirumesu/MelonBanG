import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/json.dart';
import '../../core/store.dart';
import '../../domain/torrent_identity.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';
import 'pikpak_client.dart';
import 'records.dart';

/// PikPak as a download accelerator: files are read from its CDN over
/// several connections into the media cache, and served to the player from
/// there while they arrive. Content PikPak already stores is leased without
/// a drive file; other resources are downloaded by PikPak's servers into the
/// drive first, and that copy is deleted once the local copy is complete.
/// Resources PikPak refuses to download are BT's.
class PikPakTransfer implements Transfer, CloudIndex {
  PikPakTransfer(
    this.store,
    String directory,
    this.client, {
    http.Client? transferClient,
  }) : directory = p.normalize(p.absolute(directory)),
       _http = transferClient ?? http.Client();

  final AppStore store;
  final String directory;
  final PikPakClient client;
  final http.Client _http;
  @override
  CacheMethod get method => CacheMethod.pikpak;
  final _changes = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => _changes.stream;
  final _tasks = <String, Json>{};
  final _adding = <String, Future<Json>>{};
  final _removing = <String, Future<void>>{};
  final _fetches = <String, _Fetch>{};
  final _streams = <int, _Fetch>{};
  final _links = <String, Future<String>>{};
  final _held = <String, Future<bool>>{};
  final _received = <String, int>{};
  Future<void>? _worker, _writes, _closing;
  Future<HttpServer>? _server;
  String? _runningId;
  Completer<void>? _halt;
  Timer? _ticker;
  int _ticks = 0;
  // Distinct from libtorrent's stream ids: the player releases streams by id
  // across transfers.
  int _nextStream = 1 << 40;
  bool _closed = false;

  @override
  Future<void> initialize() async {
    _requireOpen();
    for (final task in await store.list('pikpak_downloads')) {
      final id = '${task['id']}';
      task['savePath'] = p.join(directory, id);
      task['downloadSpeedBytesPerSecond'] = 0;
      task['files'] = objects(task['files']).map((file) {
        file['path'] = p.join('${task['savePath']}', '${file['relativePath']}');
        return file;
      }).toList();
      await _reconcile(task);
      _tasks[id] = task;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _schedule();
    _emit();
  }

  @override
  List<DownloadTask> tasks() => [
    for (final task in _tasks.values) downloadTask(task, CacheMethod.pikpak),
  ];

  @override
  bool contains(String id) => _tasks.containsKey(id);

  @override
  Future<DownloadTask> addMagnet(
    Uri magnet, {
    String? title,
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    List<String> releaseGroups = const [],
  }) async {
    _requireOpen();
    if (!client.isSignedIn) throw StateError('请先在视频源页面登录 PikPak');
    final fingerprint = magnetInfoHash(magnet);
    return downloadTask(
      await _adding.putIfAbsent(
        fingerprint,
        () =>
            _create(
              magnet.toString(),
              fingerprint,
              title ?? magnet.queryParameters['dn'],
              subjectId,
              episodeId,
              coverUrl,
              releaseGroups,
            ).whenComplete(() {
              _adding.remove(fingerprint);
            }),
      ),
      CacheMethod.pikpak,
    );
  }

  /// PikPak resolves magnets only; the torrent is reduced to its info hash.
  @override
  Future<DownloadTask> addTorrent(
    Uint8List bytes,
    String name, {
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    List<String> releaseGroups = const [],
  }) => addMagnet(
    Uri(
      scheme: 'magnet',
      queryParameters: {'xt': 'urn:btih:${torrentInfoHash(bytes)}', 'dn': name},
    ),
    title: name,
    subjectId: subjectId,
    episodeId: episodeId,
    coverUrl: coverUrl,
    releaseGroups: releaseGroups,
  );

  Future<Json> _create(
    String input,
    String fingerprint,
    String? title,
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    List<String> releaseGroups,
  ) async {
    coverUrl ??= await cachedCover(store, subjectId);
    await _removing[fingerprint];
    _requireOpen();
    final existing = _tasks.values
        .where((task) => task['fingerprint'] == fingerprint)
        .firstOrNull;
    if (existing != null) {
      if (releaseGroups.isNotEmpty &&
          ((existing['releaseGroups'] as List?)?.isEmpty ?? true)) {
        existing['releaseGroups'] = List<String>.of(releaseGroups);
        await _persist(existing);
        _emit();
      }
      return existing;
    }
    final files = await _indexed(input);
    String? cloudTaskId;
    if (files == null) {
      try {
        cloudTaskId = await client.offline(input);
      } on PikPakCaptchaRequired {
        rethrow;
      } on PikPakException catch (error) {
        // Out of drive space or offline downloads for the day.
        throw TransferUnavailable(error.message);
      }
    }
    _requireOpen();
    final id = newId();
    final savePath = p.join(directory, id);
    final task = <String, dynamic>{
      'id': id,
      'provider': 'pikpak',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'kind': 'magnet',
      'input': input,
      'fingerprint': fingerprint,
      'title': title ?? files?.first.path.split('/').first ?? fingerprint,
      if (releaseGroups.isNotEmpty)
        'releaseGroups': List<String>.of(releaseGroups),
      'savePath': savePath,
      'subjectId': subjectId,
      'episodeId': episodeId,
      'coverUrl': coverUrl,
      'status': 'queued',
      'progress': 0.0,
      'complete': false,
      'manualPaused': false,
      'downloadSpeedBytesPerSecond': 0,
      'cloudTaskId': ?cloudTaskId,
      'files': _records(id, savePath, [
        for (final file in files ?? const <PikPakIndexedFile>[])
          (path: file.path, size: file.size, gcid: file.gcid, cloudId: null),
      ]),
    };
    _updateProgress(task);
    _tasks[id] = task;
    await _persist(task);
    _schedule();
    _emit();
    return task;
  }

  /// The files of [input] PikPak can lease now; null when its servers have
  /// to download the resource first.
  Future<List<PikPakIndexedFile>?> _indexed(String input) async {
    final indexed = await client.resolveMagnet(input);
    if (indexed == null ||
        indexed.any((file) => _isVideo(file.name) && file.gcid == null)) {
      return null;
    }
    final files = [
      for (final file in indexed)
        if (file.gcid != null && file.size > 0) file,
    ];
    final video = files.where((file) => _isVideo(file.name)).firstOrNull;
    if (video == null) throw const TransferUnavailable('该资源没有视频文件');
    // A lease briefly takes the file's size of drive space.
    final free = await client.freeSpace();
    final largest = files.map((file) => file.size).reduce(max);
    if (free != null && free < largest) {
      throw const TransferUnavailable('PikPak 剩余空间不足以中转该资源');
    }
    try {
      await _lease(video);
    } on PikPakContentMissing {
      return null;
    }
    return files;
  }

  List<Json> _records(
    String id,
    String savePath,
    List<({String path, int size, String? gcid, String? cloudId})> files,
  ) {
    final used = <String>{};
    return [
      for (final (index, file) in files.indexed)
        () {
          var relative = _relativePath(file.path);
          if (!used.add(relative.toLowerCase())) {
            relative = p.join('$index', relative);
            used.add(relative.toLowerCase());
          }
          final name = file.path.split('/').last;
          return <String, dynamic>{
            'id': '$index',
            'downloadId': id,
            'name': name,
            'relativePath': relative,
            'path': p.join(savePath, relative),
            'size': file.size,
            'gcid': ?file.gcid,
            'cloudFileId': ?file.cloudId,
            'ranges': <List<int>>[],
            'downloadedBytes': 0,
            'progress': 0.0,
            'complete': false,
            'mediaKind': _isVideo(name) ? 'video' : 'other',
          };
        }(),
    ];
  }

  Future<String> _lease(PikPakIndexedFile file) =>
      _cached(file.gcid!, () => client.lease(file));

  Future<String> _cached(String key, Future<String> Function() link) =>
      _links[key] ??= link().onError<Object>((error, stack) {
        _links.remove(key);
        Error.throwWithStackTrace(error, stack);
      });

  /// Files of the drive copy read their own link; leased files share one
  /// per content hash.
  Future<String> _link(_Fetch fetch) => switch (fetch.file['cloudFileId']) {
    final String id => _cached(id, () => client.link(id)),
    _ => _lease(
      PikPakIndexedFile(
        '${fetch.file['name']}',
        fetch.size,
        '${fetch.file['gcid']}',
      ),
    ),
  };

  /// Drops [link] once the CDN rejects it, so the next request reads anew.
  void _expire(_Fetch fetch, Future<String> link) {
    final key = '${fetch.file['cloudFileId'] ?? fetch.file['gcid']}';
    if (identical(_links[key], link)) _links.remove(key);
  }

  bool _active(Json task) =>
      !_closed &&
      identical(_tasks[task['id']], task) &&
      task['manualPaused'] != true &&
      client.isSignedIn;

  void _schedule() {
    if (_closed || _worker != null) return;
    for (final task in _tasks.values) {
      if (task['complete'] == true ||
          task['manualPaused'] == true ||
          task['status'] == 'failed' ||
          _fetched(task)) {
        continue;
      }
      if (client.isSignedIn) {
        task['status'] = 'queued';
        task['errorMessage'] = null;
      } else {
        task['status'] = 'paused';
        task['errorMessage'] = '登录 PikPak 后可继续';
      }
    }
    final next = _tasks.values
        .where((task) => _active(task) && task['status'] == 'queued')
        .firstOrNull;
    if (next == null) return;
    _runningId = '${next['id']}';
    _halt = Completer<void>();
    _worker = _run(next).whenComplete(() {
      _worker = null;
      _runningId = null;
      _halt = null;
      _schedule();
      _emit();
    });
  }

  Future<void> _run(Json task) async {
    final halt = _halt!.future;
    try {
      task['errorMessage'] = null;
      if (objects(task['files']).isEmpty) {
        await _acquire(task, halt);
        if (!_active(task)) return;
      }
      task['status'] = 'downloading';
      _emit();
      for (final file in (task['files'] as List).cast<Json>()) {
        if (!_active(task)) return;
        if (file['complete'] == true) continue;
        final fetch = _fetch(task, file);
        fetch.hold();
        try {
          await Future.any([fetch.running ?? Future<void>.value(), halt]);
        } finally {
          fetch.release();
        }
        if (fetch.error case final error?) throw error;
      }
      if (!_active(task)) return;
      _checkComplete(task);
      await _persist(task);
    } catch (error) {
      if (!_active(task)) return;
      task['status'] = 'failed';
      task['errorMessage'] = '$error';
      task['downloadSpeedBytesPerSecond'] = 0;
      await _persist(task);
    } finally {
      _emit();
    }
  }

  /// Waits for PikPak's servers to download the resource into the drive,
  /// then records the drive copy's files.
  Future<void> _acquire(Json task, Future<void> halt) async {
    task['status'] = 'metadata';
    task['cloudProgress'] = 0.0;
    _emit();
    // A failed cloud download is submitted again when the task resumes.
    final cloudTaskId =
        '${task['cloudTaskId'] ??= await client.offline('${task['input']}')}';
    await _persist(task);
    Json remote;
    while (true) {
      remote = await client.offlineTask(cloudTaskId);
      if (!_active(task)) return;
      if (remote['phase'] == 'PHASE_TYPE_ERROR') {
        task.remove('cloudTaskId');
        task.remove('cloudProgress');
        client.deleteOffline(cloudTaskId).ignore();
        throw StateError(
          'PikPak 云端下载失败：${remote['message'] ?? remote['phase']}',
        );
      }
      task['cloudProgress'] = (_integer(remote['progress']) / 100).clamp(
        0.0,
        1.0,
      );
      _emit();
      if (remote['phase'] == 'PHASE_TYPE_COMPLETE') break;
      await Future.any([
        Future<void>.delayed(const Duration(seconds: 3)),
        halt,
      ]);
      if (!_active(task)) return;
    }
    final files = await client.files('${remote['file_id']}');
    if (!_active(task)) return;
    task.remove('cloudProgress');
    task['files'] = _records('${task['id']}', '${task['savePath']}', [
      for (final file in files)
        if (file.size > 0)
          (path: file.path, size: file.size, gcid: null, cloudId: file.id),
    ]);
    if (objects(task['files']).isEmpty) {
      throw StateError('PikPak 云端下载没有可缓存的文件');
    }
    await _persist(task);
  }

  /// Every byte is local; files the player still reads are renamed later.
  bool _fetched(Json task) {
    final files = (task['files'] as List).cast<Json>();
    return files.isNotEmpty &&
        files.every(
          (file) =>
              file['complete'] == true ||
              _fetches['${task['id']}/${file['id']}']?.done == true,
        );
  }

  _Fetch _fetch(Json task, Json file) => _fetches.putIfAbsent(
    '${task['id']}/${file['id']}',
    () => _Fetch(this, task, file),
  );

  /// Renames a fully fetched file once no player connection reads it; an
  /// open file cannot be renamed on Windows.
  Future<void> _finish(_Fetch fetch) async {
    if (!fetch.done ||
        fetch.running != null ||
        fetch.readers.isNotEmpty ||
        fetch.file['complete'] == true ||
        fetch.finishing != null) {
      return;
    }
    final finishing = File(fetch.partPath).rename(fetch.path);
    fetch.finishing = finishing;
    await finishing;
    fetch.file['complete'] = true;
    fetch.finishing = null;
    _checkComplete(fetch.task);
    await _persist(fetch.task);
    _emit();
  }

  void _checkComplete(Json task) {
    _updateProgress(task);
    final files = objects(task['files']);
    if (files.isEmpty || files.any((file) => file['complete'] != true)) return;
    task['complete'] = true;
    task['status'] = 'completed';
    task['progress'] = 1.0;
    task['downloadSpeedBytesPerSecond'] = 0;
    // The drive copy only fed the local one.
    if (task.remove('cloudTaskId') case final String cloud) {
      client.deleteOffline(cloud).ignore();
    }
  }

  void _tick() {
    if (_closed) return;
    final active = {
      for (final fetch in _fetches.values)
        if (fetch.running != null) fetch.task,
    };
    var changed = active.isNotEmpty;
    for (final task in _tasks.values) {
      final speed = _received[task['id']] ?? 0;
      if (task['downloadSpeedBytesPerSecond'] != speed) {
        task['downloadSpeedBytesPerSecond'] = speed;
        changed = true;
      }
    }
    _received.clear();
    if (!changed) return;
    for (final task in active) {
      _updateProgress(task);
    }
    if (++_ticks % 5 == 0) {
      for (final task in active) {
        // A failed save is retried by the next one.
        _persist(task).ignore();
      }
    }
    _emit();
  }

  Future<void> _reconcile(Json task) async {
    for (final file in objects(task['files'])) {
      final size = _integer(file['size']);
      if (await File('${file['path']}').exists() &&
          await File('${file['path']}').length() == size) {
        file['complete'] = true;
        file['ranges'] = [
          [0, size],
        ];
        continue;
      }
      final partial = File('${file['path']}.part');
      final length = await partial.exists() ? await partial.length() : 0;
      file['complete'] = false;
      file['ranges'] = (_Ranges.fromJson(
        file['ranges'],
      )..clip(length)).toJson();
    }
    final files = task['files'] = objects(task['files']);
    task['complete'] =
        files.isNotEmpty && files.every((file) => file['complete'] == true);
    if (task['complete'] == true) task['status'] = 'completed';
    _updateProgress(task);
  }

  void _updateProgress(Json task) {
    var total = 0, bytes = 0;
    for (final file in (task['files'] as List).cast<Json>()) {
      final fetch = _fetches['${task['id']}/${file['id']}'];
      if (fetch != null) file['ranges'] = fetch.have.toJson();
      final size = _integer(file['size']);
      final have = _Ranges.fromJson(file['ranges']).total;
      file['downloadedBytes'] = have;
      file['progress'] = file['complete'] == true
          ? 1.0
          : size > 0
          ? have / size
          : 0.0;
      total += size;
      bytes += have;
    }
    task['totalBytes'] = total;
    task['downloadedBytes'] = bytes;
    task['progress'] = task['complete'] == true
        ? 1.0
        : total > 0
        ? bytes / total
        : 0.0;
  }

  @override
  Future<void> pause(String id) async {
    _requireOpen();
    final task = _task(id);
    task['manualPaused'] = true;
    task['status'] = 'paused';
    await _stopWorker(id);
    if (task['complete'] != true) task['status'] = 'paused';
    task['downloadSpeedBytesPerSecond'] = 0;
    _updateProgress(task);
    await _persist(task);
    _schedule();
    _emit();
  }

  @override
  Future<void> resume(String id) async {
    _requireOpen();
    final task = _task(id);
    if (task['complete'] == true) return;
    if (_runningId == id) {
      if (task['status'] != 'failed' && task['manualPaused'] != true) return;
      await _worker;
      _requireOpen();
      if (!identical(_tasks[id], task)) throw StateError('下载任务不存在');
    }
    task['manualPaused'] = false;
    task['errorMessage'] = null;
    task['status'] = 'queued';
    await _persist(task);
    _schedule();
    _emit();
  }

  @override
  bool get available => client.isSignedIn && !client.needsAuthorization;

  @override
  Future<bool> holds(String infoHash) => _held[infoHash] ??= client
      .resolveMagnet('magnet:?xt=urn:btih:$infoHash')
      .then(
        (files) =>
            files?.any((file) => _isVideo(file.name) && file.gcid != null) ??
            false,
      )
      .onError<Object>((error, stack) {
        _held.remove(infoHash);
        Error.throwWithStackTrace(error, stack);
      });

  /// The signed-in account's name; null when signed out.
  String? get accountName =>
      client.isSignedIn ? client.displayName ?? 'PikPak' : null;
  bool get needsAuthorization => client.needsAuthorization;
  Uri? get verificationUrl => client.verificationUrl;

  /// Releases credentials held behind system authorization.
  Future<void> unlock() => _changeAccount(client.unlock);
  Future<void> signIn(String username, String password) =>
      _changeAccount(() => client.signIn(username, password));
  Future<void> signOut() => _changeAccount(client.signOut);

  Future<void> _changeAccount(Future<void> Function() change) async {
    try {
      await change();
    } on PikPakCaptchaRequired catch (error) {
      throw SourceVerificationRequired(error.url.toString());
    }
    _requireOpen();
    if (_runningId case final running? when !client.isSignedIn) {
      await _stopWorker(running);
    }
    _schedule();
    _emit();
  }

  Future<void> _stopWorker(String id) async {
    if (_runningId != id) return;
    if (_halt?.isCompleted == false) _halt!.complete();
    await _worker;
  }

  @override
  Future<void> remove(String id) {
    _requireOpen();
    final task = _tasks[id];
    if (task == null) return Future.value();
    final key = '${task['fingerprint']}';
    return _removing.putIfAbsent(
      key,
      () => _remove(task).whenComplete(() {
        _removing.remove(key);
      }),
    );
  }

  Future<void> _remove(Json task) async {
    final id = '${task['id']}';
    _tasks.remove(id);
    await _stopWorker(id);
    if (task['cloudTaskId'] case final String cloud when client.isSignedIn) {
      // Also cancels a cloud download still running.
      client.deleteOffline(cloud).ignore();
    }
    final fetches = [
      for (final entry in _fetches.entries.toList())
        if (entry.key.startsWith('$id/')) entry.value,
    ];
    _streams.removeWhere((_, fetch) => fetches.contains(fetch));
    for (final fetch in fetches) {
      _fetches.remove('$id/${fetch.file['id']}');
      await fetch.close();
    }
    await _writes;
    await store.remove('pikpak_downloads', id);
    final local = Directory(p.join(directory, id));
    if (await local.exists()) await local.delete(recursive: true);
    _emit();
  }

  (Json, Json, int) _video(String id, String? fileId) {
    final task = _task(id);
    final videos = objects(task['files'])
        .where((file) => file['mediaKind'] == 'video')
        .toList();
    if (fileId == null && videos.length > 1) {
      throw StateError('资源包含多个视频，请在缓存列表中选择具体文件');
    }
    final file = (task['files'] as List)
        .cast<Json>()
        .where(
          (file) =>
              file['mediaKind'] == 'video' &&
              (fileId == null || file['id'] == fileId),
        )
        .firstOrNull;
    if (file == null) throw StateError('资源没有可播放的视频');
    return (task, file, videos.length);
  }

  @override
  TransferMedia media(String id, {String? fileId}) {
    final (task, file, videos) = _video(id, fileId);
    return TransferMedia(
      file: downloadFile(file),
      incomplete: file['complete'] != true,
      subjectId: task['subjectId'] as int?,
      episodeId: videos == 1 ? task['episodeId'] as int? : null,
    );
  }

  @override
  Future<TransferMedia> openMedia(String id, {String? fileId}) async {
    final selected = media(id, fileId: fileId);
    if (!selected.incomplete) return selected;
    final (task, file, _) = _video(id, fileId);
    final fetch = _fetch(task, file);
    if (!fetch.done && !client.isSignedIn) {
      throw StateError('请先在视频源页面登录 PikPak');
    }
    final server = await (_server ??= HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    ).then((server) => server..listen(_serve)));
    final stream = _nextStream++;
    _streams[stream] = fetch;
    fetch.hold();
    await resume(id);
    return selected.streaming(
      'http://127.0.0.1:${server.port}/stream/$stream',
      id: stream,
    );
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    final stream = int.tryParse(request.uri.pathSegments.lastOrNull ?? '');
    final fetch = _streams[stream];
    if (fetch == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final size = fetch.size;
    final range = RegExp(r'^bytes=(\d*)-(\d*)')
        .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    var start = 0, end = size - 1;
    if (range != null) {
      if (range[1]!.isEmpty) {
        start = max(0, size - int.parse(range[2]!));
      } else {
        start = int.parse(range[1]!);
        if (range[2]!.isNotEmpty) end = min(int.parse(range[2]!), size - 1);
      }
    }
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (start >= size) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
      await response.close();
      return;
    }
    response.headers.contentType = ContentType.binary;
    response.contentLength = end - start + 1;
    if (range != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    // The body is written to the socket itself, so a released stream can
    // drop it even while the player has stopped reading.
    response.persistentConnection = false;
    final socket = await response.detachSocket();
    final reader = _Reader(stream!, start, socket);
    fetch.readers.add(reader);
    socket.listen(
      null,
      onDone: () => fetch.closeReader(reader),
      onError: (Object _) => fetch.closeReader(reader),
      cancelOnError: true,
    );
    try {
      await fetch.send(reader, end + 1);
    } on IOException {
      // The player dropped the connection, as it does on a seek.
    } finally {
      socket.destroy();
      fetch.readers.remove(reader);
      fetch.arrived();
      unawaited(_finish(fetch));
    }
  }

  @override
  void releaseStreamsExcept(int? keep) {
    for (final id in _streams.keys.toList()) {
      if (id == keep) continue;
      final fetch = _streams.remove(id)!;
      for (final reader in fetch.readers.toList()) {
        if (reader.stream == id) fetch.closeReader(reader);
      }
      fetch.release();
    }
  }

  Future<void> _persist(Json task) {
    _updateProgress(task);
    final saved = Map<String, dynamic>.of(task)
      ..['files'] = [
        for (final file in objects(task['files'])) {...file},
      ];
    final writing = (_writes ?? Future<void>.value()).then(
      (_) => store.put('pikpak_downloads', '${task['id']}', saved),
    );
    _writes = writing.catchError((Object _) {});
    return writing;
  }

  Json _task(String id) => _tasks[id] ?? (throw StateError('下载任务不存在'));
  void _requireOpen() {
    if (_closed) throw StateError('下载器已关闭');
  }

  void _emit() {
    if (!_closed) _changes.add(null);
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _ticker?.cancel();
    if (_runningId != null) await _stopWorker(_runningId!);
    await Future.wait(
      _adding.values.map(
        (value) => value.then<void>((_) {}, onError: (Object _) {}),
      ),
    );
    await Future.wait(_removing.values);
    _streams.clear();
    for (final fetch in _fetches.values) {
      await fetch.close();
    }
    for (final task in _tasks.values) {
      task['downloadSpeedBytesPerSecond'] = 0;
      await _persist(task);
    }
    await _writes;
    await (await _server)?.close(force: true);
    _http.close();
    await _changes.close();
  }

  static bool _isVideo(String name) => const {
    '.mkv',
    '.mp4',
    '.avi',
    '.webm',
    '.mov',
    '.m4v',
    '.ts',
    '.wmv',
    '.flv',
    '.rmvb',
  }.contains(p.extension(name).toLowerCase());
  static int _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static String _relativePath(String raw) => p.joinAll(
    raw
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .map((part) => part.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_')),
  );
}

/// One file's transfer from the CDN into its `.part` file. Up to eight
/// connections fetch ranges, chosen from where player connections read and
/// otherwise in file order; the background download and playback share it.
class _Fetch {
  _Fetch(this.transfer, this.task, this.file)
    : size = PikPakTransfer._integer(file['size']),
      have = _Ranges.fromJson(file['ranges']);

  /// PikPak refuses a ninth simultaneous connection to one signed link.
  static const connections = 8;

  /// Requests inside a reader's window stay small, so contiguous data ahead
  /// of the player grows at the speed of every connection together.
  static const near = 1 << 20, far = 4 << 20, window = 32 << 20;
  static const idle = Duration(seconds: 20);

  final PikPakTransfer transfer;
  final Json task, file;
  final int size;
  final _Ranges have;
  final claims = <_Claim>{};
  final readers = <_Reader>[];
  int _holders = 0;
  Future<void>? running, finishing;
  Object? error;
  var _work = Completer<void>(), _data = Completer<void>();

  bool get done => have.covers(size);
  bool get _wanted => _holders > 0 && !transfer._closed;
  String get path => '${file['path']}';
  String get partPath => '$path.part';

  void hold() {
    _holders++;
    if (running != null) return;
    if (done) {
      unawaited(transfer._finish(this));
      return;
    }
    error = null;
    running = _run().whenComplete(() {
      running = null;
      arrived();
      unawaited(transfer._finish(this));
    });
  }

  void release() {
    if (--_holders == 0) _stop();
  }

  void _stop() {
    for (final claim in claims) {
      claim.abort();
    }
    _wake();
  }

  /// Stops fetching and drops every player connection.
  Future<void> close() async {
    _holders = 0;
    for (final reader in readers.toList()) {
      closeReader(reader);
    }
    _stop();
    await running;
    while (readers.isNotEmpty) {
      await _data.future;
    }
  }

  void closeReader(_Reader reader) {
    reader.closed = true;
    reader.socket.destroy();
    arrived();
  }

  void _fail(Object failure) {
    error ??= failure;
    for (final claim in claims) {
      claim.abort();
    }
    arrived();
    _wake();
  }

  void _wake() {
    final work = _work;
    _work = Completer<void>();
    work.complete();
  }

  /// Wakes readers waiting for data, a stop or a failure.
  void arrived() {
    final data = _data;
    _data = Completer<void>();
    data.complete();
  }

  Future<void> _run() async {
    await Directory(p.dirname(path)).create(recursive: true);
    await File(partPath).create();
    await Future.wait([for (var i = 0; i < connections; i++) _worker()]);
  }

  /// One connection. A connection that keeps failing for about fifteen
  /// seconds without receiving data fails the fetch; a refusal from the API
  /// fails it at once.
  Future<void> _worker() async {
    var failures = 0;
    while (_wanted && !done && error == null) {
      final claim = _pick();
      if (claim == null) {
        await _work.future;
        continue;
      }
      claims.add(claim);
      final start = claim.cursor;
      try {
        await _download(claim);
        failures = 0;
      } on http.RequestAbortedException {
        // Stopped, or handed to a reader that seeked elsewhere.
      } on PikPakException catch (failure) {
        _fail(failure);
      } catch (failure) {
        if (claim.cursor > start) failures = 0;
        if (!_wanted || error != null) break;
        if (++failures >= 6) {
          _fail(failure);
          break;
        }
        await Future<void>.delayed(Duration(seconds: min(failures, 4)));
      } finally {
        claims.remove(claim);
        _wake();
      }
    }
    _wake();
  }

  Future<void> _download(_Claim claim) async {
    final link = transfer._link(this);
    final url = await link;
    if (!_wanted || claim.cursor >= claim.end) return;
    final request =
        http.AbortableRequest(
            'GET',
            Uri.parse(url),
            abortTrigger: claim.aborted.future,
          )
          ..headers['Range'] = 'bytes=${claim.cursor}-${claim.end - 1}'
          ..headers['Accept-Encoding'] = 'identity';
    final response = await transfer._http
        .send(request)
        .timeout(
          idle,
          onTimeout: () {
            claim.abort();
            throw TimeoutException('PikPak 文件连接超时');
          },
        );
    if (const {401, 403, 410}.contains(response.statusCode)) {
      await response.stream.listen(null).cancel();
      transfer._expire(this, link);
      throw const HttpException('PikPak 下载链接已失效');
    }
    if (response.statusCode != HttpStatus.partialContent ||
        !(response.headers['content-range'] ?? '').startsWith(
          'bytes ${claim.cursor}-',
        )) {
      await response.stream.listen(null).cancel();
      throw HttpException('PikPak 文件下载失败（HTTP ${response.statusCode}）');
    }
    final output = await File(partPath).open(mode: FileMode.append);
    try {
      await output.setPosition(claim.cursor);
      await for (final bytes in response.stream.timeout(idle)) {
        final length = min(bytes.length, claim.end - claim.cursor);
        if (length > 0) {
          await output.writeFrom(bytes, 0, length);
          have.add(claim.cursor, claim.cursor + length);
          claim.cursor += length;
          transfer._received.update(
            '${task['id']}',
            (value) => value + length,
            ifAbsent: () => length,
          );
          arrived();
        }
        if (claim.cursor >= claim.end || !_wanted) break;
      }
    } finally {
      await output.close();
    }
    if (_wanted && claim.cursor < claim.end) {
      throw const HttpException('PikPak 连接提前结束');
    }
  }

  /// The next range to fetch: where a reader waits, then the windows ahead
  /// of readers, newest first, then the rest of the file from the newest
  /// reader on.
  _Claim? _pick() {
    for (final reader in readers.reversed) {
      final waiting = reader.waiting;
      if (waiting == null) continue;
      final claim = claims
          .where((claim) => claim.cursor <= waiting && waiting < claim.end)
          .firstOrNull;
      if (claim == null) return _claim(waiting, near);
      if (waiting - claim.cursor > near) {
        claim.end = waiting;
        return _claim(waiting, near);
      }
    }
    for (final reader in readers.reversed) {
      final start = _gap(reader.position, min(reader.position + window, size));
      if (start != null) return _claim(start, near);
    }
    final from = readers.lastOrNull?.position ?? 0;
    final start = _gap(from, size) ?? _gap(0, from);
    return start == null ? null : _claim(start, far);
  }

  int? _gap(int from, int limit) {
    var offset = from;
    while (offset < limit) {
      final covered = have.endFrom(offset);
      if (covered > offset) {
        offset = covered;
        continue;
      }
      final claim = claims
          .where((claim) => claim.cursor <= offset && offset < claim.end)
          .firstOrNull;
      if (claim == null) return offset;
      offset = claim.end;
    }
    return null;
  }

  _Claim _claim(int start, int length) {
    var end = min(start + length, size);
    end = min(end, have.nextStart(start) ?? end);
    for (final claim in claims) {
      if (claim.cursor > start && claim.cursor < end) end = claim.cursor;
    }
    return _Claim(start, end);
  }

  /// Bytes from [offset] up to the end of the data held, waiting until it
  /// arrives; null once the reader is closed or the fetch stopped.
  Future<int?> _readable(_Reader reader, int offset) async {
    while (true) {
      if (reader.closed || error != null) return null;
      final end = have.endFrom(offset);
      if (end > offset) {
        reader.waiting = null;
        return end;
      }
      if (running == null && !done) return null;
      if (reader.waiting != offset) {
        reader.waiting = offset;
        _preempt(offset);
        _wake();
      }
      await _data.future;
    }
  }

  /// Hands the connection furthest from [offset] to it when every
  /// connection is busy and none will reach it soon.
  void _preempt(int offset) {
    if (claims.length < connections ||
        claims.any(
          (claim) =>
              claim.cursor <= offset &&
              offset < claim.end &&
              offset - claim.cursor <= near,
        )) {
      return;
    }
    bool ahead(_Claim claim) => readers.any(
      (reader) =>
          claim.cursor >= reader.position &&
          claim.cursor < reader.position + window,
    );
    final victims = claims.where((claim) => !ahead(claim)).toList()
      ..sort(
        (a, b) =>
            (b.cursor - offset).abs().compareTo((a.cursor - offset).abs()),
      );
    victims.firstOrNull?.abort();
  }

  /// Writes bytes up to [end] to the reader's socket as they arrive.
  Future<void> send(_Reader reader, int end) async {
    await finishing;
    final input = await File(file['complete'] == true ? path : partPath).open();
    try {
      var offset = reader.position;
      while (offset < end) {
        final readable = await _readable(reader, offset);
        if (readable == null) return;
        final length = min(min(readable, end) - offset, 512 * 1024);
        await input.setPosition(offset);
        reader.socket.add(await input.read(length));
        await reader.socket.flush();
        offset += length;
        reader.position = offset;
      }
    } finally {
      await input.close();
    }
  }
}

class _Claim {
  _Claim(this.cursor, this.end);

  /// The next byte this connection writes; [end] may be cut short while it
  /// runs.
  int cursor, end;
  final aborted = Completer<void>();
  void abort() {
    if (!aborted.isCompleted) aborted.complete();
  }
}

/// A player connection reading from [position].
class _Reader {
  _Reader(this.stream, this.position, this.socket);
  final int stream;
  final Socket socket;
  int position;
  int? waiting;
  bool closed = false;
}

/// Sorted, disjoint byte ranges, each `[start, end)`.
class _Ranges {
  _Ranges.fromJson(dynamic value) {
    for (final range in value is List ? value : const []) {
      if (range case [final int start, final int end]) add(start, end);
    }
  }

  final _starts = <int>[], _ends = <int>[];

  void add(int start, int end) {
    if (end <= start) return;
    var i = 0;
    while (i < _starts.length && _ends[i] < start) {
      i++;
    }
    var j = i;
    while (j < _starts.length && _starts[j] <= end) {
      start = min(start, _starts[j]);
      end = max(end, _ends[j]);
      j++;
    }
    _starts.replaceRange(i, j, [start]);
    _ends.replaceRange(i, j, [end]);
  }

  /// The end of the range holding [offset], or [offset] when none does.
  int endFrom(int offset) {
    for (var i = 0; i < _starts.length; i++) {
      if (_starts[i] > offset) break;
      if (offset < _ends[i]) return _ends[i];
    }
    return offset;
  }

  /// The start of the first range after [offset].
  int? nextStart(int offset) {
    for (final start in _starts) {
      if (start > offset) return start;
    }
    return null;
  }

  bool covers(int size) =>
      size == 0 || (_starts.length == 1 && _starts[0] == 0 && _ends[0] >= size);

  int get total {
    var sum = 0;
    for (var i = 0; i < _starts.length; i++) {
      sum += _ends[i] - _starts[i];
    }
    return sum;
  }

  void clip(int length) {
    for (var i = _starts.length - 1; i >= 0; i--) {
      if (_starts[i] >= length) {
        _starts.removeAt(i);
        _ends.removeAt(i);
      } else if (_ends[i] > length) {
        _ends[i] = length;
      }
    }
  }

  List<List<int>> toJson() => [
    for (var i = 0; i < _starts.length; i++) [_starts[i], _ends[i]],
  ];
}
