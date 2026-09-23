import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/bittorrent_settings.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/store.dart';

Uint8List bencode(Object value) {
  if (value is int) return Uint8List.fromList(ascii.encode('i${value}e'));
  if (value is String) return bencode(Uint8List.fromList(utf8.encode(value)));
  if (value is Uint8List) {
    return Uint8List.fromList([...ascii.encode('${value.length}:'), ...value]);
  }
  if (value is List<Object>) {
    return Uint8List.fromList([108, ...value.expand(bencode), 101]);
  }
  if (value is Map<String, Object>) {
    final keys = value.keys.toList()..sort();
    return Uint8List.fromList([
      100,
      ...keys.expand((key) => [...bencode(key), ...bencode(value[key]!)]),
      101,
    ]);
  }
  throw ArgumentError.value(value);
}

List<int> integer(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native torrent receives verified pieces and preserves files across shutdown',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Local torrent verification')),
        ),
      );
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-torrent-',
      );
      final peer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final tracker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final emptyTracker = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      var emptyAnnounces = 0, workingAnnounces = 0;
      emptyTracker.listen((request) async {
        emptyAnnounces++;
        request.response.add(
          bencode(<String, Object>{'interval': 1800, 'peers': Uint8List(0)}),
        );
        await request.response.close();
      });
      final payload = Uint8List.fromList(
        List.generate(65536, (i) => (i * 17 + i ~/ 89) % 256),
      );
      const pieceLength = 16384;
      final pieceHashes = Uint8List.fromList([
        for (var i = 0; i < payload.length; i += pieceLength)
          ...sha1.convert(payload.sublist(i, i + pieceLength)).bytes,
      ]);
      final info = <String, Object>{
        'name': 'fixture.mkv',
        'length': payload.length,
        'piece length': pieceLength,
        'pieces': pieceHashes,
        'private': 1,
      };
      final hash = sha1.convert(bencode(info)).bytes;
      final metadata = bencode(<String, Object>{
        'announce': 'http://127.0.0.1:${emptyTracker.port}/announce',
        'announce-list': <Object>[
          <Object>['http://127.0.0.1:${emptyTracker.port}/announce'],
          <Object>['http://127.0.0.1:${tracker.port}/announce'],
        ],
        'info': info,
      });
      final sockets = <Socket>[];
      final releasePieces = Completer<void>();
      var servedBytes = 0;
      tracker.listen((request) async {
        workingAnnounces++;
        request.response.headers.contentType = ContentType.binary;
        request.response.add(
          bencode(<String, Object>{
            'interval': 1,
            'complete': 1,
            'incomplete': 0,
            'peers': Uint8List.fromList([
              127,
              0,
              0,
              1,
              peer.port >> 8,
              peer.port & 255,
            ]),
          }),
        );
        await request.response.close();
      });
      peer.listen((socket) {
        sockets.add(socket);
        var buffer = <int>[];
        var handshake = false;
        socket.listen(
          (chunk) {
            buffer.addAll(chunk);
            if (!handshake) {
              if (buffer.length < 68) return;
              buffer = buffer.sublist(68);
              handshake = true;
              socket.add([
                19,
                ...ascii.encode('BitTorrent protocol'),
                ...List.filled(8, 0),
                ...hash,
                ...ascii.encode('-MB0001-123456789012'),
              ]);
              socket.add([...integer(2), 5, 0xf0, ...integer(1), 1]);
            }
            while (buffer.length >= 4) {
              final length = ByteData.sublistView(
                Uint8List.fromList(buffer.sublist(0, 4)),
              ).getUint32(0);
              if (buffer.length < length + 4) return;
              final message = buffer.sublist(4, 4 + length);
              buffer = buffer.sublist(4 + length);
              if (message.isNotEmpty && message[0] == 6) {
                final request = ByteData.sublistView(
                  Uint8List.fromList(message),
                );
                final index = request.getUint32(1),
                    begin = request.getUint32(5),
                    count = request.getUint32(9);
                final start = index * pieceLength + begin;
                releasePieces.future.then((_) {
                  socket.add([
                    ...integer(count + 9),
                    7,
                    ...integer(index),
                    ...integer(begin),
                    ...payload.sublist(start, start + count),
                  ]);
                  servedBytes += count;
                });
              }
            }
          },
          onError: (_) {},
          onDone: socket.destroy,
        );
      });
      final portProbe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final incomingPort = portProbe.port;
      await portProbe.close();
      final store = await AppStore.open('${directory.path}/test.sqlite');
      var downloads = DownloadRepository(store, '${directory.path}/downloads');
      try {
        await downloads.initialize();
        await downloads.saveSettings(
          BitTorrentSettings(
            listenPort: incomingPort,
            dht: false,
            upnp: false,
            ipv6: false,
          ),
        );

        final added = await Future.wait([
          downloads.addTorrent(metadata, 'Fixture'),
          downloads.addTorrent(metadata, 'Fixture'),
        ]).timeout(const Duration(seconds: 10));
        final task = added.first;
        expect(added.last['id'], task['id']);
        final changedTrackers = bencode(<String, Object>{
          'announce': 'http://127.0.0.1:${tracker.port}/announce',
          'comment': 'Same content from another RSS provider',
          'info': info,
        });
        expect(
          (await downloads.addTorrent(changedTrackers, 'Other provider'))['id'],
          task['id'],
        );
        final hexHash = hash
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
        expect(
          (await downloads.addMagnet('magnet:?xt=urn:btih:$hexHash'))['id'],
          task['id'],
        );
        expect(objects(downloads.snapshot()['tasks']), hasLength(1));
        LibtorrentFlutter.instance.configureSession(
          BtConfig(
            peersListenPort: incomingPort,
            disableDht: true,
            disableUpnp: true,
            disableUtp: true,
            enableIpv6: false,
          ),
        );
        for (
          var i = 0;
          i < 50 && objects(downloads.snapshot()['files']).isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(
          number(objects(downloads.snapshot()['tasks']).single['progress']),
          lessThan(1),
        );
        final streaming = await downloads.openMedia('${task['id']}');
        expect(streaming['incomplete'], true);
        final http = HttpClient();
        try {
          final request = await http.getUrl(
            Uri.parse('${streaming['streamUrl']}'),
          );
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=65504-65535');
          final response = request.close();
          releasePieces.complete();
          final received = await response.timeout(const Duration(seconds: 30));
          expect(received.statusCode, HttpStatus.partialContent);
          final bytes = await received.fold<List<int>>(
            [],
            (all, next) => all..addAll(next),
          );
          expect(bytes, payload.sublist(65504));
          final seek = await http.getUrl(
            Uri.parse('${streaming['streamUrl']}'),
          );
          seek.headers.set(HttpHeaders.rangeHeader, 'bytes=0-31');
          final sought = await seek.close();
          expect(
            await sought.fold<List<int>>([], (all, next) => all..addAll(next)),
            payload.sublist(0, 32),
          );
        } finally {
          http.close(force: true);
          downloads.releaseStreamsExcept(null);
        }
        Json current = {};
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          current = objects(downloads.snapshot()['tasks']).single;
          if (current['status'] == 'seeding') break;
        }
        expect(current['status'], 'seeding', reason: current.toString());
        expect(emptyAnnounces, greaterThan(0));
        expect(
          workingAnnounces,
          greaterThan(0),
          reason: 'An empty first tier must not hide peers in another tier',
        );
        expect(current['trackerCount'], 2);
        expect(current['workingTrackers'], 2);
        expect(current['dhtNodes'], -1);
        expect(servedBytes, greaterThanOrEqualTo(payload.length));
        final media = downloads.media('${task['id']}');
        expect(media['size'], payload.length);
        expect(media['progress'], 1.0);
        final idleSeedSeconds = number(
          objects(downloads.snapshot()['tasks']).single['seedSeconds'],
        );
        await tester.pump(const Duration(seconds: 3));
        expect(
          number(objects(downloads.snapshot()['tasks']).single['seedSeconds']),
          greaterThan(idleSeedSeconds + 1),
        );
        final file = File('${media['path']}');
        expect(sha1.convert(await file.readAsBytes()), sha1.convert(payload));
        // A real incoming leecher requests a verified piece from the app.
        final leecher = await Socket.connect(
          InternetAddress.loopbackIPv4,
          incomingPort,
        );
        sockets.add(leecher);
        final uploadedPiece = Completer<Uint8List>();
        var incoming = <int>[], receivedHandshake = false, requested = false;
        leecher.listen(
          (chunk) {
            incoming.addAll(chunk);
            if (!receivedHandshake) {
              if (incoming.length < 68) return;
              incoming = incoming.sublist(68);
              receivedHandshake = true;
            }
            while (incoming.length >= 4) {
              final length = ByteData.sublistView(
                Uint8List.fromList(incoming.sublist(0, 4)),
              ).getUint32(0);
              if (incoming.length < length + 4) return;
              final message = incoming.sublist(4, length + 4);
              incoming = incoming.sublist(length + 4);
              if (message.isEmpty) continue;
              if (message[0] == 1 && !requested) {
                requested = true;
                leecher.add([
                  ...integer(13),
                  6,
                  ...integer(0),
                  ...integer(0),
                  ...integer(pieceLength),
                ]);
              } else if (message[0] == 7 && !uploadedPiece.isCompleted) {
                uploadedPiece.complete(Uint8List.fromList(message.sublist(9)));
              }
            }
          },
          onError: (Object e) {
            if (!uploadedPiece.isCompleted) uploadedPiece.completeError(e);
          },
        );
        leecher.add([
          19,
          ...ascii.encode('BitTorrent protocol'),
          ...List.filled(8, 0),
          ...hash,
          ...ascii.encode('-MB0001-098765432109'),
          ...integer(2),
          5,
          0,
          ...integer(1),
          2,
        ]);
        expect(
          await uploadedPiece.future.timeout(const Duration(seconds: 20)),
          payload.sublist(0, pieceLength),
        );
        leecher.destroy();
        await tester.pump(const Duration(seconds: 2));
        expect(
          number(
            objects(downloads.snapshot()['tasks']).single['uploadedBytes'],
          ),
          greaterThanOrEqualTo(pieceLength),
        );
        await store.database.execute(
          "CREATE TRIGGER fail_download_write BEFORE INSERT ON documents WHEN NEW.scope='downloads' BEGIN SELECT RAISE(FAIL, 'disk unavailable'); END",
        );
        await expectLater(
          downloads.pause('${task['id']}'),
          throwsA(isA<Exception>()),
        );
        expect(
          objects(downloads.snapshot()['tasks']).single['persistenceError'],
          isNotNull,
        );
        await store.database.execute('DROP TRIGGER fail_download_write');
        await downloads.resume('${task['id']}');
        expect(
          objects(downloads.snapshot()['tasks']).single['persistenceError'],
          isNull,
        );
        expect(
          (await store.get('downloads', '${task['id']}'))?['manualPaused'],
          false,
        );
        final uploadedBytes = number(
          objects(downloads.snapshot()['tasks']).single['uploadedBytes'],
        );
        await downloads.saveSettings(
          const BitTorrentSettings(seedRatio: 0.25, dht: false, upnp: false),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          objects(downloads.snapshot()['tasks']).single['seedStopReason'],
          'ratio',
        );
        expect(
          LibtorrentFlutter.instance.torrents.values.single.isPaused,
          isTrue,
        );
        expect(
          number(objects(downloads.snapshot()['tasks']).single['seedSeconds']),
          greaterThan(0),
        );
        await downloads.saveSettings(
          const BitTorrentSettings(seedMode: 'off', dht: false, upnp: false),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          objects(downloads.snapshot()['tasks']).single['status'],
          'completed',
        );
        expect(
          LibtorrentFlutter.instance.torrents.values.single.isPaused,
          isTrue,
        );
        expect(LibtorrentFlutter.instance.torrents.values.single.numPeers, 0);
        // Exercise the metadata persistence used by magnets, then restore offline.
        final cachedMetadata =
            '${directory.path}/downloads/metadata/cached.torrent';
        expect(
          LibtorrentFlutter.instance.saveMetadata(
            LibtorrentFlutter.instance.torrents.keys.single,
            cachedMetadata,
          ),
          isTrue,
        );
        await downloads.pause('${task['id']}');
        await downloads.close();
        expect(
          await file.exists(),
          isTrue,
          reason: 'Closing the engine must preserve completed media',
        );
        for (final socket in sockets) {
          socket.destroy();
        }
        await peer.close();
        await tracker.close(force: true);
        await emptyTracker.close(force: true);
        final transferredBeforeRestart = servedBytes;
        final savedTask = (await store.get('downloads', '${task['id']}'))!;
        final seedSeconds = number(savedTask['seedSeconds']);
        await store.put('downloads', '${task['id']}', {
          ...savedTask,
          'kind': 'magnet',
          'input': 'magnet:?xt=urn:btih:$hexHash',
          'metadataPath': cachedMetadata,
        });

        downloads = DownloadRepository(store, '${directory.path}/downloads');
        await downloads.initialize();
        expect(
          sha1.convert(await file.readAsBytes()),
          sha1.convert(payload),
          reason: 'Reattaching must not alter existing file contents',
        );
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (objects(downloads.snapshot()['tasks']).single['status'] ==
              'paused') {
            break;
          }
        }
        expect(
          objects(downloads.snapshot()['tasks']).single['status'],
          'paused',
        );
        expect(downloads.settings.seedMode, 'off');
        expect(
          number(
            objects(downloads.snapshot()['tasks']).single['uploadedBytes'],
          ),
          uploadedBytes,
        );
        expect(
          number(objects(downloads.snapshot()['tasks']).single['seedSeconds']),
          seedSeconds,
        );
        expect(
          LibtorrentFlutter.instance.torrents.values.single.isPaused,
          isTrue,
        );

        await downloads.resume('${task['id']}');
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (objects(downloads.snapshot()['tasks']).single['status'] ==
              'completed') {
            break;
          }
        }
        expect(
          objects(downloads.snapshot()['tasks']).single['status'],
          'completed',
          reason: objects(downloads.snapshot()['tasks']).single.toString(),
        );
        expect(sha1.convert(await file.readAsBytes()), sha1.convert(payload));
        expect(
          servedBytes,
          transferredBeforeRestart,
          reason: 'Restart must reuse verified local pieces without a seeder',
        );
        expect(downloads.media('${task['id']}')['path'], file.path);
        await downloads.saveSettings(
          const BitTorrentSettings(
            seedMode: 'unlimited',
            dht: false,
            upnp: false,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          objects(downloads.snapshot()['tasks']).single['status'],
          'seeding',
        );
        await downloads.stopSeeding('${task['id']}');
        await downloads.saveSettings(
          const BitTorrentSettings(
            seedMode: 'unlimited',
            activeSeeds: 3,
            dht: false,
            upnp: false,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          objects(downloads.snapshot()['tasks']).single['seedStopReason'],
          'manual',
        );
        expect(
          LibtorrentFlutter.instance.torrents.values.single.isPaused,
          isTrue,
        );
        await downloads.close();
        downloads = DownloadRepository(store, '${directory.path}/downloads');
        await downloads.initialize();
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (objects(downloads.snapshot()['tasks']).single['status'] ==
              'completed') {
            break;
          }
        }
        expect(
          objects(downloads.snapshot()['tasks']).single['status'],
          'completed',
        );
        expect(
          LibtorrentFlutter.instance.torrents.values.single.isPaused,
          isTrue,
        );
        expect(LibtorrentFlutter.instance.torrents.values.single.numPeers, 0);
        expect(
          objects(downloads.snapshot()['tasks']).single['seedStopReason'],
          'manual',
        );
        await downloads.resume('${task['id']}');
        await tester.pump(const Duration(seconds: 1));
        expect(
          objects(downloads.snapshot()['tasks']).single['status'],
          'seeding',
        );
        await downloads.stopSeeding('${task['id']}');
        await downloads.close();
        await file.writeAsBytes([
          ...Uint8List(pieceLength),
          ...payload.sublist(pieceLength),
        ], flush: true);
        downloads = DownloadRepository(store, '${directory.path}/downloads');
        await downloads.initialize();
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          current = objects(downloads.snapshot()['tasks']).single;
          if (number(current['progress']) == 0.75) break;
        }
        expect(
          current['progress'],
          0.75,
          reason:
              'Restart must reuse valid pieces and reject the damaged piece',
        );
        expect(downloads.media('${task['id']}')['incomplete'], true);
        expect(downloads.media('${task['id']}')['progress'], .75);
      } finally {
        await downloads.close();
        await store.close();
        for (final socket in sockets) {
          socket.destroy();
        }
        await peer.close();
        await tracker.close(force: true);
        await emptyTracker.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'queue limits, manual pauses and startup policy reach native handles',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-queue-',
      );
      final store = await AppStore.open('${directory.path}/test.sqlite');
      var downloads = DownloadRepository(store, '${directory.path}/downloads');
      try {
        await downloads.initialize();
        await downloads.saveSettings(
          const BitTorrentSettings(activeDownloads: 1, dht: false, upnp: false),
        );
        final tasks = <Json>[];
        for (var i = 0; i < 3; i++) {
          tasks.add(
            await downloads.addTorrent(
              bencode(<String, Object>{
                'info': <String, Object>{
                  'name': 'queued-$i.mkv',
                  'length': 16384,
                  'piece length': 16384,
                  'pieces': Uint8List.fromList(
                    sha1.convert(Uint8List(16384)).bytes,
                  ),
                  'private': 1,
                },
              }),
              'Queued $i',
            ),
          );
        }
        await tester.pump(const Duration(seconds: 2));
        expect(
          LibtorrentFlutter.instance.torrents.values.where((t) => !t.isPaused),
          hasLength(1),
        );
        expect(
          objects(downloads.snapshot()['tasks'])
              .where((t) => t['status'] == 'queued'),
          hasLength(2),
        );
        await downloads.pause('${tasks.first['id']}');
        await tester.pump(const Duration(seconds: 1));
        expect(
          LibtorrentFlutter.instance.torrents.values
              .singleWhere((t) => !t.isPaused)
              .name,
          'queued-1.mkv',
        );
        await downloads.saveSettings(
          const BitTorrentSettings(
            activeDownloads: 0,
            dht: false,
            upnp: false,
            resumeOnStartup: false,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          LibtorrentFlutter.instance.torrents.values.where((t) => !t.isPaused),
          hasLength(2),
        );
        await downloads.close();
        downloads = DownloadRepository(store, '${directory.path}/downloads');
        await downloads.initialize();
        await tester.pump(const Duration(seconds: 2));
        expect(
          objects(downloads.snapshot()['tasks'])
              .every((t) => t['status'] == 'paused'),
          isTrue,
        );
        expect(
          LibtorrentFlutter.instance.torrents.values.every(
            (t) => t.isPaused && t.numPeers == 0,
          ),
          isTrue,
        );
        await downloads.resume('${tasks.last['id']}');
        await tester.pump(const Duration(seconds: 1));
        expect(
          LibtorrentFlutter.instance.torrents.values
              .singleWhere((t) => !t.isPaused)
              .name,
          'queued-2.mkv',
        );
        final metadata = await File('${tasks.last['input']}').readAsBytes();
        final removing = downloads.remove('${tasks.last['id']}');
        final adding = downloads.addTorrent(metadata, 'Readded');
        await removing;
        final replacement = await adding;
        expect(replacement['id'], isNot(tasks.last['id']));
        expect(await File('${replacement['input']}').exists(), isTrue);
        expect(objects(downloads.snapshot()['tasks']), hasLength(3));
        await downloads.close();
        await expectLater(
          downloads.resume('${replacement['id']}'),
          throwsStateError,
        );
      } finally {
        await downloads.close();
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );
  testWidgets('streaming keeps the entire persistent torrent wanted', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'melonbang-stream-priority-',
    );
    final store = await AppStore.open('${directory.path}/test.sqlite');
    final downloads = DownloadRepository(store, '${directory.path}/downloads');
    const length = 40 * 1024 * 1024;
    final metadata = bencode(<String, Object>{
      'info': <String, Object>{
        'name': 'large.mkv',
        'length': length,
        'piece length': 1024 * 1024,
        'pieces': Uint8List(40 * 20),
        'private': 1,
      },
    });
    try {
      await downloads.initialize();
      await downloads.saveSettings(
        const BitTorrentSettings(dht: false, upnp: false, ipv6: false),
      );
      final task = await downloads.addTorrent(metadata, 'Large fixture');
      for (
        var i = 0;
        i < 50 && objects(downloads.snapshot()['files']).isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final media = await downloads.openMedia('${task['id']}');
      expect(media['streamUrl'], startsWith('http://127.0.0.1:'));
      await tester.pump(const Duration(seconds: 2));
      expect(
        objects(downloads.snapshot()['tasks']).single['totalBytes'],
        length,
        reason:
            'Playback must not zero priorities outside its head/tail window',
      );
      downloads.releaseStreamsExcept(null);
    } finally {
      await downloads.close();
      await store.close();
      await directory.delete(recursive: true);
    }
  });
}
