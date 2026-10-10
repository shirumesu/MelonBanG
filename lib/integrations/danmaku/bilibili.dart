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
import 'matching.dart';

const _headers = {'Referer': 'https://www.bilibili.com/'};

/// Bilibili: official `media_bangumi` matches only; locators are EP/BV ids or
/// playback URLs (BV parts through `p`).
class BilibiliDanmaku implements DanmakuMatcher {
  BilibiliDanmaku(this.api);
  final ApiClient api;

  @override
  String get id => 'bilibili';
  @override
  String get label => 'Bilibili';

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
    for (final query
        in titles.map(ChineseHelper.convertToSimplifiedChinese).toSet()) {
      final result = await api.map(
        Uri.https('api.bilibili.com', '/x/web-interface/search/type', {
          'search_type': 'media_bangumi',
          'keyword': query,
        }),
        headers: _headers,
      );
      _check(result);
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
    final season = await api.map(
      Uri.https('api.bilibili.com', '/pgc/view/web/season', {
        'season_id': candidates.single,
      }),
      headers: _headers,
    );
    _check(season);
    if (season['result'] is! Map) throw StateError('Bilibili 番剧详情暂不可用');
    final episodes = objects(object(season['result'])['episodes'])
        .where((item) => episodeNumber('${item['title']}') == episode.number)
        .map((item) => positiveId(item['id']))
        .whereType<String>()
        .toSet();
    return episodes.length == 1 ? 'ep${episodes.single}' : null;
  }

  @override
  Future<List<DanmakuComment>> load(String locator) async {
    final episode = RegExp(r'ep(\d+)').firstMatch(locator);
    late Json video;
    if (episode != null) {
      final response = await api.map(
        Uri.https('api.bilibili.com', '/pgc/view/web/season', {
          'ep_id': episode[1]!,
        }),
        headers: _headers,
      );
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
      final response = await api.map(
        Uri.https('api.bilibili.com', '/x/web-interface/view', {'bvid': bv}),
        headers: _headers,
      );
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
        headers: _headers,
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
              headers: _headers,
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

void _check(Json value) {
  if (value['code'] != 0) {
    throw StateError('Bilibili 番剧请求失败：${value['message'] ?? value['code']}');
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
  try {
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
  } on InvalidProtocolBufferException catch (e) {
    throw FormatException('Invalid danmaku protobuf: $e');
  }
  return rows;
}
