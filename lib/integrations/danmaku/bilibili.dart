import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:pinyin/pinyin.dart' show ChineseHelper;
import 'package:protobuf/protobuf.dart';
import 'package:xml/xml.dart';

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/danmaku.dart';
import '../../domain/sources.dart';
import '../sources/bilibili.dart';
import 'matching.dart';

/// Bilibili: automatic matching takes official `media_bangumi` matches
/// only; manual search is the resource search's, over official seasons and
/// uploads. Locators are EP ids or BV ids with their part as `p`.
class BilibiliDanmaku implements DanmakuSearch, DanmakuFollower {
  BilibiliDanmaku(this.api)
    : _engine = BilibiliEngine(
        api,
        SourceInstance(
          id: 'bilibili-danmaku',
          name: 'Bilibili',
          engine: 'bilibili-web',
          kind: SourceKind.online,
          baseUrls: ['https://api.bilibili.com'],
          website: 'https://www.bilibili.com',
          config: {},
        ),
      );
  final ApiClient api;
  final BilibiliEngine _engine;

  @override
  String get id => 'bilibili';
  @override
  String get label => 'Bilibili';

  @override
  String get description =>
      '自动匹配番剧区的官方条目；也可以在播放器的弹幕页搜索番剧、投稿视频和合集，'
      '或粘贴 EP、BV 号和播放链接。';
  @override
  String? get unconfigured => null;

  @override
  Future<DanmakuMatch> match(DanmakuQuery query) async {
    final episode = await query.episode();
    final locator = await _locator(episode);
    return locator == null
        ? const DanmakuMatch.none('未匹配到官方番剧或章节')
        : DanmakuMatch.found(locator);
  }

  Future<String?> _locator(DanmakuEpisode episode) async {
    final titles = searchTitles(episode);
    if (titles.isEmpty) return null;
    final normalizedTitles = titles.map(normalizedTitle).toSet();
    final candidates = <String>{};
    // Search refuses requests without a browser agent and guest cookie.
    await _engine.guest(null);
    for (final query
        in titles.map(ChineseHelper.convertToSimplifiedChinese).toSet()) {
      final result = await _engine.request('/x/web-interface/search/type', {
        'search_type': 'media_bangumi',
        'keyword': query,
      });
      final data = object(result['data']);
      if (data['result'] is! List && data['numResults'] != 0) {
        throw StateError('Bilibili 番剧搜索暂不可用');
      }
      for (final item in objects(data['result'])) {
        if (normalizedTitles.contains(normalizedTitle('${item['title']}'))) {
          final id = positiveId(item['season_id']);
          if (id != null) candidates.add(id);
        }
      }
    }
    if (candidates.length != 1) return null;
    final season = await _engine.request('/pgc/view/web/season', {
      'season_id': candidates.single,
    });
    if (season['result'] is! Map) throw StateError('Bilibili 番剧详情暂不可用');
    final episodes = objects(object(season['result'])['episodes'])
        .where((item) => episodeNumber('${item['title']}') == episode.number)
        .map((item) => positiveId(item['id']))
        .whereType<String>()
        .toSet();
    return episodes.length == 1 ? 'ep${episodes.single}' : null;
  }

  @override
  Future<List<DanmakuCandidate>> search(String title) async => [
    for (final subject in await _engine.searchSubjects(
      ChineseHelper.convertToSimplifiedChinese(title),
    ))
      DanmakuCandidate(
        title: subject.title,
        subtitle: [
          subject.line,
          ?subject.year?.toString(),
          if (subject.episodeTotal case final total?) '$total 话',
          ?subject.description,
        ].join(' · '),
        open: subject.choosePart
            ? () => _video(subject.id)
            : () async => [
                for (final episode in await _engine.episodes(subject))
                  DanmakuCandidate(
                    title: episode.label,
                    locator: 'ep${episode.ref.data['epId']}',
                  ),
              ],
      ),
  ];

  /// An upload's parts, then the collection it belongs to.
  Future<List<DanmakuCandidate>> _video(String bvid) async {
    await _engine.guest(null);
    final value = await _engine.request('/x/web-interface/view', {
      'bvid': bvid,
    });
    final data = object(value['data']);
    final collection = object(data['ugc_season']);
    return [
      ..._parts(data),
      if (collection.isNotEmpty)
        DanmakuCandidate(
          title: '所属合集 · ${collection['title']}',
          subtitle: '${collection['ep_count']} 个视频',
          open: () async => _collection(collection),
        ),
    ];
  }

