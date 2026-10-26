import 'dart:convert';
import 'dart:isolate';

import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../../domain/torrent_identity.dart';

/// Torrent index sites read through RSS search feeds. An optional `metadata`
/// step names a known page parser that adds release groups and sizes.
class RssEngine implements TorrentSourceEngine {
  RssEngine(this.api, this.instance);
  final ApiClient api;
  @override
  final SourceInstance instance;
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
    final response = await api.send(
      uri,
      cancel: cancel,
      headers: {
        'Accept': accept,
        ...object(step['headers']).map((k, v) => MapEntry(k, '$v')),
      },
    );
    return utf8.decode(response.bodyBytes);
  }

  @override
  Future<List<TorrentRelease>> search(
    String keyword, {
    RequestCancellation? cancel,
  }) async {
    final step = object(instance.config['search']);
    final uri = _address(step, keyword);
    return _releases(
      _rss,
      await _read(
        uri,
        step,
        'application/rss+xml,application/xml,text/xml',
        cancel: cancel,
      ),
      uri,
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
        yield await _releases(dmhyMetadata, await page(uri), uri);
      case 'mikan':
        final series = await _parse(mikanSeriesPages, await page(uri), uri);
        // Publish each series as it arrives. Its page names the groups but
        // shows a group's latest 15 releases; its feed holds every release,
        // while the search feed stops at 100 (2026-10-21: a whole-subject
        // search of 二十世纪电气目录 lost a group's first two episodes).
        yield* Stream.fromFutures(
          series.map((address) async {
            final feed = address.resolve(
              '/RSS/Bangumi?bangumiId=${address.pathSegments.last}',
            );
            final listed = page(address)
                .then((body) => _releases(_mikan, body, address));
            final complete = shared
                .putIfAbsent(
                  feed,
                  () => _read(
                    feed,
                    step,
                    'application/rss+xml,application/xml,text/xml',
                    cancel: cancel,
                  ),
                )
                .then((body) => _releases(_rss, body, feed));
            final groups = {
              for (final row in await listed) torrentIdentity(row.locator): row,
            };
            return [
              for (final row in await complete)
                switch (groups[torrentIdentity(row.locator)]) {
                  final known? => row.enrich(known),
                  null => row,
                },
            ];
          }),
        );
      default:
        throw FormatException('不支持的资源页解析：${step['parser']}');
    }
  }
}

/// Parses a feed or page off the UI isolate: a whole-subject search reads
/// many large ones at once. [parse] must be a top-level function, so the
/// closure carries nothing but the text.
Future<T> _parse<T>(T Function(String, Uri) parse, String body, Uri base) =>
    Isolate.run(() => parse(body, base));

/// Parses releases like [_parse], along with what a search works out from
/// each: its identity and title annotations, which the UI isolate then only
/// looks up. Working them out there stalled it for a page of releases.
Future<List<TorrentRelease>> _releases(
  List<TorrentRelease> Function(String, Uri) parse,
  String body,
  Uri base,
) async {
  final (rows, identities, described) = await Isolate.run(() {
    final rows = parse(body, base);
    return (
      rows,
      torrentIdentities(rows.map((row) => row.locator)),
      describeReleases(rows),
    );
  });
  keepIdentities(identities);
  keepDescribed(described);
  return rows;
}

List<TorrentRelease> _rss(String body, Uri base) => parseRss(body, base: base);
List<TorrentRelease> _mikan(String body, Uri _) => mikanMetadata(body);

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
