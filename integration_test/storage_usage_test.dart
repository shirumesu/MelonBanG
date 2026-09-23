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
import 'package:melonbang/data/network.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/memory_credentials.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'settings measures native storage and refreshes after file changes',
    (tester) async {
      MediaKit.ensureInitialized();
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1100, 760));
      await windowManager.show();
      final root = await Directory.systemTemp.createTemp('melonbang-storage-');
      final media = await Directory(p.join(root.path, 'downloads')).create();
      await File(p.join(media.path, 'video'))
          .writeAsBytes(List.filled(2097152, 1));
      final services = AppServices(
        directory: root.path,
        credentials: MemoryCredentials(),
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response('{"data":[],"items":[]}', 200),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await services.close();
        await root.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MelonApp(
            service: services,
            preferences: await SharedPreferences.getInstance(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用数据'));
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('已用 2.0 MiB').evaluate().isNotEmpty) break;
      }
      expect(find.text('已用 2.0 MiB'), findsOneWidget);
      expect(find.text('暂时无法统计'), findsNothing);
      await File(p.join(media.path, 'second-video'))
          .writeAsBytes(List.filled(2097152, 2));
      await tester.tap(find.byTooltip('刷新空间用量').last);
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('已用 4.0 MiB').evaluate().isNotEmpty) break;
      }
      expect(find.text('已用 4.0 MiB'), findsOneWidget);
      expect(tester.takeException(), isNull);
      const output = String.fromEnvironment('TEST_CAPTURE');
      if (output.isNotEmpty) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
    },
  );
}
