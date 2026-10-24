import 'dart:typed_data';

import 'sources.dart';

/// How a task's bytes are fetched: a release over BT or through PikPak, or
/// an online source's stream.
enum CacheMethod {
  bt('BT'),
  pikpak('PikPak'),
  online('在线');

  const CacheMethod(this.label);
  final String label;
}

enum DownloadStatus {
  metadata,
  checking,
  queued,
  downloading,
  seeding,
  completed,
  paused,
  failed,
}

/// Why a finished BT task no longer seeds; [trimmed] once some of its files
/// were deleted, which leaves the rest as plain cached files.
enum SeedStop { manual, ratio, time, disabled, trimmed }

/// What a task's pause/resume control does now.
enum TaskToggle { pause, resume, stopSeeding, resumeSeeding }

class DownloadFile {
  const DownloadFile({
    required this.id,
    required this.downloadId,
    required this.name,
    required this.path,
    required this.size,
    required this.progress,
    required this.video,
  });
  final String id, downloadId, name, path;
  final int size;
  final double progress;
  final bool video;
}

/// BT swarm state; null fields are not known yet.
class SwarmStats {
  const SwarmStats({
    this.peers = 0,
    this.knownPeers,
    this.trackers,
    this.workingTrackers,
    this.failedTrackers,
    this.dhtNodes,
  });
  final int peers;
  final int? knownPeers, trackers, workingTrackers, failedTrackers, dhtNodes;
}

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.method,
    required this.title,
    required this.status,
    required this.progress,
    this.subjectId,
    this.episodeId,
    this.coverUrl,
    this.releaseGroups = const [],
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.totalBytes = 0,
    this.uploadedBytes = 0,
    this.seedSeconds = 0,
    this.errorMessage,
    this.persistenceError,
    this.seedingStopped = false,
    this.seedStop,
    this.swarm = const SwarmStats(),
    this.files = const [],
    this.cloudProgress,
    this.source,
  });
  final String id, title;
  final CacheMethod method;
  final DownloadStatus status;
  final double progress, seedSeconds;
  final int? subjectId, episodeId;
  final String? coverUrl, errorMessage, persistenceError;
  final List<String> releaseGroups;
  final int downloadSpeed, uploadSpeed, totalBytes, uploadedBytes;
  final bool seedingStopped;
  final SeedStop? seedStop;
  final SwarmStats swarm;
  final List<DownloadFile> files;

  /// How far PikPak's servers have downloaded the resource into the drive,
  /// while they still do.
  final double? cloudProgress;

  /// The online source and line an online download saves.
  final String? source;

  bool get complete => progress >= 1;
  bool get cloud => method == CacheMethod.pikpak;

  /// Only BT tasks share what they downloaded.
  bool get seeds => method == CacheMethod.bt;

  /// Null while verifying, once a finished PikPak or online task is done,
  /// and when the seeding settings stopped a finished BT task.
  TaskToggle? get toggle {
    final resumable =
        status == DownloadStatus.paused ||
        status == DownloadStatus.failed ||
        (status == DownloadStatus.completed && seedingStopped);
    if (status == DownloadStatus.checking) return null;
    if (!complete) return resumable ? TaskToggle.resume : TaskToggle.pause;
    if (!seeds) return null;
    if (resumable) return TaskToggle.resumeSeeding;
    return status == DownloadStatus.seeding || status == DownloadStatus.queued
        ? TaskToggle.stopSeeding
        : null;
  }

  /// Files can be opened unless the task is verifying or has failed.
  bool get playable =>
      status != DownloadStatus.checking && status != DownloadStatus.failed;
  List<DownloadFile> get videos => [
    for (final file in files)
      if (file.video) file,
  ];
}

class TransferSnapshot {
  const TransferSnapshot([this.tasks = const []]);
  final List<DownloadTask> tasks;

