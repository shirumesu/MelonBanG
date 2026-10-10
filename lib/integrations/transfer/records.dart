import '../../data/catalog.dart';
import '../../data/json.dart';
import '../../data/store.dart';
import '../../domain/transfer.dart';

/// Decodes a stored task record; BT and PikPak share these field names.
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
  );
}

DownloadFile downloadFile(Json file) => DownloadFile(
  id: '${file['id']}',
  downloadId: '${file['downloadId']}',
  name: '${file['name']}',
  path: '${file['path']}',
  size: number(file['size']).toInt(),
  progress: number(file['progress']),
  video: file['mediaKind'] == 'video',
);

/// Cover of a subject whose detail is cached locally, for tasks added
/// without one.
Future<String?> cachedCover(AppStore store, int? subjectId) async {
  if (subjectId == null) return null;
  final cover = (await cachedSubjectDetail(store, subjectId))?['coverUrl'];
  return cover is String && cover.isNotEmpty ? cover : null;
}
