import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/data/resource_metadata.dart';
import 'package:melonbang/data/sources.dart';
import 'package:melonbang/data/store.dart';

class QueueDownloads extends DownloadRepository {
  QueueDownloads(super.store, super.directory);
  Json? queued;
  @override
  Future<Json> addMagnet(
    String input, {
    int? subjectId,
    int? episodeId,
    String? coverUrl,
  }) async => queued = {
    'input': input,
    'subjectId': subjectId,
    'episodeId': episodeId,
    'coverUrl': coverUrl,
  };
}

const hash = '0123456789012345678901234567890123456789';
String rss(String title) =>
    '<rss><channel><item><title>$title</title><enclosure length="1024" url="magnet:?xt=urn:btih:$hash"/></item></channel></rss>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('aliases use catalogue names and preserve compound release groups from site DOM', () {
    expect(
      resourceNames({
        'nameCn': '中文名',
        'name': '日本語',
        'aliases': ['中文名', 'Alias'],
        'infobox': [
          {
            'key': '别名',
            'value': [
              {'v': 'Another'},
            ],
          },
        ],
      }),
      ['中文名', '日本語', 'Alias', 'Another'],
    );
    final rows = dmhyMetadata(
      '''<table id="topic_list"><tbody><tr><td>date</td><td>Anime</td><td class="title"><a href="/topics/list/team_id/7">A &amp; B</a><a href="/topics/view/42.html">[A &amp; B] Show [01]</a></td><td><a href="magnet:?xt=urn:btih:$hash">M</a></td><td>400MB</td></tr></tbody></table>''',
      Uri.parse('https://share.dmhy.org/'),
    );
    expect(rows.single['releaseGroups'], ['A & B']);
    final mikan = mikanMetadata(
      '''<div class="subgroup-text"><a href="/Home/PublishGroup/7">A &amp; B</a></div><div class="episode-table"><table><tbody><tr><td><input data-magnet="magnet:?xt=urn:btih:$hash"></td><td><a href="/Home/Episode/$hash">Title</a></td></tr></tbody></table></div><div class="subgroup-text"><a href="/Home/PublishGroup/8">Other</a></div><div class="episode-table"></div>''',
    );
    expect(mikan.single['releaseGroups'], ['A & B']);
    expect(
      resourceIdentity({
        'locator': 'https://mikanani.me/Download/$hash.torrent',
      }),
      hash,
    );
  });

  test('first alias is downloadable while other searches and metadata wait; IDs remain stable', () async {
    final directory = await Directory.systemTemp.createTemp('resource-test');
    final store = await AppStore.open('${directory.path}/test.sqlite');
    final slow = Completer<http.Response>(),
        metadata = Completer<http.Response>();
    final first = Completer<void>();
    final updates = <Json>[];
    final queries = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        final name = request.url.queryParameters.values.first;
        if (!request.url.path.contains('RSS') &&
            !request.url.path.contains('/rss/')) {
          return metadata.future;
        }
        queries.add(name);
        if (name == '日本語 01') return slow.future;
        return http.Response(
          rss('中文资源'),
          200,
          headers: {'content-type': 'application/xml; charset=utf-8'},
        );
      }),
    );
    final downloads = QueueDownloads(store, directory.path);
    final source = SourceRepository(api, downloads);
    final searching = source.search(
      42,
      '中文',
      alternativeNames: ['日本語', '中文'],
      episodeKeyword: '01',
      episodeId: 9,
      coverUrl: 'https://example.org/poster.jpg',
      onUpdate: (state) {
        updates.add(state);
        if (objects(state['candidates']).isNotEmpty && !first.isCompleted) {
          first.complete();
        }
      },
    );
    await first.future;
    final candidate = objects(updates.last['candidates']).first;
    await source.enqueue(candidate['candidateId']);
    expect(downloads.queued?['subjectId'], 42);
    expect(downloads.queued?['episodeId'], 9);
    expect(downloads.queued?['coverUrl'], 'https://example.org/poster.jpg');
    expect(slow.isCompleted, isFalse);
    slow.complete(http.Response(rss('Same hash through alias'), 200));
    metadata.complete(http.Response('<html></html>', 200));
    final finalState = await searching;
    expect(queries.where((q) => q == '中文 01'), hasLength(2));
    expect(
      objects(finalState['candidates']),
      hasLength(2),
    ); // One per provider, regardless of alias.
    expect(
      objects(finalState['candidates']).first['candidateId'],
      candidate['candidateId'],
    );
    expect(
      objects(finalState['providers']).every((e) => e['status'] == 'ready'),
      isTrue,
    );
    api.close();
    await downloads.close();
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'one failed name retains results; cancelled contexts stop publishing',
    () async {
      final directory = await Directory.systemTemp.createTemp('resource-test');
      final store = await AppStore.open('${directory.path}/test.sqlite');
      final api = ApiClient(
        client: MockClient(
          (request) async => request.url.queryParameters.values.first == 'bad'
              ? http.Response('', 503)
              : http.Response(
                  request.url.path.contains('RSS') ||
                          request.url.path.contains('/rss/')
                      ? rss('Available')
                      : '<html></html>',
                  200,
                ),
        ),
      );
      final source = SourceRepository(
        api,
        QueueDownloads(store, directory.path),
      );
      final result = await source.search(42, 'good', alternativeNames: ['bad']);
      expect(objects(result['candidates']), hasLength(2));
      expect(
        objects(result['providers']).every((e) => e['status'] == 'partial'),
        isTrue,
      );
      var count = 0;
      await source.search(
        42,
        'good',
        isCurrent: () => false,
        onUpdate: (_) => count++,
      );
      expect(count, 0);
      api.close();
      await store.close();
      await directory.delete(recursive: true);
    },
  );
}
