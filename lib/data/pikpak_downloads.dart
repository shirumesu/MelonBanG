import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'json.dart';
import 'pikpak.dart';
import 'store.dart';
import 'torrent_identity.dart';

/// Cloud acquisition and local cache records have independent lifetimes.
class PikPakDownloadRepository {
  PikPakDownloadRepository(
    this.store,
    String directory,
    this.client, {
    http.Client? transferClient,
    this.pollInterval = const Duration(seconds: 5),
  }) : directory = p.normalize(p.absolute(directory)),
       _transfer = transferClient ?? http.Client();

  final AppStore store;
  final String directory;
  final PikPakClient client;
  final Duration pollInterval;
  final http.Client _transfer;
  final changes = StreamController<Json>.broadcast();
  final _tasks = <String, Json>{};
  final _adding = <String, Future<Json>>{};
  final _removing = <String, Future<void>>{};
  Future<void>? _worker, _writes, _closing;
  String? _runningId;
  Completer<void>? _abort, _wake;
  bool _closed = false;

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
      await _reconcileFiles(task);
      _tasks[id] = task;
    }
    _schedule();
    _emit();
  }

  Json snapshot() => {
    'tasks': _tasks.values
        .map((task) => object(jsonDecode(jsonEncode(task))))
        .toList(),
    'files': _tasks.values.expand((task) => objects(task['files'])).toList(),
  };

  bool contains(String id) => _tasks.containsKey(id);

  Future<Json> addMagnet(
    String input, {
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    String? title,
    List<String> releaseGroups = const [],
  }) {
    _requireOpen();
    final owner = client.userId;
    if (!client.isSignedIn || owner == null) {
      throw StateError('请先在设置中登录 PikPak');
    }
    final uri = Uri.parse(input.trim());
    if (uri.scheme != 'magnet') throw const FormatException('请输入磁力链接');
    final fingerprint = magnetInfoHash(uri);
    final key = '$owner:$fingerprint';
    return _adding.putIfAbsent(
      key,
      () =>
          _create(
            uri.toString(),
            owner,
            fingerprint,
            title ?? uri.queryParameters['dn'] ?? 'PikPak 云端缓存',
            subjectId,
            episodeId,
            coverUrl,
            releaseGroups,
          ).whenComplete(() {
            _adding.remove(key);
          }),
    );
  }

  Future<Json> _create(
    String input,
    String owner,
    String fingerprint,
    String title,
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    List<String> releaseGroups,
  ) async {
    await _removing['$owner:$fingerprint'];
    _requireOpen();
    final existing = _tasks.values
        .where(
          (task) =>
              task['ownerId'] == owner && task['fingerprint'] == fingerprint,
        )
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
    final id = newId();
    final task = <String, dynamic>{
      'id': id,
      'provider': 'pikpak',
      'ownerId': owner,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'kind': 'magnet',
      'input': input,
      'fingerprint': fingerprint,
      'title': title,
      if (releaseGroups.isNotEmpty)
        'releaseGroups': List<String>.of(releaseGroups),
      'savePath': p.join(directory, id),
      'subjectId': subjectId,
      'episodeId': episodeId,
      'coverUrl': coverUrl,
      'status': 'queued',
      'phase': 'cloud',
      'progress': 0.0,
      'cloudProgress': 0.0,
      'complete': false,
      'manualPaused': false,
      'downloadSpeedBytesPerSecond': 0,
      'files': <Json>[],
    };
    _tasks[id] = task;
    await _persist(task);
    _schedule();
    _emit();
    return task;
  }

  bool _owns(Json task) =>
      client.isSignedIn && client.userId == task['ownerId'];
  bool _active(Json task) =>
      !_closed &&
      identical(_tasks[task['id']], task) &&
      task['manualPaused'] != true &&
      _owns(task);

  void _schedule() {
    if (_closed || _worker != null) return;
    for (final task in _tasks.values) {
      if (task['complete'] == true ||
          task['manualPaused'] == true ||
          task['status'] == 'failed') {
        continue;
      }
      if (!_owns(task)) {
        task['status'] = 'paused';
        task['errorMessage'] = '登录创建此缓存的 PikPak 账号后可继续';
      } else {
        task['status'] = 'queued';
      }
    }
    final next = _tasks.values
        .where(
          (task) =>
              _active(task) &&
              task['complete'] != true &&
              task['status'] != 'failed',
        )
        .firstOrNull;
    if (next == null) return;
    _runningId = '${next['id']}';
    _worker = _run(next).whenComplete(() {
      _worker = null;
      _runningId = null;
      _abort = null;
      _schedule();
      _emit();
    });
  }

  Future<void> _run(Json task) async {
    try {
      task['errorMessage'] = null;
      if (objects(task['files']).isEmpty) await _acquire(task);
      if (!_active(task)) return;
      task['phase'] = 'local';
      task['status'] = 'downloading';
      await _reconcileFiles(task);
      await _persist(task);
      if (!_active(task)) return;
      _emit();
      for (final file in (task['files'] as List).cast<Json>()) {
        if (!_active(task)) return;
        if (file['complete'] == true) continue;
        await _cacheFile(task, file);
      }
      if (!_active(task)) return;
      _updateProgress(task);
      task['complete'] = true;
      task['status'] = 'completed';
      task['progress'] = 1.0;
      task['downloadSpeedBytesPerSecond'] = 0;
      await _persist(task);
    } catch (error) {
      if (!_active(task)) return;
      task['status'] = 'failed';
      task['errorMessage'] = '$error';
      task['downloadSpeedBytesPerSecond'] = 0;
      try {
        await _persist(task);
      } catch (_) {
        // The next explicit retry also retries saving the record.
      }
    } finally {
      task['downloadSpeedBytesPerSecond'] = 0;
      _emit();
    }
  }

  Future<void> _acquire(Json task) async {
    task['status'] = 'metadata';
    task['phase'] = 'cloud';
    _emit();
    if (task['cloudTaskId'] == null && task['cloudRootId'] == null) {
      final result = await client.offlineDownload('${task['input']}');
      if (!identical(_tasks[task['id']], task)) return;
      final remote = object(result['task']).isEmpty
          ? result
          : object(result['task']);
      task['cloudTaskId'] = remote['id'];
      task['cloudRootId'] = remote['file_id'] ?? object(result['file'])['id'];
      if (task['cloudTaskId'] == null && task['cloudRootId'] == null) {
        throw StateError('PikPak 未返回云端任务');
      }
      await _persist(task);
      if (!_active(task)) return;
    }
    while (_active(task) && task['cloudTaskId'] != null) {
      final remote = await client.task('${task['cloudTaskId']}');
      if (!_active(task)) return;
      final phase = '${remote['phase']}';
      task['cloudProgress'] = (_integer(remote['progress']) / 100).clamp(
        0.0,
        1.0,
      );
      task['cloudRootId'] = remote['file_id'] ?? task['cloudRootId'];
      if (phase == 'PHASE_TYPE_ERROR') {
        task.remove('cloudTaskId');
        task.remove('cloudRootId');
        throw StateError(
          '${remote['message'] ?? remote['reason'] ?? 'PikPak 云端下载失败'}',
        );
      }
      _emit();
      if (phase == 'PHASE_TYPE_COMPLETE') break;
      _wake = Completer<void>();
      final timer = Timer(pollInterval, () {
        if (!_wake!.isCompleted) _wake!.complete();
      });
      await _wake!.future;
      timer.cancel();
      _wake = null;
    }
    if (!_active(task)) return;
    final root = task['cloudRootId'];
    if (root == null || '$root'.isEmpty) throw StateError('PikPak 云端文件尚未就绪');
    final leaves = await client.files('$root');
    if (!_active(task)) return;
    if (leaves.isEmpty) throw StateError('PikPak 云端任务没有可缓存文件');
    final usedPaths = <String>{};
    task['files'] = leaves.map((remote) {
      final name = '${remote['name'] ?? remote['id']}';
      var relative = _relativePath('${remote['path'] ?? name}');
      if (!usedPaths.add(relative.toLowerCase())) {
        relative = p.join('${remote['id']}', relative);
        usedPaths.add(relative.toLowerCase());
      }
      return <String, dynamic>{
        'id': '${remote['id']}',
        'cloudFileId': '${remote['id']}',
        'downloadId': task['id'],
        'name': name,
        'relativePath': relative,
        'path': p.join('${task['savePath']}', relative),
        'size': _size(remote['size']),
        'downloadedBytes': 0,
        'progress': 0.0,
        'complete': false,
        'mediaKind':
            '${remote['mime_type']}'.startsWith('video/') ||
                const {
                  '.mkv',
                  '.mp4',
                  '.avi',
                  '.webm',
                  '.mov',
                  '.m4v',
                  '.ts',
                  '.wmv',
                }.contains(p.extension(name).toLowerCase())
            ? 'video'
            : 'other',
      };
    }).toList();
    task['cloudProgress'] = 1.0;
    await _persist(task);
  }

  Future<void> _cacheFile(Json task, Json file) async {
    final target = File('${file['path']}');
    final partial = File('${file['path']}.part');
    await target.parent.create(recursive: true);
    var offset = await partial.exists() ? await partial.length() : 0;
    var declaredSize = _size(file['size']);
    if (offset == declaredSize) {
      if (!await partial.exists()) await partial.writeAsBytes([]);
      await partial.rename(target.path);
      file['downloadedBytes'] = declaredSize;
      file['complete'] = true;
      file['progress'] = 1.0;
      _updateProgress(task);
      await _persist(task);
      return;
    }
    if (offset > declaredSize && declaredSize > 0) {
      await partial.writeAsBytes([]);
      offset = 0;
    }
    final remote = await client.file('${file['cloudFileId']}');
    if (!_active(task)) return;
    if (declaredSize < 0) declaredSize = _size(remote['size']);
    final address = _downloadAddress(remote);
    _abort = Completer<void>();
    final request =
        http.AbortableRequest(
            'GET',
            Uri.parse(address),
            abortTrigger: _abort!.future,
          )
          ..headers['Accept'] = 'application/octet-stream'
          ..headers['Accept-Encoding'] = 'identity';
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
    final response = await _transfer
        .send(request)
        .timeout(
          const Duration(seconds: 45),
          onTimeout: () {
            if (_abort?.isCompleted == false) _abort!.complete();
            throw TimeoutException('PikPak 文件连接超时，请重试');
          },
        );
    if (!_active(task)) {
      await response.stream.listen(null).cancel();
      return;
    }
    var expected = declaredSize;
    if (response.statusCode == 206) {
      final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
          .firstMatch(response.headers['content-range'] ?? '');
      if (range == null ||
          int.parse(range[1]!) != offset ||
          int.parse(range[2]!) + 1 != int.parse(range[3]!) ||
          (declaredSize >= 0 && int.parse(range[3]!) != declaredSize)) {
        await response.stream.listen(null).cancel();
        throw StateError('PikPak 返回的续传范围不匹配，请重试');
      }
      expected = int.parse(range[3]!);
    } else if (response.statusCode == 200) {
      offset = 0;
      final length = response.contentLength;
      if (declaredSize >= 0 && length != null && length != declaredSize) {
        await response.stream.listen(null).cancel();
        throw StateError('PikPak 返回的文件大小不匹配');
      }
      expected = length ?? declaredSize;
    } else {
      await response.stream.listen(null).cancel();
      throw HttpException('PikPak 文件下载失败（HTTP ${response.statusCode}）');
    }
    if (expected < 0) {
      await response.stream.listen(null).cancel();
      throw StateError('PikPak 未提供可校验的文件大小');
    }
    file['size'] = expected;
    final sink = partial.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    var received = offset, lastBytes = offset, lastTick = 0;
    final clock = Stopwatch()..start();
    try {
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 45),
      )) {
        if (!_active(task)) break;
        received += bytes.length;
        if (received > expected) throw StateError('PikPak 文件内容超出预期大小');
        sink.add(bytes);
        file['downloadedBytes'] = received;
        file['progress'] = received / expected;
        final now = clock.elapsedMilliseconds;
        if (now - lastTick >= 500) {
          task['downloadSpeedBytesPerSecond'] =
              ((received - lastBytes) * 1000 / (now - lastTick)).round();
          lastTick = now;
          lastBytes = received;
          _updateProgress(task);
          _emit();
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
      _abort = null;
    }
    if (!_active(task)) return;
    if (received != expected || await partial.length() != expected) {
      throw StateError('PikPak 文件尚未完整缓存，可继续下载');
    }
    await partial.rename(target.path);
    file['complete'] = true;
    file['progress'] = 1.0;
    _updateProgress(task);
    await _persist(task);
    _emit();
  }

  Future<void> _reconcileFiles(Json task) async {
    final files = objects(task['files']);
    for (final file in files) {
      final target = File('${file['path']}'),
          partial = File('${file['path']}.part');
      final size = _integer(file['size']);
      final complete = await target.exists() && await target.length() == size;
      final bytes = complete
          ? size
          : await partial.exists()
          ? await partial.length()
          : 0;
      file['complete'] = complete;
      file['downloadedBytes'] = bytes;
      file['progress'] = complete
          ? 1.0
          : size > 0
          ? (bytes / size).clamp(0.0, 1.0)
          : 0.0;
    }
    task['files'] = files;
    task['complete'] =
        files.isNotEmpty && files.every((file) => file['complete'] == true);
    if (task['complete'] == true) task['status'] = 'completed';
    _updateProgress(task);
  }

  void _updateProgress(Json task) {
    final files = objects(task['files']);
    final total = files.fold<int>(
      0,
      (sum, file) => sum + _integer(file['size']).clamp(0, 1 << 62),
    );
    final bytes = files.fold<int>(
      0,
      (sum, file) => sum + _integer(file['downloadedBytes']),
    );
    task['totalBytes'] = total;
    task['downloadedBytes'] = bytes;
    task['progress'] = task['complete'] == true
        ? 1.0
        : total > 0
        ? (bytes / total).clamp(0.0, 1.0)
        : 0.0;
  }

  Future<void> pause(String id) async {
    _requireOpen();
    final task = _task(id);
    task['manualPaused'] = true;
    task['status'] = 'paused';
    await _stop(id);
    await _reconcileFiles(task);
    if (task['complete'] != true) task['status'] = 'paused';
    await _persist(task);
    _emit();
  }

  Future<void> resume(String id) async {
    _requireOpen();
    final task = _task(id);
    if (task['complete'] == true) return;
    if (!_owns(task)) throw StateError('请登录创建此缓存的 PikPak 账号');
    if (_runningId == id) {
      if (task['status'] != 'failed' && task['manualPaused'] != true) return;
      await _worker;
      _requireOpen();
      if (!identical(_tasks[id], task)) throw StateError('下载任务不存在');
      if (!_owns(task)) throw StateError('请登录创建此缓存的 PikPak 账号');
    }
    task['manualPaused'] = false;
    task['errorMessage'] = null;
    task['status'] = 'queued';
    await _persist(task);
    _schedule();
    _emit();
  }

  Future<void> accountChanged() async {
    _requireOpen();
    final running = _runningId;
    if (running != null && !_owns(_task(running))) await _stop(running);
    _schedule();
    _emit();
  }

  Future<void> _stop(String id) async {
    if (_runningId != id) return;
    if (_abort?.isCompleted == false) _abort!.complete();
    if (_wake?.isCompleted == false) _wake!.complete();
    await _worker;
  }

  Future<void> remove(String id) {
    _requireOpen();
    final task = _tasks[id];
    if (task == null) return Future.value();
    final key = '${task['ownerId']}:${task['fingerprint']}';
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
    await _stop(id);
    await _writes;
    await store.remove('pikpak_downloads', id);
    final local = Directory(p.join(directory, id));
    if (await local.exists()) await local.delete(recursive: true);
    _emit();
  }

  Json media(String id, {String? fileId}) {
    final task = _task(id);
    final videos = objects(task['files'])
        .where((file) => file['mediaKind'] == 'video')
        .toList();
    if (fileId == null && videos.length > 1) {
      throw StateError('资源包含多个视频，请在缓存列表中选择具体文件');
    }
    final file = videos
        .where((file) => fileId == null || file['id'] == fileId)
        .firstOrNull;
    if (file == null) throw StateError('云端下载完成后即可播放');
    if (file['complete'] != true && !_owns(task)) {
      throw StateError('请登录创建此缓存的 PikPak 账号');
    }
    return {
      ...file,
      'incomplete': file['complete'] != true,
      'subjectId': task['subjectId'],
      'episodeId': videos.length == 1 ? task['episodeId'] : null,
    };
  }

  Json episodeMedia(int subjectId, int episodeId) {
    final matches =
        _tasks.values
            .where(
              (task) =>
                  task['subjectId'] == subjectId &&
                  task['episodeId'] == episodeId,
            )
            .toList()
          ..sort(
            (a, b) => number(b['progress']).compareTo(number(a['progress'])),
          );
    for (final task in matches) {
      try {
        return media('${task['id']}');
      } on StateError {
        continue;
      }
    }
    throw StateError('该章节尚无可播放下载，请选择资源或具体视频文件');
  }

  Future<Json> openMedia(String id, {String? fileId}) async {
    final selected = media(id, fileId: fileId);
    if (selected['incomplete'] != true) return selected;
    final remote = await client.file('${selected['cloudFileId']}');
    if (!_owns(_task(id))) throw StateError('PikPak 账号已切换，请重新选择文件');
    await resume(id);
    return {
      ...selected,
      'streamUrl': _downloadAddress(remote),
      'sourceHeaders': <String, String>{'Accept': 'application/octet-stream'},
    };
  }

  Future<void> _persist(Json task) {
    final saved = object(jsonDecode(jsonEncode(task)));
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
    if (!_closed) changes.add(snapshot());
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    if (_runningId != null) await _stop(_runningId!);
    await Future.wait(
      _adding.values.map(
        (value) => value.then<void>((_) {}, onError: (Object _) {}),
      ),
    );
    await Future.wait(_removing.values);
    for (final task in _tasks.values) {
      await _reconcileFiles(task);
      await _persist(task);
    }
    await _writes;
    _transfer.close();
    await changes.close();
  }

  static int _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static int _size(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? -1;
  static String _relativePath(String raw) => p.joinAll(
    raw
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .map((part) => part.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_')),
  );
  static String _downloadAddress(Json file) {
    final original = object(object(file['links'])['application/octet-stream']);
    for (final candidate in [original['url'], file['web_content_link']]) {
      final uri = Uri.tryParse('$candidate');
      if (uri != null &&
          const {'https', 'http'}.contains(uri.scheme) &&
          uri.host.isNotEmpty) {
        return uri.toString();
      }
    }
    throw StateError('PikPak 未提供原始文件下载地址');
  }
}
