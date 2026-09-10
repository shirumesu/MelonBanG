import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/account.dart';
import 'package:melonbang/data/credentials.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/data/store.dart';
import 'package:melonbang/data/catalog.dart';
import 'package:melonbang/data/tracking.dart';
import 'package:melonbang/ui/core/theme.dart';
import 'package:melonbang/ui/settings/connection_settings.dart';
import 'package:melonbang/ui/settings/settings_page.dart';

import 'support/memory_credentials.dart';

class ObservedCredentials extends MemoryCredentials {
  final reads = <(String, bool)>[];
  bool locked = false, failWrites = false;
  @override
  Future<String?> read(String key, {bool allowInteraction = true}) async {
    reads.add((key, allowInteraction));
    if (locked && !allowInteraction) {
      throw const CredentialInteractionRequired();
    }
    return super.read(key);
  }

  @override
  Future<void> write(String key, String? value) async {
    if (failWrites) throw StateError('write failed');
    await super.write(key, value);
  }
}

void main() {
  test(
    'cache shares reads, retries denied access, and tracks durable writes',
    () async {
      final storage = ObservedCredentials()..locked = true;
      storage.values['oauth'] = 'first';
      final credentials = CachedCredentials(storage);
      await expectLater(
        credentials.read('oauth', allowInteraction: false),
        throwsA(isA<CredentialInteractionRequired>()),
      );
      expect(
        await Future.wait([
          credentials.read('oauth'),
          credentials.read('oauth'),
        ]),
        ['first', 'first'],
      );
      expect(storage.reads, [('oauth', false), ('oauth', true)]);
      storage.failWrites = true;
      await expectLater(
        credentials.write('oauth', 'unsaved'),
        throwsStateError,
      );
      expect(await credentials.read('oauth'), 'first');
      storage.failWrites = false;
      await Future.wait([
        credentials.write('oauth', 'next'),
        credentials.write('oauth', null),
      ]);
      expect(await credentials.read('oauth'), isNull);
      expect(storage.values['oauth'], isNull);
    },
  );

  test('one login gesture unlocks saved account and configuration for quiet refresh', () async {
    final storage = ObservedCredentials()..locked = true;
    storage.values['account'] = jsonEncode({
      'user': {'userId': '7'},
      'expiresAt': 0,
      'refresh_token': 'test',
    });
    var refreshes = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        expect(request.url.path, '/oauth/access_token');
        refreshes++;
        return http.Response(
          jsonEncode({'access_token': 'renewed', 'expires_in': 3600}),
          200,
        );
      }),
    );
    final account = AccountRepository(
      api,
      CachedCredentials(storage),
      launch: (_) async => fail('Saved login should be restored'),
    );
    try {
      await account.initialize();
      expect(account.session, isNull);
      expect(storage.reads, [('account', false)]);
      expect((await account.signIn())['userId'], '7');
      expect(await account.accessToken(), 'renewed');
      expect(await account.accessToken(), 'renewed');
      expect(refreshes, 1);
      expect(account.needsAuthorization, isFalse);
      expect(storage.reads, [
        ('account', false),
        ('account', true),
        ('oauth', true),
      ]);
    } finally {
      await account.close();
      api.close();
    }
  });

  test(
    'locked restart preserves local account data without exposing tokens',
    () async {
      final store = await AppStore.open(':memory:');
      final storage = ObservedCredentials();
      storage.values['account'] = jsonEncode({
        'user': {
          'userId': '7',
          'nickname': 'Test',
          'access_token': 'must-not-copy',
        },
        'access_token': 'secret',
        'refresh_token': 'refresh-secret',
        'expiresAt': 0,
      });
      final api = ApiClient(
        client: MockClient((_) async => fail('Locked account must not sync')),
      );
      final first = AccountRepository(api, storage, store: store);
      await first.initialize();
      expect(await store.get('account', 'profile'), {
        'userId': '7',
        'nickname': 'Test',
      });
      await store.put('collection:7', '1', {
        'subjectId': 1,
        'status': 'watching',
      });
      await store.enqueue('7', 'subject:1', {
        'subjectId': 1,
        'status': 'watching',
      });
      await first.close();
      storage.locked = true;
      final restarted = AccountRepository(
        api,
        CachedCredentials(storage),
        store: store,
      );
      final catalog = CatalogRepository(api, store);
      final tracking = TrackingRepository(store, restarted, catalog);
      try {
        await restarted.initialize();
        expect(restarted.needsAuthorization, isTrue);
        expect(restarted.userId, '7');
        expect((await tracking.collection()).single['subjectId'], 1);
        await tracking.flush();
        expect((await store.pending('7')).length, 1);
        await restarted.signOut();
        expect(restarted.session, isNull);
        expect(await store.get('account', 'profile'), isNull);
        expect((await store.list('collection:7')).length, 1);
      } finally {
        await tracking.close();
        await restarted.close();
        await catalog.close();
        api.close();
        await store.close();
      }
    },
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('settings read only the edited service on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('melonbang-credential-ui-'),
      ))!;
      final storage = ObservedCredentials();
      storage.values['dandanplay'] = jsonEncode({
        'appId': 'keep',
        'appSecret': 'untouched',
      });
      final services = AppServices(
        directory: directory.path,
        credentials: CachedCredentials(storage),
      );
      try {
        await tester.runAsync(services.start);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(false).copyWith(platform: platform),
            home: Scaffold(
              body: SettingsPage(
                account: null,
                sync: const {},
                dark: false,
                dataDirectory: null,
                connectionSettings: ConnectionSettings(services: services),
                bitTorrentSettings: const SizedBox(),
                onAccountAction: () {},
                onCancelSignIn: () {},
                onThemeChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(storage.reads, [('account', false)]);
        await tester.tap(find.text('服务连接'));
        await tester.pumpAndSettle();
        expect(storage.reads, [('account', false)]);
        await tester.tap(find.text('编辑 Bangumi'));
        await tester.pumpAndSettle();
        expect(storage.reads, [('account', false), ('oauth', true)]);
        await tester.enterText(
          find.widgetWithText(TextField, 'Bangumi Client ID'),
          'new-client',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Bangumi Client Secret'),
          'new-secret',
        );
        await tester.tap(find.text('保存 Bangumi'));
        await tester.pumpAndSettle();
        expect(jsonDecode(storage.values['oauth']!)['clientId'], 'new-client');
        expect(
          jsonDecode(storage.values['dandanplay']!)['appSecret'],
          'untouched',
        );
        await tester.tap(find.text('已保存 · 编辑 Bangumi'));
        await tester.pumpAndSettle();
        expect(storage.reads.length, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await services.close();
          await directory.delete(recursive: true);
        });
      }
    });
  }
}
