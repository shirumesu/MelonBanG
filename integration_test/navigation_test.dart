import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:melonbang/app.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/memory_credentials.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'navigation keeps async results and playback tied to their context',
    (tester) async {
      MediaKit.ensureInitialized();
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1360, 860));
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-navigation-',
      );
      final slowSearch = Completer<void>();
      final slowDetail = Completer<void>();
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.host == 'share.dmhy.org' ||
              request.url.host == 'mikanani.me') {
            final keyword = request.url.queryParameters.values.first;
            if (keyword == 'old') await slowSearch.future;
            return http.Response(
              '<rss><channel><item><title>$keyword result</title>'
              '<enclosure url="magnet:?xt=urn:btih:0123456789012345678901234567890123456789"/>'
              '</item></channel></rss>',
              200,
            );
          }
          final id = int.tryParse(request.url.pathSegments.last);
          if (id == 3) await slowDetail.future;
          return http.Response(
            jsonEncode(
              id == null
                  ? {'data': [], 'items': []}
                  : {
                      'data': {
                        'subjectId': id,
                        'name': 'Subject $id',
                        'nameCn': 'Subject $id',
                        'episodes': [
                          {
                            'episodeId': id * 10,
                            'sort': 1,
                            'name': 'Episode $id',
                          },
                        ],
                      },
                    },
            ),
            200,
          );
        }),
      );
      final services = AppServices(
        directory: directory.path,
        credentials: MemoryCredentials(),
        api: api,
      );
      addTearDown(() async {
        if (!slowSearch.isCompleted) slowSearch.complete();
        if (!slowDetail.isCompleted) slowDetail.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
        await services.close();
        await directory.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MelonApp(
          service: services,
          preferences: await SharedPreferences.getInstance(),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final dynamic state = tester.state(find.byType(MelonApp));
      await state.playback.player.setVolume(0.0);
      await state.openSubject(<String, dynamic>{
        'subjectId': 1,
        'name': 'Subject 1',
      });
      await tester.pump();
      final Future<void> update = state.updateTracking(<String, dynamic>{
        'kind': 'subjectCollection',
        'subjectId': 1,
        'status': 'watching',
      });
      state.navigate('settings');
      await update;
      await tester.pump();
      expect(find.text('服务连接'), findsOneWidget);
      expect(find.text('番剧详情'), findsNothing);

      await state.openSubject(<String, dynamic>{
        'subjectId': 1,
        'name': 'Subject 1',
      });
      await state.findResources();
      state.resourceSearch.text = 'old';
      final Future<void> oldSearch = state.searchResources();
      state.resourceSearch.text = 'new';
      await state.searchResources();
      slowSearch.complete();
      await oldSearch;
      await tester.pump();
      expect(find.text('new result'), findsNWidgets(2));
      expect(find.text('old result'), findsNothing);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(
        fields.map((field) => field.controller).toSet().length,
        2,
        reason:
            'Resource keywords must not overwrite the global catalogue search.',
      );

      const media = String.fromEnvironment('TEST_MEDIA');
      expect(
        File(media).existsSync(),
        isTrue,
        reason: 'Supply --dart-define=TEST_MEDIA=...',
      );
      await state.openSubject(<String, dynamic>{'subjectId': 1});
      await state.openVideo(media, <String, dynamic>{'episodeId': 10});
      await tester.pump();
      final dynamic firstPlayer = tester.state(find.byType(PlayerPage));
      await firstPlayer.offsetSubtitle(2.0);
      await state.openSubject(<String, dynamic>{'subjectId': 2});
      await tester.pump();
      state.navigate('player');
      await tester.pump();
      final dynamic returnedPlayer = tester.state(find.byType(PlayerPage));
      await returnedPlayer.offsetSubtitle(.5);
      expect(state.playback.subtitleDelay, 2.5);
      await tester.tap(find.text('选集'));
      await tester.pump();
      expect(find.text('Episode 1'), findsOneWidget);
      expect(find.text('Episode 2'), findsNothing);
      await state.openVideo(media);
      await tester.pump();
      expect(find.textContaining('此视频没有关联章节'), findsOneWidget);
      expect(state.playback.subtitleDelay, 0);

      final slowMedia = Completer<void>();
      final Future<void> firstOpen = state.startPlayback(() async {
        await slowMedia.future;
        return services.library.local(media, subjectId: 1, episodeId: 10);
      });
      await tester.pump(const Duration(milliseconds: 100));
      final Future<void> secondOpen = state.startPlayback(
        () => services.library.local(media, subjectId: 2, episodeId: 20),
      );
      slowMedia.complete();
      await Future.wait([firstOpen, secondOpen]);
      for (var i = 0; i < 20 && state.playerSubject == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.playback.session['subjectId'], 2);
      expect(services.library.current?['id'], state.playback.session['id']);
      expect(state.playerSubject['subjectId'], 2);
      await (state.startPlayback(
        () => services.library.local(media, subjectId: 3, episodeId: 30),
      ) as Future<void>).timeout(const Duration(seconds: 3));
      expect(
        state.playback.session['subjectId'],
        3,
        reason: 'Slow chapter metadata must not hold the video-open queue.',
      );
      await state.startPlayback(
        () => services.library.local(media, subjectId: 2, episodeId: 20),
      );
      slowDetail.complete();
      for (var i = 0; i < 20 && state.playerSubject == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.playerSubject['subjectId'], 2);
      expect(tester.takeException(), isNull);
    },
  );
}
