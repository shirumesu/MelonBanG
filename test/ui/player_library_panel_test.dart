import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/data/sources.dart';
import 'package:melonbang/data/store.dart';
import 'package:melonbang/ui/player/player_library_panel.dart';
import 'package:melonbang/ui/player/player_theme.dart';

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
          if (keyword == 'old') await gate.future;
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
      var episodeOpened = false;
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox.shrink());
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
            body: Center(
              child: SizedBox(
                width: 310,
                height: 720,
                child: StreamBuilder<Json>(
                  stream: downloads.changes.stream,
                  initialData: downloads.state,
                  builder: (_, snapshot) => PlayerLibraryPanel(
                    service: services,
                    subjectId: 7,
                    subject: const {
                      'subjectId': 7,
                      'name': 'Subject',
                      'episodes': [
                        {'episodeId': 71, 'sort': 1, 'name': 'One'},
                        {'episodeId': 72, 'sort': 2, 'name': 'Two'},
                      ],
                    },
                    episodeId: 71,
                    title: 'Current episode',
                    downloads: snapshot.data!,
                    onEpisode: (_) => episodeOpened = true,
                    onPlayFile: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('找资源'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '资源关键词'), 'old');
      await tester.tap(find.byTooltip('搜索资源'));
      await tester.pump();
      await tester.tap(find.text('选集'));
      await tester.pump();
      await tester.tap(find.byTooltip('查找第 2 话资源'));
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('old result'), findsNothing);
      expect(find.text('Subject 02 result'), findsNWidgets(2));
      await tester.tap(find.widgetWithText(TextButton, '下载').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('下载未能加入'), findsOneWidget);
      expect(downloads.queued, isEmpty);
      downloads.fail = false;
      await tester.tap(find.widgetWithText(TextButton, '下载').first);
      await tester.pumpAndSettle();
      expect(downloads.queued.single['subjectId'], 7);
      expect(downloads.queued.single['episodeId'], 72);
      expect(find.text('已加入缓存'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(episodeOpened, isFalse);
      expect(find.text('正在播放 · 第 1 话'), findsOneWidget);
      await tester.tap(find.byTooltip('暂停下载'));
      await tester.pumpAndSettle();
      expect(find.text('已暂停'), findsOneWidget);
      await tester.tap(find.byTooltip('继续下载'));
      await tester.pumpAndSettle();
      expect(find.text('下载中 · 1.0 MB/s'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );
}
