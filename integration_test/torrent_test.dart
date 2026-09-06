import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/store.dart';

Uint8List bencode(Object value) {
  if (value is int) return Uint8List.fromList(ascii.encode('i${value}e'));
  if (value is String) return bencode(Uint8List.fromList(utf8.encode(value)));
  if (value is Uint8List) {
    return Uint8List.fromList([...ascii.encode('${value.length}:'), ...value]);
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
        'announce': 'http://127.0.0.1:${tracker.port}/announce',
        'info': info,
      });
      final sockets = <Socket>[];
      var servedBytes = 0;
      tracker.listen((request) async {
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
                socket.add([
                  ...integer(count + 9),
                  7,
                  ...integer(index),
                  ...integer(begin),
                  ...payload.sublist(start, start + count),
                ]);
                servedBytes += count;
              }
            }
          },
          onError: (_) {},
          onDone: socket.destroy,
        );
      });
      final store = await AppStore.open('${directory.path}/test.sqlite');
      var downloads = DownloadRepository(store, '${directory.path}/downloads');
      try {
        await downloads.initialize();
        final added = await Future.wait([
          downloads.addTorrent(metadata, 'Fixture'),
          downloads.addTorrent(metadata, 'Fixture'),
        ]).timeout(const Duration(seconds: 10));
        final task = added.first;
        expect(added.last['id'], task['id']);
        expect(objects(downloads.snapshot()['tasks']), hasLength(1));
        LibtorrentFlutter.instance.configureSession(
          const BtConfig(
            disableDht: true,
            disableUpnp: true,
            disableUtp: true,
            enableIpv6: true,
          ),
        );
        Json current = {};
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          current = objects(downloads.snapshot()['tasks']).single;
          if (current['status'] == 'completed') break;
        }
        expect(current['status'], 'completed', reason: current.toString());
        expect(servedBytes, greaterThanOrEqualTo(payload.length));
        final media = downloads.media('${task['id']}');
        final file = File('${media['path']}');
        expect(sha1.convert(await file.readAsBytes()), sha1.convert(payload));
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
        final transferredBeforeRestart = servedBytes;
        downloads = DownloadRepository(store, '${directory.path}/downloads');
        await downloads.initialize();
        expect(
          sha1.convert(await file.readAsBytes()),
          sha1.convert(payload),
          reason: 'Reattaching must not alter existing file contents',
        );
        expect(
          objects(downloads.snapshot()['tasks']).single['status'],
          'paused',
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
        expect(() => downloads.media('${task['id']}'), throwsStateError);
      } finally {
        await downloads.close();
        await store.close();
        for (final socket in sockets) {
          socket.destroy();
        }
        await peer.close();
        await tracker.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}
