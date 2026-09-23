import 'package:libtorrent_flutter/libtorrent_flutter.dart' as lt;

import 'json.dart';

/// Persistent download policy; independent of the streaming engine's cache knobs.
class BitTorrentSettings {
  const BitTorrentSettings({
    this.seedMode = 'limited',
    this.seedRatio = 1,
    this.seedMinutes = 60,
    this.downloadKiB = 0,
    this.uploadKiB = 1024,
    this.activeDownloads = 3,
    this.activeSeeds = 2,
    this.connectionsPerTask = 50,
    this.listenPort = 0,
    this.resumeOnStartup = true,
    this.dht = true,
    this.upnp = true,
    this.ipv6 = true,
    this.forceEncryption = false,
  });

  final String seedMode;
  final double seedRatio;
  final int seedMinutes, downloadKiB, uploadKiB, activeDownloads, activeSeeds;
  final int connectionsPerTask, listenPort;
  final bool resumeOnStartup, dht, upnp, ipv6, forceEncryption;

  factory BitTorrentSettings.fromJson(Json data) => BitTorrentSettings(
    seedMode: data['seedMode'] as String? ?? 'limited',
    seedRatio: (data['seedRatio'] as num?)?.toDouble() ?? 1,
    seedMinutes: (data['seedMinutes'] as num?)?.toInt() ?? 60,
    downloadKiB: (data['downloadKiB'] as num?)?.toInt() ?? 0,
    uploadKiB: (data['uploadKiB'] as num?)?.toInt() ?? 1024,
    activeDownloads: (data['activeDownloads'] as num?)?.toInt() ?? 3,
    activeSeeds: (data['activeSeeds'] as num?)?.toInt() ?? 2,
    connectionsPerTask: (data['connectionsPerTask'] as num?)?.toInt() ?? 50,
    listenPort: (data['listenPort'] as num?)?.toInt() ?? 0,
    resumeOnStartup: data['resumeOnStartup'] as bool? ?? true,
    dht: data['dht'] as bool? ?? true,
    upnp: data['upnp'] as bool? ?? true,
    ipv6: data['ipv6'] as bool? ?? true,
    forceEncryption: data['forceEncryption'] as bool? ?? false,
  );

  factory BitTorrentSettings.fromStoredJson(Json data) {
    final values = {...data};
    for (final (key, maximum, previousMaximum) in [
      ('activeDownloads', 5, 20),
      ('activeSeeds', 3, 20),
      ('seedMinutes', 1440, 525600),
    ]) {
      final value = values[key];
      if (value is num && value > maximum && value <= previousMaximum) {
        values[key] = maximum;
      }
    }
    return BitTorrentSettings.fromJson(values);
  }

  Json toJson() => {
    'seedMode': seedMode,
    'seedRatio': seedRatio,
    'seedMinutes': seedMinutes,
    'downloadKiB': downloadKiB,
    'uploadKiB': uploadKiB,
    'activeDownloads': activeDownloads,
    'activeSeeds': activeSeeds,
    'connectionsPerTask': connectionsPerTask,
    'listenPort': listenPort,
    'resumeOnStartup': resumeOnStartup,
    'dht': dht,
    'upnp': upnp,
    'ipv6': ipv6,
    'forceEncryption': forceEncryption,
  };

  void validate() {
    if (!['off', 'limited', 'unlimited'].contains(seedMode) ||
        !seedRatio.isFinite ||
        seedRatio < 0 ||
        seedRatio > 1000 ||
        seedMinutes < 0 ||
        seedMinutes > 1440 ||
        (seedMode == 'limited' && seedRatio == 0 && seedMinutes == 0)) {
      throw const FormatException('限量做种需至少设置一个停止条件；分享率 0–1000，时长 0–1440 分钟');
    }
    if (downloadKiB < 0 ||
        downloadKiB > 1048576 ||
        uploadKiB < 0 ||
        uploadKiB > 1048576 ||
        activeDownloads < 0 ||
        activeDownloads > 5 ||
        activeSeeds < 0 ||
        activeSeeds > 3 ||
        connectionsPerTask < 5 ||
        connectionsPerTask > 500 ||
        listenPort < 0 ||
        listenPort > 65535) {
      throw const FormatException('请检查限速、任务数量、连接数及端口范围');
    }
  }

  String? stopReason(Json task) {
    if (seedMode == 'off') return 'disabled';
    if (seedMode == 'unlimited') return null;
    final size = number(task['totalBytes']);
    if (seedRatio > 0 &&
        size > 0 &&
        number(task['uploadedBytes']) / size >= seedRatio) {
      return 'ratio';
    }
    if (seedMinutes > 0 && number(task['seedSeconds']) >= seedMinutes * 60) {
      return 'time';
    }
    return null;
  }

  lt.BtConfig get engineConfig => lt.BtConfig(
    downloadRateLimit: downloadKiB,
    uploadRateLimit: uploadKiB,
    connectionsLimit: connectionsPerTask,
    peersListenPort: listenPort,
    disableDht: !dht,
    disableUpnp: !upnp,
    enableIpv6: ipv6,
    forceEncrypt: forceEncryption,
  );
}

String downloadStatus(Json task) => switch (task['status']) {
  'metadata' => '获取种子信息',
  'checking' => '校验本地文件',
  'queued' => number(task['progress']) >= 1 ? '等待做种' : '排队中',
  'downloading' || 'ready' =>
    task['peerCount'] == 0 && number(task['downloadSpeedBytesPerSecond']) == 0
        ? '寻找下载节点'
        : '下载中',
  'seeding' => '做种中',
  'completed' => switch (task['seedStopReason']) {
    'manual' => '已完成 · 已手动停止做种',
    'ratio' => '已完成 · 达到分享率',
    'time' => '已完成 · 达到做种时限',
    _ => '已完成 · 已停止做种',
  },
  'paused' => number(task['progress']) >= 1 ? '已暂停做种' : '已暂停',
  'failed' => '需要重试',
  _ => '等待下载',
};
