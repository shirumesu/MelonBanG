import 'dart:convert';

import 'package:xml/xml.dart';

import 'downloads.dart';
import 'json.dart';
import 'resource_metadata.dart';
import 'network.dart';

class SourceRepository {
  SourceRepository(this.api, this.downloads);
  final ApiClient api;
  final DownloadRepository downloads;
  final _candidates = <String, Json>{};
  Future<Json> search(
    int subjectId,
    String keyword, {
    int? episodeId,
    Iterable<String> alternativeNames = const [],
    String episodeKeyword = '',
    String? coverUrl,
    void Function(Json)? onUpdate,
    bool Function()? isCurrent,
  }) async {
    final keywords = {keyword.trim(), ...alternativeNames.map((e) => e.trim())}
        .where((e) => e.isNotEmpty)
        .map(
          (e) =>
              [e, episodeKeyword.trim()].where((e) => e.isNotEmpty).join(' '),
        )
        .toList();
    if (keywords.isEmpty) {
      return {'candidates': <Json>[], 'providers': <Json>[]};
    }
    final candidates = <String, Json>{};
    final providers = [
      for (final source in [('dmhy', '动漫花园'), ('mikan', '蜜柑计划')])
        <String, dynamic>{
          'providerId': source.$1,
          'providerName': source.$2,
          'status': 'loading',
          'resultCount': 0,
          'completed': 0,
          'failed': 0,
          'total': keywords.length,
        },
    ];
    bool current() => isCurrent?.call() ?? true;
    Json snapshot() => {
      'candidates': candidates.values
          .map((e) => <String, dynamic>{...e})
          .toList(),
      'providers': providers.map((e) => <String, dynamic>{...e}).toList(),
    };
    void emit() {
      if (current()) onUpdate?.call(snapshot());
    }

    final pages = <Uri, Future<String>>{};
    Future<String> page(Uri uri) => pages.putIfAbsent(
      uri,
      () async => utf8.decode(
        (await api.send(uri, headers: {'Accept': 'text/html'})).bodyBytes,
      ),
    );
    final metadata = <String, Json>{};
    void enrich(String providerId, List<Json> rows) {
      if (!current()) return;
      for (final row in rows) {
        final identity = resourceIdentity(row);
        metadata['$providerId:$identity'] = row;
        final candidate = candidates['$providerId:$identity'];
        if (candidate != null) {
          candidate.addAll({
            for (final field in ['releaseGroups', 'sizeLabel', 'detailUrl'])
              if (row[field] != null) field: row[field],
          });
        }
      }
      emit();
    }

    Future<void> details(Json provider, String name) async {
      if (!current()) return;
      try {
        if (provider['providerId'] == 'dmhy') {
          final uri = Uri.https('share.dmhy.org', '/topics/list', {
            'keyword': name,
          });
          enrich('dmhy', dmhyMetadata(await page(uri), uri));
        } else {
          final uri = Uri.https('mikanani.me', '/Home/Search', {
            'searchstr': name,
          });
          final series = mikanSeriesPages(await page(uri), uri);
          await Future.wait(
            series.map((uri) async {
              if (current()) enrich('mikan', mikanMetadata(await page(uri)));
            }),
          );
        }
      } catch (_) {
        // Optional site metadata must never discard usable RSS downloads.
        if (current()) {
          provider['metadataMessage'] = '部分字幕组信息暂不可用';
          emit();
        }
      }
    }

    emit();
    await Future.wait(
      providers.expand(
        (provider) => keywords.map((name) async {
          if (!current()) return;
          final id = '${provider['providerId']}';
          final uri = id == 'dmhy'
              ? Uri.https('share.dmhy.org', '/topics/rss/rss.xml', {
                  'keyword': name,
                })
              : Uri.https('mikanani.me', '/RSS/Search', {'searchstr': name});
          var succeeded = false;
          try {
            final response = await api.send(
              uri,
              headers: {
                'Accept': 'application/rss+xml,application/xml,text/xml',
              },
            );
            if (!current()) return;
            final rows = parseRss(utf8.decode(response.bodyBytes), base: uri);
            for (final row in rows) {
              final identity = '$id:${resourceIdentity(row)}';
              if (candidates.containsKey(identity)) continue;
              final candidate = <String, dynamic>{
                ...row,
                ...?metadata[identity],
                'candidateId': newId(),
                'providerId': id,
                'providerName': provider['providerName'],
                'subjectId': subjectId,
                'episodeId': episodeId,
                'coverUrl': coverUrl,
              };
              candidates[identity] = candidate;
              _candidates['${candidate['candidateId']}'] = candidate;
            }
            succeeded = true;
          } catch (e) {
            provider['failed'] = (provider['failed'] as int) + 1;
            provider['message'] = '$e';
          } finally {
            provider['completed'] = (provider['completed'] as int) + 1;
            provider['resultCount'] = candidates.values
                .where((e) => e['providerId'] == id)
                .length;
            if (provider['completed'] == provider['total']) {
              provider['status'] = provider['failed'] == 0
                  ? 'ready'
                  : provider['failed'] == provider['total']
                  ? 'error'
                  : 'partial';
            }
            emit();
          }
          if (succeeded) await details(provider, name);
        }),
      ),
    );
    // Preserve active results even if a large alias search exceeds the history cap.
    final activeIds = candidates.values.map((e) => e['candidateId']).toSet();
    for (final id in _candidates.keys.toList()) {
      if (_candidates.length <= 3000) break;
      if (!activeIds.contains(id)) _candidates.remove(id);
    }
    return snapshot();
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
        coverUrl: candidate['coverUrl'] as String?,
      );
    }
    final response = await api.send(Uri.parse(locator));
    return downloads.addTorrent(
      response.bodyBytes,
      '${candidate['title']}',
      subjectId: subjectId,
      episodeId: episodeId,
      coverUrl: candidate['coverUrl'] as String?,
    );
  }
}

List<Json> parseRss(String xml, {required Uri base}) {
  final document = XmlDocument.parse(xml);
  if (document.rootElement.name.local != 'rss') {
    throw const FormatException('资源站未返回有效 RSS');
  }
  final results = <Json>[];
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
    final locator = raw.startsWith('magnet:')
        ? raw
        : base.resolve(raw).toString();
    results.add({
      'title': item.getElement('title')?.innerText.trim() ?? '未命名资源',
      'locator': locator,
      'publishedAt':
          item.getElement('pubDate')?.innerText ??
          item.getElement('torrent')?.getElement('pubDate')?.innerText,
      'sizeBytes': int.tryParse(attachment?.getAttribute('length') ?? ''),
      if (link != null) 'detailUrl': base.resolve(link).toString(),
    });
  }
  return results;
}

bool _isTorrentLocator(String? value) {
  if (value == null) return false;
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'magnet' || uri.path.toLowerCase().endsWith('.torrent'));
}
