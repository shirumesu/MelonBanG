import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import '../../core/hls_playlist.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../../core/store.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';
import 'records.dart';

/// Online entries saved into the media cache, one task at a time. An HLS
/// stream is fetched segment by segment over several connections, AES-128
/// segments are decrypted, and the segments are joined into one file; a
/// direct stream is fetched as a file, with its separate audio track beside
/// it. Links are read from the source again when they expire. Until a task
/// completes, playing it plays the entry from its source.
class OnlineDownloads implements OnlineTransfer {
  OnlineDownloads(
    this.store,
    String directory,
    this.api,
    this.resolve, {
    http.Client? transferClient,
  }) : directory = p.normalize(p.absolute(directory)),
       _http = transferClient ?? http.Client();

  final AppStore store;
  @override
  final String directory;
  final ApiClient api;

  /// Reads an entry's stream from its source, advertisements filtered.
  final Future<ResolvedStream> Function(StreamRef ref) resolve;
  final http.Client _http;
  static const _connections = 6;
  static const _idle = Duration(seconds: 30);

  @override
  CacheMethod get method => CacheMethod.online;
  final _changes = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => _changes.stream;
  final _tasks = <String, Json>{};
  final _received = <String, int>{};
  Future<void>? _worker, _writes, _closing;
  String? _runningId;
  Completer<void>? _halt;
  Timer? _ticker;
  int _ticks = 0;
  bool _closed = false;

