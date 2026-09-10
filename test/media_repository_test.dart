import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melonbang/data/catalog.dart';
import 'package:melonbang/data/danmaku_repository.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/data/playback_library.dart';
import 'package:melonbang/data/store.dart';
import 'package:melonbang/data/torrent_identity.dart';

import 'support/memory_credentials.dart';

class _Credentials extends MemoryCredentials {
  _Credentials() {
    values['dandanplay'] = jsonEncode({
      'appId': 'test-app',
      'appSecret': 'test-secret',
    });
  }
}

class _Downloads extends DownloadRepository {
  _Downloads(super.store, super.directory);
  bool verified = true;
  bool removed = false;
  late String mediaPath;
  @override
  bool contains(String id) => id == 'task' && !removed;
  @override
  Json episodeMedia(int subjectId, int episodeId) => {
    'downloadId': 'replacement',
    'id': '0',
  };
  @override
  Json media(String id, {String? fileId}) {
    if (!verified) throw StateError('请等待下载完成后播放');
    return {
      'id': '0',
      'downloadId': id,
      'path': mediaPath,
      'subjectId': 42,
      'episodeId': 7,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('torrent identity ignores metadata and preserves raw info bytes', () {
    final info = Uint8List.fromList([
      ...ascii.encode('d4:name1:x6:pieces3:'),
      0,
      255,
      128,
      101,
    ]);
    final first = Uint8List.fromList([
      ...ascii.encode('d4:info'),
      ...info,
      101,
    ]);
    final second = Uint8List.fromList([
      ...ascii.encode('d7:comment5:other4:info'),
      ...info,
      101,
    ]);
    expect(torrentInfoHash(first), sha1.convert(info).toString());
    expect(torrentInfoHash(second), torrentInfoHash(first));
    expect(
      () => torrentInfoHash(Uint8List.fromList(ascii.encode('d4:info'))),
      throwsFormatException,
    );
  });

  test('magnet identity accepts equivalent hex and base32 hashes after other topics', () {
    const hexadecimal = '0123456789abcdef0123456789abcdef01234567';
    const base32 = 'AERUKZ4JVPG66AJDIVTYTK6N54ASGRLH';
    expect(
      magnetInfoHash(
        Uri.parse('magnet:?xt=urn:sha1:other&xt=urn:btih:$base32'),
      ),
      hexadecimal,
    );
    expect(
      magnetInfoHash(
        Uri.parse('magnet:?xt=urn:btih:${hexadecimal.toUpperCase()}'),
      ),
      hexadecimal,
    );
  });

  test('Dandanplay signs the request path without query parameters', () async {
    var requests = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        requests++;
        expect(request.headers['X-AppId'], 'test-app');
        final timestamp = request.headers['X-Timestamp'];
        expect(int.tryParse(timestamp ?? ''), isNotNull);
        expect(request.url.query, isNotEmpty);
        expect(
          request.headers['X-Signature'],
          base64Encode(
            sha256
                .convert(
                  utf8.encode('test-app$timestamp/api/v2/comment/7test-secret'),
                )
                .bytes,
          ),
        );
        return http.Response(
          jsonEncode({
            'comments': [
              {'p': '1,1,16777215,user', 'm': 'Hello'},
            ],
          }),
          200,
        );
      }),
    );
    final repository = DanmakuRepository(api, _Credentials());
    expect((await repository.dandan(7)).single['text'], 'Hello');
    expect(requests, 1);
    api.close();
  });

  test(
    'Dandanplay logical failures cannot be reported as empty success',
    () async {
      final api = ApiClient(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'success': false, 'errorMessage': 'Quota exceeded'}),
            200,
          ),
        ),
      );
      final repository = DanmakuRepository(api, _Credentials());
      await expectLater(repository.dandan(7), throwsStateError);
      api.close();
    },
  );

  test('comments deduplicate equivalent integer and fractional timestamps', () {
    expect(
      normalizeComments([
        {'timeSeconds': 1, 'mode': 'scroll', 'text': 'Same'},
        {'timeSeconds': 1.0, 'mode': 'scroll', 'text': 'Same'},
      ]),
      hasLength(1),
    );
  });

  test(
    'episode shortcuts revalidate downloaded data instead of trusting its path',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-media-',
      );
      final store = await AppStore.open('${directory.path}/test.sqlite');
      final api = ApiClient();
      final downloads = _Downloads(store, '${directory.path}/downloads');
      downloads.mediaPath = (await File(
        '${directory.path}/video.mkv',
      ).writeAsBytes([0])).path;
      final library = PlaybackLibrary(
        store,
        downloads,
        DanmakuRepository(api, _Credentials()),
        CatalogRepository(api, store),
      );
      try {
        final session = await library.fromDownload('task');
        await library.save(session, 20, 100, false);
        await library.save(session, 0, 0, false);
        expect((await library.progress(42, 7))?['positionSeconds'], 20);
        await library.save(session, 120, 100, false);
        expect((await library.progress(42, 7))?['positionSeconds'], 100);
        expect((await library.episode(42, 7))['episodeId'], 7);
        downloads.verified = false;
        await expectLater(library.episode(42, 7), throwsStateError);
        downloads.verified = true;
        downloads.removed = true;
        expect((await library.episode(42, 7))['episodeId'], 7);
        expect(
          (await store.get('episode_files', '42:7'))?['downloadId'],
          'replacement',
        );
      } finally {
        await library.close();
        await downloads.close();
        api.close();
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
