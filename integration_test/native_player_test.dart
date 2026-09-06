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
                onOpen: () {},
                onBack: () {},
                onError: errors.add,
                fullScreen: false,
                onFullScreenChanged: windowManager.setFullScreen,
                onEpisode: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await windowManager.show();
      await playback.player.setVolume(0);
      await playback.openLocal(mediaPath);
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
      await tester.pumpWidget(const SizedBox.shrink());
      await playback.close();
      await services.close();
      await directory.delete(recursive: true);
    },
  );
}
