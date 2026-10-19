import '../../domain/transfer.dart';

/// Status text.
String downloadStatus(DownloadTask task) => switch (task.status) {
  DownloadStatus.metadata when task.cloudProgress != null =>
    'PikPak 云端下载 ${(task.cloudProgress! * 100).floor()}%',
  DownloadStatus.metadata when task.cloud => '读取 PikPak 收录信息',
  DownloadStatus.metadata when task.method == CacheMethod.online => '读取视频地址',
  DownloadStatus.downloading when !task.seeds => '下载中',
  DownloadStatus.metadata => '获取种子信息',
  DownloadStatus.checking => '校验本地文件',
  DownloadStatus.queued => task.complete ? '等待做种' : '排队中',
  DownloadStatus.downloading =>
    task.swarm.peers == 0 && task.downloadSpeed == 0 ? '寻找下载节点' : '下载中',
  DownloadStatus.seeding => '做种中',
  DownloadStatus.completed when !task.seeds => '已完成',
  DownloadStatus.completed => switch (task.seedStop) {
    SeedStop.ratio => '已达分享率',
    SeedStop.time => '已达做种时长',
    _ => '已停止做种',
  },
  DownloadStatus.paused => task.complete ? '已暂停做种' : '已暂停',
  DownloadStatus.failed => '需要重试',
};

/// Where a task comes from beside its status: PikPak, or the online source;
/// null for BT.
String? downloadOrigin(DownloadTask task) => switch (task.method) {
  CacheMethod.bt => null,
  CacheMethod.pikpak => 'PikPak',
  CacheMethod.online => task.source ?? CacheMethod.online.label,
};

/// Why none of the task's videos can be played yet; null when one can.
String? playBlocked(DownloadTask task) => switch (task.status) {
  DownloadStatus.checking => '正在校验本地文件',
  DownloadStatus.failed => '下载失败，请先重试',
  _ when task.videos.isNotEmpty => null,
  _ when task.cloudProgress != null => 'PikPak 云端下载完成后可播放',
  _ when task.files.isNotEmpty => '没有可播放的视频文件',
  _ => switch (task.method) {
    CacheMethod.bt => '取得种子信息后可播放',
    CacheMethod.pikpak => '读取 PikPak 收录信息后可播放',
    CacheMethod.online => '读取视频地址后可播放',
  },
};

/// The label and tooltip of a task's pause/resume control.
String toggleLabel(TaskToggle toggle) => switch (toggle) {
  TaskToggle.pause => '暂停',
  TaskToggle.resume => '继续下载',
  TaskToggle.stopSeeding => '停止做种',
  TaskToggle.resumeSeeding => '继续做种',
};

String transferRate(int bytes) {
  if (bytes <= 0) return '0 B/s';
  if (bytes < 1024) return '$bytes B/s';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KiB/s';
  return '${(bytes / 1048576).toStringAsFixed(1)} MiB/s';
}
