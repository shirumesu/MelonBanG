import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/sources.dart';

/// Bilibili web API as a guest: official seasons and uploader videos, played
/// through a generated DASH manifest of the best available AVC/AAC tracks.
class BilibiliEngine implements OnlineSourceEngine {
  BilibiliEngine(this.api, this.instance);
  final ApiClient api;
  @override
  final SourceInstance instance;
  String? _cookie;
  @override
  String get currentBase => instance.baseUrls.first;
  @override
  Uri? lastRequest;
  @override
  int? lastStatus;
  Map<String, String> get mediaHeaders => {
    'Referer': '${instance.website}/',
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
      throw SourceVerificationRequired('${instance.website}');
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

  SourceSubject season(Json row) => SourceSubject(
    id: 'ss${row['season_id']}',
    title: html.parseFragment(row['title'] as String).text!,
    line: '官方番剧',
    year: switch (row['pubtime']) {
      final int timestamp => DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
      ).year,
      _ => null,
    },
    data: {'seasonId': row['season_id']},
  );

  SourceSubject video(Json row) {
    final author = row['author'] ?? object(row['owner'])['name'];
    return SourceSubject(
      id: row['bvid'] as String,
      title: html.parseFragment(row['title'] as String).text!,
      line: '投稿 · $author',
      // Search rows give "m:ss"; the view API gives seconds.
      description: _clock(switch (row['duration']) {
        final String clock =>
          clock.split(':').fold(0, (a, b) => a * 60 + int.parse(b)),
        final seconds => seconds as int,
      }),
      choosePart: true,
    );
  }

  @override
  Future<List<SourceSubject>> searchSubjects(
    String name, {
    RequestCancellation? cancel,
  }) async {
    await guest(cancel);
    final locator = RegExp(r'BV[0-9A-Za-z]{10}|(?:ss|ep)\d+')
        .firstMatch(name)?[0];
    if (locator != null) {
      if (locator.startsWith('BV')) {
        final data = await request('/x/web-interface/view', {
          'bvid': locator,
        }, cancel: cancel);
        return [video(object(data['data']))];
      }
      final data = await request('/pgc/view/web/season', {
        locator.startsWith('ss') ? 'season_id' : 'ep_id': locator.substring(2),
      }, cancel: cancel);
      return [season(object(data['result']))];
    }
    final results = await Future.wait([
      for (final type in ['media_bangumi', 'video'])
        request('/x/web-interface/search/type', {
          'search_type': type,
          'keyword': name,
          'page': '1',
        }, cancel: cancel),
    ]);
    return [
      for (final row in objects(object(results[0]['data'])['result']))
        season(row),
      for (final row in objects(object(results[1]['data'])['result']))
        video(row),
    ];
  }

  @override
  Future<List<SourceEpisode>> episodes(
    SourceSubject subject, {
    RequestCancellation? cancel,
  }) async {
    await guest(cancel);
    if (subject.choosePart) {
      final value = await request('/x/web-interface/view', {
        'bvid': subject.id,
      }, cancel: cancel);
      final data = object(value['data']);
      final line = '投稿 · ${object(data['owner'])['name']}';
      return [
        for (final page in objects(data['pages']))
          SourceEpisode(
            label: 'P${page['page']} · ${page['part']}',
            description: _clock(page['duration'] as int),
            line: line,
            ref: StreamRef(instance.id, {
              'bvid': data['bvid'],
              'cid': page['cid'],
              'page': page['page'],
              'line': line,
              'url':
                  '${instance.website}/video/${data['bvid']}?p=${page['page']}',
            }),
          ),
      ];
    }
    final value = await request('/pgc/view/web/season', {
      'season_id': '${subject.data['seasonId']}',
    }, cancel: cancel);
    return [
      for (final episode in objects(object(value['result'])['episodes']))
        SourceEpisode(
          label:
              '第${episode['title']}话 · ${episode['long_title']}${episode['badge'] == '' ? '' : ' · ${episode['badge']}'}',
          line: '官方番剧',
          ref: StreamRef(instance.id, {
            'epId': episode['id'],
            'bvid': episode['bvid'],
            'cid': episode['cid'],
            'members': episode['status'] == 13,
            'line': '官方番剧',
            'url': '${instance.website}/bangumi/play/ep${episode['id']}',
          }),
        ),
    ];
  }

  @override
  Future<ResolvedStream> resolve(
    StreamRef ref, {
    RequestCancellation? cancel,
  }) async {
    if (ref.data['members'] == true) {
      throw StateError('Bilibili 此集为会员专享，访客无法播放完整正片');
    }
    await guest(cancel);
    // The season player API caps guests at 480p; official free episodes play
    // through the video player API, whose `try_look` lifts guests to 1080p.
    final value = await request('/x/player/playurl', {
      'bvid': ref.data['bvid'] as String,
      'cid': '${ref.data['cid']}',
      'fnval': '4048',
      'qn': '80',
      'fourk': '1',
      'try_look': '1',
    }, cancel: cancel);
    final locator = ref.data['epId'] != null
        ? 'ep${ref.data['epId']}'
        : '${ref.data['bvid']}?p=${ref.data['page']}';
    final dash = object(object(value['data'])['dash']);
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
    return ResolvedStream(
      url: _mediaUrl(selected),
      playlist: manifest(dash, selected, audios.first),
      format: StreamFormat.dash,
      headers: mediaHeaders,
      sourceId: instance.id,
      line: ref.data['line'] as String?,
      quality: '${selected['height']}p',
      danmakuProvider: 'bilibili',
      danmakuLocator: locator,
    );
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
                      builder.element('BaseURL', nest: _mediaUrl(track));
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

/// The track's Bilibili-hosted `upos-` mirror; the primary URL is often a
/// third-party PCDN edge whose TLS handshakes fail intermittently.
String _mediaUrl(Json track) {
  final urls = [
    track['baseUrl'] as String,
    ...(track['backupUrl'] as List).cast<String>(),
  ];
  return urls.firstWhere(
    (url) => Uri.parse(url).host.startsWith('upos-'),
    orElse: () => urls.first,
  );
}

/// "1:02:03" or "2:03".
String _clock(int seconds) {
  String two(int value) => value.toString().padLeft(2, '0');
  final minutes = seconds ~/ 60 % 60, hours = seconds ~/ 3600;
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds % 60)}'
      : '$minutes:${two(seconds % 60)}';
}
