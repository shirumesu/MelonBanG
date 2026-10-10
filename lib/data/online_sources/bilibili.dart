import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import '../json.dart';
import '../network.dart';
import 'engine.dart';

const bilibiliSourceRule = <String, dynamic>{
  'id': 'bilibili-video',
  'name': 'Bilibili（外接）',
  'engine': 'bilibili-web',
  'baseUrls': ['https://api.bilibili.com'],
  'website': 'https://www.bilibili.com',
  'manualOnly': true,
  'description': '访客播放，按实际可用画质打开。投稿需确认内容和分 P；会员与地区限制由 B 站决定。',
};

class BilibiliSource implements OnlineSource {
  BilibiliSource(this.api, this.rule);
  final ApiClient api;
  final Json rule;
  String? _cookie;
  String get id => rule['id'] as String;
  @override
  String get currentBase => (rule['baseUrls'] as List).first as String;
  @override
  Uri? lastRequest;
  @override
  int? lastStatus;
  Map<String, String> get mediaHeaders => {
    'Referer': '${rule['website']}/',
    'User-Agent': 'Mozilla/5.0',
  };

  Future<Json> request(
    String path,
    Map<String, String> query, {
    RequestCancellation? cancel,
  }) async {
    final uri = Uri.parse(currentBase)
        .replace(path: path, queryParameters: query);
    lastRequest = uri;
    lastStatus = null;
    final response = await api.send(
      uri,
      headers: {...mediaHeaders, 'Cookie': ?_cookie},
      cancel: cancel,
    );
    lastStatus = response.statusCode;
    final value = object(await decodeJsonBytes(response.bodyBytes));
    if (value['code'] == -352 || value['code'] == -412) {
      throw SourceVerificationRequired('${rule['website']}');
    }
    if (value['code'] != 0) {
      throw StateError('Bilibili：${value['message']}（${value['code']}）');
    }
    return value;
  }

  Future<void> guest(RequestCancellation? cancel) async {
    if (_cookie != null) return;
    final value = await request('/x/frontend/finger/spi', {}, cancel: cancel);
    final data = object(value['data']);
    _cookie = 'buvid3=${data['b_3']}; buvid4=${data['b_4']}';
  }