  /// A collection's videos, under its sections when it has several; a
  /// multi-part video opens to its parts.
  List<DanmakuCandidate> _collection(Json collection) {
    List<DanmakuCandidate> videos(Json section) => [
      for (final video in objects(section['episodes']))
        if (objects(video['pages']).length > 1)
          DanmakuCandidate(
            title: '${video['title']}',
            subtitle: '${objects(video['pages']).length} P',
            open: () async => _parts(video),
          )
        else
          ..._parts(video),
    ];
    final sections = objects(collection['sections']);
    return sections.length == 1
        ? videos(sections.single)
        : [
            for (final section in sections)
              DanmakuCandidate(
                title: '${section['title']}',
                subtitle: '${objects(section['episodes']).length} 个视频',
                open: () async => videos(section),
              ),
          ];
  }

  /// A video's parts; a single part takes the video's title.
  List<DanmakuCandidate> _parts(Json video) {
    final pages = objects(video['pages']);
    return [
      for (final page in pages)
        DanmakuCandidate(
          title: pages.length == 1
              ? '${video['title']}'
              : 'P${page['page']} · ${page['part']}',
          subtitle: '${(number(page['duration']) / 60).round()} 分钟',
          locator: '${video['bvid']}?p=${page['page']}',
        ),
    ];
  }

  @override
  Future<DanmakuCandidate?> follow(
    String locator,
    double from,
    double to,
  ) async {
    await _engine.guest(null);
    final episode = RegExp(r'ep(\d+)').firstMatch(locator);
    final List<({String name, String label, String locator, num seconds})> rows;
    if (episode != null) {
      final value = await _engine.request('/pgc/view/web/season', {
        'ep_id': episode[1]!,
      });
      rows = [
        for (final item in objects(object(value['result'])['episodes']))
          (
            name: '${item['title']}',
            label: '第${item['title']}话 ${item['long_title']}'.trim(),
            locator: 'ep${item['id']}',
            seconds: number(item['duration']) / 1000,
          ),
      ];
    } else {
      final bvid = RegExp(r'BV[a-zA-Z0-9]+').firstMatch(locator)![0]!;
      final value = await _engine.request('/x/web-interface/view', {
        'bvid': bvid,
      });
      final data = object(value['data']);
      final pages = objects(data['pages']);
      // A multi-part video's parts, else the single-part videos of the
      // collection it belongs to.
      rows = pages.length > 1
          ? [
              for (final page in pages)
                (
                  name: '${page['part']}',
                  label: 'P${page['page']} · ${page['part']}',
                  locator: '$bvid?p=${page['page']}',
                  seconds: number(page['duration']),
                ),
            ]
          : [
              for (final section in objects(
                object(data['ugc_season'])['sections'],
              ))
                for (final video in objects(section['episodes']))
                  if (objects(video['pages']) case [final page])
                    (
                      name: '${video['title']}',
                      label: '${video['title']}',
                      locator: '${video['bvid']}?p=1',
                      seconds: number(page['duration']),
                    ),
            ];
    }
    final anchor = rows.where((row) => row.locator == locator).firstOrNull;
    if (anchor == null) return null;
    final row = followRow(
      // Much shorter than the picked episode: a preview, clip or half.
      rows.where((row) => row.seconds >= anchor.seconds * .6),
      (row) => row.name,
      anchor,
      from,
      to,
    );
    return row == null
        ? null
        : DanmakuCandidate(title: row.label, locator: row.locator);
  }

