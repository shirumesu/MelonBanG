import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pinyin/pinyin.dart' show ChineseHelper;
import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html;
import 'package:protobuf/protobuf.dart';

import 'service_configuration.dart';
import 'json.dart';
import 'network.dart';

class DandanMatch {
  const DandanMatch({this.episodeId, this.candidates = const []});
  final int? episodeId;
  final List<Json> candidates;
}

class DanmakuRepository {
  DanmakuRepository(
    this.api, {
    this.configuration = const ServiceConfiguration(),
  });
  final ApiClient api;
  final ServiceConfiguration configuration;

  Future<String?> automaticLocator(
    String provider,
    String title,
    double episode, {
    Iterable<String> alternativeTitles = const [],
  }) async {
    if (!['bilibili', 'bahamut'].contains(provider)) {
      throw ArgumentError.value(provider);
    }
    if (!episode.isFinite || episode <= 0) return null;
    final titles = {
      title,
      ...alternativeTitles,
    }.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
    if (titles.isEmpty) return null;
    final normalizedTitles = titles.map(_normalizedTitle).toSet();
    final queries = titles
        .map(
          provider == 'bahamut'
              ? ChineseHelper.convertToTraditionalChinese
              : ChineseHelper.convertToSimplifiedChinese,
        )
        .toSet();
    final candidates = <String>{};
    const headers = {'Referer': 'https://www.bilibili.com/'};
    for (final query in queries) {
      if (provider == 'bilibili') {
        final result = await api.map(
          Uri.https('api.bilibili.com', '/x/web-interface/search/type', {
            'search_type': 'media_bangumi',
            'keyword': query,
          }),
          headers: headers,
        );
        _checkBilibili(result);
        final data = object(result['data']);
        if (data['result'] is! List && data['numResults'] != 0) {
          throw StateError('Bilibili 番剧搜索暂不可用');
        }
        for (final item in objects(data['result'])) {
          if (normalizedTitles.contains(_normalizedTitle('${item['title']}'))) {
            final id = _positiveId(item['season_id']);
            if (id != null) candidates.add(id);
          }
        }
      } else {
        final response = await api.send(
          Uri.https('ani.gamer.com.tw', '/search.php', {'keyword': query}),
        );
        final document = html.parse(utf8.decode(response.bodyBytes));
        for (final link in document.querySelectorAll('a[href]')) {
          final uri = Uri.tryParse(link.attributes['href']!);
          if (uri == null || !uri.path.endsWith('animeRef.php')) continue;
          final names = [
            if (link.querySelector('.theme-name') case final name?) name.text,
            ...link
                .querySelectorAll('img[alt]')
                .map((img) => img.attributes['alt']!),
            if (link.children.isEmpty) link.text,
          ];
          if (names.any(
            (name) => normalizedTitles.contains(_normalizedTitle(name)),
          )) {
            final sn = _positiveId(uri.queryParameters['sn']);
            if (sn != null) candidates.add(sn);
          }
        }
      }
    }
    if (candidates.length != 1) return null;
    if (provider == 'bilibili') {
      final season = await api.map(
        Uri.https('api.bilibili.com', '/pgc/view/web/season', {
          'season_id': candidates.single,
        }),
        headers: headers,
      );
      _checkBilibili(season);
      if (season['result'] is! Map) throw StateError('Bilibili 番剧详情暂不可用');
      final episodes = objects(object(season['result'])['episodes'])
          .where((item) => _episodeNumber('${item['title']}') == episode)
          .map((item) => _positiveId(item['id']))
          .whereType<String>()
          .toSet();
      return episodes.length == 1 ? 'ep${episodes.single}' : null;
    }
    final page = await api.send(
      Uri.https('ani.gamer.com.tw', '/animeRef.php', {'sn': candidates.single}),
    );
    final document = html.parse(utf8.decode(page.bodyBytes));
    final episodes = <String>{};
    // Main episodes have their own list; dubbed versions and specials reuse numbers.
    for (final list in document.querySelectorAll('.season > ul')) {
      final heading = list.previousElementSibling;
      final isMain = heading?.localName == 'p' && heading!.text.trim() == '本篇';
      final isOnlyUnlabelled =
          heading == null &&
          list.parent!.children.length == 1 &&
          document.querySelectorAll('.season').length == 1;
      if (!isMain && !isOnlyUnlabelled) continue;
      for (final link in list.querySelectorAll('a[href]')) {
        final uri = Uri.tryParse(link.attributes['href']!);
        final sn = _positiveId(
          link.attributes['data-ani-video-sn'] ?? uri?.queryParameters['sn'],
        );
        if (_episodeNumber(link.text) == episode && sn != null) {
          episodes.add(sn);
        }
      }
    }
    return episodes.length == 1 ? 'sn=${episodes.single}' : null;
  }

