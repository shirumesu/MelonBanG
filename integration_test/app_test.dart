import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:melonbang/app.dart';
import 'package:melonbang/app_services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('desktop shell uses Dart repositories and opens native dialogs', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1360, 860));
    await windowManager.show();
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('melonbang-shell-');
    final service = AppServices(directory: directory.path);
    await service.start();
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MelonApp(
          service: service,
          preferences: await SharedPreferences.getInstance(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(await service.store.list('downloads'), isEmpty);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('本季热度'), findsOneWidget);
    expect(find.text('继续播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
    const path = String.fromEnvironment('TEST_CAPTURE');
    if (path.isNotEmpty) {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }
    await tester.tap(find.text('缓存'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('磁力链接'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('添加磁力链接'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('登录 Bangumi'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    await service.close();
    await directory.delete(recursive: true);
  });
}
