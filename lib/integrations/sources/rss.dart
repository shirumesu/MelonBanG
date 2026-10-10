import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/sources.dart';

/// Torrent index sites read through RSS search feeds. An optional `metadata`
/// step names a known page parser that adds release groups and sizes.
class RssEngine implements TorrentSourceEngine {
  RssEngine(this.api, this.instance);
  final ApiClient api;
  @override
  final SourceInstance instance;
  @override
  Uri? lastRequest;
  @override
  int? lastStatus;
  @override
  String get currentBase => instance.baseUrls.first;
  Json get _metadata => object(instance.config['metadata']);

  Uri _address(Json step, String keyword) => Uri.parse(currentBase).resolve(
    '${step['url']}'.replaceAll('{query}', Uri.encodeQueryComponent(keyword)),
  );

  Future<String> _read(
    Uri uri,
    Json step,
    String accept, {
    RequestCancellation? cancel,
  }) async {
    lastRequest = uri;
    lastStatus = null;
    final response = await api.send(
      uri,
      cancel: cancel,
      headers: {
        'Accept': accept,
        ...object(step['headers']).map((k, v) => MapEntry(k, '$v')),
      },
    );
    lastStatus = response.statusCode;
    return utf8.decode(response.bodyBytes);
  }

  @override
  Future<List<TorrentRelease>> search(
    String keyword, {
    RequestCancellation? cancel,
  }) async {
    final step = object(instance.config['search']);
    final uri = _address(step, keyword);
    return parseRss(
      await _read(
        uri,
        step,
        'application/rss+xml,application/xml,text/xml',
        cancel: cancel,
      ),
      base: uri,
    );
  }

  @override
  Stream<List<TorrentRelease>> metadata(
    String keyword, {
    Map<Uri, Future<String>>? pages,
    RequestCancellation? cancel,
  }) async* {
    final step = _metadata;
    if (step.isEmpty) return;
    final shared = pages ?? {};
    Future<String> page(Uri uri) => shared.putIfAbsent(
      uri,
      () => _read(uri, step, 'text/html', cancel: cancel),
    );
    final uri = _address(step, keyword);
    switch (step['parser']) {
      case 'dmhy':
        yield dmhyMetadata(await page(uri), uri);
      case 'mikan':
        final series = mikanSeriesPages(await page(uri), uri);
        // Publish each series page as it arrives.
        yield* Stream.fromFutures(
          series.map((address) async => mikanMetadata(await page(address))),
        );
      default:
        throw FormatException('不支持的资源页解析：${step['parser']}');
    }
  }
}

List<TorrentRelease> parseRss(String xml, {required Uri base}) {
  final document = XmlDocument.parse(xml);
  if (document.rootElement.name.local != 'rss') {
    throw const FormatException('资源站未返回有效 RSS');
  }
  final results = <TorrentRelease>[];
  for (final item in document.findAllElements('item')) {
    final attachment = item.getElement('enclosure');
    final enclosure = attachment?.getAttribute('url')?.trim();
    final link = item.getElement('link')?.innerText.trim();
    final magnet = RegExp(r'magnet:\?[^\s<>"\x27]+')
        .firstMatch(item.innerText)
        ?.group(0);
    final raw =
        (_isTorrentLocator(enclosure) ||
                attachment?.getAttribute('type') == 'application/x-bittorrent'
            ? enclosure
            : null) ??
        magnet ??
        (_isTorrentLocator(link) ? link : null);
    if (raw == null) continue;
    results.add(
      TorrentRelease(
        title: item.getElement('title')?.innerText.trim() ?? '未命名资源',
        locator: raw.startsWith('magnet:') ? raw : base.resolve(raw).toString(),
        publishedAt:
            item.getElement('pubDate')?.innerText ??
            item.getElement('torrent')?.getElement('pubDate')?.innerText,
        sizeBytes: int.tryParse(attachment?.getAttribute('length') ?? ''),
        detailUrl: link == null ? null : base.resolve(link).toString(),
      ),
    );
  }
  return results;
}

bool _isTorrentLocator(String? value) {
  if (value == null) return false;
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'magnet' || uri.path.toLowerCase().endsWith('.torrent'));
}

List<TorrentRelease> dmhyMetadata(String body, Uri base) {
  final document = html.parse(body);
  final result = <TorrentRelease>[];
  for (final row in document.querySelectorAll('#topic_list tbody tr')) {
    final title = row.querySelector('td.title a[href*="/topics/view/"]');
    final magnet = row.querySelector('a[href^="magnet:"]')?.attributes['href'];
    if (title == null || magnet == null) continue;
    final cells = row.querySelectorAll('td');
    result.add(
      TorrentRelease(
        title: title.text.trim(),
        locator: magnet,
        releaseGroups: row
            .querySelectorAll('td.title a[href*="/team_id/"]')
            .map((e) => e.text.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(),
        sizeLabel: cells.length > 4 ? cells[4].text.trim() : null,
        detailUrl: base.resolve(title.attributes['href']!).toString(),
      ),
    );
  }
  return result;
}

List<Uri> mikanSeriesPages(String body, Uri base) => html
    .parse(body)
    .querySelectorAll('.an-ul a[href^="/Home/Bangumi/"]')
    .map((e) => base.resolve(e.attributes['href']!))
    .toSet()
    .toList();

List<TorrentRelease> mikanMetadata(String body) {
  final document = html.parse(body);
  final result = <TorrentRelease>[];
  for (final group in document.querySelectorAll('.subgroup-text')) {
    final name = group
        .querySelector('a[href^="/Home/PublishGroup/"]')
        ?.text
        .trim();
    final table = group.nextElementSibling;
    if (name == null ||
        name.isEmpty ||
        table == null ||
        !table.classes.contains('episode-table')) {
      continue;
    }
    for (final row in table.querySelectorAll('tbody tr')) {
      final title = row.querySelector('a[href^="/Home/Episode/"]');
      final locator =
          row.querySelector('[data-magnet]')?.attributes['data-magnet'] ??
          row.querySelector('a[href^="magnet:"]')?.attributes['href'];
      if (title == null || locator == null) continue;
      result.add(
        TorrentRelease(
          title: title.text.trim(),
          locator: locator,
          releaseGroups: [name],
        ),
      );
    }
  }
  return result;
}
