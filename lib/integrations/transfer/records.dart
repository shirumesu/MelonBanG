import 'dart:io';

import 'package:path/path.dart' as p;

import '../catalog.dart';
import '../../core/deleted_files.dart';
import '../../core/error_message.dart';
import '../../core/json.dart';
import '../../core/store.dart';
import '../../domain/transfer.dart';

/// Whether a file may be a video. Release names often lack or misstate the
/// extension, so only extensions known to be something else rule a file out
/// and the player recognises the rest by content; files under 1 MiB are not
/// episodes.
bool mayBeVideo(String name, int size) =>
    size >= 1 << 20 && !_notVideo.contains(p.extension(name).toLowerCase());

const _notVideo = {
  // Subtitles
  '.ass', '.ssa', '.srt', '.sub', '.idx', '.sup', '.vtt', '.lrc',
  // Audio
  '.mka', '.mp3', '.flac', '.aac', '.m4a', '.ogg', '.opus', '.wav', '.ape',
  '.wv', '.tta', '.dts', '.ac3', '.eac3', '.thd',
  // Images
  '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tif', '.tiff', '.avif',
  // Fonts, archives and documents
  '.ttf', '.otf', '.ttc', '.woff', '.woff2', '.zip', '.rar', '.7z', '.tar',
  '.gz', '.bz2', '.xz', '.txt', '.nfo', '.md', '.pdf', '.htm', '.html',
  '.url', '.log', '.cue', '.xml', '.json', '.torrent', '.exe', '.iso',
  '.sfv', '.md5', '.sha1', '.sha256', '.db', '.lnk',
};