  DownloadTask? task(String id) =>
      tasks.where((task) => task.id == id).firstOrNull;
  List<DownloadTask> forSubject(int? subjectId) => subjectId == null
      ? const []
      : [
          for (final task in tasks)
            if (task.subjectId == subjectId) task,
        ];
}

/// A task's video file selected for playback.
class TransferMedia {
  const TransferMedia({
    required this.file,
    required this.incomplete,
    this.subjectId,
    this.episodeId,
    this.streamUrl,
    this.headers,
    this.streamId,
    this.audioPath,
    this.danmaku,
    this.online,
  });
  final DownloadFile file;
  final bool incomplete;
  final int? subjectId, episodeId;

  /// The separate audio track of a saved online stream.
  final String? audioPath;

  /// The danmaku the saved online stream supplied, as (provider, locator).
  final (String, String)? danmaku;

  /// Set by [Transfer.openMedia] while an online download is incomplete: the
  /// entry plays from its source meanwhile.
  final ResolvedStream? online;

  /// Set by [Transfer.openMedia] when an incomplete file has to be streamed.
  final String? streamUrl;
  final Map<String, String>? headers;
  final int? streamId;

  TransferMedia streaming(
    String url, {
    Map<String, String>? headers,
    int? id,
  }) => TransferMedia(
    file: file,
    incomplete: incomplete,
    subjectId: subjectId,
    episodeId: episodeId,
    streamUrl: url,
    headers: headers,
    streamId: id,
  );

  TransferMedia playingOnline(ResolvedStream stream) => TransferMedia(
    file: file,
    incomplete: incomplete,
    subjectId: subjectId,
    episodeId: episodeId,
    online: stream,
  );
}

/// A transfer cannot fetch this resource. It is reported, not retried with
/// another transfer the user did not choose.
class TransferUnavailable implements Exception {
  const TransferUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// PikPak's content index, for search results it can deliver at once.
abstract interface class CloudIndex {
  /// Signed in and usable now.
  bool get available;

  /// Whether the index holds a video of the torrent [infoHash], so its
  /// download starts from PikPak's CDN without a cloud download first.
  Future<bool> holds(String infoHash);
}

/// The owner of one method's download tasks.
abstract interface class Transfer {
  CacheMethod get method;

  /// Where the tasks' files are saved.
  String get directory;

  /// Fires whenever [tasks] may have changed.
  Stream<void> get changes;

  /// Restores saved tasks; finished tasks whose files were all deleted from
  /// disk are removed.
  Future<void> initialize();
  List<DownloadTask> tasks();
  bool contains(String id);
  Future<void> pause(String id);
  Future<void> resume(String id);
  Future<void> remove(String id);

  /// The task's video, or the [fileId] one; throws [StateError] when none can
  /// be played yet.
  TransferMedia media(String id, {String? fileId});
  Future<TransferMedia> openMedia(String id, {String? fileId});

  /// Stops media streams opened by [openMedia], except [keep].
  void releaseStreamsExcept(int? keep);
  Future<void> close();
}

/// A way of turning a magnet or torrent into local files: BT through
/// libtorrent, or PikPak reading content it already stores from its CDN.
abstract interface class TorrentTransfer implements Transfer {
  Future<DownloadTask> addMagnet(
    Uri magnet, {
    String? title,
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    List<String> releaseGroups,
  });
  Future<DownloadTask> addTorrent(
    Uint8List bytes,
    String name, {
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    List<String> releaseGroups,
  });

  /// Deletes [fileIds] of a finished task and keeps its other files.
  Future<void> removeFiles(String id, Set<String> fileIds);
}

/// Saves online entries: HLS segments or direct files, read again from the
/// source whenever its links expire.
abstract interface class OnlineTransfer implements Transfer {
  Future<DownloadTask> addOnline(
    StreamRef ref, {
    required String title,
    required String source,
    int? subjectId,
    int? episodeId,
    String? coverUrl,
  });
}
