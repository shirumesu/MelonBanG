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

  /// The mirror that answered last; the first one until then.
  String? _base;
  @override
  String get currentBase => _base ?? instance.baseUrls.firstOrNull ?? '';
  Json get _metadata => object(instance.config['metadata']);

  Uri _address(Json step, String keyword, [String? base]) =>
      Uri.parse(base ?? currentBase).resolve(
        '${step['url']}'.replaceAll(
          '{query}',
          Uri.encodeQueryComponent(keyword),
        ),
      );

  /// [uri]'s text, or with [end] only up to where it matches.
  Future<String> _read(
    Uri uri,
    Json step,
    String accept, {
    Pattern? end,
    RequestCancellation? cancel,
  }) async {
    final headers = {
      'Accept': accept,
      ...object(step['headers']).map((k, v) => MapEntry(k, '$v')),
    };
    if (end != null) {
      return api.head(uri, end, headers: headers, cancel: cancel);
    }
    final response = await api.send(uri, cancel: cancel, headers: headers);
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  @override
  Future<List<TorrentRelease>> search(
    String keyword, {
    RequestCancellation? cancel,
  }) async {
    final step = object(instance.config['search']);
    // A mirror that fails or answers with something else than a feed (a
    // challenge page) hands over to the next; the last failure is reported.
    Object? failure;
    for (final base in {?_base, ...instance.baseUrls}) {
      final uri = _address(step, keyword, base);
      try {
        final releases = await _releases(
          _rss,
          await _read(
            uri,
            step,
            'application/rss+xml,application/xml,text/xml',
            cancel: cancel,
          ),
          uri,
        );
        _base = base;
        return releases;
      } catch (error) {
        cancel?.throwIfCancelled();
        failure = error;
      }
    }
    throw failure ?? const FormatException('资源站未返回有效 RSS');
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
    Future<String> page(Uri uri, {Pattern? end}) => shared.putIfAbsent(
      uri,
      () => _read(uri, step, 'text/html', end: end, cancel: cancel),
    );
    Future<String> feed(Uri uri) => shared.putIfAbsent(
      uri,
      () => _read(
        uri,
        step,
        'application/rss+xml,application/xml,text/xml',
        cancel: cancel,
      ),
    );
    final uri = _address(step, keyword);
    switch (step['parser']) {
      case 'dmhy':
        yield await _releases(dmhyMetadata, await page(uri), uri);
      case 'mikan':
        // Mikan's pages are large and the site can be slow (2026-10-27: about
        // 10 KB/s, a search page of 530 KB and a series page of 370 KB, past
        // the request timeout). The series list and a series' group list sit
        // in their first 15 KB, so only that is read; each group's feed then
        // holds all its releases, past the search feed's 100 (2026-10-21: a
        // whole-subject search of 二十世纪电气目录 lost a group's first two
        // episodes). Each series publishes as it arrives, and one that fails
        // keeps none of the others from arriving; the first failure is
        // reported once they all have.
        final series = await _parse(
          mikanSeriesPages,
          await page(uri, end: RegExp(r'an-ul[\s\S]*?</ul>')),
          uri,
        );
        Object? failure;
        Future<List<TorrentRelease>> tolerate(
          Future<List<TorrentRelease>> read,
        ) => read.catchError((Object error) {
          cancel?.throwIfCancelled();
          failure ??= error;
          return const <TorrentRelease>[];
        });
        yield* Stream.fromFutures(
          series.map(
            (address) => tolerate(() async {
              final groups = await _parse(
                mikanGroups,
                await page(address, end: RegExp(r'leftbar-nav[\s\S]*?</ul>')),
                address,
              );
              final bangumi = address.pathSegments.last;
              final releases = await Future.wait([
                for (final (group, name) in groups)
                  tolerate(
                    feed(
                      address.resolve(
                        '/RSS/Bangumi?bangumiId=$bangumi&subgroupid=$group',
                      ),
                    ).then((body) => _releases(_credited(name), body, address)),
                  ),
              ]);
              return releases.expand((rows) => rows).toList();
            }()),
          ),
        );
        if (failure case final error?) throw error;
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

/// Parses a Mikan group feed, crediting its releases to [group]; the
/// closure carries only the name.
List<TorrentRelease> Function(String, Uri) _credited(String? group) =>
    (body, base) => [
      for (final row in parseRss(body, base: base))
        group == null
            ? row
            : row.enrich(
                TorrentRelease(
                  title: row.title,
                  locator: row.locator,
                  releaseGroups: [group],
                ),
              ),
    ];

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
    String? field(String name) => item.childElements
        .where((e) => e.name.local == name)
        .firstOrNull
        ?.innerText
        .trim();
    // Nyaa names its .torrent files by number and states the info hash
    // apart; as a magnet the release merges with other sites' copies.
    final hash = field('infoHash');
    final raw =
        (_isTorrentLocator(enclosure) ||
                attachment?.getAttribute('type') == 'application/x-bittorrent'
            ? enclosure
            : null) ??
        magnet ??
        (_isTorrentLocator(link) ? link : null);
    if (raw == null) continue;
    final locator = raw.startsWith('magnet:')
        ? raw
        : hash != null && RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(hash)
        ? 'magnet:?xt=urn:btih:${hash.toLowerCase()}'
        : switch (Uri.tryParse(raw)) {
            final uri? => base.resolveUri(uri).toString(),
            null => null,
          };
    if (locator == null) continue;
    results.add(
      TorrentRelease(
        title: item.getElement('title')?.innerText.trim() ?? '未命名资源',
        locator: locator,
        publishedAt:
            item.getElement('pubDate')?.innerText ??
            item.getElement('torrent')?.getElement('pubDate')?.innerText,
        sizeBytes: int.tryParse(attachment?.getAttribute('length') ?? ''),
        sizeLabel: field('size'),
        detailUrl: _webPage(base, link),
      ),
    );
  }
  return results;
}

/// [link] resolved against [base] when it is a web page: release pages
/// open in the browser, and a feed's link may be anything.
String? _webPage(Uri base, String? link) {
  final uri = link == null ? null : Uri.tryParse(link);
  if (uri == null) return null;
  final page = base.resolveUri(uri);
  return (page.isScheme('http') || page.isScheme('https')) &&
          page.host.isNotEmpty
      ? page.toString()
      : null;
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
        detailUrl: _webPage(base, title.attributes['href']),
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

/// A Mikan series page's groups as (id, name), from the list at its top.
/// The name is null for 202, 生肉/不明字幕, where Mikan files releases of no
/// known group.
List<(String, String?)> mikanGroups(String body, Uri _) => [
  for (final link
      in html
          .parse(body)
          .querySelectorAll('.leftbar-nav a.subgroup-name[data-anchor]'))
    if (link.attributes['data-anchor']!.replaceFirst('#', '') case final id
        when id.isNotEmpty)
      (id, id == '202' ? null : link.text.trim()),
];