  Future<Json> _dandan(String path, {Json? body}) async {
    if (!configuration.hasDandanplay) {
      throw StateError('此版本尚未启用弹弹play，请使用其他弹幕来源或已配置的应用版本。');
    }
    final appId = configuration.dandanplayAppId.trim();
    final appSecret = configuration.dandanplayAppSecret.trim();
    final uri = Uri.parse('https://api.dandanplay.net$path');
    final timestamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final signature = base64Encode(
      sha256
          .convert(utf8.encode('$appId$timestamp${uri.path}$appSecret'))
          .bytes,
    );
    return api.map(
      uri,
      method: body == null ? 'GET' : 'POST',
      body: body,
      headers: {
        'X-AppId': appId,
        'X-Timestamp': timestamp,
        'X-Signature': signature,
      },
    );
  }

  Future<List<Json>> search(String title, {double? episode}) async {
    final value = await _dandan(
      '/api/v2/search/episodes?anime=${Uri.encodeQueryComponent(title)}'
      '${episode == null ? '' : '&episode=${episode.toInt()}'}',
    );
    if (value['success'] != true) throw StateError('弹弹play搜索失败');
    return objects(value['animes'])
        .expand(
          (anime) => objects(anime['episodes']).map(
            (e) => {
              ...e,
              'animeTitle': anime['animeTitle'],
              'animeId': anime['animeId'],
            },
          ),
        )
        .toList();
  }

  Future<DandanMatch> matchBangumi(int subjectId, double episode) async {
    if (!episode.isFinite || episode <= 0) return const DandanMatch();
    final value = await _dandan('/api/v2/bangumi/bgmtv/$subjectId');
    if (value['success'] != true) {
      throw StateError('弹弹play条目映射失败：${value['errorMessage'] ?? '未知错误'}');
    }
    final bangumi = object(value['bangumi']);
    final candidates = objects(bangumi['episodes'])
        .where((item) => _episodeNumber('${item['episodeNumber']}') == episode)
        .where((item) => _positiveId(item['episodeId']) != null)
        .map(
          (item) => <String, dynamic>{
            ...item,
            'animeTitle': bangumi['animeTitle'],
          },
        )
        .toList();
    return DandanMatch(
      episodeId: candidates.length == 1
          ? int.parse('${candidates.single['episodeId']}')
          : null,
      candidates: candidates,
    );
  }

  Future<DandanMatch> matchTitles(
    Iterable<String> names,
    double episode,
  ) async {
    if (!episode.isFinite ||
        episode <= 0 ||
        episode != episode.roundToDouble()) {
      return const DandanMatch();
    }
    final titles = names
        .map((name) => name.trim())
        .where((name) => name.length >= 2)
        .toSet();
    final normalized = titles.map(_normalizedTitle).toSet();
    final candidates = <String, Json>{};
    for (final title in titles) {
      for (final item in await search(title, episode: episode)) {
        final id = _positiveId(item['episodeId']);
        if (id != null) candidates[id] = item;
      }
    }
    final exact = candidates.values.where((item) {
      final prefix = RegExp(r'^第\s*(\d+)\s*[話话集](?:\s|$)')
          .firstMatch('${item['episodeTitle']}');
      final number =
          _episodeNumber('${item['episodeNumber'] ?? item['episodeTitle']}') ??
          (prefix == null ? null : double.tryParse(prefix[1]!));
      return normalized.contains(_normalizedTitle('${item['animeTitle']}')) &&
          number == episode;
    }).toList();
    return DandanMatch(
      episodeId: exact.length == 1
          ? int.parse('${exact.single['episodeId']}')
          : null,
      candidates: exact.isEmpty ? candidates.values.toList() : exact,
    );
  }