/// Decodes a stored task record; every transfer shares these field names.
DownloadTask downloadTask(Json task, CacheMethod method) {
  int? count(String key) =>
      task.containsKey(key) ? number(task[key]).toInt() : null;
  final stop = task['seedStopReason'];
  return DownloadTask(
    id: task['id'] as String,
    method: method,
    title: task['title'] as String,
    status: DownloadStatus.values.byName(task['status'] as String),
    progress: number(task['progress']),
    subjectId: task['subjectId'] as int?,
    episodeId: task['episodeId'] as int?,
    coverUrl: task['coverUrl'] as String?,
    releaseGroups: (task['releaseGroups'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    downloadSpeed: number(task['downloadSpeedBytesPerSecond']).toInt(),
    uploadSpeed: number(task['uploadSpeedBytesPerSecond']).toInt(),
    totalBytes: number(task['totalBytes']).toInt(),
    uploadedBytes: number(task['uploadedBytes']).toInt(),
    seedSeconds: number(task['seedSeconds']),
    errorMessage: task['errorMessage'] as String?,
    persistenceError: task['persistenceError'] as String?,
    seedingStopped: task['seedingStopped'] == true,
    seedStop: stop == null ? null : SeedStop.values.byName(stop as String),
    swarm: SwarmStats(
      peers: number(task['peerCount']).toInt(),
      knownPeers: count('knownPeerCount'),
      trackers: count('trackerCount'),
      workingTrackers: count('workingTrackers'),
      failedTrackers: count('failedTrackers'),
      dhtNodes: count('dhtNodes'),
    ),
    files: objects(task['files']).map(downloadFile).toList(),
    cloudProgress: (task['cloudProgress'] as num?)?.toDouble(),
    source: task['source'] as String?,
  );
}

/// The stored records of one transfer's tasks in [collection], each task
/// keeping its files in a folder named after it under [directory]. Writes
/// run one after another, each saving the task as it was when asked.
class TaskRecords {
  TaskRecords(this.store, this.collection, this.directory);
  final AppStore store;
  final String collection, directory;
  Future<void> _writes = Future.value();

  /// The stored tasks with their paths placed under [directory] and their
  /// speed cleared. A task whose files were all deleted outside the app is
  /// discarded instead.
  Future<List<Json>> restore() async {
    final restored = <Json>[];
    for (final task in await store.list(collection)) {
      final id = '${task['id']}';
      final savePath = task['savePath'] = p.join(directory, id);
      task['downloadSpeedBytesPerSecond'] = 0;
      task['files'] = [
        for (final file in objects(task['files']))
          file..['path'] = p.join(savePath, '${file['relativePath']}'),
      ];
      if (await taskDeletedOutside(task, directory)) {
        await discard(id);
      } else {
        restored.add(task);
      }
    }
    return restored;
  }

  Future<void> put(Json task) {
    final saved = <String, dynamic>{
      for (final MapEntry(:key, :value) in task.entries)
        // Lists a running task appends to are copied too.
        key: value is List ? List<dynamic>.of(value) : value,
    };
    saved['files'] = [
      for (final file in objects(task['files'])) {...file},
    ];
    final writing = _writes.then(
      (_) => store.put(collection, '${task['id']}', saved),
    );
    _writes = writing.catchError((Object _) {});
    return writing;
  }

  /// Deletes the record and folder of task [id] once earlier writes finish.
  /// The folder is moved aside first: on Windows that fails while another
  /// program, such as a player, has a file in it open, before anything is
  /// deleted, so the task stays whole instead of its files outliving its
  /// record where nothing lists them.
  Future<void> discard(String id) async {
    await _writes;
    final folder = Directory(p.join(directory, id));
    Directory? removed;
    if (await folder.exists()) {
      try {
        removed = await folder.rename(p.join(directory, '$id.removed'));
      } on FileSystemException catch (error, stack) {
        // Access denied or a sharing violation.
        if (!Platform.isWindows ||
            !const {5, 32}.contains(error.osError?.errorCode)) {
          rethrow;
        }
        Error.throwWithStackTrace(TaskFilesInUse(error), stack);
      }
    }
    await store.remove(collection, id);
    await removed?.delete(recursive: true);
  }

  /// Completes once the writes asked for so far finish.
  Future<void> get settled => _writes;
}

/// A task's folder could not be deleted because another program has a file
/// in it open; nothing was deleted, and the task stays.
class TaskFilesInUse implements UserFacingError {
  const TaskFilesInUse(this.cause);
  final FileSystemException cause;

  @override
  String get userMessage => '缓存文件正被其他程序使用，关闭后再删除';

  @override
  String toString() => 'TaskFilesInUse: $cause';
}

/// A stored finished task whose files were all deleted outside the app; its
/// record goes with them, as [deletedOutside] decides.
Future<bool> taskDeletedOutside(Json task, String directory) async =>
    task['complete'] == true &&
    await deletedOutside([
      for (final file in objects(task['files'])) '${file['path']}',
    ], directory);

DownloadFile downloadFile(Json file) => DownloadFile(
  id: '${file['id']}',
  downloadId: '${file['downloadId']}',
  name: '${file['name']}',
  path: '${file['path']}',
  size: number(file['size']).toInt(),
  progress: number(file['progress']),
  video: file['mediaKind'] == 'video',
);

/// Places an existing [task], added again with [subjectId] and [episodeId],
/// under them when it has none: a torrent first added by hand and later
/// chosen from a subject joins that subject. A subject or episode the task
/// already has is kept, and an episode is taken only from its own subject.
/// True when the task changed.
bool backfillPlace(
  Json task,
  int? subjectId,
  int? episodeId,
  String? coverUrl,
) {
  var changed = false;
  if (subjectId != null && task['subjectId'] == null) {
    task['subjectId'] = subjectId;
    if (task['coverUrl'] == null && coverUrl != null) {
      task['coverUrl'] = coverUrl;
    }
    changed = true;
  }
  if (episodeId != null &&
      task['episodeId'] == null &&
      task['subjectId'] == subjectId) {
    task['episodeId'] = episodeId;
    changed = true;
  }
  return changed;
}

/// Cover of a subject whose detail is cached locally, for tasks added
/// without one.
Future<String?> cachedCover(AppStore store, int? subjectId) async {
  if (subjectId == null) return null;
  final cover = (await cachedSubjectDetail(store, subjectId))?['coverUrl'];
  return cover is String && cover.isNotEmpty ? cover : null;
}
