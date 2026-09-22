import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:melonbang/data/catalog.dart';
import 'package:melonbang/data/danmaku_repository.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/data/playback_library.dart';
import 'package:melonbang/data/store.dart';

import 'support/service_configuration.dart';

class _Downloads extends DownloadRepository {
  _Downloads(super.store, super.directory);

  final tasks = <String, Json>{};
  final blocked = <String, String>{};
  final mediaRequests = <String>[];

  @override
  bool contains(String id) => tasks.containsKey(id);

  @override
  Json snapshot() => {'tasks': tasks.values.toList()};

  @override
  Json media(String id, {String? fileId}) {
    mediaRequests.add(id);
    final task = tasks[id];
    if (task == null) throw StateError('下载任务不存在');
    if (blocked[id] case final error?) throw StateError(error);
    if (fileId != null && fileId != task['id']) {
      throw StateError('视频文件不存在');
    }
    return task;
  }

  @override
  Json episodeMedia(int subjectId, int episodeId) {
    final entry = tasks.entries
        .where(
          (entry) =>
              entry.value['subjectId'] == subjectId &&
              entry.value['episodeId'] == episodeId,
        )
        .firstOrNull;
    if (entry == null) throw StateError('该章节尚无完成的下载');
    return media(entry.key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppStore store;
  late ApiClient api;
  late _Downloads downloads;
  late PlaybackLibrary library;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'melonbang-availability-',
    );
    store = await AppStore.open('${directory.path}/store.sqlite');
    api = ApiClient(
      client: MockClient(
        (_) async => throw StateError('Availability must use local data'),
      ),
    );
    downloads = _Downloads(store, '${directory.path}/downloads');
    library = PlaybackLibrary(
      store,
      downloads,
      DanmakuRepository(api, configuration: testServiceConfiguration),
      CatalogRepository(api, store),
    );
  });

  tearDown(() async {
    await library.close();
    await downloads.close();
    api.close();
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<String> video(String name) async =>
      (await File('${directory.path}/$name.mkv').writeAsBytes([0])).path;

  Future<void> localBinding(int subjectId, int episodeId) async {
    await store.put('episode_files', '$subjectId:$episodeId', {
      'path': await video('$subjectId-$episodeId'),
    });
  }

  Future<void> progress(
    int subjectId,
    int episodeId, {
    double position = 20,
    double duration = 100,
    bool completed = false,
    int updated = 1,
  }) async {
    final key = '$subjectId:$episodeId';
    // Existing progress rows store identity only in the document key.
    await store.put('playback_progress', key, {
      'positionSeconds': position,
      'durationSeconds': duration,
      'completed': completed,
    });
    await store.database.update(
      'documents',
      {'updated': updated},
      where: 'scope=? AND id=?',
      whereArgs: ['playback_progress', key],
    );
  }

  Future<void> downloadedBinding(
    String taskId,
    int subjectId,
    int episodeId,
  ) async {
    final path = await video(taskId);
    downloads.tasks[taskId] = {
      'id': 'file-0',
      'downloadId': taskId,
      'path': path,
      'subjectId': subjectId,
      'episodeId': episodeId,
    };
    await store.put('episode_files', '$subjectId:$episodeId', {
      'downloadId': taskId,
      'fileId': 'file-0',
      'path': path,
    });
  }

  test('subject resume can be found outside the home limit', () async {
    await localBinding(1, 10);
    await localBinding(2, 20);
    await progress(1, 10, updated: 1);
    await progress(2, 20, updated: 2);
    expect((await library.recent(limit: 1)).single['subjectId'], 2);
    expect(
      (await library.recent(limit: 1, forSubject: 1)).single['episodeId'],
      10,
    );
  });

  test('recent uses legacy row identities, newest available chapter per subject, and real chapter sort', () async {
    await localBinding(42, 700);
    await localBinding(42, 701);
    await localBinding(43, 880);
    await progress(42, 700, updated: 1);
    await progress(42, 701, updated: 3);
    await progress(43, 880, updated: 2);
    await store.put('catalog', 'detail:42', {
      'value': {
        'data': {
          'subjectId': 42,
          'name': 'A real cached title',
          'episodes': [
            {'episodeId': 700, 'ep': 5},
            {'episodeId': 701, 'ep': 6, 'sort': 7},
          ],
        },
      },
    });
    await store.put('catalog', 'detail:43', {
      'value': {
        'data': {
          'subjectId': 43,
          'name': 'Another title',
          'episodes': [
            {'episodeId': 880, 'sort': 2},
          ],
        },
      },
    });
    final recent = await library.recent();
    expect(recent.map((item) => item['subjectId']), [42, 43]);
    expect(recent.first['episodeId'], 701);
    expect(recent.first['episodeSort'], 6);
    expect(recent.last['episodeSort'], 2);
    expect(recent.first['name'], 'A real cached title');
    expect(recent.first['positionSeconds'], 20);
    expect(await library.recent(limit: 1), hasLength(1));
  });

  test(
    'recent rejects completed, missing, empty and exhausted playback positions',
    () async {
      for (var id = 1; id <= 7; id++) {
        await localBinding(id, id * 100);
      }
      await progress(1, 100, updated: 1);
      await progress(2, 200, completed: true, updated: 2);
      await progress(3, 300, position: 0, updated: 3);
      await progress(4, 400, position: 100, updated: 4);
      await progress(5, 500, duration: 0, updated: 5);
      await progress(6, 600, position: -1, updated: 6);
      await progress(7, 700, updated: 7);
      await File('${directory.path}/7-700.mkv').delete();
      await store.put('playback_progress', 'unbound-old-row', {
        'positionSeconds': 20,
        'durationSeconds': 100,
      });
      final recent = await library.recent();
      expect(recent, hasLength(1));
      expect(recent.single['subjectId'], 1);
      expect(recent.single['episodeSort'], isNull);
    },
  );

  test('an unavailable newer chapter does not hide an older playable chapter of the same series', () async {
    await localBinding(42, 701);
    await progress(42, 701, updated: 1);
    await progress(42, 702, updated: 2);
    final recent = await library.recent();
    expect(recent, hasLength(1));
    expect(recent.single['episodeId'], 701);
  });

  test('local and downloaded playback availability respects validation and removed downloads', () async {
    await localBinding(42, 1);
    await localBinding(99, 9);
    await downloadedBinding('ready', 42, 2);
    await downloadedBinding('incomplete', 42, 3);
    await downloadedBinding('checking', 42, 4);
    await downloadedBinding('removed', 42, 5);
    await downloadedBinding('missing-file', 42, 6);
    downloads.blocked['incomplete'] = '请等待下载完成后播放';
    downloads.blocked['checking'] = '文件校验中';
    downloads.tasks.remove('removed');
    await File('${directory.path}/missing-file.mkv').delete();
    for (var id = 1; id <= 6; id++) {
      await progress(42, id, updated: id);
    }
    expect(await library.playableEpisodes(42), {1, 2});
    expect(
      downloads.mediaRequests,
      containsAll(['ready', 'incomplete', 'checking', 'missing-file']),
    );
    expect(await File('${directory.path}/incomplete.mkv').exists(), isTrue);
    expect(await File('${directory.path}/checking.mkv').exists(), isTrue);
    expect(await File('${directory.path}/removed.mkv').exists(), isTrue);
    final recent = await library.recent();
    expect(recent.single['episodeId'], 2);
    await expectLater(library.episode(42, 3), throwsStateError);
    await expectLater(library.episode(42, 4), throwsStateError);
    await expectLater(library.episode(42, 5), throwsStateError);
  });

  test('verified replacement downloads can restore availability without trusting a stale binding', () async {
    await downloadedBinding('removed', 42, 7);
    downloads.tasks.remove('removed');
    await progress(42, 7);
    expect(await library.playableEpisodes(42), isEmpty);
    downloads.tasks['replacement'] = {
      'id': 'replacement-file',
      'downloadId': 'replacement',
      'path': await video('replacement'),
      'subjectId': 42,
      'episodeId': 7,
    };
    expect(await library.playableEpisodes(42), {7});
    expect((await library.recent()).single['episodeId'], 7);
    expect(downloads.mediaRequests.last, 'replacement');
  });

  test('real local save lifecycle enters and leaves recent playback', () async {
    final session = await library.local(
      await video('local'),
      subjectId: 42,
      episodeId: 901,
    );
    await library.save(session, 21, 100, false);
    expect((await library.recent()).single['positionSeconds'], 21);
    expect(await library.playableEpisodes(42), {901});
    await library.save(session, 100, 100, true);
    expect(await library.recent(), isEmpty);
    expect(await library.playableEpisodes(42), {901});
  });
}
