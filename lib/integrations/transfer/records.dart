import 'dart:io';

import 'package:path/path.dart' as p;

import '../catalog.dart';
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

/// A finished task whose files were all deleted outside the app; its record
/// goes with them. A missing [directory], such as an unplugged drive, deletes
/// nothing.
Future<bool> deletedOutside(Json task, String directory) async {
  final files = objects(task['files']);
  if (task['complete'] != true ||
      files.isEmpty ||
      !await Directory(directory).exists()) {
    return false;
  }
  for (final file in files) {
    final path = '${file['path']}';
    if (await File(path).exists() || await File('$path.part').exists()) {
      return false;
    }
  }
  return true;
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
