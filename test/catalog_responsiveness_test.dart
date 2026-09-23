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

http.Response jsonResponse(Json body) => http.Response(jsonEncode(body), 200);

Json subjectResponse(String name) => {
  'data': {
    'subjectId': 42,
    'name': name,
    'episodes': [
      {'episodeId': 7, 'ep': 1, 'type': 'main', 'name': 'First'},
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppStore store;
  final pendingResponses = <Completer<http.Response>>[];
  final disposals = <FutureOr<void> Function()>[];

  Completer<http.Response> delayedResponse() {
    final response = Completer<http.Response>();
    pendingResponses.add(response);
    return response;
  }

  ApiClient client(Future<http.Response> Function(http.Request) handler) {
    final api = ApiClient(client: MockClient(handler));
    disposals.add(api.close);
    return api;
  }

  CatalogRepository catalogFor(ApiClient api) {
    final catalog = CatalogRepository(api, store);
    disposals.add(catalog.close);
    return catalog;
  }

  Future<AccountRepository> signedIn(ApiClient api) async {
    final credentials = MemoryCredentials();
    await credentials.write(
      'account',
      jsonEncode({
        'access_token': 'test-token',
        'expiresAt': DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
        'user': {'userId': '1', 'username': 'test'},
      }),
    );
    final account = AccountRepository(api, credentials);
    disposals.add(account.close);
    await account.initialize();
    return account;
  }

  test(
    'fresh saved lists appear before revalidation and receive changed artwork',
    () async {
      final remote = delayedResponse();
      final catalog = catalogFor(client((_) => remote.future));
      final date = catalog.scheduleDate;
      await store.put('catalog', 'today:$date', {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'value': {
          'date': date,
          'items': [
            {'subjectId': 42, 'name': 'Saved'},
          ],
        },
      });
      final cached = Completer<Json>();
      final loading = catalog.today(onCached: cached.complete);
      expect(
        objects((await cached.future)['items']).single['coverUrl'],
        isNull,
      );
      expect(remote.isCompleted, isFalse);
      remote.complete(
        jsonResponse({
          'date': date,
          'items': [
            {
              'subjectId': 42,
              'name': 'Saved',
              'coverUrl': 'https://images.test/42.jpg',
            },
          ],
        }),
      );
      expect(
        objects((await loading)['items']).single['coverUrl'],
        'https://images.test/42.jpg',
      );
      expect(catalog.coverFor(42), 'https://images.test/42.jpg');
    },
  );

  test('missing list artwork reuses persisted details without remote detail fan-out', () async {
    final catalog = catalogFor(
      client((_) async => throw StateError('Unexpected network request')),
    );
    await store.put('catalog', 'detail:42', {
      'savedAt': 0,
      'value': {
        'data': {'subjectId': 42, 'coverUrl': 'https://images.test/saved.jpg'},
      },
    });
    await Future.wait([
      catalog.resolveCover(42),
      catalog.resolveCover(42),
      catalog.resolveCover(99),
    ]);
    expect(catalog.coverFor(42), 'https://images.test/saved.jpg');
    expect(catalog.coverFor(99), isNull);
    final changes = <int>[];
    final subscription = catalog.coverChanges.stream.listen(changes.add);
    catalog.summary({
      'subjectId': 42,
      'coverUrl': 'https://images.test/updated.jpg',
    });
    catalog.summary({
      'subjectId': 42,
      'coverUrl': 'https://images.test/updated.jpg',
    });
    catalog.summary({'subjectId': 42, 'coverUrl': null});
    await Future<void>.delayed(Duration.zero);
    expect(changes, [42]);
    expect(catalog.coverFor(42), 'https://images.test/updated.jpg');
    await subscription.cancel();
  });

  test(
    'collection background reads coalesce and skip empty preferred artwork',
    () async {
      final response = delayedResponse();
      var requests = 0;
      final api = client((_) {
        requests++;
        return response.future;
      });
      final account = await signedIn(api);
      final tracking = TrackingRepository(store, account, catalogFor(api));
      disposals.add(tracking.close);
      final first = tracking.refresh();
      final second = tracking.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      response.complete(
        jsonResponse({
          'total': 1,
          'data': [
            {
              'subject_id': 42,
              'type': 3,
              'subject': {
                'name': 'Collected',
                'images': {
                  'common': '',
                  'large': 'https://images.test/large.jpg',
                },
              },
            },
          ],
        }),
      );
      await Future.wait([first, second]);
      expect(
        (await tracking.collection()).single['coverUrl'],
        'https://images.test/large.jpg',
      );
    },
  );

  test(
    'server stale snapshots do not become fresh for another local hour',
    () async {
      var requests = 0;
      final catalog = catalogFor(
        client((_) async {
          requests++;
          return jsonResponse({
            ...subjectResponse(
              requests == 1 ? 'Server stale detail' : 'Fresh detail',
            ),
            'cache': requests == 1
                ? {'stale': true}
                : {
                    'expiresAt': DateTime.now()
                        .add(const Duration(hours: 1))
                        .toIso8601String(),
                  },
          });
        }),
      );
      expect((await catalog.subject(42))['name'], 'Server stale detail');
      final available = <Json>[];
      expect(
        (await catalog.subject(42, onCached: available.add))['name'],
        'Fresh detail',
      );
      expect(available.single['name'], 'Server stale detail');
      await catalog.subject(42);
      expect(requests, 2);
    },
  );

  test(
    'server expiry is honored even while the local snapshot is recent',
    () async {
      await store.put('catalog', 'detail:42', {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'value': {
          ...subjectResponse('Expired at server'),
          'cache': {'expiresAt': '2020-01-01T00:00:00Z'},
        },
      });
      final catalog = catalogFor(
        client((_) async => jsonResponse(subjectResponse('Refreshed'))),
      );
      final available = <Json>[];
      expect(
        (await catalog.subject(42, onCached: available.add))['name'],
        'Refreshed',
      );
      expect(available.single['name'], 'Expired at server');
    },
  );

  setUp(() async {
    pendingResponses.clear();
    disposals.clear();
    directory = await Directory.systemTemp.createTemp('melonbang-response-');
    store = await AppStore.open('${directory.path}/test.sqlite');
  });

  tearDown(() async {
    for (final response in pendingResponses) {
      if (!response.isCompleted) response.complete(http.Response('', 503));
    }
    for (final dispose in disposals.reversed) {
      await dispose();
    }
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'expired detail is available before one shared network refresh',
    () async {
      await store.put('catalog', 'detail:42', {
        'savedAt': 0,
        'value': subjectResponse('Saved detail'),
      });
      final requested = Completer<void>();
      final response = delayedResponse();
      var requests = 0;
      final catalog = catalogFor(
        client((_) {
          requests++;
          if (!requested.isCompleted) requested.complete();
          return response.future;
        }),
      );
      final firstCached = Completer<Json>();
      final secondCached = Completer<Json>();
      var finished = 0;
      final first = catalog.subject(42, onCached: firstCached.complete).then((
        item,
      ) {
        finished++;
        return item;
      });
      final second = catalog.subject(42, onCached: secondCached.complete).then((
        item,
      ) {
        finished++;
        return item;
      });

      final cached = await Future.wait([
        firstCached.future,
        secondCached.future,
      ]);
      await requested.future;
      expect(cached.map((item) => item['name']), everyElement('Saved detail'));
      expect(objects(cached.first['episodes']).single['sort'], 1);
      expect(finished, 0);
      expect(requests, 1);

      response.complete(jsonResponse(subjectResponse('Updated detail')));
      final results = await Future.wait([first, second]);
      expect(
        results.map((item) => item['name']),
        everyElement('Updated detail'),
      );
      expect((await catalog.subject(42))['name'], 'Updated detail');
      expect(requests, 1);
    },
  );

  test(
    'failed explicit refresh keeps the displayed and persisted homepage',
    () async {
      await store.put('catalog', 'trending:8:0', {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'value': {
          'data': [
            {'subjectId': 42, 'name': 'Saved recommendation'},
          ],
          'hasMore': false,
        },
      });
      final requested = Completer<void>();
      final response = delayedResponse();
      var requests = 0;
      final catalog = catalogFor(
        client((_) {
          requests++;
          requested.complete();
          return response.future;
        }),
      );
      final displayed = Completer<List<Json>>();
      final result = expectLater(
        catalog.trending(refresh: true, limit: 8, onCached: displayed.complete),
        throwsA(isA<ApiException>()),
      );
      expect((await displayed.future).single['name'], 'Saved recommendation');
      await requested.future;
      response.complete(http.Response('', 503));
      await result;
      expect(
        (await catalog.trending(limit: 8)).single['name'],
        'Saved recommendation',
      );
      expect(requests, 1);
    },
  );

  test('homepage requests only its eight recommendations', () async {
    final requests = <Uri>[];
    final catalog = catalogFor(
      client((request) async {
        requests.add(request.url);
        return jsonResponse({
          'data': [
            for (var id = 1; id <= 8; id++)
              {'subjectId': id, 'name': 'Title $id'},
          ],
          'total': 232,
          'hasMore': true,
        });
      }),
    );
    expect(await catalog.trending(limit: 8), hasLength(8));
    expect(requests, hasLength(1));
    expect(requests.single.queryParameters, {'limit': '8', 'offset': '0'});
  });

  test(
    'full catalogue pagination follows returned rows when a page is capped',
    () async {
      final offsets = <String?>[];
      final catalog = catalogFor(
        client((request) async {
          final offset = int.parse(request.url.queryParameters['offset']!);
          offsets.add(request.url.queryParameters['offset']);
          return jsonResponse({
            'data': [
              for (var id = offset + 1; id <= offset + 2; id++)
                {'subjectId': id},
            ],
            'limit': 2,
            'hasMore': offset == 0,
          });
        }),
      );
      expect((await catalog.trending()).map((item) => item['subjectId']), [
        1,
        2,
        3,
        4,
      ]);
      expect(offsets, ['0', '2']);
    },
  );

  test(
    'today never displays a previous Shanghai day from a fresh cache',
    () async {
      final shanghai = DateTime.now().toUtc().add(const Duration(hours: 8));
      final date = shanghai.toIso8601String().substring(0, 10);
      final yesterday = shanghai
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      final oldSchedule = {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'value': {
          'date': yesterday,
          'items': [
            {'subjectId': 7, 'name': 'Yesterday'},
          ],
        },
      };
      await store.put('catalog', 'today', oldSchedule);
      await store.put('catalog', 'today:$yesterday', oldSchedule);
      final requested = Completer<void>();
      final response = delayedResponse();
      final catalog = catalogFor(
        client((_) {
          requested.complete();
          return response.future;
        }),
      );
      final displayed = <Json>[];
      final loading = catalog.today(onCached: displayed.add);
      await requested.future;
      expect(displayed, isEmpty);
      response.complete(
        jsonResponse({
          'date': date,
          'items': [
            {'subjectId': 42, 'name': 'Today'},
            {'subjectId': null, 'id': 999, 'name': 'Unlinked'},
          ],
        }),
      );
      final today = await loading;
      expect(today['date'], date);
      expect(objects(today['items']).single['subjectId'], 42);
    },
  );

  test(
    'cold detail and progress run together and publish local progress first',
    () async {
      final detailRequested = Completer<void>();
      final progressRequested = Completer<void>();
      final detailResponse = delayedResponse();
      final progressResponse = delayedResponse();
      final api = client((request) {
        if (request.url.host == 'api.bgm.tv') {
          expect(request.headers['Authorization'], 'Bearer test-token');
          progressRequested.complete();
          return progressResponse.future;
        }
        detailRequested.complete();
        return detailResponse.future;
      });
      final account = await signedIn(api);
      final tracking = TrackingRepository(store, account, catalogFor(api));
      disposals.add(tracking.close);
      await store.put('collection:1', '42', {
        'subjectId': 42,
        'status': 'watching',
      });
      await store.put('episodes:1', '7', {
        'subjectId': 42,
        'episodeId': 7,
        'status': 'watched',
      });
      await store.database.update('documents', {'updated': 0});
      final available = Completer<Json>();
      var finished = false;
      final loading = tracking
          .subject(42, onAvailable: available.complete)
          .then((item) {
            finished = true;
            return item;
          });

      await Future.wait([detailRequested.future, progressRequested.future]);
      expect(finished, isFalse);
      detailResponse.complete(jsonResponse(subjectResponse('First detail')));
      final local = await available.future;
      expect(local['name'], 'First detail');
      expect(object(local['collection'])['status'], 'watching');
      expect(objects(local['episodes']).single['status'], 'watched');
      expect(finished, isFalse);

      progressResponse.complete(
        jsonResponse({
          'total': 1,
          'data': [
            {
              'episode': {'id': 7},
              'type': 0,
            },
          ],
        }),
      );
      expect(
        objects((await loading)['episodes']).single['status'],
        'unwatched',
      );
    },
  );

  test(
    'reopening a detail coalesces progress and reuses its recent sync',
    () async {
      final progressRequested = Completer<void>();
      final progressResponse = delayedResponse();
      var progressRequests = 0;
      final api = client((request) async {
        if (request.url.host == 'api.bgm.tv') {
          progressRequests++;
          if (!progressRequested.isCompleted) progressRequested.complete();
          return progressResponse.future;
        }
        return jsonResponse(subjectResponse('Detail'));
      });
      final account = await signedIn(api);
      final tracking = TrackingRepository(store, account, catalogFor(api));
      disposals.add(tracking.close);
      final first = tracking.subject(42);
      await progressRequested.future;
      final reopened = tracking.subject(42);
      progressResponse.complete(
        jsonResponse({
          'total': 1,
          'data': [
            {
              'episode': {'id': 7},
              'type': 2,
            },
          ],
        }),
      );
      for (final detail in await Future.wait([first, reopened])) {
        expect(objects(detail['episodes']).single['status'], 'watched');
      }
      expect(progressRequests, 1);
      await tracking.subject(42);
      expect(progressRequests, 1);
      await tracking.refreshEpisodes(42);
      expect(
        progressRequests,
        2,
        reason: 'Explicit synchronization stays fresh',
      );
    },
  );

  test('failed episode synchronization is retried on the next visit', () async {
    var progressRequests = 0;
    final api = client((request) async {
      if (request.url.host == 'api.bgm.tv') {
        progressRequests++;
        if (progressRequests == 1) return http.Response('', 503);
        return jsonResponse({'total': 0, 'data': []});
      }
      return jsonResponse(subjectResponse('Detail'));
    });
    final account = await signedIn(api);
    final tracking = TrackingRepository(store, account, catalogFor(api));
    disposals.add(tracking.close);
    expect((await tracking.subject(42))['name'], 'Detail');
    expect(tracking.lastSyncError, contains('503'));
    await tracking.subject(42);
    expect(progressRequests, 2);
  });

  test('expired detail publishes local progress before either remote request finishes', () async {
    await store.put('catalog', 'detail:42', {
      'savedAt': 0,
      'value': subjectResponse('Saved detail'),
    });
    await store.put('episodes:1', '7', {
      'subjectId': 42,
      'episodeId': 7,
      'status': 'watched',
    });
    final detailResponse = delayedResponse();
    final progressResponse = delayedResponse();
    final api = client(
      (request) => request.url.host == 'api.bgm.tv'
          ? progressResponse.future
          : detailResponse.future,
    );
    final account = await signedIn(api);
    final tracking = TrackingRepository(store, account, catalogFor(api));
    disposals.add(tracking.close);
    final firstAvailable = Completer<Json>();
    final publications = <Json>[];
    final loading = tracking.subject(
      42,
      onAvailable: (item) {
        publications.add(item);
        if (!firstAvailable.isCompleted) firstAvailable.complete(item);
      },
    );

    final saved = await firstAvailable.future;
    expect(saved['name'], 'Saved detail');
    expect(objects(saved['episodes']).single['status'], 'watched');
    expect(detailResponse.isCompleted, isFalse);
    expect(progressResponse.isCompleted, isFalse);

    detailResponse.complete(jsonResponse(subjectResponse('Updated detail')));
    progressResponse.complete(jsonResponse({'total': 0, 'data': []}));
    expect((await loading)['name'], 'Updated detail');
    expect(publications.last['name'], 'Updated detail');
  });

  test('switching accounts blocks late detail callbacks and remote progress writes', () async {
    final detailRequested = Completer<void>();
    final progressRequested = Completer<void>();
    final detailResponse = delayedResponse();
    final progressResponse = delayedResponse();
    final api = client((request) {
      if (request.url.host == 'api.bgm.tv') {
        progressRequested.complete();
        return progressResponse.future;
      }
      detailRequested.complete();
      return detailResponse.future;
    });
    final account = await signedIn(api);
    final tracking = TrackingRepository(store, account, catalogFor(api));
    disposals.add(tracking.close);
    final publications = <Json>[];
    final loading = expectLater(
      tracking.subject(42, onAvailable: publications.add),
      throwsStateError,
    );
    await Future.wait([detailRequested.future, progressRequested.future]);
    await account.signOut();
    detailResponse.complete(
      jsonResponse(subjectResponse('Old account detail')),
    );
    progressResponse.complete(
      jsonResponse({
        'total': 1,
        'data': [
          {
            'episode': {'id': 7},
            'type': 2,
          },
        ],
      }),
    );
    await loading;
    expect(publications, isEmpty);
    expect(await store.list('episodes:1'), isEmpty);
    expect(await store.list('episodes:local'), isEmpty);
  });
}
