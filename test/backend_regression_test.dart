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
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('melonbang-backend-');
    store = await AppStore.open('${directory.path}/test.sqlite');
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'catalog shutdown prevents a late response from writing a closed cache',
    () async {
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      final api = ApiClient(
        client: MockClient((_) {
          requested.complete();
          return response.future;
        }),
      );
      final catalog = CatalogRepository(api, store);
      final fetching = expectLater(catalog.subject(42), throwsStateError);
      await requested.future;
      final closing = catalog.close();
      response.complete(
        http.Response(
          jsonEncode({
            'data': {'subjectId': 42},
          }),
          200,
        ),
      );
      await closing;
      await fetching;
      expect(await store.get('catalog', 'detail:42'), isNull);
      api.close();
    },
  );

  test(
    'concurrent status and score edits preserve both local fields',
    () async {
      final api = ApiClient();
      final account = AccountRepository(api, MemoryCredentials());
      final tracking = TrackingRepository(
        store,
        account,
        CatalogRepository(api, store),
      );
      addTearDown(() async {
        await tracking.close();
        await account.close();
        api.close();
      });
      await store.put('collection:local', '42', {
        'subjectId': 42,
        'status': 'wish',
      });
      await Future.wait([
        tracking.setCollection(42, status: CollectionStatus.watching),
        tracking.setCollection(42, score: 9),
      ]);
      final item = (await tracking.collection()).single;
      expect(item['status'], 'watching');
      expect(item['userScore'], 9);
    },
  );

  test(
    'first concurrent collection edits do not reset the remote status to wish',
    () async {
      final writes = <Json>[];
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            writes.add(object(jsonDecode(request.body)));
            return http.Response('', 204);
          }
          return http.Response(
            jsonEncode({
              'data': {'subjectId': 42, 'name': 'Title'},
            }),
            200,
          );
        }),
      );
      final credentials = MemoryCredentials();
      credentials.values['account'] = jsonEncode({
        'access_token': 'token',
        'expiresAt': DateTime.now().millisecondsSinceEpoch + 3600000,
        'user': {'userId': '1'},
      });
      final account = AccountRepository(api, credentials);
      await account.initialize();
      final tracking = TrackingRepository(
        store,
        account,
        CatalogRepository(api, store),
      );
      addTearDown(() async {
        await tracking.close();
        await account.close();
        api.close();
      });
      await Future.wait([
        tracking.setCollection(42, status: CollectionStatus.watching),
        tracking.setCollection(42, score: 9),
      ]);
      await tracking.flush();
      expect(writes, [
        {'type': 3},
        {'rate': 9},
      ]);
      expect((await tracking.collection()).single['status'], 'watching');
    },
  );

  test(
    'an account switch cancels collection edits still loading details',
    () async {
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      final api = ApiClient(
        client: MockClient((_) {
          requested.complete();
          return response.future;
        }),
      );
      final credentials = MemoryCredentials();
      credentials.values['account'] = jsonEncode({
        'access_token': 'old',
        'user': {'userId': '1'},
      });
      final account = AccountRepository(api, credentials);
      await account.initialize();
      final tracking = TrackingRepository(
        store,
        account,
        CatalogRepository(api, store),
      );
      addTearDown(() async {
        await tracking.close();
        await account.close();
        api.close();
      });
      final result = expectLater(
        tracking.setCollection(42, score: 8),
        throwsStateError,
      );
      await requested.future;
      await account.signOut();
      response.complete(
        http.Response(
          jsonEncode({
            'data': {'subjectId': 42},
          }),
          200,
        ),
      );
      await result;
      expect(await store.pending('1'), isEmpty);
      expect(await store.list('collection:1'), isEmpty);
    },
  );

  test(
    'refresh preserves a refresh token omitted in the rotated response',
    () async {
      final credentials = MemoryCredentials();
      credentials.values['oauth'] = jsonEncode({
        'clientId': 'id',
        'clientSecret': 'secret',
      });
      credentials.values['account'] = jsonEncode({
        'access_token': 'old',
        'refresh_token': 'reusable',
        'expiresAt': 0,
        'user': {'userId': '1'},
      });
      var refreshes = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          refreshes++;
          expect(
            Uri.splitQueryString(request.body)['refresh_token'],
            'reusable',
          );
          return http.Response(
            jsonEncode({'access_token': 'new-$refreshes', 'expires_in': 0}),
            200,
          );
        }),
      );
      final account = AccountRepository(api, credentials);
      addTearDown(() async {
        await account.close();
        api.close();
      });
      await account.initialize();
      expect(await account.accessToken(), 'new-1');
      expect(await account.accessToken(), 'new-2');
    },
  );

  test(
    'concurrent unauthorized requests share one refresh and retry once',
    () async {
      final credentials = MemoryCredentials();
      credentials.values['oauth'] = '{}';
      credentials.values['account'] = jsonEncode({
        'access_token': 'old',
        'refresh_token': 'refresh',
        'expiresAt': DateTime.now().millisecondsSinceEpoch + 3600000,
        'user': {'userId': '1'},
      });
      var refreshes = 0, retries = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/oauth/access_token') {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return http.Response(
              jsonEncode({'access_token': 'new', 'expires_in': 3600}),
              200,
            );
          }
          if (request.headers['Authorization'] == 'Bearer old') {
            return http.Response('', 401);
          }
          retries++;
          return http.Response('{}', 200);
        }),
      );
      final account = AccountRepository(api, credentials);
      addTearDown(() async {
        await account.close();
        api.close();
      });
      await account.initialize();
      await Future.wait([account.request('/v0/me'), account.request('/v0/me')]);
      expect(refreshes, 1);
      expect(retries, 2);
    },
  );

  test(
    'credential save failure cannot replace the current account token',
    () async {
      final credentials = _FailingCredentials();
      credentials.values['oauth'] = '{}';
      credentials.values['account'] = jsonEncode({
        'access_token': 'old',
        'refresh_token': 'refresh',
        'expiresAt': 0,
        'user': {'userId': '1'},
      });
      var refreshes = 0;
      final api = ApiClient(
        client: MockClient((_) async {
          refreshes++;
          return http.Response(
            jsonEncode({'access_token': 'new', 'expires_in': 3600}),
            200,
          );
        }),
      );
      final account = AccountRepository(api, credentials);
      addTearDown(() async {
        await account.close();
        api.close();
      });
      await account.initialize();
      credentials.fail = true;
      await expectLater(account.accessToken(), throwsStateError);
      credentials.fail = false;
      expect(await account.accessToken(), 'new');
      expect(refreshes, 2);
      expect(
        object(jsonDecode(credentials.values['account']!))['access_token'],
        'new',
      );
    },
  );
}

class _FailingCredentials extends MemoryCredentials {
  bool fail = false;
  @override
  Future<void> write(String key, String? value) async {
    if (fail) throw StateError('Storage unavailable');
    await super.write(key, value);
  }
}
