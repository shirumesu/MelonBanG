import '../../domain/transfer.dart';

/// Status text.
String downloadStatus(DownloadTask task) => switch (task.status) {
  DownloadStatus.metadata when task.cloudProgress != null =>
    'PikPak 云端下载 ${(task.cloudProgress! * 100).floor()}%',
  DownloadStatus.metadata when task.cloud => '读取 PikPak 收录信息',
  DownloadStatus.downloading when task.cloud => '下载中',
  DownloadStatus.metadata => '获取种子信息',
  DownloadStatus.checking => '校验本地文件',
  DownloadStatus.queued => task.complete ? '等待做种' : '排队中',
  DownloadStatus.downloading =>
    task.swarm.peers == 0 && task.downloadSpeed == 0 ? '寻找下载节点' : '下载中',
  DownloadStatus.seeding => '做种中',
  DownloadStatus.completed => switch (task.seedStop) {
    SeedStop.ratio => '已达分享率',
    SeedStop.time => '已达做种时长',
    _ => '已停止做种',
  },
  DownloadStatus.paused => task.complete ? '已暂停做种' : '已暂停',
  DownloadStatus.failed => '需要重试',
};

String transferRate(int bytes) {
  if (bytes <= 0) return '0 B/s';
  if (bytes < 1024) return '$bytes B/s';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KiB/s';
  return '${(bytes / 1048576).toStringAsFixed(1)} MiB/s';
}
