import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:melonbang/ui/core/app_chrome.dart';
import 'package:melonbang/ui/player/player_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:melonbang/app.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/network.dart';
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
      await windowManager.setFullScreen(false);
      await tester.pump(const Duration(seconds: 1));
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setSize(const Size(1360, 860));
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-navigation-',
      );
      final slowSearch = Completer<void>();
      final slowDetail = Completer<void>();
      final slowReturningDetail = Completer<void>();
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
          if (id == 4) await slowReturningDetail.future;
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
        await windowManager.setFullScreen(false);
        await tester.pump(const Duration(seconds: 1));
        if (!slowSearch.isCompleted) slowSearch.complete();
        if (!slowDetail.isCompleted) slowDetail.complete();
        if (!slowReturningDetail.isCompleted) slowReturningDetail.complete();
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
      await state.playback.player.setVolume(20.0);
      await tester.pump(const Duration(milliseconds: 100));
      await state.playback.toggleMute();
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.playback.player.state.volume, 0);
      await state.playback.toggleMute();
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.playback.player.state.volume, 20);
      await state.playback.player.setVolume(0.0);
      await state.openSubject(<String, dynamic>{
        'subjectId': 1,
        'name': 'Subject 1',
      });
      await tester.pump(const Duration(milliseconds: 200));
      final Future<void> update = state.updateTracking(<String, dynamic>{
        'kind': 'subjectCollection',
        'subjectId': 1,
        'status': 'watching',
      });
      state.navigate('settings');
      await update;
      await tester.pump(const Duration(milliseconds: 200));
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
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('new result'), findsNWidgets(2));
      expect(find.text('old result'), findsNothing);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(
        fields
            .where(
              (field) =>
                  field.controller == state.search ||
                  field.controller == state.resourceSearch,
            )
            .length,
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
      await tester.pump(const Duration(milliseconds: 200));
      final pageKey = state.playerPageKey;
      final originalPage = pageKey.currentState;
      await tester.tap(find.byTooltip('弹幕'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PlayerSettings), findsOneWidget);
      final danmakuField = find.widgetWithText(TextField, '剧集网址或编号');
      await tester.scrollUntilVisible(
        danmakuField,
        240,
        scrollable: find
            .descendant(
              of: find.byType(PlayerSettings),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(danmakuField, 'BV-draft');
      await tester.tap(find.byTooltip('关闭播放菜单'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.playerPageKey.currentState.menu, isNull);
      expect(find.text('手动匹配'), findsNothing);
      await tester.tap(find.byTooltip('弹幕'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.scrollUntilVisible(
        danmakuField,
        220,
        scrollable: find
            .descendant(
              of: find.byType(PlayerSettings),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('BV-draft'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭播放菜单'));
      await tester.pump(const Duration(milliseconds: 200));

      final originalSize = await windowManager.getSize();
      await tester.tap(find.byTooltip('窗口全屏'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.windowFullScreen, isTrue);
      expect(await windowManager.isFullScreen(), isFalse);
      expect(await windowManager.getSize(), originalSize);
      expect(find.byType(AppSidebar), findsNothing);
      expect(find.byType(AppTitleBar), findsOneWidget);
      expect(pageKey.currentState, same(originalPage));
      await tester.tap(find.byTooltip('显示屏全屏（F）'));
      for (var i = 0; i < 30 && state.fullScreen != true; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.fullScreen, isTrue);
      expect(await windowManager.isFullScreen(), isTrue);
      expect(find.byType(AppTitleBar), findsNothing);
      expect(find.text('手动匹配'), findsNothing);
      final wasPlaying = state.playback.player.state.playing;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.playback.player.state.playing, !wasPlaying);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      for (var i = 0; i < 30 && state.fullScreen != false; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.fullScreen, isFalse);
      expect(state.windowFullScreen, isTrue);
      expect(await windowManager.isFullScreen(), isFalse);
      await tester.tap(find.byTooltip('退出窗口全屏'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.windowFullScreen, isFalse);
      expect(find.byType(AppSidebar), findsOneWidget);
      expect(pageKey.currentState, same(originalPage));
      await tester.tap(find.byTooltip('弹幕'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.scrollUntilVisible(
        danmakuField,
        220,
        scrollable: find
            .descendant(
              of: find.byType(PlayerSettings),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('BV-draft'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭播放菜单'));
      await tester.pump(const Duration(milliseconds: 200));

      // A hidden panel must remain reachable without a duplicate bottom action.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final panelButton = tester.getCenter(find.byTooltip('收起选集与资源'));
      await tester.tap(find.byTooltip('收起选集与资源'));
      await mouse.moveTo(const Offset(500, 300));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byTooltip('展开选集与资源').hitTestable(), findsNothing);
      await mouse.moveTo(panelButton - const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byTooltip('展开选集与资源').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('展开选集与资源'));
      await mouse.removePointer();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('播放设置'));
      await tester.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('延后 0.5 秒'));
        await tester.pump(const Duration(milliseconds: 200));
      }
      await state.openSubject(<String, dynamic>{'subjectId': 2});
      await tester.pump(const Duration(milliseconds: 200));
      state.navigate('player');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('播放设置'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('延后 0.5 秒'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.playback.subtitleDelay, 2.5);
      await tester.tap(find.byTooltip('关闭播放菜单'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Episode 1'), findsOneWidget);
      expect(find.textContaining('Episode 2'), findsNothing);
      await state.openVideo(media);
      await tester.pump(const Duration(milliseconds: 200));
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
      await state.startPlayback(
        () => services.library.local(media, subjectId: 4, episodeId: 40),
      );
      expect(state.playerSubject, isNull);
      state.navigate('home');
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.route, 'home');
      state.goBack();
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.route, 'player');
      expect(state.playerSubject, isNull);
      slowReturningDetail.complete();
      for (var i = 0; i < 20 && state.playerSubject == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        state.playerSubject?['subjectId'],
        4,
        reason: 'Leaving and returning must retain metadata for the same playback session.',
      );
      expect(find.textContaining('Episode 4'), findsOneWidget);
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
      await state.playback.player.seek(const Duration(seconds: 20));
      await state.playback.player.play();
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.playback.player.state.playing, isTrue);
      state.goBack();
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.route, 'subject');
      expect(state.subject?['subjectId'], 2);
      expect(state.playback.player.state.playing, isFalse);
      for (var i = 0; i < 20 && state.subjectResume == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.subjectResume?['episodeId'], 20);
      expect(state.subjectResume?['positionSeconds'], greaterThanOrEqualTo(19));
      expect(state.cachedEpisodeIds, contains(20));
      state.navigate('home');
      await tester.pump(const Duration(milliseconds: 300));
      final resumeAction = find.text('继续第 1 话').first;
      await tester.ensureVisible(resumeAction);
      await tester.tap(resumeAction);
      for (var i = 0; i < 30 && state.route != 'player'; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.route, 'player');
      expect(state.playback.session['subjectId'], 2);
      expect(state.playback.session['episodeId'], 20);
      for (
        var i = 0;
        i < 30 && state.playback.player.state.position.inSeconds < 19;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        state.playback.player.state.position.inSeconds,
        greaterThanOrEqualTo(19),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
