import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/pikpak.dart';
import 'package:melonbang/data/pikpak_downloads.dart';
import 'package:melonbang/data/store.dart';
import 'package:path/path.dart' as p;

import 'support/memory_credentials.dart';

const _magnet =
    'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Example';

class _PikPak extends PikPakClient {
  _PikPak() : super(MemoryCredentials());
  String? owner = 'account-a';
  String address = 'https://cdn.example/original';
  String? originalAddress;
  String phase = 'PHASE_TYPE_COMPLETE';
  int additions = 0, urlRequests = 0, polls = 0;
  Completer<void>? createGate, fileGate;
  List<Json> leaves = [
    {
      'id': 'video',
      'name': 'episode.mkv',
      'size': '8',
      'mime_type': 'video/x-matroska',
    },
  ];
  @override
  bool get isSignedIn => owner != null;
  @override
  String? get userId => owner;
  @override
  Future<Json> offlineDownload(String magnet) async {
    additions++;
    await createGate?.future;
    return {
      'task': {'id': 'cloud-task', 'file_id': 'folder'},
    };
  }

  @override
  Future<Json> task(String id) async {
    polls++;
    return {
      'id': id,
      'phase': phase,
      'progress': phase == 'PHASE_TYPE_COMPLETE' ? 100 : 40,
      'file_id': 'folder',
    };
  }

  @override
  Future<List<Json>> files(String rootId) async => leaves;
  @override
  Future<Json> file(String id) async {
    urlRequests++;
    await fileGate?.future;
    return {
      'id': id,
      'web_content_link': '$address?signature=$urlRequests',
      if (originalAddress != null)
        'links': {
          'application/octet-stream': {'url': originalAddress},
        },
    };
  }
}