  Future<DandanMatch> matchFile(
    String path,
    double duration, {
    bool filenameOnly = false,
    int? fileSize,
  }) async {
    String? hash;
    if (!filenameOnly) {
      final file = File(path);
      final handle = await file.open();
      try {
        hash = md5.convert(await handle.read(16 * 1024 * 1024)).toString();
      } finally {
        await handle.close();
      }
      fileSize = await file.length();
    }
    final value = await _dandan(
      '/api/v2/match',
      body: {
        'fileName': p.basenameWithoutExtension(path),
        'fileHash': ?hash,
        if (fileSize != null && fileSize > 0) 'fileSize': fileSize,
        'videoDuration': duration.isFinite && duration > 0
            ? duration.round()
            : 0,
        'matchMode': filenameOnly ? 'fileNameOnly' : 'hashAndFileName',
      },
    );
    if (value['success'] != true) {
      throw StateError('弹弹play匹配失败：${value['errorMessage'] ?? '未知错误'}');
    }
    final matches = objects(value['matches']);
    if (value['isMatched'] == true && matches.length == 1) {
      final id = _positiveId(matches.single['episodeId']);
      if (id == null) throw StateError('弹弹play返回了无效章节');
      return DandanMatch(episodeId: int.parse(id));
    }
    return DandanMatch(
      candidates: matches
          .where((item) => _positiveId(item['episodeId']) != null)
          .toList(),
    );
  }

  Future<List<Json>> dandan(int episodeId) async {
    final value = await _dandan(
      '/api/v2/comment/$episodeId?withRelated=true&chConvert=1',
    );
    if (value['success'] == false) {
      throw StateError('弹弹play弹幕获取失败：${value['errorMessage'] ?? '未知错误'}');
    }
    return normalizeComments(
      objects(value['comments']).map((c) {
        final fields = '${c['p']}'.split(',');
        return {
          'timeSeconds': double.tryParse(fields.first),
          'mode': fields.length > 1
              ? _mode(int.tryParse(fields[1]) ?? 1)
              : 'scroll',
          'color': fields.length > 2
              ? _color(int.tryParse(fields[2]) ?? 0xffffff)
              : '#ffffff',
          'text': c['m'],
        };
      }),
    );
  }

  Future<List<Json>> bilibili(String locator) async {
    final headers = {'Referer': 'https://www.bilibili.com/'};
    final episode = RegExp(r'ep(\d+)').firstMatch(locator);
    late Json video;
    if (episode != null) {
      final response = await api.map(
        Uri.https('api.bilibili.com', '/pgc/view/web/season', {
          'ep_id': episode[1]!,
        }),
        headers: headers,
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
        headers: headers,
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
    final comments = <Json>[];
    try {
      final xml = await api.send(
        Uri.https('comment.bilibili.com', '/$cid.xml'),
        headers: headers,
      );
      comments.addAll(parseBilibiliXml(utf8.decode(xml.bodyBytes)));
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
              headers: headers,
            );
            comments.addAll(parseBilibiliSegment(response.bodyBytes));
          } catch (e) {
            failure = e;
          }
        }),
      );
    }
    if (comments.isEmpty && failure != null) {
      throw StateError('Bilibili 弹幕获取失败：$failure');
    }
    return normalizeComments(comments);
  }

  Future<List<Json>> bahamut(String locator) async {
    final sn =
        Uri.tryParse(locator)?.queryParameters['sn'] ??
        RegExp(r'^(?:sn=)?(\d+)$').firstMatch(locator)?[1];
    if (sn == null) throw const FormatException('请输入动画疯 sn 或播放链接');
    final value = await api.json(
      Uri.https('ani.gamer.com.tw', '/ajax/danmuGet.php'),
      method: 'POST',
      body: <String, String>{'sn': sn},
      headers: {
        'Origin': 'https://ani.gamer.com.tw',
        'Referer': 'https://ani.gamer.com.tw/animeVideo.php?sn=$sn',
      },
    );
    return normalizeComments(
      objects(value).map(
        (c) => {
          'timeSeconds': number(c['time']) / 10,
          'text': c['text'],
          'color': c['color'],
          'mode': switch (c['position']) {
            1 => 'top',
            2 => 'bottom',
            _ => 'scroll',
          },
        },
      ),
    );
  }
}

