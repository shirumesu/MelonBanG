import '../core/json.dart';
import 'transfer.dart';

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

  /// Saved settings; a value missing or of the wrong type takes the default.
  factory BitTorrentSettings.fromJson(Json data) {
    const fallback = BitTorrentSettings();
    T read<T>(String key, T value) => switch (data[key]) {
      final T saved => saved,
      final num saved when T == double => saved.toDouble() as T,
      final num saved when T == int => saved.toInt() as T,
      _ => value,
    };
    return BitTorrentSettings(
      seedMode: read('seedMode', fallback.seedMode),
      seedRatio: read('seedRatio', fallback.seedRatio),
      seedMinutes: read('seedMinutes', fallback.seedMinutes),
      downloadKiB: read('downloadKiB', fallback.downloadKiB),
      uploadKiB: read('uploadKiB', fallback.uploadKiB),
      activeDownloads: read('activeDownloads', fallback.activeDownloads),
      activeSeeds: read('activeSeeds', fallback.activeSeeds),
      connectionsPerTask: read(
        'connectionsPerTask',
        fallback.connectionsPerTask,
      ),
      listenPort: read('listenPort', fallback.listenPort),
      resumeOnStartup: read('resumeOnStartup', fallback.resumeOnStartup),
      dht: read('dht', fallback.dht),
      upnp: read('upnp', fallback.upnp),
      ipv6: read('ipv6', fallback.ipv6),
      forceEncryption: read('forceEncryption', fallback.forceEncryption),
    );
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

  SeedStop? stopReason(int totalBytes, int uploadedBytes, double seedSeconds) {
    if (seedMode == 'off') return SeedStop.disabled;
    if (seedMode == 'unlimited') return null;
    if (seedRatio > 0 &&
        totalBytes > 0 &&
        uploadedBytes / totalBytes >= seedRatio) {
      return SeedStop.ratio;
    }
    if (seedMinutes > 0 && seedSeconds >= seedMinutes * 60) {
      return SeedStop.time;
    }
    return null;
  }
}
