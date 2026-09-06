import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melonbang/data/account.dart';
import 'package:melonbang/data/catalog.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/data/store.dart';
import 'package:melonbang/data/tracking.dart';

import 'support/memory_credentials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppStore store;
  late AccountRepository account;
  late TrackingRepository tracking;
  late ApiClient api;

  Future<void> initialize(
    Future<http.Response> Function(http.Request) handler,
  ) async {
    api = ApiClient(client: MockClient(handler));
    final credentials = MemoryCredentials();
    await credentials.write(
      'account',
      jsonEncode({
        'access_token': 'token',
        'expiresAt': DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
        'user': {'userId': '1', 'username': 'test'},
      }),
    );
    account = AccountRepository(api, credentials);
    await account.initialize();
    tracking = TrackingRepository(
      store,
      account,
      CatalogRepository(api, store),
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('melonbang-sync-');
    store = await AppStore.open('${directory.path}/test.sqlite');
  });
  tearDown(() async {
    await tracking.close();
    await account.close();
    api.close();
    await store.close();
    await directory.delete(recursive: true);
  });

  test('queued collection is created before an earlier episode edit', () async {
    var collected = false;
    final requests = <String>[];
    await initialize((request) async {
      requests.add(request.method);
      if (request.method == 'POST') collected = true;
      if (request.method == 'PUT' && !collected) return http.Response('', 400);
      return http.Response('', 204);
    });
    await store.enqueue('1', 'episode:7', {
      'kind': 'episode',
      'subjectId': 42,
      'episodeId': 7,
      'status': 'watched',
    });
    await store.enqueue('1', 'subject:42', {
      'kind': 'subject',
      'subjectId': 42,
      'status': 'watching',
    });
    await tracking.flush();
    expect(requests, ['POST', 'PUT']);
    expect(await store.pending('1'), isEmpty);
  });

  test(
    'a rejected episode does not block other subjects and can be retried',
    () async {
      var collected = false;
      final updated = <String>[];
      await initialize((request) async {
        if (request.url.path.endsWith('/episodes/7') && !collected) {
          return http.Response('', 400);
        }
        updated.add(request.url.path);
        return http.Response('', 204);
      });
      await store.enqueue('1', 'episode:7', {
        'kind': 'episode',
        'subjectId': 42,
        'episodeId': 7,
        'status': 'watched',
      });
      await store.enqueue('1', 'subject:99', {
        'kind': 'subject',
        'subjectId': 99,
        'status': 'watching',
      });
      await store.enqueue('1', 'episode:8', {
        'kind': 'episode',
        'subjectId': 99,
        'episodeId': 8,
        'status': 'watched',
      });
      await tracking.flush();
      expect(updated, [
        '/v0/users/-/collections/99',
        '/v0/users/-/collections/-/episodes/8',
      ]);
      expect(await store.pending('1'), hasLength(1));
      expect(tracking.lastSyncError, contains('请先收藏'));
      collected = true;
      await tracking.flush();
      expect(await store.pending('1'), isEmpty);
      expect(tracking.lastSyncError, isNull);
    },
  );

  test(
    'an edit made during a pending sync is drained without waiting for a timer',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final writes = <Json>[];
      await initialize((request) async {
        writes.add(object(jsonDecode(request.body)));
        if (writes.length == 1) {
          started.complete();
          await release.future;
        }
        return http.Response('', 204);
      });
      await store.put('collection:1', '42', {
        'subjectId': 42,
        'status': 'wish',
      });
      await tracking.setCollection(42, status: CollectionStatus.watching);
      await started.future;
      await tracking.setCollection(42, status: CollectionStatus.completed);
      release.complete();
      await tracking.flush();
      expect(writes, [
        {'type': 3},
        {'type': 2},
      ]);
      expect(await store.pending('1'), isEmpty);
    },
  );

  test(
    'sync diagnostics do not follow a signed-out account into guest mode',
    () async {
      await initialize((_) async => http.Response('', 503));
      await store.enqueue('1', 'subject:42', {
        'kind': 'subject',
        'subjectId': 42,
        'status': 'watching',
      });
      await tracking.flush();
      expect(tracking.lastSyncError, isNotNull);
      await account.signOut();
      final state = await tracking.syncState();
      expect(state['lastSyncError'], isNull);
      expect(state['pendingMutationCount'], 0);
    },
  );

  test('Bangumi collection cards use the SlimSubject score', () async {
    await initialize(
      (request) async => http.Response(
        jsonEncode({
          'total': 1,
          'data': [
            {
              'subject_id': 42,
              'type': 3,
              'rate': 9,
              'subject': {'id': 42, 'name': 'Title', 'score': 8.2, 'eps': 12},
            },
          ],
        }),
        200,
      ),
    );
    await tracking.refresh();
    final item = (await tracking.collection()).single;
    expect(item['score'], 8.2);
    expect(item['userScore'], 9);
  });

  test('refresh removes remote deletions while preserving pending local collections', () async {
    await initialize((request) async {
      if (request.method == 'POST') return http.Response('', 503);
      return http.Response(jsonEncode({'total': 0, 'data': []}), 200);
    });
    await store.put('collection:1', '42', {'subjectId': 42, 'status': 'wish'});
    await store.put('collection:1', '99', {
      'subjectId': 99,
      'status': 'watching',
    });
    await store.database.update('documents', {'updated': 0});
    await store.enqueue('1', 'subject:99', {
      'kind': 'subject',
      'subjectId': 99,
      'status': 'watching',
    });
    await tracking.refresh();
    expect((await tracking.collection()).single['subjectId'], 99);
    expect(await store.pending('1'), hasLength(1));
  });

  test(
    'subject loading cannot combine identities across an account switch',
    () async {
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      await initialize((request) async {
        requested.complete();
        return response.future;
      });
      final result = expectLater(tracking.subject(42), throwsStateError);
      await requested.future;
      await account.signOut();
      response.complete(
        http.Response(
          jsonEncode({
            'data': {'subjectId': 42, 'name': 'Title', 'episodes': []},
          }),
          200,
        ),
      );
      await result;
      expect(await tracking.collection(), isEmpty);
    },
  );
}
