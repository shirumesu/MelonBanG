import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:melonbang/app.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/credentials.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/data/store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/memory_credentials.dart';
import '../test/support/service_configuration.dart';

class _LockedCredentials extends MemoryCredentials {
  final authorized = Completer<void>();
  final reads = <(String, bool)>[];
  @override
  Future<String?> read(String key, {bool allowInteraction = true}) async {
    reads.add((key, allowInteraction));
    if (!allowInteraction) throw const CredentialInteractionRequired();
    if (key == 'account') await authorized.future;
    return super.read(key);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('one unlock updates the shell even when collection sync fails', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1360, 860));
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'melonbang-account-ui-',
    );
    final store = await AppStore.open('${directory.path}/melonbang.sqlite');
    const user = {
      'userId': '7',
      'username': 'test',
      'nickname': 'Test Account',
    };
    await store.put('account', 'profile', user);
    await store.put('collection:7', '1', {
      'subjectId': 1,
      'name': 'Saved anime',
      'status': 'watching',
    });
    await store.close();
    final storage = _LockedCredentials();
    storage.values['account'] = jsonEncode({
      'user': user,
      'access_token': 'old',
      'refresh_token': 'test',
      'expiresAt': 0,
    });
    var refreshes = 0, syncs = 0;
    final services = AppServices(
      directory: directory.path,
      configuration: testServiceConfiguration,
      credentials: CachedCredentials(storage),
      api: ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/oauth/access_token') {
            refreshes++;
            return http.Response(
              jsonEncode({'access_token': 'fresh', 'expires_in': 3600}),
              200,
            );
          }
          if (request.url.host == 'api.bgm.tv') {
            syncs++;
            return http.Response('{}', 503);
          }
          return http.Response('{"data":[],"items":[]}', 200);
        }),
      ),
    );
    final capture = GlobalKey();
    try {
      await services.start();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MelonApp(
            service: services,
            preferences: await SharedPreferences.getInstance(),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(services.account.userId, '7');
      expect((await services.tracking.collection()).length, 1);
      expect(syncs, 0);
      await tester.tap(find.text('设置'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('待解锁'), findsOneWidget);
      expect(find.text('解锁同步'), findsOneWidget);
      const path = String.fromEnvironment('TEST_CAPTURE');
      if (path.isNotEmpty) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
      await tester.tap(find.text('解锁同步'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('连接中…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('连接中…'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      storage.authorized.complete();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(refreshes, 1);
      expect(syncs, 1);
      expect(storage.reads, [('account', false), ('account', true)]);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
      expect(find.text('登录 Bangumi'), findsNothing);
      expect((await services.tracking.collection()).length, 1);
      expect(tester.takeException(), isNull);
    } finally {
      if (!storage.authorized.isCompleted) storage.authorized.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
      await services.close();
      await directory.delete(recursive: true);
    }
  });
}