class _RealHttp extends HttpOverrides {}

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for cache state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Json _task(PikPakDownloadRepository cache, String id) =>
    objects(cache.snapshot()['tasks']).singleWhere((task) => task['id'] == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late AppStore store;
  late _PikPak api;
  late PikPakDownloadRepository cache;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('melonbang-pikpak-test-');
    store = await AppStore.open(p.join(temporary.path, 'app.sqlite'));
    api = _PikPak();
    cache = PikPakDownloadRepository(
      store,
      p.join(temporary.path, 'downloads'),
      api,
      transferClient: MockClient(
        (request) async => http.Response.bytes(utf8.encode('12345678'), 200),
      ),
      pollInterval: const Duration(milliseconds: 20),
    );
    await cache.initialize();
  });

  tearDown(() async {
    if (api.createGate?.isCompleted == false) api.createGate!.complete();
    if (api.fileGate?.isCompleted == false) api.fileGate!.complete();
    await cache.close();
    await store.close();
    await temporary.delete(recursive: true);
  });

  test('cloud acquisition caches exact original bytes and survives restart without login', () async {
    final created = await Future.wait([
      cache.addMagnet(_magnet, subjectId: 42, episodeId: 7),
      cache.addMagnet(_magnet),
    ]);
    expect(created[0]['id'], created[1]['id']);
    final id = '${created.first['id']}';
    await _until(() => _task(cache, id)['complete'] == true);
    expect(api.additions, 1);
    final media = await cache.openMedia(id);
    expect(await File('${media['path']}').readAsString(), '12345678');
    expect(media['incomplete'], false);
    expect(media['episodeId'], 7);
    expect(await File('${media['path']}.part').exists(), false);
    final stored = jsonEncode(await store.list('pikpak_downloads'));
    expect(stored, isNot(contains('signature=')));
    expect(stored, isNot(contains('cdn.example')));
    await cache.close();
    api.owner = null;
    cache = PikPakDownloadRepository(
      store,
      p.join(temporary.path, 'downloads'),
      api,
    );
    await cache.initialize();
    final restored = await cache.openMedia(id);
    expect(restored['id'], media['id']);
    expect(restored['path'], media['path']);
    expect(restored['streamUrl'], isNull);
    expect(cache.episodeMedia(42, 7)['downloadId'], id);
  });

  test('real HTTP transfer pauses, resumes with Range, and publishes only complete files', () async {
    await cache.close();
    final bytes = List<int>.generate(512 * 1024, (index) => index % 251);
    api.leaves.single['size'] = '${bytes.length}';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.address = 'http://127.0.0.1:${server.port}/original';
    final releaseFirst = Completer<void>();
    final ranges = <String?>[];
    final handlers = <Future<void>>[];
    server.listen((request) {
      handlers.add(() async {
        try {
          final range = request.headers.value('range');
          ranges.add(range);
          final offset = range == null
              ? 0
              : int.parse(range.substring(6, range.length - 1));
          request.response.contentLength = bytes.length - offset;
          if (range != null) {
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(
              'Content-Range',
              'bytes $offset-${bytes.length - 1}/${bytes.length}',
            );
          }
          if (ranges.length == 1) {
            request.response.add(bytes.sublist(0, 128 * 1024));
            await request.response.flush();
            await releaseFirst.future;
          } else {
            request.response.add(bytes.sublist(offset));
          }
          await request.response.close();
        } on HttpException {
          // Pausing deliberately aborts the first connection.
        } on SocketException {
          // Pausing deliberately aborts the first connection.
        }
      }());
    });
    addTearDown(() async {
      if (!releaseFirst.isCompleted) releaseFirst.complete();
      await server.close(force: true);
      await Future.wait(handlers);
    });
    cache = PikPakDownloadRepository(
      store,
      p.join(temporary.path, 'downloads'),
      api,
      transferClient: IOClient(_RealHttp().createHttpClient(null)),
    );
    await cache.initialize();
    final task = await cache.addMagnet(_magnet);
    final id = '${task['id']}';
    await _until(() => objects(cache.snapshot()['files']).isNotEmpty);
    final media = cache.media(id);
    final partial = File('${media['path']}.part');
    await _until(() => partial.existsSync() && partial.lengthSync() > 0);
    expect(File('${media['path']}').existsSync(), false);
    await cache.pause(id);
    final offset = await partial.length();
    expect(offset, greaterThan(0));
    expect(offset, lessThan(bytes.length));
    releaseFirst.complete();
    await cache.close();
    cache = PikPakDownloadRepository(
      store,
      p.join(temporary.path, 'downloads'),
      api,
      transferClient: IOClient(_RealHttp().createHttpClient(null)),
    );
    await cache.initialize();
    expect(_task(cache, id)['manualPaused'], true);
    await cache.resume(id);
    await _until(() => _task(cache, id)['complete'] == true);
    expect(ranges, [null, 'bytes=$offset-']);
    expect(await File('${media['path']}').readAsBytes(), bytes);
    expect(await partial.exists(), false);
    expect(api.additions, 1);
  });

  test('multiple videos require explicit file selection and keep episode association unset', () async {
    api.leaves = [
      {'id': 'a', 'name': 'episode1.mkv', 'size': '8'},
      {'id': 'b', 'name': 'episode2.mkv', 'size': '8'},
    ];
    final task = await cache.addMagnet(_magnet, subjectId: 42, episodeId: 7);
    final id = '${task['id']}';
    await _until(() => _task(cache, id)['complete'] == true);
    expect(() => cache.media(id), throwsStateError);
    expect(cache.media(id, fileId: 'b')['episodeId'], isNull);
    expect(cache.media(id, fileId: 'b')['subjectId'], 42);
    expect(cache.media(id, fileId: 'b')['name'], 'episode2.mkv');
  });

  test(
    'unfinished playback refreshes original URL and enforces owning account',
    () async {
      api.fileGate = Completer<void>();
      final task = await cache.addMagnet(_magnet);
      final id = '${task['id']}';
      await _until(() => api.urlRequests > 0);
      final pausing = cache.pause(id);
      api.fileGate!.complete();
      await pausing;
      api.fileGate = null;
      api.owner = 'account-b';
      await cache.accountChanged();
      expect(() => cache.media(id), throwsStateError);
      await expectLater(cache.resume(id), throwsStateError);
      api.owner = 'account-a';
      final selected = await cache.openMedia(id);
      expect(
        selected['streamUrl'],
        startsWith('https://cdn.example/original?signature='),
      );
      expect(selected['sourceHeaders'], {'Accept': 'application/octet-stream'});
    },
  );

  test(
    'invalid HTTP resume range never becomes a completed local file',
    () async {
      await cache.close();
      cache = PikPakDownloadRepository(
        store,
        p.join(temporary.path, 'downloads'),
        api,
        transferClient: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode('12345678'),
            206,
            headers: {'content-range': 'bytes 2-9/10'},
          ),
        ),
      );
      await cache.initialize();
      final task = await cache.addMagnet(_magnet);
      final id = '${task['id']}';
      await _until(() => _task(cache, id)['status'] == 'failed');
      expect(_task(cache, id)['complete'], false);
      expect(File('${cache.media(id)['path']}').existsSync(), false);
    },
  );

  test(
    'removing an in-flight cloud request cannot resurrect its local task',
    () async {
      api.createGate = Completer<void>();
      final task = await cache.addMagnet(_magnet);
      final id = '${task['id']}';
      await _until(() => api.additions == 1);
      final removing = cache.remove(id);
      api.createGate!.complete();
      api.createGate = null;
      await removing;
      expect(cache.contains(id), false);
      expect(await store.list('pikpak_downloads'), isEmpty);
      final replacement = await cache.addMagnet(_magnet);
      expect(replacement['id'], isNot(id));
      await _until(
        () => _task(cache, '${replacement['id']}')['complete'] == true,
      );
    },
  );

  test(
    'pausing cloud acquisition preserves the cloud job for resume',
    () async {
      api.createGate = Completer<void>();
      final task = await cache.addMagnet(_magnet);
      final id = '${task['id']}';
      await _until(() => api.additions == 1);
      final pausing = cache.pause(id);
      api.createGate!.complete();
      api.createGate = null;
      await pausing;
      expect(_task(cache, id)['cloudTaskId'], 'cloud-task');
      await cache.resume(id);
      await _until(() => _task(cache, id)['complete'] == true);
      expect(api.additions, 1);
    },
  );

  test(
    'unknown file sizes are downloaded and verified using HTTP content length',
    () async {
      api.leaves.single.remove('size');
      final task = await cache.addMagnet(_magnet);
      final id = '${task['id']}';
      await _until(() => _task(cache, id)['complete'] == true);
      final media = cache.media(id);
      expect(media['size'], 8);
      expect(await File('${media['path']}').readAsString(), '12345678');
      expect(api.urlRequests, greaterThan(0));
    },
  );

  test('a failed cloud acquisition can retry with a new cloud job', () async {
    api.phase = 'PHASE_TYPE_RUNNING';
    final task = await cache.addMagnet(_magnet);
    final id = '${task['id']}';
    await _until(() => api.polls > 0);
    final locked = Completer<void>(), release = Completer<void>();
    final saving = store.database.transaction((transaction) async {
      locked.complete();
      await release.future;
    });
    await locked.future;
    try {
      api.phase = 'PHASE_TYPE_ERROR';
      await _until(() => _task(cache, id)['status'] == 'failed');
      api.phase = 'PHASE_TYPE_COMPLETE';
      final retrying = cache.resume(id);
      release.complete();
      await retrying;
    } finally {
      if (!release.isCompleted) release.complete();
      await saving;
    }
    await _until(() => _task(cache, id)['complete'] == true);
    expect(api.additions, 2);
    await cache.resume(id);
    expect(_task(cache, id)['status'], 'completed');
  });

  test('empty files remain complete after a restart', () async {
    api.leaves.single['size'] = '0';
    final task = await cache.addMagnet(_magnet);
    final id = '${task['id']}';
    await _until(() => _task(cache, id)['complete'] == true);
    expect(await File('${cache.media(id)['path']}').length(), 0);
    await cache.close();
    cache = PikPakDownloadRepository(
      store,
      p.join(temporary.path, 'downloads'),
      api,
    );
    await cache.initialize();
    expect(_task(cache, id)['progress'], 1.0);
    expect(cache.media(id)['progress'], 1.0);
  });

  test(
    'original octet-stream links take precedence for caching and playback',
    () async {
      await cache.close();
      api.originalAddress = 'https://cdn.example/octets?signature=fresh';
      final requested = <Uri>[];
      cache = PikPakDownloadRepository(
        store,
        p.join(temporary.path, 'downloads'),
        api,
        transferClient: MockClient((request) async {
          requested.add(request.url);
          return http.Response.bytes(utf8.encode('12345678'), 200);
        }),
      );
      await cache.initialize();
      api.fileGate = Completer<void>();
      final task = await cache.addMagnet(_magnet);
      final id = '${task['id']}';
      await _until(() => api.urlRequests > 0);
      final pausing = cache.pause(id);
      api.fileGate!.complete();
      await pausing;
      api.fileGate = null;
      expect((await cache.openMedia(id))['streamUrl'], api.originalAddress);
      await _until(() => _task(cache, id)['complete'] == true);
      expect(requested.single.toString(), api.originalAddress);
      expect(
        jsonEncode(await store.list('pikpak_downloads')),
        isNot(contains('signature=')),
      );
    },
  );
}