String _normalizedTitle(String value) =>
    ChineseHelper.convertToSimplifiedChinese(
      html.parseFragment(value).text ?? '',
    ).toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

String? _positiveId(dynamic value) {
  final id = int.tryParse('$value');
  return id != null && id > 0 ? '$id' : null;
}

double? _episodeNumber(String value) {
  final match = RegExp(r'^(?:第\s*)?(\d+(?:\.\d+)?)(?:\s*[話话集])?$')
      .firstMatch(value.trim());
  return match == null ? null : double.tryParse(match[1]!);
}

void _checkBilibili(Json value) {
  if (value['code'] != 0) {
    throw StateError('Bilibili 番剧请求失败：${value['message'] ?? value['code']}');
  }
}

String _color(int value) =>
    '#${(value & 0xffffff).toRadixString(16).padLeft(6, '0')}';
String? _mode(int value) => switch (value) {
  1 || 2 || 3 => 'scroll',
  4 => 'bottom',
  5 => 'top',
  _ => null,
};
List<Json> normalizeComments(Iterable<Json> input) {
  final unique = <String, Json>{};
  for (final comment in input) {
    final time = comment['timeSeconds'];
    final text = '${comment['text'] ?? ''}'.trim();
    final mode = comment['mode'];
    if (time is! num ||
        !time.isFinite ||
        time < 0 ||
        text.isEmpty ||
        !['scroll', 'top', 'bottom'].contains(mode)) {
      continue;
    }
    final color = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch('${comment['color']}')
        ? '${comment['color']}'
        : '#ffffff';
    unique['${time.toDouble()}:$mode:$text'] = {
      'timeSeconds': time.toDouble(),
      'text': text,
      'mode': mode,
      'color': color,
    };
  }
  return unique.values.toList()..sort(
    (a, b) => number(a['timeSeconds']).compareTo(number(b['timeSeconds'])),
  );
}

List<Json> parseBilibiliXml(String xml) => normalizeComments(
  XmlDocument.parse(xml).findAllElements('d').map((d) {
    final fields = (d.getAttribute('p') ?? '').split(',');
    return {
      'timeSeconds': double.tryParse(fields.first),
      'mode': fields.length > 1 ? _mode(int.tryParse(fields[1]) ?? 0) : null,
      'color': fields.length > 3
          ? _color(int.tryParse(fields[3]) ?? 0xffffff)
          : '#ffffff',
      'text': d.innerText,
    };
  }),
);

/// Decode only the fields needed from DmSegMobileReply / DanmakuElem.
List<Json> parseBilibiliSegment(Uint8List bytes) {
  final rows = <Json>[];
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
      final row = <String, dynamic>{'color': '#ffffff', 'timeSeconds': 0.0};
      while (!entry.isAtEnd()) {
        final tag = entry.readTag();
        switch (tag) {
          case 16:
            row['timeSeconds'] = entry.readInt32() / 1000;
          case 24:
            row['mode'] = _mode(entry.readInt32());
          case 40:
            row['color'] = _color(entry.readUint32());
          case 58:
            row['text'] = entry.readString();
          default:
            if (!entry.skipField(tag)) {
              throw const FormatException('Invalid protobuf field');
            }
        }
      }
      rows.add(row);
    }
  } on InvalidProtocolBufferException catch (e) {
    throw FormatException('Invalid danmaku protobuf: $e');
  }
  return normalizeComments(rows);
}