  @override
  Future<void> initialize() async {
    _requireOpen();
    for (final task in await store.list('online_downloads')) {
      final id = '${task['id']}';
      task['savePath'] = p.join(directory, id);
      task['downloadSpeedBytesPerSecond'] = 0;
      task['files'] = objects(task['files']).map((file) {
        file['path'] = p.join('${task['savePath']}', '${file['relativePath']}');
        return file;
      }).toList();
      if (await deletedOutside(task, directory)) {
        await _discard(task);
        continue;
      }
      // A file deleted outside the app is fetched again.
      for (final file in _files(task)) {
        if (file['complete'] == true &&
            !await File('${file['path']}').exists()) {
          file['complete'] = false;
          file['progress'] = 0.0;
          task['complete'] = false;
        }
      }
      if (task['complete'] != true && task['status'] != 'failed') {
        task['status'] = task['manualPaused'] == true ? 'paused' : 'queued';
      }
      _updateProgress(task);
      _tasks[id] = task;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _schedule();
    _emit();
  }

  @override
  List<DownloadTask> tasks() => [
    for (final task in _tasks.values) downloadTask(task, method),
  ];

  @override
  bool contains(String id) => _tasks.containsKey(id);

  @override
  Future<DownloadTask> addOnline(
    StreamRef ref, {
    required String title,
    required String source,
    int? subjectId,
    int? episodeId,
    String? coverUrl,
  }) async {
    _requireOpen();
    final fingerprint = '${ref.sourceId}:${jsonEncode(ref.data)}';
    coverUrl ??= await cachedCover(store, subjectId);
    _requireOpen();
    final existing = _tasks.values
        .where((task) => task['fingerprint'] == fingerprint)
        .firstOrNull;
    if (existing != null) return downloadTask(existing, method);
    final id = newId();
    final task = <String, dynamic>{
      'id': id,
      'provider': 'online',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'kind': 'online',
      'fingerprint': fingerprint,
      'ref': {'sourceId': ref.sourceId, 'data': ref.data},
      'title': title,
      'source': source,
      'savePath': p.join(directory, id),
      'subjectId': subjectId,
      'episodeId': episodeId,
      'coverUrl': coverUrl,
      'status': 'queued',
      'progress': 0.0,
      'complete': false,
      'manualPaused': false,
      'downloadSpeedBytesPerSecond': 0,
      'files': <Json>[],
    };
    _tasks[id] = task;
    await _persist(task);
    _schedule();
    _emit();
    return downloadTask(task, method);
  }

  StreamRef _ref(Json task) {
    final ref = object(task['ref']);
    return StreamRef('${ref['sourceId']}', object(ref['data']));
  }

  bool _active(Json task) =>
      !_closed &&
      identical(_tasks[task['id']], task) &&
      task['manualPaused'] != true;

  void _schedule() {
    if (_closed || _worker != null) return;
    final next = _tasks.values
        .where(
          (task) =>
              _active(task) &&
              task['complete'] != true &&
              task['status'] == 'queued',
        )
        .firstOrNull;
    if (next == null) return;
    _runningId = '${next['id']}';
    final halt = _halt = Completer<void>();
    _worker = _run(next, halt.future).whenComplete(() {
      _worker = null;
      _runningId = null;
      _halt = null;
      _schedule();
      _emit();
    });
  }

  Future<void> _run(Json task, Future<void> halt) async {
    try {
      task['status'] = 'metadata';
      task['errorMessage'] = null;
      _emit();
      final job = _Job(this, task, halt, await resolve(_ref(task)));
      if (!_active(task)) return;
      if (job.stream.danmakuProvider case final provider?) {
        task['danmakuProvider'] = provider;
        task['danmakuLocator'] = job.stream.danmakuLocator;
      }
      task['status'] = 'downloading';
      _emit();
      if (job.stream.format == StreamFormat.hls) {
        await job.hls();
      } else {
        await job.direct();
      }
      if (!_active(task)) return;
      task['complete'] = true;
      task['status'] = 'completed';
      task['downloadSpeedBytesPerSecond'] = 0;
      await _persist(task);
    } catch (error) {
      if (!_active(task)) return;
      task['status'] = 'failed';
      task['errorMessage'] = '$error'.replaceFirst('Bad state: ', '');
      task['downloadSpeedBytesPerSecond'] = 0;
      await _persist(task);
    } finally {
      _emit();
    }
  }

  void _count(Json task, int bytes) => _received.update(
    '${task['id']}',
    (value) => value + bytes,
    ifAbsent: () => bytes,
  );

  void _tick() {
    if (_closed) return;
    var changed = false;
    for (final task in _tasks.values) {
      final speed = _received[task['id']] ?? 0;
      if (task['downloadSpeedBytesPerSecond'] != speed) {
        task['downloadSpeedBytesPerSecond'] = speed;
        changed = true;
      }
    }
    _received.clear();
    final running = _tasks[_runningId];
    if (running != null) {
      _updateProgress(running);
      // A failed save is retried by the next one.
      if (++_ticks % 5 == 0) _persist(running).ignore();
      changed = true;
    }
    if (changed) _emit();
  }

  /// The task's own file records, which runs update in place.
  List<Json> _files(Json task) => (task['files'] as List).cast<Json>();

  void _updateProgress(Json task) {
    final files = _files(task);
    if (task['segmentCount'] case final int count) {
      final done = (task['segmentsDone'] as List? ?? const []).length;
      final bytes = number(task['segmentBytes']).toInt();
      final file = files.firstOrNull;
      final progress = task['complete'] == true ? 1.0 : done / count;
      if (file != null && file['complete'] != true) {
        file['size'] = done == 0 ? 0 : bytes * count ~/ done;
        file['downloadedBytes'] = bytes;
        file['progress'] = progress;
      }
      task['progress'] = progress;
    } else {
      var total = 0, bytes = 0;
      for (final file in files) {
        final size = number(file['size']).toInt();
        final have = file['complete'] == true
            ? size
            : number(file['downloadedBytes']).toInt();
        file['progress'] = size > 0 ? have / size : 0.0;
        total += size;
        bytes += have;
      }
      task['progress'] = task['complete'] == true
          ? 1.0
          : total > 0 && files.every((file) => number(file['size']) > 0)
          ? bytes / total
          : 0.0;
    }
    task['totalBytes'] = files.fold<int>(
      0,
      (sum, file) => sum + number(file['size']).toInt(),
    );
  }

  @override
  Future<void> pause(String id) async {
    _requireOpen();
    final task = _task(id);
    if (task['complete'] == true) return;
    task['manualPaused'] = true;
    await _stopWorker(id);
    task['status'] = 'paused';
    task['downloadSpeedBytesPerSecond'] = 0;
    await _persist(task);
    _schedule();
    _emit();
  }

  @override
  Future<void> resume(String id) async {
    _requireOpen();
    final task = _task(id);
    if (task['complete'] == true || _runningId == id) return;
    task['manualPaused'] = false;
    task['errorMessage'] = null;
    task['status'] = 'queued';
    await _persist(task);
    _schedule();
    _emit();
  }

  Future<void> _stopWorker(String id) async {
    if (_runningId != id) return;
    if (_halt?.isCompleted == false) _halt!.complete();
    await _worker;
  }

  @override
  Future<void> remove(String id) async {
    _requireOpen();
    final task = _tasks.remove(id);
    if (task == null) return;
    await _stopWorker(id);
    await _discard(task);
    _emit();
  }

  /// Deletes a task's record and folder.
  Future<void> _discard(Json task) async {
    await _writes;
    await store.remove('online_downloads', '${task['id']}');
    final folder = Directory('${task['savePath']}');
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  @override
  TransferMedia media(String id, {String? fileId}) {
    final task = _task(id);
    final files = _files(task);
    final video = files
        .where((file) => file['mediaKind'] == 'video')
        .firstOrNull;
    if (video == null) throw StateError('尚未读取到视频地址');
    final audio = files
        .where((file) => file['mediaKind'] == 'audio')
        .firstOrNull;
    return TransferMedia(
      file: downloadFile(video),
      incomplete: task['complete'] != true,
      subjectId: task['subjectId'] as int?,
      episodeId: task['episodeId'] as int?,
      audioPath: audio?['path'] as String?,
      danmaku: switch (task['danmakuProvider']) {
        final String provider => (provider, '${task['danmakuLocator']}'),
        _ => null,
      },
    );
  }

  @override
  Future<TransferMedia> openMedia(String id, {String? fileId}) async {
    final selected = media(id, fileId: fileId);
    if (!selected.incomplete) return selected;
    return selected.playingOnline(await resolve(_ref(_task(id))));
  }

  @override
  void releaseStreamsExcept(int? keep) {}

  Future<void> _persist(Json task) {
    _updateProgress(task);
    final saved = Map<String, dynamic>.of(task)
      ..['files'] = [
        for (final file in objects(task['files'])) {...file},
      ];
    final writing = (_writes ?? Future<void>.value()).then(
      (_) => store.put('online_downloads', '${task['id']}', saved),
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
    if (_halt?.isCompleted == false) _halt!.complete();
    await _worker;
    for (final task in _tasks.values) {
      task['downloadSpeedBytesPerSecond'] = 0;
      await _persist(task);
    }
    await _writes;
    _http.close();
    await _changes.close();
  }
}

/// The source refused a link it handed out earlier.
class _Expired implements Exception {
  const _Expired(this.status);
  final int status;
}

/// One run of a task: its current stream, read again when links expire.
class _Job {
  _Job(this.transfer, this.task, this.halt, this.stream);
  final OnlineDownloads transfer;
  final Json task;
  final Future<void> halt;
  ResolvedStream stream;
  _Media? media;
  Future<void>? _refreshing;
  int _refreshes = 0;
  final _keys = <Uri, Future<Uint8List>>{};

  String get savePath => '${task['savePath']}';
  bool get active => transfer._active(task);

  /// Reads the stream again; three reads in a row without a successful
  /// fetch fail the task.
  Future<void> _refresh() => _refreshing ??= () async {
    if (++_refreshes > 3) throw StateError('视频源的地址反复失效，请稍后重试');
    stream = await transfer.resolve(transfer._ref(task));
    if (media case final old?) {
      final next = await _playlist();
      if (next.segments.length != old.segments.length) {
        throw StateError('视频源的分段已变化，请移除后重新下载');
      }
      media = next;
    }
  }().whenComplete(() => _refreshing = null);

  /// Runs [action], reading the stream again when its links expire and
  /// retrying network failures a few times.
  Future<T> _retry<T>(Future<T> Function() action) async {
    var failures = 0;
    while (true) {
      final used = stream;
      try {
        final result = await action();
        _refreshes = 0;
        return result;
      } on _Expired {
        // Connections that failed together share one new read.
        if (identical(stream, used)) {
          await _refresh();
        } else {
          await _refreshing;
        }
      } on StateError {
        rethrow;
      } catch (error) {
        if (!active || ++failures > 4) rethrow;
        await Future<void>.delayed(Duration(seconds: failures));
      }
    }
  }

  Future<_Media> _playlist() async => _Media.parse(
    stream.playlist ??
        (await fetchPlaylist(
          transfer.api,
          Uri.parse(stream.url),
          stream.headers,
        )).$1,
  );

  Future<http.StreamedResponse> _get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final abort = Completer<void>();
    halt.whenComplete(() {
      if (!abort.isCompleted) abort.complete();
    }).ignore();
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..headers.addAll({
            'User-Agent': 'Mozilla/5.0',
            ...stream.headers,
            ...headers,
          });
    final response = await transfer._http
        .send(request)
        .timeout(
          OnlineDownloads._idle,
          onTimeout: () {
            if (!abort.isCompleted) abort.complete();
            throw TimeoutException('视频源连接超时');
          },
        );
    if (const {401, 403, 404, 410}.contains(response.statusCode)) {
      await response.stream.listen(null).cancel();
      throw _Expired(response.statusCode);
    }
    if (response.statusCode >= 300) {
      await response.stream.listen(null).cancel();
      throw HttpException('视频源下载失败（HTTP ${response.statusCode}）');
    }
    return response;
  }

  Future<Uint8List> _bytes(Uri uri) async {
    final response = await _get(uri);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(OnlineDownloads._idle)) {
      builder.add(chunk);
      transfer._count(task, chunk.length);
    }
    return builder.takeBytes();
  }

  String _name(String extension) {
    final base = '${task['title']}'
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim();
    final short = base.length > 120 ? base.substring(0, 120) : base;
    return '${short.isEmpty ? task['id'] : short}$extension';
  }

  Json _file(String id, String name, String kind) => {
    'id': id,
    'downloadId': '${task['id']}',
    'name': name,
    'relativePath': name,
    'path': p.join(savePath, name),
    'size': 0,
    'downloadedBytes': 0,
    'progress': 0.0,
    'complete': false,
    'mediaKind': kind,
  };

  /// Fetches the segments not yet on disk, then joins them in order.
  Future<void> hls() async {
    final initial = await _retry(_playlist);
    media = initial;
    final count = initial.segments.length;
    final folder = Directory(p.join(savePath, 'segments'));
    String segment(int index) => p.join(folder.path, '$index.seg');
    final done = <int>{
      if (task['segmentCount'] == count)
        for (final index in task['segmentsDone'] as List? ?? const [])
          index as int,
    };
    if (task['segmentCount'] != count && await folder.exists()) {
      await folder.delete(recursive: true);
    }
    await folder.create(recursive: true);
    var bytes = 0;
    for (final index in done.toList()) {
      final file = File(segment(index));
      if (await file.exists()) {
        bytes += await file.length();
      } else {
        done.remove(index);
      }
    }
    final extension = initial.map == null ? '.ts' : '.mp4';
    if (transfer._files(task).firstOrNull?['name'] case final String name
        when name.endsWith(extension)) {
      // Kept from an earlier run of the same stream.
    } else {
      task['files'] = <Json>[_file('0', _name(extension), 'video')];
    }
    task
      ..['segmentCount'] = count
      ..['segmentsDone'] = done.toList()
      ..['segmentBytes'] = bytes;
    await transfer._persist(task);
    final initPath = p.join(folder.path, 'init.seg');
    if (initial.map != null && !await File(initPath).exists()) {
      final data = await _retry(() => _bytes(media!.map!));
      await File(initPath).writeAsBytes(data);
    }
    final pending = [
      for (var index = 0; index < count; index++)
        if (!done.contains(index)) index,
    ];
    Object? failure;
    StackTrace? failureStack;
    Future<void> worker() async {
      while (pending.isNotEmpty && failure == null && active) {
        final index = pending.removeAt(0);
        try {
          final data = await _retry(() async {
            final part = media!.segments[index];
            final raw = await _bytes(part.uri);
            return part.key == null
                ? raw
                : _decrypt(raw, await _key(part.key!), part.iv!);
          });
          if (!active) return;
          final file = File(segment(index));
          await File('${file.path}.part').writeAsBytes(data);
          await File('${file.path}.part').rename(file.path);
          done.add(index);
          bytes += data.length;
          task
            ..['segmentsDone'] = done.toList()
            ..['segmentBytes'] = bytes;
        } catch (error, stack) {
          if (!active) return;
          failure ??= error;
          failureStack ??= stack;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < OnlineDownloads._connections; i++) worker(),
    ]);
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    if (!active) return;
    final file = transfer._files(task).first;
    final part = File('${file['path']}.part');
    final sink = part.openWrite();
    try {
      if (initial.map != null) await sink.addStream(File(initPath).openRead());
      for (var index = 0; index < count; index++) {
        await sink.addStream(File(segment(index)).openRead());
      }
    } finally {
      await sink.close();
    }
    await part.rename('${file['path']}');
    await folder.delete(recursive: true);
    file
      ..['size'] = await File('${file['path']}').length()
      ..['complete'] = true
      ..['progress'] = 1.0;
  }

  Future<Uint8List> _key(Uri uri) =>
      _keys[uri] ??= _retry(() => _bytes(uri))
          .then((key) {
            if (key.length != 16) throw StateError('视频源的解密密钥无效');
            return key;
          })
          .onError<Object>((error, stack) {
            _keys.remove(uri);
            Error.throwWithStackTrace(error, stack);
          });

  static Uint8List _decrypt(Uint8List data, Uint8List key, Uint8List iv) =>
      (PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
            false,
            PaddedBlockCipherParameters(
              ParametersWithIV(KeyParameter(key), iv),
              null,
            ),
          ))
          .process(data);

