import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'credentials.dart';
import 'json.dart';
import 'network.dart';

class DanmakuRepository {
  DanmakuRepository(this.api, this.credentials);
  final ApiClient api;
  final Credentials credentials;

  Future<String> automaticLocator(
    String provider,
    String title,
    double episode,
  ) async {
    String normalized(String value) => value
        .replaceAll(RegExp('<[^>]*>'), '')
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');
    if (provider == 'bilibili') {
      const headers = {'Referer': 'https://www.bilibili.com/'};
      final result = await api.map(
        Uri.https('api.bilibili.com', '/x/web-interface/wbi/search/type', {
          'search_type': 'media_bangumi',
          'keyword': title,
        }),
        headers: headers,
      );
      final candidates = objects(object(result['data'])['result'])
          .where((r) => normalized('${r['title']}') == normalized(title))
          .toList();
      if (candidates.length != 1) {
        throw StateError('Bilibili 没有唯一匹配，请手动输入 EP 或 BV');
      }
      final season = await api.map(
        Uri.https('api.bilibili.com', '/pgc/view/web/season', {
          'season_id': '${candidates.single['season_id']}',
        }),
        headers: headers,
      );
      final episodes = objects(object(season['result'])['episodes'])
          .where((e) => double.tryParse('${e['title']}') == episode)
          .toList();
      if (episodes.length != 1) throw StateError('Bilibili 未匹配到对应章节');
      return 'ep${episodes.single['id']}';
    }
    final response = await api.send(
      Uri.https('ani.gamer.com.tw', '/search.php'),
      method: 'POST',
      body: <String, String>{'keyword': title},
    );
    final html = utf8.decode(response.bodyBytes);
    final results =
        RegExp(
              r'''<img[^>]*alt=["']([^"']+)["'][^>]*>[\s\S]{0,2000}?<a[^>]*href=["'][^"']*animeRef\.php\?sn=(\d+)''',
              caseSensitive: false,
            )
            .allMatches(html)
            .where((m) => normalized(m[1]!) == normalized(title))
            .toList();
    if (results.length != 1) throw StateError('动画疯没有唯一匹配，请手动输入 sn');
    final page = await api.send(
      Uri.https('ani.gamer.com.tw', '/animeRef.php', {
        'sn': results.single[2]!,
      }),
    );
    final links = RegExp(
      r'''<a[^>]*href=["'][^"']*animeVideo\.php\?sn=(\d+)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    ).allMatches(utf8.decode(page.bodyBytes));
    final episodes = links
        .where(
          (m) =>
              double.tryParse(
                RegExp(
                      r'\d+(?:\.\d+)?',
                    ).firstMatch(m[2]!.replaceAll(RegExp('<[^>]*>'), ''))?[0] ??
                    '',
              ) ==
              episode,
        )
        .toList();
    if (episodes.length != 1) throw StateError('动画疯未匹配到对应章节');
    return 'sn=${episodes.single[1]}';
  }

  Future<void> configure(String appId, String appSecret) => credentials.write(
    'dandanplay',
    jsonEncode({'appId': appId.trim(), 'appSecret': appSecret.trim()}),
  );
  Future<Json> _dandan(String path, {Json? body}) async {
    final config = object(
      jsonDecode(await credentials.read('dandanplay') ?? '{}'),
    );
    final appId = '${config['appId'] ?? ''}';
    final appSecret = '${config['appSecret'] ?? ''}';
    if (appId.isEmpty || appSecret.isEmpty) {
      throw StateError('请先在设置中填写弹弹play应用凭据');
    }
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

  Future<List<Json>> search(String title) async {
    final value = await _dandan(
      '/api/v2/search/episodes?anime=${Uri.encodeQueryComponent(title)}',
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

  Future<int> matchFile(String path, double duration) async {
    final file = File(path);
    final handle = await file.open();
    late List<int> prefix;
    try {
      prefix = await handle.read(16 * 1024 * 1024);
    } finally {
      await handle.close();
    }
    final value = await _dandan(
      '/api/v2/match',
      body: {
        'fileName': p.basename(path),
        'fileHash': md5.convert(prefix).toString(),
        'fileSize': await file.length(),
        'videoDuration': duration.round(),
        'matchMode': 'hashAndFileName',
      },
    );
    final matches = objects(value['matches']);
    if (value['success'] != true ||
        value['isMatched'] != true ||
        matches.length != 1) {
      throw StateError('没有唯一匹配，请手动搜索并选择章节');
    }
    return number(matches.first['episodeId']).toInt();
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

String _color(int value) =>
    '#${value.toRadixString(16).padLeft(6, '0').substring(0, 6)}';
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
  final outer = _Proto(bytes);
  while (!outer.done) {
    final tag = outer.integer();
    if (tag == 10) {
      final entry = _Proto(outer.bytes());
      final row = <String, dynamic>{'color': '#ffffff'};
      while (!entry.done) {
        final tag = entry.integer();
        switch (tag) {
          case 16:
            row['timeSeconds'] = entry.integer() / 1000;
          case 24:
            row['mode'] = _mode(entry.integer());
          case 40:
            row['color'] = _color(entry.integer());
          case 58:
            row['text'] = utf8.decode(entry.bytes(), allowMalformed: true);
          default:
            entry.skip(tag & 7);
        }
      }
      rows.add(row);
    } else {
      outer.skip(tag & 7);
    }
  }
  return normalizeComments(rows);
}

class _Proto {
  _Proto(this.data);
  final Uint8List data;
  int offset = 0;
  bool get done => offset >= data.length;
  int integer() {
    var value = 0;
    for (var shift = 0; shift < 70; shift += 7) {
      if (done) throw const FormatException('Truncated protobuf');
      final b = data[offset++];
      value |= (b & 127) << shift;
      if (b < 128) return value;
    }
    throw const FormatException('Invalid protobuf integer');
  }

  Uint8List bytes() {
    final length = integer();
    if (length < 0 || offset + length > data.length) {
      throw const FormatException('Truncated protobuf field');
    }
    final result = Uint8List.sublistView(data, offset, offset + length);
    offset += length;
    return result;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        integer();
      case 1:
        offset += 8;
      case 2:
        bytes();
      case 5:
        offset += 4;
      default:
        throw const FormatException('Unsupported protobuf wire');
    }
    if (offset > data.length) {
      throw const FormatException('Truncated protobuf field');
    }
  }
}
