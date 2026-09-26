import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/cache_method.dart';
import 'package:melonbang/data/catalog.dart';
import 'package:melonbang/data/danmaku_repository.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/data/pikpak.dart';
import 'package:melonbang/data/pikpak_downloads.dart';
import 'package:melonbang/data/playback_library.dart';
import 'package:melonbang/data/store.dart';

import 'support/memory_credentials.dart';

class CloudDownloads extends PikPakDownloadRepository {
  CloudDownloads(super.store, super.directory, super.client);
  final queued = <Json>[];
  String? action;

  @override
  Future<void> initialize() async {}

  @override
  Future<Json> addMagnet(
    String input, {
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    String? title,
  }) async {
    final task = <String, dynamic>{
      'id': 'cloud-${queued.length}',
      'input': input,
      'provider': 'pikpak',
      'subjectId': subjectId,
      'episodeId': episodeId,
      'coverUrl': coverUrl,
      'title': title,
      'status': 'downloading',
      'progress': 0.5,
    };
    queued.add(task);
    changes.add(snapshot());
    return task;
  }

  @override
  Json snapshot() => {'tasks': queued, 'files': <Json>[]};

  @override
  bool contains(String id) => queued.any((t) => t['id'] == id);

  @override
  Json media(String id, {String? fileId}) => {
    'id': fileId ?? 'video',
    'downloadId': id,
    'incomplete': true,
    'path': '$directory/video.mkv',
    'subjectId': 42,
    'episodeId': 7,
  };

  @override
  Future<Json> openMedia(String id, {String? fileId}) async => {
    ...media(id, fileId: fileId),
    'streamUrl': 'https://example.org/video.mkv',
    'sourceHeaders': {'Accept': 'application/octet-stream'},
  };

  @override
  Future<void> pause(String id) async => action = 'pause:$id';
  @override
  Future<void> resume(String id) async => action = 'resume:$id';
  @override
  Future<void> remove(String id) async {
    queued.removeWhere((t) => t['id'] == id);
    action = 'remove:$id';
  }

  @override
  Future<void> close() async => changes.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persisted preference routes imports, playback and actions through cloud cache', () async {
    final root = await Directory.systemTemp.createTemp('melonbang-routing-');
    final store = await AppStore.open('${root.path}/store.sqlite');
    final client = PikPakClient(MemoryCredentials());
    final cloud = CloudDownloads(store, root.path, client);
    var downloads = DownloadRepository(store, root.path, pikpak: cloud);
    try {
      await downloads.initialize();
      expect(downloads.defaultMethod, CacheMethod.bt);
      await downloads.saveCacheMethod(CacheMethod.pikpak);
      await downloads.close();
      final restoredCloud = CloudDownloads(store, root.path, client);
      downloads = DownloadRepository(store, root.path, pikpak: restoredCloud);
      await downloads.initialize();
      expect(downloads.defaultMethod, CacheMethod.pikpak);
      final task = await downloads.addMagnet(
        'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
        subjectId: 42,
        episodeId: 7,
        coverUrl: 'https://example.org/cover.jpg',
      );
      final id = '${task['id']}';
      expect(restoredCloud.queued.single['subjectId'], 42);
      expect(
        objects(downloads.snapshot()['tasks']).single['provider'],
        'pikpak',
      );
      expect(downloads.contains(id), isTrue);
      expect(downloads.episodeMedia(42, 7)['downloadId'], id);
      final media = await downloads.openMedia(id, fileId: 'selected');
      expect(media['id'], 'selected');
      expect(media['sourceHeaders'], {'Accept': 'application/octet-stream'});
      final api = ApiClient();
      final library = PlaybackLibrary(
        store,
        downloads,
        DanmakuRepository(api),
        CatalogRepository(api, store),
      );
      try {
        final session = await library.fromDownload(id, fileId: 'selected');
        expect(session['resumeKey'], 'download:$id:selected');
        expect(session['remoteSource'], isTrue);
        expect(object(session['source'])['headers'], {
          'Accept': 'application/octet-stream',
        });
        expect(
          (await store.get('episode_files', '42:7'))!['fileId'],
          'selected',
        );
      } finally {
        await library.close();
        api.close();
      }
      await downloads.pause(id);
      expect(restoredCloud.action, 'pause:$id');
      await downloads.resume(id);
      expect(restoredCloud.action, 'resume:$id');
      await downloads.remove(id);
      expect(downloads.contains(id), isFalse);
      await downloads.saveCacheMethod(CacheMethod.bt);
      await downloads.addTorrent(
        Uint8List.fromList('d4:infod4:name5:videoee'.codeUnits),
        'video.torrent',
        method: CacheMethod.pikpak,
      );
      expect(restoredCloud.queued.single['input'], startsWith('magnet:?'));
      expect(downloads.defaultMethod, CacheMethod.bt);
    } finally {
      await downloads.close();
      client.close();
      await store.close();
      await root.delete(recursive: true);
    }
  });
}
