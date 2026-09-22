import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melonbang/data/account.dart';
import 'package:melonbang/data/catalog.dart';
import 'package:melonbang/data/credentials.dart';
import 'package:melonbang/data/danmaku_repository.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/data/playback_library.dart';
import 'package:melonbang/data/sources.dart';
import 'package:melonbang/data/store.dart';
import 'package:melonbang/data/tracking.dart';

import 'support/memory_credentials.dart';
import 'support/service_configuration.dart';

class ControlledDanmaku extends DanmakuRepository {
  ControlledDanmaku(super.api);
  final responses = <String, Completer<List<Json>>>{};
  @override
  Future<List<Json>> bilibili(String locator) => responses[locator]!.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('melonbang-data-');
    store = await AppStore.open('${directory.path}/test.sqlite');
  });
  tearDown(() async {
    if (store.database.isOpen) await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'manual catalogue refresh bypasses cache and reports network failure',
    () async {
      var version = 1, requests = 0;
      var online = true;
      final api = ApiClient(
        client: MockClient((request) async {
          requests++;
          if (!online) return http.Response('', 503);
          final item = {'subjectId': version, 'name': 'Version $version'};
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/today')
                  ? {
                      'items': [item],
                    }
                  : {
                      'data': [item],
                      'hasMore': false,
                    },
            ),
            200,
          );
        }),
      );
      final catalog = CatalogRepository(api, store);
      expect((await catalog.trending()).single['subjectId'], 1);
      await catalog.today();
      version = 2;
      expect((await catalog.trending()).single['subjectId'], 1);
      expect(requests, 2);
      expect((await catalog.trending(refresh: true)).single['subjectId'], 2);
      expect(
        objects((await catalog.today(refresh: true))['items'])
            .single['subjectId'],
        2,
      );
      online = false;
      await expectLater(
        catalog.trending(refresh: true),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        catalog.today(refresh: true),
        throwsA(isA<Exception>()),
      );
      expect((await catalog.trending()).single['subjectId'], 2);
    },
  );

  test(
    'complete details survive search results and unavailable network',
    () async {
      var online = true;
      final api = ApiClient(
        client: MockClient((request) async {
          if (!online) return http.Response('', 503);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/search')
                  ? {
                      'data': [
                        {'subjectId': 42, 'name': 'Short result'},
                      ],
                    }
                  : {
                      'data': {
                        'subjectId': 42,
                        'name': 'Complete',
                        'episodes': [
                          {'episodeId': 7, 'sort': 1, 'name': 'First'},
                        ],
                        'characters': [
                          {'name': 'Character'},
                        ],
                      },
                    },
            ),
            200,
          );
        }),
      );
      final catalog = CatalogRepository(api, store);
      expect(objects((await catalog.subject(42))['episodes']), hasLength(1));
      await catalog.search('Complete');
      online = false;
      final detail = await catalog.subject(42);
      expect(detail['name'], 'Complete');
      expect(objects(detail['characters']), hasLength(1));
      api.close();
    },
  );

  test('pending edits survive restart and overlay remote refresh until acknowledged', () async {
    var online = false;
    final writes = <Json>[];
    final credentials = MemoryCredentials();
    await credentials.write(
      'account',
      jsonEncode({
        'access_token': 'test-token',
        'expiresAt': DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
        'user': {'userId': '1', 'username': 'test'},
      }),
    );
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          if (!online) return http.Response('', 503);
          writes.add(object(jsonDecode(request.body)));
          return http.Response('', 204);
        }
        if (request.url.host == 'api.bgm.tv') {
          return http.Response(
            jsonEncode({
              'total': 1,
              'data': [
                {
                  'subject_id': 42,
                  'type': 1,
                  'subject': {'name': 'Remote'},
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {'subjectId': 42, 'name': 'Local', 'episodes': []},
          }),
          200,
        );
      }),
    );
    final account = AccountRepository(api, credentials);
    await account.initialize();
    var tracking = TrackingRepository(
      store,
      account,
      CatalogRepository(api, store),
    );
    await tracking.setCollection(42, status: CollectionStatus.watching);
    await tracking.flush();
    expect(await store.pending('1'), hasLength(1));
    await tracking.close();
    await store.close();
    store = await AppStore.open('${directory.path}/test.sqlite');
    tracking = TrackingRepository(
      store,
      account,
      CatalogRepository(api, store),
    );
    await tracking.refresh();
    expect((await tracking.collection()).single['status'], 'watching');
    expect(await store.pending('1'), hasLength(1));
    online = true;
    await tracking.flush();
    expect(writes.single, {'type': 3});
    expect(await store.pending('1'), isEmpty);
    await tracking.close();
    await account.close();
    api.close();
  });

  test('signing out cannot send another account queue and local tracking remains usable', () async {
    final api = ApiClient(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': {'subjectId': 42, 'name': 'Local', 'episodes': []},
          }),
          200,
        ),
      ),
    );
    final account = AccountRepository(api, MemoryCredentials());
    await account.initialize();
    await store.enqueue('another-user', 'subject:99', {
      'kind': 'subject',
      'subjectId': 99,
      'status': 'watching',
    });
    final tracking = TrackingRepository(
      store,
      account,
      CatalogRepository(api, store),
    );
    await tracking.setCollection(42, status: CollectionStatus.wish);
    await tracking.setEpisode(42, 7, EpisodeStatus.watched);
    await tracking.flush();
    expect((await tracking.collection()).single['subjectId'], 42);
    expect(await store.pending('another-user'), hasLength(1));
    expect(await store.pending('local'), isEmpty);
    await tracking.close();
    await account.close();
    api.close();
  });

  test(
    'a delayed remote refresh cannot erase a newly acknowledged edit',
    () async {
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      final credentials = MemoryCredentials();
      await credentials.write(
        'account',
        jsonEncode({
          'access_token': 'test-token',
          'expiresAt': DateTime.now()
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
          'user': {'userId': '1', 'username': 'test'},
        }),
      );
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'POST') return http.Response('', 204);
          if (request.url.host == 'api.bgm.tv') {
            requested.complete();
            return response.future;
          }
          return http.Response(
            jsonEncode({
              'data': {'subjectId': 42, 'name': 'Local'},
            }),
            200,
          );
        }),
      );
      final account = AccountRepository(api, credentials);
      await account.initialize();
      final tracking = TrackingRepository(
        store,
        account,
        CatalogRepository(api, store),
      );
      final refresh = tracking.refresh();
      await requested.future;
      await tracking.setCollection(42, status: CollectionStatus.completed);
      await tracking.flush();
      expect(await store.pending('1'), isEmpty);
      response.complete(
        http.Response(jsonEncode({'total': 0, 'data': []}), 200),
      );
      await refresh;
      expect((await tracking.collection()).single['status'], 'completed');
      await tracking.close();
      await account.close();
      api.close();
    },
  );

  test(
    'Windows credentials round trip Unicode without writing plaintext',
    () async {
      final credentials = WindowsCredentials('${directory.path}/credentials');
      const secret = '仅用于测试-token-密钥';
      await credentials.write('account', secret);
      final raw = await File('${directory.path}/credentials/account.bin')
          .readAsBytes();
      expect(utf8.decode(raw, allowMalformed: true), isNot(contains(secret)));
      expect(await credentials.read('account'), secret);
      await credentials.write('account', null);
      expect(await credentials.read('account'), isNull);
    },
    skip: !Platform.isWindows,
  );

  test(
    'late danmaku matches cannot replace the latest selection or new session',
    () async {
      final api = ApiClient();
      final danmaku = ControlledDanmaku(api);
      final downloads = DownloadRepository(
        store,
        '${directory.path}/downloads',
      );
      final library = PlaybackLibrary(
        store,
        downloads,
        danmaku,
        CatalogRepository(api, store),
      );
      final media = await File('${directory.path}/video.mkv').writeAsBytes([0]);
      await library.local(media.path);
      for (final key in ['old', 'latest', 'previous-session']) {
        danmaku.responses[key] = Completer<List<Json>>();
      }
      final old = library.loadSource('bilibili', 'old');
      final latest = library.loadSource('bilibili', 'latest');
      danmaku.responses['latest']!.complete([
        {'timeSeconds': 1, 'text': 'Latest', 'mode': 'scroll'},
      ]);
      await latest;
      danmaku.responses['old']!.complete([
        {'timeSeconds': 1, 'text': 'Old', 'mode': 'scroll'},
      ]);
      await old;
      expect(objects(library.current!['danmaku']).single['text'], 'Latest');
      expect(
        (await store.get(
          'danmaku_matches',
          '${media.path}:bilibili',
        ))!['locator'],
        'latest',
      );
      library.enable('bilibili', false);
      expect(objects(library.current!['danmaku']), isEmpty);
      library.enable('bilibili', true);
      expect(objects(library.current!['danmaku']), hasLength(1));
      final previous = library.loadSource('bilibili', 'previous-session');
      await library.local(media.path);
      danmaku.responses['previous-session']!.complete([
        {'timeSeconds': 1, 'text': 'Previous', 'mode': 'scroll'},
      ]);
      await previous;
      expect(objects(library.current!['danmaku']), isEmpty);
      await library.close();
      await downloads.close();
      api.close();
    },
  );

  test('failed replacement danmaku does not retain comments from the previous episode', () async {
    final api = ApiClient();
    final danmaku = ControlledDanmaku(api);
    final downloads = DownloadRepository(store, '${directory.path}/downloads');
    final library = PlaybackLibrary(
      store,
      downloads,
      danmaku,
      CatalogRepository(api, store),
    );
    final file = await File('${directory.path}/video.mkv').writeAsBytes([0]);
    await library.local(file.path);
    danmaku.responses['old'] = Completer<List<Json>>()
      ..complete([
        {'timeSeconds': 1, 'text': 'Old episode', 'mode': 'scroll'},
      ]);
    await library.loadSource('bilibili', 'old');
    final next = Completer<List<Json>>();
    danmaku.responses['next'] = next;
    final loading = library.loadSource('bilibili', 'next');
    next.completeError(StateError('Provider unavailable'));
    await loading;
    expect(objects(library.current!['danmaku']), isEmpty);
    expect(
      objects(library.current!['danmakuSources'])
          .firstWhere((s) => s['id'] == 'bilibili')['status'],
      'error',
    );
    await library.close();
    await downloads.close();
    api.close();
  });

  test(
    'RSS ignores artwork enclosures and accepts torrent URLs with queries',
    () {
      final results = parseRss(
        '<rss><channel><item><title>Episode</title><enclosure type="image/jpeg" url="cover.jpg"/><link>/file.torrent?token=test</link></item></channel></rss>',
        base: Uri.parse('https://example.com/rss'),
      );
      expect(
        results.single['locator'],
        'https://example.com/file.torrent?token=test',
      );
    },
  );

  test(
    'Bahamut matching uses decoded DOM titles and deduplicates episode links',
    () async {
      final api = ApiClient(
        client: MockClient(
          (request) async => http.Response(
            request.url.path == '/search.php'
                ? '<ul><li><a href="animeRef.php?sn=42"><img alt="A &amp; B"></a><a href="animeRef.php?sn=42">A &amp; B</a></li></ul>'
                : '<section class="season"><p>本篇</p><ul><li><a href="?sn=7&amp;ref=series" data-ani-video-sn="7"><span>1</span></a><a href="?sn=7">1</a></li></ul></section>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );
      expect(
        await DanmakuRepository(
          api,
          configuration: testServiceConfiguration,
        ).automaticLocator('bahamut', 'A & B', 1),
        'sn=7',
      );
      api.close();
    },
  );

  test(
    'RSS enclosures preserve magnets, resolve torrents, and decode titles',
    () {
      final results = parseRss(
        '<rss><channel><item><title>A &amp; B</title><enclosure url="magnet:?xt=urn:btih:123&amp;dn=A"/></item><item><title>Episode</title><enclosure url="/a.torrent"/></item><item><title>Not a download</title><link>https://example.com/page</link></item></channel></rss>',
        base: Uri.parse('https://example.com/feed'),
      );
      expect(results, hasLength(2));
      expect(results.first['title'], 'A & B');
      expect(results.first['locator'], 'magnet:?xt=urn:btih:123&dn=A');
      expect(results.last['locator'], 'https://example.com/a.torrent');
    },
  );

  test(
    'XML danmaku normalizes timing and modes, rejecting unsupported commands',
    () {
      final comments = parseBilibiliXml(
        '<i><d p="2.5,5,25,16777215">Top &amp; text</d><d p="-1,1,25,0">negative</d><d p="1,7,25,0">command</d><d p="1,4,25,255">Bottom</d></i>',
      );
      expect(comments, hasLength(2));
      expect(comments.first, {
        'timeSeconds': 1.0,
        'mode': 'bottom',
        'color': '#0000ff',
        'text': 'Bottom',
      });
      expect(comments.last['text'], 'Top & text');
    },
  );
  test(
    'segmented protobuf comments decode without accepting truncated fields',
    () {
      final segment = Uint8List.fromList([
        10,
        12,
        16,
        0xe8,
        7,
        24,
        1,
        40,
        0xff,
        1,
        58,
        2,
        104,
        105,
      ]);
      expect(parseBilibiliSegment(segment).single, {
        'timeSeconds': 1.0,
        'mode': 'scroll',
        'color': '#0000ff',
        'text': 'hi',
      });
      expect(
        () => parseBilibiliSegment(Uint8List.fromList([10, 12, 16])),
        throwsFormatException,
      );
    },
  );
}