  /// Fetches the video file and its separate audio track, resuming partial
  /// files.
  Future<void> direct() async {
    final extension = switch (p
        .extension(Uri.parse(stream.url).path)
        .toLowerCase()) {
      final known
          when const {'.mp4', '.mkv', '.flv', '.webm'}.contains(known) =>
        known,
      _ => '.mp4',
    };
    final ids = ['0', if (stream.audioUrl != null) '1'];
    final kept = transfer._files(task);
    task['files'] = <Json>[
      for (final id in ids)
        kept.where((file) => file['id'] == id).firstOrNull ??
            (id == '0'
                ? _file(id, _name(extension), 'video')
                : _file(id, _name('.audio.m4a'), 'audio')),
    ];
    await transfer._persist(task);
    for (final file in transfer._files(task)) {
      if (!active) return;
      if (file['complete'] == true) continue;
      await _retry(
        () =>
            _fetchFile(file, file['id'] == '0' ? stream.url : stream.audioUrl!),
      );
    }
  }

  Future<void> _fetchFile(Json file, String url) async {
    final part = File('${file['path']}.part');
    var offset = await part.exists() ? await part.length() : 0;
    final response = await _get(
      Uri.parse(url),
      headers: {if (offset > 0) 'Range': 'bytes=$offset-'},
    );
    if (response.statusCode != HttpStatus.partialContent) offset = 0;
    final total = switch (RegExp(r'/(\d+)$')
        .firstMatch(response.headers['content-range'] ?? '')) {
      final match? => int.parse(match[1]!),
      null => offset + (response.contentLength ?? 0),
    };
    file['size'] = total;
    final output = await part.open(
      mode: offset == 0 ? FileMode.write : FileMode.append,
    );
    try {
      await for (final chunk in response.stream.timeout(
        OnlineDownloads._idle,
      )) {
        await output.writeFrom(chunk);
        offset += chunk.length;
        file['downloadedBytes'] = offset;
        transfer._count(task, chunk.length);
        if (!active) return;
      }
    } finally {
      await output.close();
    }
    if (total > 0 && offset < total) throw const HttpException('视频源连接提前结束');
    await part.rename('${file['path']}');
    file
      ..['size'] = offset
      ..['complete'] = true;
  }
}

