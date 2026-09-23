import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/bittorrent_settings.dart';

void main() {
  test(
    'seeding stops at either bound and zero disables an individual bound',
    () {
      const defaults = BitTorrentSettings();
      expect(
        defaults.stopReason({
          'totalBytes': 100,
          'uploadedBytes': 99,
          'seedSeconds': 3599,
        }),
        isNull,
      );
      expect(
        defaults.stopReason({'totalBytes': 100, 'uploadedBytes': 100}),
        'ratio',
      );
      expect(
        defaults.stopReason({'totalBytes': 100, 'seedSeconds': 3600}),
        'time',
      );
      expect(
        const BitTorrentSettings(seedRatio: 0)
            .stopReason({'totalBytes': 100, 'uploadedBytes': 900}),
        isNull,
      );
      expect(
        const BitTorrentSettings(seedMinutes: 0)
            .stopReason({'seedSeconds': 99999}),
        isNull,
      );
      expect(
        const BitTorrentSettings(seedMode: 'off').stopReason({}),
        'disabled',
      );
      expect(
        const BitTorrentSettings(seedMode: 'unlimited').stopReason({
          'totalBytes': 1,
          'uploadedBytes': 100,
          'seedSeconds': 99999,
        }),
        isNull,
      );
    },
  );

  test(
    'unlimited queues and legacy finite settings migrate without unbounding',
    () {
      const unlimited = BitTorrentSettings(activeDownloads: 0, activeSeeds: 0);
      expect(unlimited.validate, returnsNormally);
      expect(
        BitTorrentSettings.fromJson(unlimited.toJson()).activeDownloads,
        0,
      );
      final legacy = BitTorrentSettings.fromStoredJson({
        'activeDownloads': 20,
        'activeSeeds': 10,
        'seedMinutes': 525600,
      });
      legacy.validate();
      expect(legacy.activeDownloads, 5);
      expect(legacy.activeSeeds, 3);
      expect(legacy.seedMinutes, 1440);
      expect(
        const BitTorrentSettings(seedMinutes: 1441).validate,
        throwsFormatException,
      );
    },
  );

  test(
    'settings round-trip and reject unbounded limited mode and invalid numbers',
    () {
      const config = BitTorrentSettings(
        uploadKiB: 256,
        listenPort: 51413,
        resumeOnStartup: false,
      );
      final restored = BitTorrentSettings.fromJson(config.toJson());
      expect(restored.toJson(), config.toJson());
      expect(restored.engineConfig.uploadRateLimit, 256);
      expect(restored.engineConfig.peersListenPort, 51413);
      expect(
        const BitTorrentSettings(seedRatio: 0, seedMinutes: 0).validate,
        throwsFormatException,
      );
      expect(
        const BitTorrentSettings(activeDownloads: 6).validate,
        throwsFormatException,
      );
      expect(
        const BitTorrentSettings(uploadKiB: -1).validate,
        throwsFormatException,
      );
      expect(
        const BitTorrentSettings(seedRatio: double.nan).validate,
        throwsFormatException,
      );
    },
  );
}
