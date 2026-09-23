import 'dart:async';
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

import 'support/service_configuration.dart';

http.Response jsonResponse(Object value) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), 200);

const searchPage = '''
<div class="theme-list-block">
<a href="animeRef.php?sn=42" class="theme-list-main">
  <img alt="葬送的芙莉蓮"><p class="theme-name">葬送的芙莉蓮</p>
  <p>1741萬</p><span>共28集</span>
</a>
<a href="animeRef.php?sn=43"><p class="theme-name">葬送的芙莉蓮 第二季</p></a>
</div>''';
const seasonPage = '''
<a href="animeVideo.php?sn=999">1</a>
<section class="season">
<p>本篇</p><ul>
<li><a href="?sn=7" data-ani-video-sn="7">1</a></li>
<li><a href="?sn=8" data-ani-video-sn="8">2</a></li>
<li><a href="?sn=9" data-ani-video-sn="9">PV 3</a></li>
</ul>
<p>中文配音</p><ul><li><a href="?sn=107">1</a></li></ul>
<p>特別篇</p><ul><li><a href="?sn=207">1</a></li></ul>
</section>''';

class EpisodeDownload extends DownloadRepository {
  EpisodeDownload(super.store, super.directory);
  late String path;
  @override
  Json media(String id, {String? fileId}) => {
    'id': fileId ?? '0',
    'path': path,
    'subjectId': 42,
    'episodeId': null,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('melonbang-match-');
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'file match hashes only 16 MiB and sends filename, size and duration',
    () async {
      final bytes = Uint8List(16 * 1024 * 1024 + 10)..last = 99;
      final file = await File('${directory.path}/Episode 01.mkv')
          .writeAsBytes(bytes);
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v2/match');
          expect(jsonDecode(request.body), {
            'fileName': 'Episode 01',
            'fileHash': md5.convert(Uint8List(16 * 1024 * 1024)).toString(),
            'fileSize': bytes.length,
            'videoDuration': 1501,
            'matchMode': 'hashAndFileName',
          });
          return jsonResponse({
            'success': true,
            'isMatched': true,
            'matches': [
              {'episodeId': 7},
            ],
          });
        }),
      );
      addTearDown(api.close);
      expect(
        (await DanmakuRepository(
          api,
          configuration: testServiceConfiguration,
        ).matchFile(file.path, 1500.8)).episodeId,
        7,
      );
    },
  );

  test(
    'file suggestions remain unmatched; API failures remain errors',
    () async {
      final file = await File('${directory.path}/clip.mkv')
          .writeAsBytes([1, 2, 3]);
      var response = <String, dynamic>{
        'success': true,
        'isMatched': false,
        'matches': [
          {'episodeId': 7},
        ],
      };
      final api = ApiClient(
        client: MockClient((_) async => jsonResponse(response)),
      );
      addTearDown(api.close);
      final repository = DanmakuRepository(
        api,
        configuration: testServiceConfiguration,
      );
      expect((await repository.matchFile(file.path, 0)).episodeId, isNull);
      response = {
        'success': true,
        'isMatched': true,
        'matches': [
          {'episodeId': 7},
          {'episodeId': 8},
        ],
      };
      expect((await repository.matchFile(file.path, 0)).episodeId, isNull);
      response = {'success': false, 'errorMessage': 'Quota exceeded'};
      await expectLater(repository.matchFile(file.path, 0), throwsStateError);
    },
  );

  test('incomplete playback maps Bangumi episodes then falls back without reading bytes', () async {
    var mapped = true;
    var titleMatch = false;
    var ambiguous = false;
    final paths = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        paths.add(request.url.path);
        switch (request.url.path) {
          case '/v1/subjects/42':
            return jsonResponse({
              'data': {
                'nameCn': 'Show',
                'episodes': [
                  {'episodeId': 91, 'ep': 2},
                ],
              },
            });
          case '/api/v2/bangumi/bgmtv/42':
            if (!mapped) return http.Response('', 404);
            return jsonResponse({
              'success': true,
              'bangumi': {
                'animeTitle': 'Mapped show',
                'episodes': [
                  {'episodeId': 701, 'episodeNumber': '1'},
                  {
                    'episodeId': 702,
                    'episodeNumber': '2',
                    'episodeTitle': 'Second',
                  },
                  {'episodeId': 799, 'episodeNumber': 'S2'},
                ],
              },
            });
          case '/api/v2/search/episodes':
            expect(request.url.queryParameters['anime'], 'Show');
            expect(request.url.queryParameters['episode'], '2');
            return jsonResponse({
              'success': true,
              'animes': titleMatch
                  ? [
                      {
                        'animeTitle': 'Show',
                        'episodes': [
                          {'episodeId': 702, 'episodeTitle': '第2话 Second'},
                        ],
                      },
                    ]
                  : [],
            });
          case '/api/v2/match':
            expect(jsonDecode(request.body), {
              'fileName': 'Show - 02',
              'fileSize': 500000000,
              'videoDuration': 0,
              'matchMode': 'fileNameOnly',
            });
            return jsonResponse({
              'success': true,
              'isMatched': !ambiguous,
              'matches': [
                {
                  'episodeId': 702,
                  'animeTitle': 'Mapped show',
                  'episodeTitle': 'Second',
                },
                if (ambiguous)
                  {
                    'episodeId': 802,
                    'animeTitle': 'Other season',
                    'episodeTitle': 'Second',
                  },
              ],
            });
          case '/api/v2/comment/702':
            return jsonResponse({
              'success': true,
              'comments': [
                {'p': '1,1,16777215,user', 'm': 'Stream comment'},
              ],
            });
          default:
            throw StateError('Unexpected request: ${request.url.path}');
        }
      }),
    );
    final store = await AppStore.open('${directory.path}/stream.sqlite');
    final downloads = DownloadRepository(store, '${directory.path}/downloads');
    final library = PlaybackLibrary(
      store,
      downloads,
      DanmakuRepository(api, configuration: testServiceConfiguration),
      CatalogRepository(api, store),
    );
    addTearDown(() async {
      await library.close();
      await downloads.close();
      api.close();
      await store.close();
    });
    final session = await library.local(
      '${directory.path}/Show - 02.mkv',
      streamUrl: 'http://127.0.0.1/video',
      streamId: 1,
      subjectId: 42,
      episodeId: 91,
    );
    session['fileSize'] = 500000000;
    library.enable('bilibili', false);
    library.enable('bahamut', false);
    await library.autoMatch(0);
    expect(
      objects(library.current!['danmaku']).single['text'],
      'Stream comment',
    );
    expect(paths, contains('/api/v2/comment/702'));
    expect(paths, isNot(contains('/api/v2/match')));

    mapped = false;
    titleMatch = true;
    paths.clear();
    await library.autoMatch(0);
    expect(paths, contains('/api/v2/search/episodes'));
    expect(paths, isNot(contains('/api/v2/match')));
    expect(objects(library.current!['danmaku']), hasLength(1));

    titleMatch = false;
    paths.clear();
    await library.autoMatch(0);
    expect(paths, contains('/api/v2/match'));
    expect(objects(library.current!['danmaku']), hasLength(1));

    ambiguous = true;
    paths.clear();
    await library.autoMatch(0);
    final source = objects(library.current!['danmakuSources']).first;
    expect(source['status'], 'unmatched');
    expect(objects(source['candidates']), hasLength(2));
    expect(paths, isNot(contains('/api/v2/comment/702')));
    expect(objects(library.current!['danmaku']), isEmpty);
    await library.selectEpisode(702);
    paths.clear();
    await library.autoMatch(0);
    expect(paths, ['/api/v2/comment/702']);
    expect(
      objects(objects(library.current!['danmakuSources']).first['candidates']),
      isEmpty,
    );
  });

  test(
    'mapped repeated episode numbers stay ambiguous and specials do not match',
    () async {
      var number = '2';
      final api = ApiClient(
        client: MockClient(
          (_) async => jsonResponse({
            'success': true,
            'bangumi': {
              'episodes': [
                {'episodeId': 7, 'episodeNumber': number},
                {'episodeId': 8, 'episodeNumber': number},
              ],
            },
          }),
        ),
      );
      addTearDown(api.close);
      final repository = DanmakuRepository(
        api,
        configuration: testServiceConfiguration,
      );
      final result = await repository.matchBangumi(42, 2);
      expect(result.episodeId, isNull);
      expect(result.candidates, hasLength(2));
      number = 'S2';
      expect((await repository.matchBangumi(42, 2)).candidates, isEmpty);
    },
  );

  test('title search does not automatically select a different season or ambiguous release', () async {
    var wrongSeason = true;
    final api = ApiClient(
      client: MockClient(
        (request) async => jsonResponse({
          'success': true,
          'animes': [
            {
              'animeTitle': wrongSeason ? 'Show Season 2' : 'Show',
              'episodes': [
                {'episodeId': 7, 'episodeTitle': '第2话 Second'},
                if (!wrongSeason)
                  {'episodeId': 8, 'episodeTitle': '第2话 Dubbed'},
              ],
            },
          ],
        }),
      ),
    );
    addTearDown(api.close);
    final repository = DanmakuRepository(
      api,
      configuration: testServiceConfiguration,
    );
    expect((await repository.matchTitles(['Show'], 2)).episodeId, isNull);
    wrongSeason = false;
    final result = await repository.matchTitles(['Show'], 2);
    expect(result.episodeId, isNull);
    expect(result.candidates, hasLength(2));
  });

  test(
    'Bahamut matches traditional card titles and main episode query links',
    () async {
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/search.php') {
            expect(request.url.queryParameters['keyword'], '葬送的芙莉蓮');
            expect(request.method, 'GET');
            return http.Response(
              searchPage,
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          expect(request.url.queryParameters['sn'], '42');
          return http.Response(
            seasonPage,
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      final repository = DanmakuRepository(
        api,
        configuration: testServiceConfiguration,
      );
      expect(await repository.automaticLocator('bahamut', '葬送的芙莉莲', 1), 'sn=7');
      expect(await repository.automaticLocator('bahamut', '葬送的芙莉莲', 3), isNull);
      expect(
        await repository.automaticLocator('bahamut', '葬送的芙莉莲', 30),
        isNull,
      );
    },
  );

  test(
    'Bahamut ambiguous titles never choose the first card or a sibling title',
    () async {
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/search.php');
          return http.Response(
            '$searchPage<a href="animeRef.php?sn=44"><img alt="葬送的芙莉蓮"></a>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      expect(
        await DanmakuRepository(
          api,
          configuration: testServiceConfiguration,
        ).automaticLocator('bahamut', '葬送的芙莉莲', 1),
        isNull,
      );
    },
  );

  test(
    'Bilibili searches official bangumi aliases and selects a main episode',
    () async {
      final queries = <String>[];
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.contains('/search/')) {
            expect(request.url.queryParameters['search_type'], 'media_bangumi');
            queries.add(request.url.queryParameters['keyword']!);
            return jsonResponse({
              'code': 0,
              'data': {
                'result': [
                  {
                    'season_id': 42,
                    'title': '<em class="keyword">作品</em> &amp; A',
                  },
                  {'season_id': 43, 'title': '作品 &amp; A 第二季'},
                ],
              },
            });
          }
          expect(request.url.path, '/pgc/view/web/season');
          expect(request.url.queryParameters['season_id'], '42');
          return jsonResponse({
            'code': 0,
            'result': {
              'episodes': [
                {'id': 7, 'title': '第1话'},
                {'id': 8, 'title': 'PV 2'},
              ],
              'section': [
                {
                  'episodes': [
                    {'id': 99, 'title': '1'},
                  ],
                },
              ],
            },
          });
        }),
      );
      addTearDown(api.close);
      final repository = DanmakuRepository(
        api,
        configuration: testServiceConfiguration,
      );
      expect(
        await repository.automaticLocator(
          'bilibili',
          '别名',
          1,
          alternativeTitles: ['作品 & A'],
        ),
        'ep7',
      );
      expect(queries, ['别名', '作品 & A']);
      expect(
        await repository.automaticLocator('bilibili', '作品 & A', 2),
        isNull,
      );
    },
  );

  test(
    'Bilibili missing or ambiguous official results never search user uploads',
    () async {
      var data = <String, dynamic>{'numResults': 0};
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.url.queryParameters['search_type'], 'media_bangumi');
          return jsonResponse({'code': 0, 'data': data});
        }),
      );
      addTearDown(api.close);
      final repository = DanmakuRepository(
        api,
        configuration: testServiceConfiguration,
      );
      expect(await repository.automaticLocator('bilibili', '作品', 1), isNull);
      data = {
        'result': [
          {'season_id': 1, 'title': '作品'},
          {'season_id': 2, 'title': '作品'},
        ],
      };
      expect(await repository.automaticLocator('bilibili', '作品', 1), isNull);
      data = {'v_voucher': 'challenge'};
      await expectLater(
        repository.automaticLocator('bilibili', '作品', 1),
        throwsStateError,
      );
    },
  );

  test('autoMatch merges independent sources and keeps misses empty', () async {
    var dandanplayUnavailable = false;
    final paths = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        paths.add(request.url.path);
        switch (request.url.path) {
          case '/api/v2/match':
            if (dandanplayUnavailable) throw StateError('Provider unavailable');
            return jsonResponse({
              'success': true,
              'isMatched': true,
              'matches': [
                {'episodeId': 7},
              ],
            });
          case '/api/v2/comment/7':
            return jsonResponse({
              'success': true,
              'comments': [
                {'p': '1,1,16777215,user', 'm': 'Dandan'},
              ],
            });
          case '/v1/subjects/42':
            return jsonResponse({
              'data': {
                'nameCn': '葬送的芙莉莲',
                'episodes': [
                  {'episodeId': 7, 'ep': 1},
                ],
              },
            });
          case '/x/web-interface/search/type':
            return jsonResponse({
              'code': 0,
              'data': {'numResults': 0},
            });
          case '/search.php':
            return http.Response(
              searchPage,
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          case '/animeRef.php':
            return http.Response(
              seasonPage,
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          case '/ajax/danmuGet.php':
            expect(request.bodyFields['sn'], '7');
            return jsonResponse([
              {
                'time': 20,
                'text': 'Bahamut',
                'position': 0,
                'color': '#ffffff',
              },
            ]);
          default:
            throw StateError('Unexpected request ${request.url}');
        }
      }),
    );
    final store = await AppStore.open('${directory.path}/test.sqlite');
    final downloads = DownloadRepository(store, '${directory.path}/downloads');
    final library = PlaybackLibrary(
      store,
      downloads,
      DanmakuRepository(api, configuration: testServiceConfiguration),
      CatalogRepository(api, store),
    );
    addTearDown(() async {
      await library.close();
      await downloads.close();
      api.close();
      await store.close();
    });
    final file = await File('${directory.path}/episode.mkv').writeAsBytes([1]);
    await library.local(file.path, subjectId: 42, episodeId: 7);
    await library.autoMatch(1500);
    expect(objects(library.current!['danmaku']).map((c) => c['text']), [
      'Dandan',
      'Bahamut',
    ]);
    expect(
      objects(library.current!['danmakuSources']).map((s) => s['status']),
      ['ready', 'unmatched', 'ready'],
    );
    expect(paths.where((p) => p == '/v1/subjects/42'), hasLength(1));
    dandanplayUnavailable = true;
    await library.autoMatch(1500);
    expect(objects(library.current!['danmaku']).single['text'], 'Bahamut');
    expect(
      objects(library.current!['danmakuSources']).map((s) => s['status']),
      ['error', 'unmatched', 'ready'],
    );
    dandanplayUnavailable = false;
    final oldId = library.current!['id'] as String;
    await library.local(file.path);
    paths.clear();
    await library.autoMatch(1500, sessionId: oldId);
    expect(paths, isEmpty);
    library.enable('dandanplay', false);
    await library.autoMatch(1500);
    expect(paths, isEmpty);
    library.enable('dandanplay', true);
    await library.autoMatch(1500);
    expect(paths, ['/api/v2/match', '/api/v2/comment/7']);
    expect(
      objects(library.current!['danmakuSources']).map((s) => s['status']),
      ['ready', 'unmatched', 'unmatched'],
    );
  });

  test('download filename resolves danmaku episode without creating a file association', () async {
    var searches = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/v1/subjects/42':
            return jsonResponse({
              'data': {
                'nameCn': '葬送的芙莉莲',
                'episodes': [
                  {'episodeId': 7, 'ep': 1},
                  {'episodeId': 8, 'ep': 2},
                ],
              },
            });
          case '/search.php':
            searches++;
            return http.Response.bytes(utf8.encode(searchPage), 200);
          case '/animeRef.php':
            return http.Response.bytes(utf8.encode(seasonPage), 200);
          case '/ajax/danmuGet.php':
            expect(request.bodyFields['sn'], '7');
            return jsonResponse([
              {'time': 10, 'text': 'First episode', 'position': 0},
            ]);
          default:
            throw StateError('Unexpected request ${request.url}');
        }
      }),
    );
    final store = await AppStore.open('${directory.path}/test.sqlite');
    final downloads = EpisodeDownload(store, '${directory.path}/downloads');
    final library = PlaybackLibrary(
      store,
      downloads,
      DanmakuRepository(api, configuration: testServiceConfiguration),
      CatalogRepository(api, store),
    );
    addTearDown(() async {
      await library.close();
      await downloads.close();
      api.close();
      await store.close();
    });
    Future<void> open(String name) async {
      downloads.path = (await File('${directory.path}/$name').writeAsBytes([1]))
          .path;
      await library.fromDownload('task', fileId: '0');
      library.enable('dandanplay', false);
      library.enable('bilibili', false);
      await library.autoMatch(100);
    }

    await open('[Group] Series - 01 [WebRip 1080p HEVC-10bit AAC ASSx2].mkv');
    expect(
      objects(library.current!['danmaku']).single['text'],
      'First episode',
    );
    expect(library.current!['episodeId'], isNull);
    expect(await store.get('episode_files', '42:7'), isNull);
    expect(searches, 1);
    await open('[Group] Series - 01v2 [1080p].mkv');
    expect(objects(library.current!['danmaku']), hasLength(1));
    for (final name in [
      'Series 1080p.mkv',
      'Series - 01-02.mkv',
      'Series - 99.mkv',
    ]) {
      final before = searches;
      await open(name);
      expect(objects(library.current!['danmaku']), isEmpty);
      expect(searches, before);
      final source = objects(library.current!['danmakuSources']).last;
      expect(source['status'], 'unmatched');
      expect(source['statusMessage'], isNotEmpty);
    }
  });

  test(
    'saved manual choice wins over late automatic match and is reused',
    () async {
      final matching = Completer<http.Response>();
      final started = Completer<void>();
      var matchRequests = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/v2/match') {
            matchRequests++;
            started.complete();
            return matching.future;
          }
          return jsonResponse({
            'success': true,
            'comments': [
              {'p': '1,1,16777215,user', 'm': request.url.path},
            ],
          });
        }),
      );
      final store = await AppStore.open('${directory.path}/test.sqlite');
      final downloads = DownloadRepository(
        store,
        '${directory.path}/downloads',
      );
      final library = PlaybackLibrary(
        store,
        downloads,
        DanmakuRepository(api, configuration: testServiceConfiguration),
        CatalogRepository(api, store),
      );
      addTearDown(() async {
        await library.close();
        await downloads.close();
        api.close();
        await store.close();
      });
      final file = await File('${directory.path}/episode.mkv')
          .writeAsBytes([1]);
      await library.local(file.path);
      final automatic = library.autoMatch(1);
      await started.future;
      await library.selectEpisode(8);
      matching.complete(
        jsonResponse({
          'success': true,
          'isMatched': true,
          'matches': [
            {'episodeId': 7},
          ],
        }),
      );
      await automatic;
      expect(
        objects(library.current!['danmaku']).single['text'],
        '/api/v2/comment/8',
      );
      await library.autoMatch(1);
      expect(matchRequests, 1);
      expect(
        objects(library.current!['danmaku']).single['text'],
        '/api/v2/comment/8',
      );
    },
  );
}
