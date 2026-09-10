import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/ui/settings/connection_settings.dart';
import 'package:melonbang/data/store.dart';
import 'package:melonbang/ui/core/theme.dart';
import 'package:melonbang/ui/acquisition/downloads_page.dart';
import 'package:melonbang/ui/settings/bittorrent_settings.dart';
import 'package:melonbang/ui/settings/settings_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'download settings save, validate and restore through settings navigation',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-settings-',
      );
      final store = await AppStore.open('${directory.path}/test.sqlite');
      final downloads = DownloadRepository(
        store,
        '${directory.path}/downloads',
      );
      await downloads.initialize();
      final capture = GlobalKey();
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              theme: appTheme(false),
              home: Scaffold(
                body: SettingsPage(
                  account: null,
                  sync: const {},
                  dark: false,
                  dataDirectory: directory.path,
                  connectionSettings: const SizedBox(),
                  bitTorrentSettings: BitTorrentSettingsPanel(
                    downloads: downloads,
                  ),
                  onAccountAction: () {},
                  onCancelSignIn: () {},
                  onThemeChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('下载与做种'));
        await tester.pumpAndSettle();
        Future<void> snapshot(String name) async {
          const output = String.fromEnvironment('TEST_CAPTURE');
          if (output.isEmpty) return;
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }

        await snapshot('bittorrent-seeding');
        final upload = find.widgetWithText(TextField, '上传限速 KiB/s（0 = 不限速）');
        await tester.ensureVisible(upload);
        await tester.enterText(upload, '256');
        final save = find.descendant(
          of: find.byType(BitTorrentSettingsPanel),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(downloads.settings.uploadKiB, 256);
        expect((await store.get('settings', 'bittorrent'))!['uploadKiB'], 256);
        expect(find.text('已保存并应用'), findsOneWidget);
        await snapshot('bittorrent-connections');
        await tester.ensureVisible(upload);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(upload).enabled, isTrue);
        // Saving disables the field and closes its input connection. Reopen it
        // with a tap, as a user would before editing the saved value.
        await tester.tap(upload);
        await tester.pumpAndSettle();
        await tester.enterText(upload, '-1');
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(upload).controller!.text, '-1');
        await tester.pumpAndSettle();
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(upload).controller!.text,
          '-1',
          reason: 'The invalid draft must survive scrolling and save',
        );
        expect(find.textContaining('保存失败'), findsOneWidget);
        expect(downloads.settings.uploadKiB, 256);
        await tester.tap(find.text('恢复推荐值'));
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(downloads.settings.uploadKiB, 1024);
        expect(tester.takeException(), isNull);
        String? pausedId;
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              theme: appTheme(false),
              home: Scaffold(
                body: DownloadsPage(
                  downloads: {
                    'files': [
                      {
                        'id': '1',
                        'downloadId': 'seed',
                        'name': 'Episode 01.mkv',
                        'mediaKind': 'video',
                        'size': 1073741824,
                        'progress': 1,
                      },
                      {
                        'id': '2',
                        'downloadId': 'seed',
                        'name': 'Episode 01.zh.ass',
                        'mediaKind': 'other',
                        'size': 65536,
                        'progress': 1,
                      },
                    ],
                    'tasks': [
                      {
                        'id': 'seed',
                        'title': '示例番剧 · 第 01 话 [1080p / 多音轨 / 简繁字幕]',
                        'status': 'seeding',
                        'progress': 1,
                        'totalBytes': 1073741824,
                        'uploadedBytes': 268435456,
                        'seedSeconds': 1200,
                        'uploadSpeedBytesPerSecond': 524288,
                        'peerCount': 8,
                      },
                      {
                        'id': 'done',
                        'title': '示例番剧 · 第 02 话',
                        'status': 'completed',
                        'progress': 1,
                        'seedStopReason': 'ratio',
                        'totalBytes': 1073741824,
                        'uploadedBytes': 1073741824,
                        'seedSeconds': 3000,
                        'peerCount': 0,
                      },
                      {
                        'id': 'queue',
                        'title': '示例番剧 · 第 03 话',
                        'status': 'queued',
                        'progress': 0.2,
                      },
                    ],
                  },
                  onAddMagnet: () {},
                  onAddTorrent: () {},
                  onOpenVideo: () {},
                  onExplore: () {},
                  onTogglePause: (task) => pausedId = '${task['id']}',
                  onRemove: (_) {},
                  onStopSeeding: (task) => pausedId = '${task['id']}',
                  onPlay: (_, _) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await snapshot('bittorrent-tasks');
        await tester.tap(find.byTooltip('查看文件'));
        await tester.pumpAndSettle();
        expect(find.text('Episode 01.zh.ass'), findsOneWidget);
        await snapshot('bittorrent-files');
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('停止做种'));
        expect(pausedId, 'seed');
        expect(find.text('已完成 · 达到分享率'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, '做种中'));
        await tester.pumpAndSettle();
        expect(find.text('示例番剧 · 第 01 话 [1080p / 多音轨 / 简繁字幕]'), findsOneWidget);
        expect(find.text('示例番剧 · 第 02 话'), findsNothing);
        expect(tester.takeException(), isNull);
        final services = AppServices(
          directory: '${directory.path}/connections',
        );
        try {
          await services.start();
          await tester.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: MaterialApp(
                theme: appTheme(false),
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
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('服务连接'));
          await tester.pumpAndSettle();
          await snapshot('credentials-collapsed');
          await tester.tap(find.text('编辑 Bangumi'));
          await tester.pumpAndSettle();
          await snapshot('credentials-edit');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await services.close();
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await downloads.close();
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
