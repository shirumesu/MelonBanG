import 'dart:typed_data';

/// How a release's bytes are fetched; also the stored default method.
enum CacheMethod {
  bt,
  pikpak;

  String get label => this == bt ? 'BT' : 'PikPak';
  CacheMethod get other => this == bt ? pikpak : bt;

  static CacheMethod fromStored(dynamic value) =>
      value == 'pikpak' ? pikpak : bt;
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

/// Why a finished BT task no longer seeds.
enum SeedStop { manual, ratio, time, disabled }

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

  bool get complete => progress >= 1;
  bool get cloud => method == CacheMethod.pikpak;

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
  });
  final DownloadFile file;
  final bool incomplete;
  final int? subjectId, episodeId;

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
}

/// A transfer cannot fetch this resource; another transfer may.
class TransferUnavailable implements Exception {
  const TransferUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A way of turning a magnet or torrent into local files: BT through
/// libtorrent, or PikPak reading content it already stores from its CDN.
abstract interface class Transfer {
  CacheMethod get method;

  /// Fires whenever [tasks] may have changed.
  Stream<void> get changes;
  Future<void> initialize();
  List<DownloadTask> tasks();
  bool contains(String id);
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