class _Segment {
  const _Segment(this.uri, this.key, this.iv);
  final Uri uri;
  final Uri? key;
  final Uint8List? iv;
}

/// A media playlist with absolute URIs.
class _Media {
  const _Media(this.segments, this.map);
  final List<_Segment> segments;

  /// The initialization section fragmented MP4 segments share.
  final Uri? map;

  static _Media parse(String text) {
    var sequence = 0;
    Uri? key, map;
    Uint8List? iv;
    final segments = <_Segment>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.tryParse(line.substring(22)) ?? 0;
      } else if (line.startsWith('#EXT-X-KEY:')) {
        final attributes = _attributes(line.substring(11));
        switch (attributes['METHOD']) {
          case 'NONE':
            key = null;
            iv = null;
          case 'AES-128':
            key = Uri.parse(attributes['URI']!);
            iv = switch (attributes['IV']) {
              final String hex => _hex(hex),
              null => null,
            };
          case final method:
            throw StateError('不支持 $method 加密的视频流');
        }
      } else if (line.startsWith('#EXT-X-MAP:')) {
        final attributes = _attributes(line.substring(11));
        if (attributes.containsKey('BYTERANGE')) {
          throw StateError('不支持按字节范围分段的视频流');
        }
        final uri = Uri.parse(attributes['URI']!);
        if (map != null && map != uri) throw StateError('不支持多段初始化的视频流');
        map = uri;
      } else if (line.startsWith('#EXT-X-BYTERANGE')) {
        throw StateError('不支持按字节范围分段的视频流');
      } else if (!line.startsWith('#')) {
        segments.add(
          _Segment(
            Uri.parse(line),
            key,
            key == null ? null : iv ?? _sequenceIv(sequence + segments.length),
          ),
        );
      }
    }
    if (segments.isEmpty) throw StateError('视频清单没有分段');
    return _Media(segments, map);
  }

  static Map<String, String> _attributes(String value) => {
    for (final match in RegExp(
      r'([A-Z0-9-]+)=("[^"]*"|[^,]*)',
    ).allMatches(value))
      match[1]!: match[2]!.replaceAll('"', ''),
  };

  static Uint8List _hex(String value) {
    final digits = value.replaceFirst(RegExp('^0[xX]'), '').padLeft(32, '0');
    return Uint8List.fromList([
      for (var i = 0; i < 32; i += 2)
        int.parse(digits.substring(i, i + 2), radix: 16),
    ]);
  }

  /// Without an IV attribute a segment's IV is its media sequence number.
  static Uint8List _sequenceIv(int sequence) {
    final iv = Uint8List(16);
    for (var i = 15, value = sequence; i >= 8; i--, value >>= 8) {
      iv[i] = value & 0xff;
    }
    return iv;
  }
}
