import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:pinyin/pinyin.dart' show ChineseHelper;
import 'package:xml/xml.dart';

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/danmaku.dart';
import 'matching.dart';

/// iQIYI: automatic matching takes an album of the same title and season,
/// dubs aside; locators are `tvid=…` with the episode's length in seconds,
/// which sets how many five-minute comment files there are. Comments of a
/// whole episode, members-only ones included, are public.
class IqiyiDanmaku implements DanmakuSearch {
  IqiyiDanmaku(this.api);
  final ApiClient api;

  @override
  String get id => 'iqiyi';
  @override
  String get label => '爱奇艺';

  @override
  String get description =>
      '爱奇艺正版番剧的弹幕，自动匹配同名同季的正片，不含配音版；'
      '也可以在播放器的弹幕页搜索。';
  @override
  String? get unconfigured => null;

  @override
  Future<DanmakuMatch> match(DanmakuQuery query) async {
    final episode = await query.episode();
    final titles = searchTitles(episode);
    final wanted = titles.map(seasonedTitle).toSet();
    final albums = <String, _Album>{};
    for (final found in await Future.wait(
      titles.map(ChineseHelper.convertToSimplifiedChinese).toSet().map(_search),
    )) {
      for (final album in found) {
        if (!dubbedTitle.hasMatch(album.title) &&
            wanted.contains(seasonedTitle(album.title))) {
          albums[album.id] = album;
        }
      }
    }
    if (albums.length != 1) return const DanmakuMatch.none('未匹配到爱奇艺番剧');
    final locators = {
      for (final row in await _episodes(albums.values.single))
        if (row.number == episode.number) row.locator,
    };
    return locators.length == 1
        ? DanmakuMatch.found(locators.single)
        : const DanmakuMatch.none('未匹配到爱奇艺章节');
  }

  @override
  Future<List<DanmakuCandidate>> search(String title) async => [
    for (final album in await _search(
      ChineseHelper.convertToSimplifiedChinese(title),
    ))
      DanmakuCandidate(
        title: album.title,
        subtitle: [
          ?album.year,
          if (album.total case final n?) '共 $n 集',
        ].join(' · '),
        open: () async => [
          for (final row in await _episodes(album))
            DanmakuCandidate(title: row.name, locator: row.locator),
        ],
      ),
  ];

  /// The albums, series and films, a search for [query] finds on iQIYI
  /// itself; clips and other sites' entries are left out.
  Future<List<_Album>> _search(String query) async {
    final value = await api.map(
      Uri.https('search.video.iqiyi.com', '/o', {
        'if': 'html5',
        'key': query,
        'pageNum': '1',
        'pageSize': '20',
      }),
    );
    return [
      for (final doc in objects(object(value['data'])['docinfos']))
        if (object(doc['albumDocInfo']) case final album
            when album['videoDocType'] == 1 &&
                album['siteId'] == 'iqiyi' &&
                RegExp(r'^(动漫|电影)').hasMatch('${album['channel']}') &&
                positiveId(album['albumId']) != null)
          _Album(
            id: '${album['albumId']}',
            title: '${album['albumTitle']}'.trim(),
            film: '${album['albumLink']}'.contains('/v_'),
            total: positiveId(album['itemTotalNumber']),
            year: RegExp(r'^\d{4}').firstMatch('${album['releaseDate']}')?[0],
          ),
    ];
  }

  /// [album]'s main episodes, a film being its one video.
  Future<List<({double? number, String name, String locator})>> _episodes(
    _Album album,
  ) async {
    if (album.film) {
      return [(number: 1, name: album.title, locator: 'tvid=${album.id}')];
    }
    final rows = <({double? number, String name, String locator})>[];
    for (var page = 1; page <= 20; page++) {
      final data = object(
        (await api.map(
          Uri.https('pcw-api.iqiyi.com', '/albums/album/avlistinfo', {
            'aid': album.id,
            'page': '$page',
            'size': '200',
          }),
        ))['data'],
      );
      for (final item in objects(data['epsodelist'])) {
        if (item['contentType'] != 1 || positiveId(item['tvId']) == null) {
          continue;
        }
        final seconds = _seconds('${item['duration'] ?? ''}');
        rows.add((
          number: switch (item['order']) {
            final num order => order.toDouble(),
            _ => null,
          },
          name: '${item['name'] ?? '第 ${item['order']} 集'}',
          locator: [
            'tvid=${item['tvId']}',
            if (seconds != null) 'duration=$seconds',
          ].join('&'),
        ));
      }
      if (data['hasMore'] != true) break;
    }
    return rows;
  }

  @override
  Future<List<DanmakuComment>> load(String locator) async {
    final fields = Uri.splitQueryString(locator);
    final tvid = positiveId(fields['tvid'] ?? locator);
    if (tvid == null) throw const FormatException('请输入爱奇艺的 tvid');
    final seconds = int.tryParse(fields['duration'] ?? '');
    // One file per five minutes; without a known length, read on until one
    // is missing.
    Future<String?> part(int index) async {
      final response = await api.send(
        Uri.https(
          'cmts.iqiyi.com',
          '/bullet/${tvid.substring(tvid.length - 4, tvid.length - 2)}'
              '/${tvid.substring(tvid.length - 2)}/${tvid}_300_$index.z',
        ),
        acceptedStatuses: const {404},
      );
      if (response.statusCode == 404) return null;
      return utf8.decode(zlib.decode(response.bodyBytes), allowMalformed: true);
    }

    final parts = <String?>[];
    if (seconds != null) {
      parts.addAll(
        await Future.wait([
          for (var index = 1; index <= (seconds / 300).ceil(); index++)
            part(index),
        ]),
      );
    } else {
      for (var index = 1; index <= 40; index++) {
        final text = await part(index);
        if (text == null) break;
        parts.add(text);
      }
    }
    final texts = parts.nonNulls.toList();
    return compute(_comments, texts);
  }
}

/// The comments of [texts], bullet files.
List<DanmakuComment> _comments(List<String> texts) =>
    sortedComments(texts.expand(_parse));

/// A bullet file's comments.
Iterable<DanmakuComment?> _parse(String text) sync* {
  final document = XmlDocument.parse(text);
  for (final bullet in document.findAllElements('bulletInfo')) {
    String field(String name) =>
        bullet.getElement(name)?.innerText.trim() ?? '';
    yield DanmakuComment.parse(
      source: 'iqiyi',
      time: double.tryParse(field('showTime')),
      text: field('content'),
      color: hexColor('#${field('color')}'),
      mode: DanmakuMode.scroll,
    );
  }
}

/// `24:09` or `1:02:03` in seconds.
int? _seconds(String text) {
  final parts = text.split(':').map(int.tryParse).toList();
  if (parts.isEmpty || parts.length > 3 || parts.contains(null)) return null;
  return parts.fold<int>(0, (total, part) => total * 60 + part!);
}

class _Album {
  const _Album({
    required this.id,
    required this.title,
    required this.film,
    this.total,
    this.year,
  });
  final String id, title;

  /// A single video, whose album id is its tvid.
  final bool film;
  final String? total, year;
}
