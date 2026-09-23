import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/ui/acquisition/resources_page.dart';
import 'package:melonbang/ui/core/theme.dart';
import 'package:melonbang/ui/player/playback.dart';
import 'package:melonbang/ui/player/player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/memory_credentials.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'shared resource sheet preserves native playback and search drafts',
    (tester) async {
      const media = String.fromEnvironment('TEST_MEDIA');
      expect(File(media).existsSync(), isTrue, reason: 'Supply TEST_MEDIA');
      MediaKit.ensureInitialized();
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1360, 860));
      await windowManager.show();
      await windowManager.focus();
      final directory = await Directory.systemTemp.createTemp('melon-sheet-');
      final api = ApiClient(
        client: MockClient((request) async {
          if (['share.dmhy.org', 'mikanani.me'].contains(request.url.host)) {
            return http.Response(
              '<rss><channel><item><title>[示例字幕组] Example - 02 [1080p][简繁内封]</title><enclosure url="magnet:?xt=urn:btih:0123456789012345678901234567890123456789"/></item></channel></rss>',
              200,
              headers: {'content-type': 'application/rss+xml; charset=utf-8'},
            );
          }
          return http.Response(jsonEncode({'data': [], 'items': []}), 200);
        }),
      );
      final services = AppServices(
        directory: directory.path,
        api: api,
        credentials: MemoryCredentials(),
      );
      await services.start();
      SharedPreferences.setMockInitialValues({});
      final playback = Playback(
        services,
        await SharedPreferences.getInstance(),
      );
      final capture = GlobalKey();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await playback.close();
        await services.close();
        await directory.delete(recursive: true);
      });
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          darkTheme: appTheme(true),
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: PlayerPage(
                playback: playback,
                service: services,
                onBack: () {},
                onError: (_) {},
                fullScreen: false,
                onFullScreenChanged: (_) async {},
                onEpisode: (_) {},
                subject: const {
                  'subjectId': 42,
                  'name': 'Example',
                  'episodes': [
                    {'episodeId': 1, 'sort': 1, 'name': '正在观看'},
                    {'episodeId': 2, 'sort': 2, 'name': '下一话'},
                  ],
                },
              ),
            ),
          ),
        ),
      );
      await playback.player.setVolume(0);
      await playback.openLocal(media, subjectId: 42, episodeId: 1);
      Future<void> advance() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await advance();
      final video = tester.element(find.byType(Video));
      final bounds = tester.getRect(find.byType(Video));
      final session = playback.session!['id'];
      await tester.tap(find.byTooltip('查找第 2 话资源'));
      await advance();
      expect(find.byType(ResourcesPage), findsOneWidget);
      expect(
        tester.widget<ResourcesPage>(find.byType(ResourcesPage)).candidates,
        hasLength(2),
      );
      expect(
        tester
            .widget<ResourcesPage>(find.byType(ResourcesPage))
            .resourceEpisode,
        2,
      );
      expect(tester.element(find.byType(Video)), same(video));
      expect(tester.getRect(find.byType(Video)), bounds);
      expect(playback.session!['id'], session);
      expect(playback.session!['episodeId'], 1);
      expect(playback.player.state.playing, isTrue);
      await tester.tap(find.byTooltip('播放 / 暂停（空格）'));
      await advance();
      expect(playback.player.state.playing, isFalse);
      await tester.tap(find.byTooltip('播放 / 暂停（空格）'));
      await advance();
      expect(playback.player.state.playing, isTrue);
      await tester.enterText(find.widgetWithText(TextField, '资源关键词'), '保留搜索输入');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await advance();
      expect(find.byType(ResourcesPage), findsNothing);
      await tester.tap(find.byTooltip('查找第 2 话资源'));
      await advance();
      expect(find.text('保留搜索输入'), findsOneWidget);
      const output = String.fromEnvironment('TEST_CAPTURE');
      Future<void> snapshot(String path) async {
        if (path.isEmpty) return;
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      expect(
        Theme.of(tester.element(find.byType(ResourcesPage))).brightness,
        Brightness.light,
      );
      await snapshot(output);
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await advance();
      expect(
        Theme.of(tester.element(find.byType(ResourcesPage))).brightness,
        Brightness.dark,
      );
      expect(tester.element(find.byType(Video)), same(video));
      expect(find.text('保留搜索输入'), findsOneWidget);
      await snapshot(output.isEmpty ? '' : '$output.dark.png');
      expect(tester.takeException(), isNull);
    },
  );
}
