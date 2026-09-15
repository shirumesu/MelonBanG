import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melonbang/data/network.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/ui/player/playback.dart';

import '../test/support/memory_credentials.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'playback auto-matches without blocking and recovers from failed replacement',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      MediaKit.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-playback-',
      );
      // A silent PCM fixture exercises the native player without external media.
      const samples = 44100 * 20;
      final bytes = Uint8List(44 + samples * 2);
      final header = ByteData.sublistView(bytes);
      void text(int offset, String value) =>
          bytes.setRange(offset, offset + value.length, value.codeUnits);
      text(0, 'RIFF');
      header.setUint32(4, bytes.length - 8, Endian.little);
      text(8, 'WAVEfmt ');
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little);
      header.setUint16(22, 1, Endian.little);
      header.setUint32(24, 44100, Endian.little);
      header.setUint32(28, 88200, Endian.little);
      header.setUint16(32, 2, Endian.little);
      header.setUint16(34, 16, Endian.little);
      text(36, 'data');
      header.setUint32(40, samples * 2, Endian.little);
      final file = await File('${directory.path}/fixture.wav')
          .writeAsBytes(bytes);
      var matches = 0;
      final matching = Completer<http.Response>();
      final credentials = MemoryCredentials();
      credentials.values['dandanplay'] = jsonEncode({
        'appId': 'test-app',
        'appSecret': 'test-secret',
      });
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/v2/match') {
            matches++;
            return matching.future;
          }
          if (request.url.path == '/api/v2/comment/7') {
            return http.Response(
              jsonEncode({
                'success': true,
                'comments': [
                  {'p': '1,1,16777215,user', 'm': 'Auto matched'},
                ],
              }),
              200,
            );
          }
          return http.Response('{"data":{}}', 200);
        }),
      );
      final services = AppServices(
        directory: directory.path,
        api: api,
        credentials: credentials,
      );
      await services.start();
      final playback = Playback(
        services,
        await SharedPreferences.getInstance(),
      );
      final subscription = services.library.changes.stream.listen(
        playback.accept,
      );
      try {
        await tester.pump(const Duration(milliseconds: 200));
        await playback.player.setVolume(0);
        await playback.openLocal(file.path, subjectId: 42, episodeId: 7);
        await tester.pump(const Duration(seconds: 1));
        expect(playback.player.state.playing, isTrue);
        expect(matches, 1);
        expect(playback.comments, isEmpty);
        matching.complete(
          http.Response(
            jsonEncode({
              'success': true,
              'isMatched': true,
              'matches': [
                {'episodeId': 7},
              ],
            }),
            200,
          ),
        );
        for (var i = 0; i < 30 && playback.comments.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(playback.comments.single['text'], 'Auto matched');
        await expectLater(
          playback.open({'status': 'failed', 'errorMessage': 'Missing media'}),
          throwsStateError,
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(playback.player.state.playing, isFalse);
        expect(playback.session, isNull);
        await playback.openLocal(file.path, subjectId: 42, episodeId: 7);
        await tester.pump(const Duration(milliseconds: 200));
        expect(playback.player.state.playing, isTrue);
        expect(matches, 2);
      } finally {
        await subscription.cancel();
        await playback.close();
        await services.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