  Json season(Json row) => {
    'id': 'ss${row['season_id']}',
    'seasonId': row['season_id'],
    'title': html.parseFragment(row['title'] as String).text!,
    'line': '官方番剧',
    if (row['pubtime'] case final int timestamp)
      'year': DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).year,
  };

  Json video(Json row) => {
    'id': row['bvid'],
    'title': html.parseFragment(row['title'] as String).text!,
    'line': '投稿 · ${row['author'] ?? object(row['owner'])['name']}',
    'description':
        '${row['author'] ?? object(row['owner'])['name']} · ${row['duration']}',
    'selectEpisode': true,
  };

  @override
  Future<List<Json>> searchSubjects(
    Iterable<String> names, {
    RequestCancellation? cancel,
  }) async {
    await guest(cancel);
    final rows = <String, Json>{};
    for (final name in names) {
      final locator = RegExp(r'BV[0-9A-Za-z]{10}|(?:ss|ep)\d+')
          .firstMatch(name)?[0];
      if (locator != null) {
        if (locator.startsWith('BV')) {
          final data = await request('/x/web-interface/view', {
            'bvid': locator,
          }, cancel: cancel);
          rows[locator] = video(object(data['data']));
        } else {
          final data = await request('/pgc/view/web/season', {
            locator.startsWith('ss') ? 'season_id' : 'ep_id': locator.substring(
              2,
            ),
          }, cancel: cancel);
          final item = season(object(data['result']));
          rows[item['id'] as String] = item;
        }
        continue;
      }
      final results = await Future.wait([
        for (final type in ['media_bangumi', 'video'])
          request('/x/web-interface/search/type', {
            'search_type': type,
            'keyword': name,
            'page': '1',
          }, cancel: cancel),
      ]);
      for (final row in objects(object(results[0]['data'])['result'])) {
        final item = season(row);
        rows[item['id'] as String] = item;
      }
      for (final row in objects(object(results[1]['data'])['result'])) {
        final item = video(row);
        rows[item['id'] as String] = item;
      }
    }
    return rows.values.toList();
  }

  @override
  Future<List<Json>> episodes(
    Json subject, {
    RequestCancellation? cancel,
  }) async {
    await guest(cancel);
    if (subject['selectEpisode'] == true) {
      final value = await request('/x/web-interface/view', {
        'bvid': subject['id'] as String,
      }, cancel: cancel);
      final data = object(value['data']);
      return [
        for (final page in objects(data['pages']))
          {
            'label': 'P${page['page']} · ${page['part']}',
            'description': '${page['duration']} 秒',
            'line': '投稿 · ${object(data['owner'])['name']}',
            'ref': {
              'sourceId': id,
              'bvid': data['bvid'],
              'cid': page['cid'],
              'page': page['page'],
              'line': '投稿 · ${object(data['owner'])['name']}',
              'url':
                  '${rule['website']}/video/${data['bvid']}?p=${page['page']}',
            },
          },
      ];
    }
    final value = await request('/pgc/view/web/season', {
      'season_id': '${subject['seasonId']}',
    }, cancel: cancel);
    return [
      for (final episode in objects(object(value['result'])['episodes']))
        {
          'label':
              '第${episode['title']}话 · ${episode['long_title']}${episode['badge'] == '' ? '' : ' · ${episode['badge']}'}',
          'line': '官方番剧',
          'ref': {
            'sourceId': id,
            'epId': episode['id'],
            'line': '官方番剧',
            'url': '${rule['website']}/bangumi/play/ep${episode['id']}',
          },
        },
    ];
  }

  @override
  Future<Json> resolve(Json ref, {RequestCancellation? cancel}) async {
    await guest(cancel);
    final Json info;
    final String locator;
    if (ref['epId'] != null) {
      final value = await request('/pgc/player/web/v2/playurl', {
        'ep_id': '${ref['epId']}',
        'fnval': '4048',
        'qn': '80',
        'fourk': '1',
      }, cancel: cancel);
      final result = object(value['result']);
      if (object(result['play_check'])['play_detail'] != 'PLAY_WHOLE') {
        throw StateError('Bilibili 此集仅提供试看或受会员、地区限制，无法播放完整正片');
      }
      info = object(result['video_info']);
      locator = 'ep${ref['epId']}';
    } else {
      final value = await request('/x/player/playurl', {
        'bvid': ref['bvid'] as String,
        'cid': '${ref['cid']}',
        'fnval': '4048',
        'qn': '80',
        'fourk': '1',
      }, cancel: cancel);
      info = object(value['data']);
      locator = '${ref['bvid']}?p=${ref['page']}';
    }
    final dash = object(info['dash']);
    final videos =
        objects(dash['video'])
            .where((track) => (track['codecs'] as String).startsWith('avc1'))
            .toList()
          ..sort(
            (a, b) => number(b['bandwidth']).compareTo(number(a['bandwidth'])),
          );
    final audios =
        objects(dash['audio'])
            .where((track) => (track['codecs'] as String).startsWith('mp4a'))
            .toList()
          ..sort(
            (a, b) => number(b['bandwidth']).compareTo(number(a['bandwidth'])),
          );
    if (videos.isEmpty || audios.isEmpty) {
      throw StateError('Bilibili 没有返回可播放的完整视频和音轨');
    }
    final selected = videos.first;
    return {
      'url': selected['baseUrl'],
      'playlist': manifest(dash, selected, audios.first),
      'kind': 'dash',
      'headers': mediaHeaders,
      'provider': id,
      'line': ref['line'],
      'quality': '${selected['height']}p',
      'danmaku': {'provider': 'bilibili', 'locator': locator},
    };
  }

  String manifest(Json dash, Json video, Json audio) {
    final builder = XmlBuilder();
    builder.element(
      'MPD',
      attributes: {
        'xmlns': 'urn:mpeg:dash:schema:mpd:2011',
        'type': 'static',
        'profiles': 'urn:mpeg:dash:profile:isoff-on-demand:2011',
        'mediaPresentationDuration': 'PT${dash['duration']}S',
        'minBufferTime': 'PT${dash['minBufferTime']}S',
      },
      nest: () {
        builder.element(
          'Period',
          nest: () {
            for (final (type, track) in [('video', video), ('audio', audio)]) {
              builder.element(
                'AdaptationSet',
                attributes: {
                  'contentType': type,
                  'mimeType': track['mimeType'] as String,
                },
                nest: () {
                  builder.element(
                    'Representation',
                    attributes: {
                      'id': '${track['id']}',
                      'bandwidth': '${track['bandwidth']}',
                      'codecs': track['codecs'] as String,
                      if (type == 'video') ...{
                        'width': '${track['width']}',
                        'height': '${track['height']}',
                        'frameRate': '${track['frameRate']}',
                      },
                    },
                    nest: () {
                      builder.element(
                        'BaseURL',
                        nest: track['baseUrl'] as String,
                      );
                      final segment = object(track['SegmentBase']);
                      builder.element(
                        'SegmentBase',
                        attributes: {
                          'indexRange': segment['indexRange'] as String,
                        },
                        nest: () {
                          builder.element(
                            'Initialization',
                            attributes: {
                              'range': segment['Initialization'] as String,
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            }
          },
        );
      },
    );
    return builder.buildDocument().toXmlString();
  }
}
