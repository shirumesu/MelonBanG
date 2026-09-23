import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:melonbang/ui/player/playback.dart';
import 'package:melonbang/ui/player/danmaku.dart';
import 'package:melonbang/ui/player/player_page.dart';
import 'package:melonbang/app_services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native video, ASS, seek, resize and fullscreen share one Flutter surface',
    (tester) async {
      const mediaPath = String.fromEnvironment('TEST_MEDIA');
      const outputPath = String.fromEnvironment('TEST_CAPTURE');
      expect(
        File(mediaPath).existsSync(),
        isTrue,
        reason: 'Supply --dart-define=TEST_MEDIA=...',
      );
      MediaKit.ensureInitialized();
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1360, 860));
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-player-',
      );
      final services = AppServices(directory: directory.path);
      await services.start();
      final playback = Playback(
        services,
        await SharedPreferences.getInstance(),
      );
      final capture = GlobalKey();
      final errors = <Object>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: PlayerPage(
                playback: playback,
                service: playback.service,
                onBack: () {},
                onError: errors.add,
                fullScreen: false,
                onFullScreenChanged: windowManager.setFullScreen,
                onEpisode: (_) {},
                subject: const {
                  'subjectId': 42,
                  'nameCn': '播放交互验证',
                  'episodes': [
                    {'episodeId': 7, 'sort': 1, 'name': '当前章节'},
                    {'episodeId': 8, 'sort': 2, 'name': '下一话'},
                    {'episodeId': 9, 'sort': 3, 'name': '待下载章节'},
                  ],
                },
                downloads: const {
                  'tasks': [
                    {
                      'id': 'preview-task',
                      'subjectId': 42,
                      'episodeId': 8,
                      'title': '下一话',
                      'status': 'downloading',
                      'progress': .42,
                      'downloadSpeedBytesPerSecond': 3355443,
                    },
                  ],
                  'files': [],
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await windowManager.show();
      await playback.player.setVolume(0);
      await playback.openLocal(mediaPath, subjectId: 42, episodeId: 7);
      for (
        var i = 0;
        i < 50 && playback.player.state.duration.inSeconds == 0;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(playback.player.state.duration.inSeconds, greaterThan(15));
      expect(
        playback.player.state.tracks.subtitle.where(
          (track) => !['auto', 'no'].contains(track.id),
        ),
        isNotEmpty,
      );
      expect(
        playback.player.state.tracks.audio
            .where((track) => !['auto', 'no'].contains(track.id))
            .length,
        greaterThanOrEqualTo(2),
      );
      await playback.player.pause();
      for (final second in [12, 2, 15, 4]) {
        await playback.player.seek(Duration(seconds: second));
        for (
          var i = 0;
          i < 30 &&
              (playback.player.state.position.inSeconds - second).abs() > 1;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          (playback.player.state.position.inSeconds - second).abs(),
          lessThanOrEqualTo(1),
        );
      }
      final subtitles = playback.player.state.tracks.subtitle;
      final originalSession = playback.session!;
      playback.session = {...originalSession, 'subjectId': 42, 'episodeId': 7};
      final saving = playback.saveProgress();
      playback.session = {...originalSession, 'subjectId': 42, 'episodeId': 8};
      await saving;
      expect(
        (await services.library.progress(42, 7))!['positionSeconds'],
        greaterThan(2),
      );
      expect(
        await services.library.progress(42, 8),
        isNull,
        reason: 'A pending save belongs to the episode captured before its first await',
      );
      playback.session = originalSession;
      await playback.player.setSubtitleTrack(
        subtitles.firstWhere((track) => !['auto', 'no'].contains(track.id)),
      );
      final audios = playback.player.state.tracks.audio
          .where((track) => !['auto', 'no'].contains(track.id))
          .toList();
      await playback.player.setAudioTrack(audios.last);
      playback.comments = [
        {
          'timeSeconds': 1,
          'text': 'Native video + Flutter danmaku',
          'mode': 'scroll',
          'color': '#ffffff',
        },
        {
          'timeSeconds': 2,
          'text': 'One composed surface',
          'mode': 'top',
          'color': '#43c99f',
        },
      ];
      await playback.player.play();
      await tester.pump(const Duration(milliseconds: 250));
      final danmakuPaint = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is DanmakuPainter,
      );
      double paintedTime() =>
          (tester.widget<CustomPaint>(danmakuPaint).painter! as DanmakuPainter)
              .clock
              .value;
      var previousTime = paintedTime();
      var previousNative = playback.player.state.position;
      var interpolatedFrames = 0;
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final current = paintedTime();
        final native = playback.player.state.position;
        if (native == previousNative && current > previousTime) {
          interpolatedFrames++;
        }
        previousTime = current;
        previousNative = native;
      }
      expect(
        interpolatedFrames,
        greaterThan(10),
        reason: 'Danmaku must move between real native position events',
      );
      debugPrint(
        'Danmaku advanced between native updates on '
        '$interpolatedFrames/60 sampled frames',
      );
      await playback.player.pause();
      await tester.pump(const Duration(seconds: 1));
      await windowManager.setSize(const Size(1100, 720));
      await tester.pump(const Duration(milliseconds: 500));
      await windowManager.setFullScreen(true);
      await tester.pump(const Duration(milliseconds: 500));
      await windowManager.setFullScreen(false);
      await windowManager.setSize(const Size(1360, 860));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(errors, isEmpty);
      if (outputPath.isNotEmpty) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(outputPath).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
      if (outputPath.isNotEmpty) {
        for (final width in [960.0, 1360.0]) {
          await windowManager.setSize(Size(width, 760));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byTooltip('播放设置'));
          await tester.pump(const Duration(milliseconds: 200));
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$outputPath-settings-${width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          await tester.tap(find.byTooltip('延后 0.5 秒'));
          await tester.pump();
          expect(playback.subtitleDelay, .5);
          await tester.tap(find.text('重置'));
          await tester.pump();
          expect(playback.subtitleDelay, 0);
          await tester.tap(find.byTooltip('关闭播放菜单'));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await playback.close();
      await services.close();
      await directory.delete(recursive: true);
    },
  );
}
