import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:melonbang/data/bittorrent_settings.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/store.dart';
import 'package:melonbang/ui/acquisition/downloads_page.dart';
import 'package:melonbang/ui/core/subject_posters.dart';
import 'package:melonbang/ui/core/theme.dart';

import 'torrent_test.dart' show bencode;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'download covers survive persistence and older tasks recover catalogue artwork',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-cover-test',
      );
      final store = await AppStore.open('${directory.path}/test.sqlite');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var imageRequests = 0;
      server.listen((request) async {
        imageRequests++;
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          ),
        );
        await request.response.close();
      });
      final cover = 'http://127.0.0.1:${server.port}/cover.png';
      await store.put('catalog', 'detail:42', {
        'value': {
          'data': {'subjectId': 42, 'coverUrl': cover},
        },
      });
      await store.put(
        'settings',
        'bittorrent',
        const BitTorrentSettings(
          dht: false,
          upnp: false,
          resumeOnStartup: false,
        ).toJson(),
      );
      var downloads = DownloadRepository(store, '${directory.path}/downloads');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await downloads.close();
        await server.close(force: true);
        await store.close();
        await directory.delete(recursive: true);
      });
      await downloads.initialize();
      final metadata = bencode(<String, Object>{
        'info': <String, Object>{
          'name': 'episode.mkv',
          'length': 1,
          'piece length': 16384,
          'pieces': Uint8List.fromList(sha1.convert([1]).bytes),
          'private': 1,
        },
      });
      final task = await downloads.addTorrent(
        metadata,
        'Example release',
        subjectId: 42,
      );
      expect(task['coverUrl'], cover);
      expect((await store.get('downloads', task['id']))?['coverUrl'], cover);
      await downloads.close();
      final oldTask = (await store.get('downloads', task['id']))!
        ..remove('coverUrl');
      await store.put('downloads', task['id'], oldTask);
      downloads = DownloadRepository(store, '${directory.path}/downloads');
      await downloads.initialize();
      expect(objects(downloads.snapshot()['tasks']).single['coverUrl'], cover);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
            body: DownloadsPage(
              downloads: downloads.snapshot(),
              onAddMagnet: () {},
              onAddTorrent: () {},
              onOpenVideo: () {},
              onExplore: () {},
              onTogglePause: (_) {},
              onRemove: (_) {},
              onStopSeeding: (_) {},
              onPlay: (_, _) {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 20 && imageRequests == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<SubjectCover>(find.byType(SubjectCover)).url, cover);
      expect(imageRequests, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
}
