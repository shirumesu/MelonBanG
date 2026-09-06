import 'dart:convert';

import 'package:xml/xml.dart';

import 'downloads.dart';
import 'json.dart';
import 'network.dart';

class SourceRepository {
  SourceRepository(this.api, this.downloads);
  final ApiClient api;
  final DownloadRepository downloads;
  final _candidates = <String, Json>{};
  Future<Json> search(int subjectId, String keyword, {int? episodeId}) async {
    final candidates = <Json>[];
    final providers = <Json>[];
    final sources = [
      (
        'dmhy',
        '动漫花园',
        Uri.https('share.dmhy.org', '/topics/rss/rss.xml', {
          'keyword': keyword,
        }),
      ),
      (
        'mikan',
        '蜜柑计划',
        Uri.https('mikanani.me', '/RSS/Search', {'searchstr': keyword}),
      ),
    ];
    await Future.wait(
      sources.map((source) async {
        try {
          final response = await api.send(
            source.$3,
            headers: {'Accept': 'application/rss+xml,application/xml,text/xml'},
          );
          final rows = parseRss(
            utf8.decode(response.bodyBytes),
            base: source.$3,
          );
          for (final row in rows) {
            final id = newId();
            final candidate = {
              ...row,
              'candidateId': id,
              'providerId': source.$1,
              'providerName': source.$2,
              'subjectId': subjectId,
              'episodeId': episodeId,
            };
            _candidates[id] = candidate;
            candidates.add(candidate);
          }
          providers.add({
            'providerName': source.$2,
            'status': 'ready',
            'resultCount': rows.length,
          });
        } catch (e) {
          providers.add({
            'providerName': source.$2,
            'status': 'error',
            'message': e.toString(),
          });
        }
      }),
    );
    return {'candidates': candidates, 'providers': providers};
  }

  Future<Json> enqueue(String id, {int? episodeId}) async {
    final candidate = _candidates[id];
    if (candidate == null) throw StateError('搜索结果已失效，请重新搜索');
    final locator = '${candidate['locator']}';
    final subjectId = candidate['subjectId'] as int;
    episodeId ??= candidate['episodeId'] as int?;
    if (locator.startsWith('magnet:')) {
      return downloads.addMagnet(
        locator,
        subjectId: subjectId,
        episodeId: episodeId,
      );
    }
    final response = await api.send(Uri.parse(locator));
    return downloads.addTorrent(
      response.bodyBytes,
      '${candidate['title']}',
      subjectId: subjectId,
      episodeId: episodeId,
    );
  }
}

List<Json> parseRss(String xml, {required Uri base}) {
  final document = XmlDocument.parse(xml);
  final results = <Json>[];
  for (final item in document.findAllElements('item')) {
    final enclosure = item.getElement('enclosure')?.getAttribute('url');
    final link = item.getElement('link')?.innerText.trim();
    final magnet = RegExp(r'magnet:\?[^\s<>"\x27]+')
        .firstMatch(item.innerText)
        ?.group(0);
    final raw =
        enclosure ??
        magnet ??
        (link?.endsWith('.torrent') == true ? link : null);
    if (raw == null) continue;
    final locator = raw.startsWith('magnet:')
        ? raw
        : base.resolve(raw).toString();
    results.add({
      'title': item.getElement('title')?.innerText.trim() ?? '未命名资源',
      'locator': locator,
      'publishedAt': item.getElement('pubDate')?.innerText,
    });
  }
  return results;
}
