import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/data/sources.dart';
import 'package:melonbang/data/store.dart';
import 'package:melonbang/ui/acquisition/resource_widgets.dart';
import 'package:melonbang/ui/acquisition/resources_page.dart';
import 'package:melonbang/ui/player/player_page.dart';
import 'package:melonbang/ui/player/player_theme.dart';

import 'player_interactions_test.dart' show MemoryPlayback;

class TestDownloads extends DownloadRepository {
  TestDownloads(super.store, super.directory);
  final queued = <Json>[];
  bool fail = true;
  Json get state => {'tasks': queued, 'files': <Json>[]};
  @override
  Future<Json> addMagnet(
    String input, {
    int? subjectId,
    int? episodeId,
    String? coverUrl,
  }) async {
    if (fail) throw StateError('Test download unavailable');
    final task = <String, dynamic>{
      'id': 'task-${queued.length}',
      'subjectId': subjectId,
      'episodeId': episodeId,
      'title': 'Downloaded episode',
      'status': 'downloading',
      'progress': .42,
      'downloadSpeedBytesPerSecond': 1048576,
    };
    queued.add(task);
    changes.add(state);
    return task;
  }

  @override
  Future<void> pause(String id) async {
    queued.firstWhere((t) => t['id'] == id)['status'] = 'paused';
    changes.add(state);
  }

  @override
  Future<void> resume(String id) async {
    queued.firstWhere((t) => t['id'] == id)['status'] = 'downloading';
    changes.add(state);
  }
}

void main() {
  testWidgets(
    'player resources retain episode context, recover enqueue failure and show live task state',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('player-library-test'),
      ))!;
      final store = (await tester.runAsync(
        () => AppStore.open('${directory.path}/test.sqlite'),
      ))!;
      final gate = Completer<void>();
      final api = ApiClient(
        client: MockClient((request) async {
          final keyword = request.url.queryParameters.values.first;
          if (keyword.startsWith('old')) await gate.future;
          return http.Response(
            '<rss><channel><item><title>$keyword result</title>'
            '<enclosure url="magnet:?xt=urn:btih:0123456789012345678901234567890123456789"/>'
            '</item></channel></rss>',
            200,
          );
        }),
      );
      final downloads = TestDownloads(store, directory.path);
      final services = AppServices(api: api)
        ..store = store
        ..downloads = downloads
        ..sources = SourceRepository(api, downloads);
      final playback = MemoryPlayback()
        ..session = {'id': 'session', 'subjectId': 7, 'episodeId': 71};
      await playback.player.play();
      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      var episodeOpened = false;
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await playback.player.dispose();
        playback.dispose();
        await tester.runAsync(() async {
          await downloads.close();
          api.close();
          await store.close();
          await directory.delete(recursive: true);
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: playerTheme(),
          home: Scaffold(
            body: StreamBuilder<Json>(
              stream: downloads.changes.stream,
              initialData: downloads.state,
              builder: (_, snapshot) => PlayerPage(
                playback: playback,
                service: services,
                subject: const {
                  'subjectId': 7,
                  'name': 'Subject',
                  'episodes': [
                    {'episodeId': 71, 'sort': 1, 'name': 'One'},
                    {'episodeId': 72, 'sort': 2, 'name': 'Two'},
                  ],
                },
                downloads: snapshot.data!,
                onBack: () {},
                onError: (_) {},
                fullScreen: false,
                onFullScreenChanged: (_) async {},
                onEpisode: (_) => episodeOpened = true,
                onPlayFile: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await settle();
      final video = tester.element(find.byType(Video));
      final videoRect = tester.getRect(find.byType(Video));
      await tester.tap(find.text('找资源'));
      await settle();
      expect(find.byType(ResourcesPage), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '资源关键词'), 'old');
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pump();
      await tester.tap(find.byTooltip('关闭资源窗口'));
      await settle();
      await tester.tap(find.byTooltip('查找第 2 话资源'));
      await settle();
      gate.complete();
      await settle();
      final resources = tester.widget<ResourcesPage>(
        find.byType(ResourcesPage),
      );
      expect(resources.resourceEpisode, 72);
      expect(
        resources.candidates.map((e) => e['title']),
        everyElement('Subject 02 result'),
      );
      expect(tester.element(find.byType(Video)), same(video));
      expect(tester.getRect(find.byType(Video)), videoRect);
      expect(playback.player.state.playing, isTrue);
      expect(playback.session!['episodeId'], 71);
      final sheet = find.byKey(const ValueKey('player-resource-sheet'));
      final sheetBounds = tester.getRect(sheet);
      await tester.drag(find.text('查找资源 · 第 2 话'), const Offset(100, 0));
      await settle();
      expect(tester.getRect(sheet), sheetBounds);

      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('播放 / 暂停（空格）').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('播放 / 暂停（空格）'));
      await settle();
      expect(playback.player.state.playing, isFalse);
      await tester.tap(find.byTooltip('播放 / 暂停（空格）'));
      await settle();
      await tester.enterText(
        find.widgetWithText(TextField, '资源关键词'),
        'Kept query',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(playback.player.state.playing, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle();
      expect(find.byType(ResourcesPage), findsNothing);
      await tester.tap(find.byTooltip('查找第 2 话资源'));
      await settle();
      expect(find.textContaining('Kept query'), findsOneWidget);
      final download = find.widgetWithText(TextButton, '下载').first;
      await tester.ensureVisible(download);
      await tester.tap(download);
      await settle();
      expect(
        find.byTooltip('添加失败，点击重试\nTest download unavailable'),
        findsOneWidget,
      );
      expect(downloads.queued, isEmpty);
      downloads.fail = false;
      await tester.tap(find.widgetWithText(TextButton, '重试').first);
      await settle();
      expect(downloads.queued.single['subjectId'], 7);
      expect(downloads.queued.single['episodeId'], 72);
      expect(find.byType(ResourceResultRow), findsWidgets);
      expect(episodeOpened, isFalse);
      expect(playback.session!['episodeId'], 71);
      await tester.tap(find.byTooltip('关闭资源窗口'));
      await settle();
      expect(find.text('42%'), findsOneWidget);
      expect(find.text('正在播放 · 第 1 话'), findsOneWidget);
      await tester.tap(find.byTooltip('暂停下载'));
      await settle();
      expect(find.text('已暂停'), findsOneWidget);
      await tester.tap(find.byTooltip('继续下载'));
      await settle();
      expect(find.text('下载中 · 1.0 MB/s'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );
}