  @override
  Future<List<DanmakuComment>> load(String locator) async {
    await _engine.guest(null);
    final episode = RegExp(r'ep(\d+)').firstMatch(locator);
    late Json video;
    if (episode != null) {
      final response = await _engine.request('/pgc/view/web/season', {
        'ep_id': episode[1]!,
      });
      final data = object(response['result']);
      final episodes = [
        ...objects(data['episodes']),
        ...objects(data['section']).expand((s) => objects(s['episodes'])),
      ];
      video = episodes.firstWhere(
        (e) => '${e['id']}' == episode[1],
        orElse: () => throw StateError('未找到 Bilibili 章节'),
      );
    } else {
      final bv = RegExp(r'BV[a-zA-Z0-9]+').firstMatch(locator)?[0];
      if (bv == null) throw const FormatException('请输入 BV 号、EP 号或播放链接');
      final response = await _engine.request('/x/web-interface/view', {
        'bvid': bv,
      });
      final pages = objects(object(response['data'])['pages']);
      final page =
          int.tryParse(Uri.tryParse(locator)?.queryParameters['p'] ?? '1') ?? 1;
      video = pages.firstWhere(
        (v) => v['page'] == page,
        orElse: () => throw StateError('未找到 Bilibili 分 P'),
      );
    }
    final cid = number(video['cid']).toInt();
    if (cid <= 0) throw StateError('弹幕 CID 无效');
    final duration = number(video['duration']) / (episode == null ? 1 : 1000);
    final comments = <DanmakuComment?>[];
    try {
      final xml = await api.send(
        Uri.https('comment.bilibili.com', '/$cid.xml'),
        headers: _engine.mediaHeaders,
      );
      final bytes = xml.bodyBytes;
      final deflated =
          xml.headers['content-encoding']?.toLowerCase() == 'deflate';
      comments.addAll(await compute(_decodeXml, (bytes, deflated)));
    } catch (_) {
      /* Segmented comments can remain available independently. */
    }
    final segments = (duration / 360).ceil().clamp(1, 100);
    Object? failure;
    for (var i = 1; i <= segments; i += 4) {
      await Future.wait(
        List.generate((segments - i + 1).clamp(0, 4), (offset) async {
          try {
            final response = await api.send(
              Uri.https('api.bilibili.com', '/x/v2/dm/web/seg.so', {
                'type': '1',
                'oid': '$cid',
                'segment_index': '${i + offset}',
              }),
              headers: _engine.mediaHeaders,
            );
            final bytes = response.bodyBytes;
            comments.addAll(await compute(_parseSegment, bytes));
          } catch (e) {
            failure = e;
          }
        }),
      );
    }
    if (comments.isEmpty && failure != null) {
      throw StateError('Bilibili 弹幕获取失败：$failure');
    }
    return compute(sortedComments, comments);
  }
}

List<DanmakuComment?> _decodeXml((List<int>, bool) payload) {
  var (bytes, deflated) = payload;
  if (deflated) {
    try {
      bytes = zlib.decode(bytes);
    } on FormatException {
      bytes = ZLibDecoder(raw: true).convert(bytes);
    }
  }
  return XmlDocument.parse(utf8.decode(bytes)).findAllElements('d').map((d) {
    final fields = (d.getAttribute('p') ?? '').split(',');
    return DanmakuComment.parse(
      source: 'bilibili',
      time: double.tryParse(fields.first),
      mode: fields.length > 1
          ? danmakuMode(int.tryParse(fields[1]) ?? 0)
          : null,
      color: fields.length > 3
          ? (int.tryParse(fields[3]) ?? 0xffffff) & 0xffffff
          : null,
      text: d.innerText,
    );
  }).toList();
}

/// Decode only the fields needed from DmSegMobileReply / DanmakuElem.
List<DanmakuComment?> _parseSegment(Uint8List bytes) {
  final rows = <DanmakuComment?>[];
  final outer = CodedBufferReader(bytes);
  while (!outer.isAtEnd()) {
    final tag = outer.readTag();
    if (tag != 10) {
      if (!outer.skipField(tag)) {
        throw const FormatException('Invalid protobuf field');
      }
      continue;
    }
    final entry = CodedBufferReader(outer.readBytes());
    double time = 0;
    DanmakuMode? mode;
    int? color;
    String? text;
    while (!entry.isAtEnd()) {
      final tag = entry.readTag();
      switch (tag) {
        case 16:
          time = entry.readInt32() / 1000;
        case 24:
          mode = danmakuMode(entry.readInt32());
        case 40:
          color = entry.readUint32() & 0xffffff;
        case 58:
          text = entry.readString();
        default:
          if (!entry.skipField(tag)) {
            throw const FormatException('Invalid protobuf field');
          }
      }
    }
    rows.add(
      DanmakuComment.parse(
        source: 'bilibili',
        time: time,
        mode: mode,
        color: color,
        text: text,
      ),
    );
  }
  return rows;
}
