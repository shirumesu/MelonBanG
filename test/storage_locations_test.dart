import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/storage_locations.dart';
import 'package:melonbang/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late StorageLocations locations;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('melonbang-storage-');
    locations = StorageLocations(
      File('${root.path}/support/storage.json'),
      '${root.path}/support/native',
    );
    await Directory(locations.media).create(recursive: true);
  });
  tearDown(() => root.delete(recursive: true));

  test('media migration rewrites downloads and episode bindings, preserves originals and credentials', () async {
    final source = '${locations.media}/task/video.mkv';
    await File(source).parent.create(recursive: true);
    await File(source).writeAsBytes(List.generate(8192, (i) => i % 256));
    final store = await AppStore.open('${locations.data}/melonbang.sqlite');
    await store.put('downloads', 'task', {
      'id': 'task',
      'savePath': '${locations.media}/task',
      'files': [
        {'id': '0', 'path': source},
      ],
      'input': 'magnet:?xt=urn:btih:test',
    });
    await store.put('episode_files', '1:2', {
      'path': source,
      'downloadId': 'task',
      'fileId': '0',
    });
    await store.put('playback_progress', '1:2', {'positionSeconds': 42});
    await store.put('danmaku_matches', '$source:dandanplay', {
      'locator': '702',
    });
    await store.close();
    final identity = locations.credentialIdentity;
    final next = '${root.path}/media';
    await locations.schedule(mediaPath: next);
    final restarted = StorageLocations(
      locations.bootstrap,
      locations.defaultData,
    );
    await restarted.load();
    await restarted.migrate();
    expect(restarted.media, next);
    expect(restarted.credentialIdentity, identity);
    expect(
      await File('$next/task/video.mkv').readAsBytes(),
      await File(source).readAsBytes(),
    );
    final reopened = await AppStore.open('${restarted.data}/melonbang.sqlite');
    expect(
      (await reopened.get('episode_files', '1:2'))!['path'],
      '$next/task/video.mkv',
    );
    expect(
      (await reopened.get('downloads', 'task'))!['savePath'],
      '$next/task',
    );
    expect(
      (await reopened.get('playback_progress', '1:2'))!['positionSeconds'],
      42,
    );
    expect(
      (await reopened.get(
        'danmaku_matches',
        '$next/task/video.mkv:dandanplay',
      ))!['locator'],
      '702',
    );
    expect(await reopened.get('danmaku_matches', '$source:dandanplay'), isNull);
    await reopened.close();
    expect(restarted.pending, isNull);
  });

  test(
    'application migration keeps nested media at its original location',
    () async {
      await File('${locations.data}/settings.json').writeAsString('settings');
      await File('${locations.media}/video.mkv').writeAsString('video');
      final oldMedia = locations.media;
      await locations.schedule(dataPath: '${root.path}/data');
      await locations.migrate();
      expect(
        await File('${locations.data}/settings.json').readAsString(),
        'settings',
      );
      expect(locations.media, oldMedia);
      expect(await Directory('${locations.data}/downloads').exists(), false);
    },
  );

  test('both destinations can be scheduled and unavailable source blocks migration', () async {
    await locations.schedule(dataPath: '${root.path}/new-data');
    await locations.schedule(mediaPath: '${root.path}/new-media');
    expect(locations.pending!['data'], '${root.path}/new-data');
    expect(locations.pending!['media'], '${root.path}/new-media');
    await Directory(locations.media).delete();
    await expectLater(locations.migrate(), throwsA(isA<FileSystemException>()));
    expect(locations.data, locations.defaultData);
    expect(locations.pending, isNotNull);
    await Directory(locations.media).create();
    await locations.migrate();
    expect(locations.data, '${root.path}/new-data');
    expect(locations.media, '${root.path}/new-media');
    expect(
      locations.previousMedia,
      contains('${locations.defaultData}/downloads'),
    );
  });

  test(
    'rejects overlapping and occupied destinations without overwriting files',
    () async {
      await expectLater(
        locations.schedule(dataPath: '${locations.data}/nested'),
        throwsStateError,
      );
      final occupied = Directory('${root.path}/occupied');
      await occupied.create();
      await File('${occupied.path}/keep').writeAsString('keep');
      await expectLater(
        locations.schedule(mediaPath: occupied.path),
        throwsStateError,
      );
      expect(await File('${occupied.path}/keep').readAsString(), 'keep');
    },
  );

  test(
    'failed migration retains current locations and retries from its journal',
    () async {
      await File('${locations.media}/video.mkv').writeAsString('video');
      final destination = '${root.path}/next';
      await locations.schedule(mediaPath: destination);
      await File('$destination/conflict').writeAsString('external');
      final oldMedia = locations.media;
      await expectLater(locations.migrate(), throwsStateError);
      expect(locations.media, oldMedia);
      expect(locations.pending, isNotNull);
      await File('$destination/conflict').delete();
      await locations.load();
      await locations.migrate();
      expect(await File('$destination/video.mkv').readAsString(), 'video');
    },
  );
}
