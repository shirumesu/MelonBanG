import '../../domain/transfer.dart';
import '../../features/appearance/appearance.dart';

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

/// What a running task is doing: [status], by default its status text, then
/// its speed and, for BT, its connected peers while it downloads.
String transferLine(DownloadTask task, ByteUnits units, {String? status}) => [
  status ?? downloadStatus(task),
  if (task.status == DownloadStatus.downloading) ...[
    units.rate(task.downloadSpeed),
    if (task.method == CacheMethod.bt) '${task.swarm.peers} 个节点',
  ],
].join('  ');

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

/// The BT counters behind a task's status, for its tooltip: how the swarm
/// is found while it downloads, and what it gave back; null for PikPak and
/// online tasks.
String? transferDetails(DownloadTask task, ByteUnits units) {
  if (!task.seeds) return null;
  final swarm = task.swarm;
  final active =
      task.status == DownloadStatus.downloading ||
      task.status == DownloadStatus.seeding;
  return [
    if (!task.complete && swarm.trackers != null) ...[
      '发现 ${swarm.knownPeers ?? 0} 个节点',
      'Tracker ${swarm.workingTrackers ?? 0}/${swarm.trackers} 可用',
      (swarm.dhtNodes ?? 0) < 0 ? 'DHT 已关闭' : 'DHT ${swarm.dhtNodes ?? 0} 个节点',
    ],
    if (active) '${swarm.peers} 个连接',
    if (active) '↑ ${units.rate(task.uploadSpeed)}',
    '已上传 ${units.format(task.uploadedBytes)}',
    '分享率 ${task.totalBytes > 0 ? (task.uploadedBytes / task.totalBytes).toStringAsFixed(2) : '0.00'}',
    if (task.complete) '做种 ${seedTime(task.seedSeconds)}',
  ].join('\n');
}

/// Said under a BT download that can find no peer at all: no tracker
/// answers, DHT has no nodes and no peer is known.
String? stalledHint(DownloadTask task) {
  final swarm = task.swarm;
  final stalled =
      task.seeds &&
      !task.complete &&
      swarm.trackers != null &&
      (task.status == DownloadStatus.metadata ||
          task.status == DownloadStatus.downloading) &&
      swarm.peers == 0 &&
      (swarm.knownPeers ?? 0) == 0 &&
      (swarm.failedTrackers ?? 0) > 0 &&
      (swarm.workingTrackers ?? 0) == 0 &&
      (swarm.dhtNodes ?? 0) <= 0;
  return stalled ? '没有找到下载节点，请检查网络是否允许 BT，或换一个资源' : null;
}

/// `45 分钟`, `3 小时 20 分钟`.
String seedTime(double seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final rest = minutes % 60;
  return '${minutes ~/ 60} 小时${rest == 0 ? '' : ' $rest 分钟'}';
}
