import 'package:html/parser.dart' as html;

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/sources.dart';

/// Bilibili web API as a guest: official seasons and uploader videos, played
/// as the best available AVC video track with a separate AAC audio track.
class BilibiliEngine implements OnlineSourceEngine {
  BilibiliEngine(this.api, this.instance);
  final ApiClient api;
  @override
  final SourceInstance instance;
  String? _cookie;
  @override
  String get currentBase => instance.baseUrls.first;
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
    final response = await api.send(
      uri,
      headers: {...mediaHeaders, 'Cookie': ?_cookie},
      cancel: cancel,
    );
    final value = object(await decodeJsonBytes(response.bodyBytes));
    if (value['code'] == -352 || value['code'] == -412) {
      throw SourceVerificationRequired('${instance.website}');
    }
    if (value['code'] != 0) {
      throw StateError('B 站没有返回内容，可能需要登录或有地区限制');
    }
    return value;
  }

  Future<void> guest(RequestCancellation? cancel) async {
    if (_cookie != null) return;
    final value = await request('/x/frontend/finger/spi', {}, cancel: cancel);
    final data = object(value['data']);
    _cookie = 'buvid3=${data['b_3']}; buvid4=${data['b_4']}';
  }

  /// Null for a row missing its season. A dub is a season of its own, titled
  /// `… 中配版`; its line says so. Search rows badge each members-only
  /// episode, which a guest cannot play.
  SourceSubject? season(Json row, {bool direct = false}) {
    if (row['season_id'] == null) return null;
    final title = _text(row['title']);
    final dub = RegExp(r'\s*中配版?$').firstMatch(title);
    final members = objects(row['eps'])
        .where(
          (e) => objects(e['badges']).any((badge) => badge['text'] == '会员'),
        )
        .length;
    final free = objects(row['eps']).length - members;
    return SourceSubject(
      id: 'ss${row['season_id']}',
      title: dub == null ? title : title.substring(0, dub.start),
      line: dub == null ? '官方番剧' : '官方番剧 · 中配',
      description: members == 0
          ? null
          : free == 0
          ? '全部为大会员专享'
          : '访客可看 $free 集，其余为大会员专享',
      year: switch (row['pubtime']) {
        final int timestamp => DateTime.fromMillisecondsSinceEpoch(
          timestamp * 1000,
        ).year,
        _ => null,
      },
      episodeTotal: _integer(row['ep_size']),
      direct: direct,
      data: {'seasonId': row['season_id']},
    );
  }

  /// Null for a row missing its video.
  SourceSubject? video(Json row, {bool direct = false}) {
    if (row['bvid'] case final String id when id.isNotEmpty) {
      final author = row['author'] ?? object(row['owner'])['name'] ?? '';
      // Search rows give "m:ss"; the view API gives seconds.
      final duration = switch (row['duration']) {
        final String clock =>
          clock.split(':').fold(0, (a, b) => a * 60 + (int.tryParse(b) ?? 0)),
        final value => _integer(value),
      };
      return SourceSubject(
        id: id,
        title: _text(row['title']),
        line: '投稿 · $author',
        description: duration == null ? null : _clock(duration),
        choosePart: true,
        durationSeconds: duration,
        publishedAt: switch (_integer(row['pubdate'])) {
          final seconds? => DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
          null => null,
        },
        // Only search rows carry the uploader's comma-separated tags.
        tags: [
          for (final tag in '${row['tag'] ?? ''}'.split(','))
            if (tag.trim().isNotEmpty) tag.trim(),
        ],
        // Search rows count comments as `video_review`; the view API in
        // `stat`.
        danmakuCount: _integer(
          row['video_review'] ?? object(row['stat'])['danmaku'],
        ),
        direct: direct,
      );
    }
    return null;
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
        return [?video(object(data['data']), direct: true)];
      }
      final data = await request('/pgc/view/web/season', {
        locator.startsWith('ss') ? 'season_id' : 'ep_id': locator.substring(2),
      }, cancel: cancel);
      return [?season(object(data['result']), direct: true)];
    }
    Future<List<Json>> search(
      String type, [
      Map<String, String>? filter,
    ]) async {
      final value = await request('/x/web-interface/search/type', {
        'search_type': type,
        'keyword': name,
        'page': '1',
        'page_size': '50',
        ...?filter,
      }, cancel: cancel);
      return objects(object(value['data'])['result']);
    }

    // A common name buries the show's uploads under other topics (萤火虫
    // finds cars), so the animation zone is searched apart too.
    final [seasons, animation, all] = await Future.wait([
      search('media_bangumi'),
      search('video', {'tids': '1'}),
      search('video'),
    ]);
    final uploads = {
      for (final row in [...animation, ...all]) '${row['bvid']}': row,
    }.values;
    // Commentary, music, art and game zones seldom hold an episode, though
    // uploaders file episodes under many others.
    bool aside(Json row) => _asideZones.contains('${row['typeid']}');
    return [
      for (final row in seasons) ?season(row),
      for (final row in uploads.where((row) => !aside(row))) ?video(row),
      for (final row in uploads.where(aside)) ?video(row),
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
            part: '${page['part']}',
            description: switch (_integer(page['duration'])) {
              final seconds? => _clock(seconds),
              null => null,
            },
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
    return seasonEpisodes(subject, cancel: cancel);
  }

  /// A season's episodes. Members-only ones (status 13) do not play for a
  /// guest, so they are left out unless [members], as their comments still
  /// load.
  Future<List<SourceEpisode>> seasonEpisodes(
    SourceSubject subject, {
    bool members = false,
    RequestCancellation? cancel,
  }) async {
    await guest(cancel);
    final value = await request('/pgc/view/web/season', {
      'season_id': '${subject.data['seasonId']}',
    }, cancel: cancel);
    final line = subject.line!;
    return [
      for (final episode in objects(
        object(value['result'])['episodes'],
      ).where((episode) => members || episode['status'] != 13))
        SourceEpisode(
          label:
              '第${episode['title']}话 · ${episode['long_title']}${episode['badge'] == '' ? '' : ' · ${episode['badge']}'}',
          line: line,
          ref: StreamRef(instance.id, {
            'epId': episode['id'],
            'bvid': episode['bvid'],
            'cid': episode['cid'],
            'line': line,
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
    await guest(cancel);
    // The season player API caps guests at 480p; official free episodes play
    // through the video player API, whose `try_look` lifts guests to 1080p.
    final value = await request('/x/player/playurl', {
      'bvid': '${ref.data['bvid']}',
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
            .where((track) => _mediaUrls(track).isNotEmpty)
            .where((track) => '${track['codecs']}'.startsWith('avc1'))
            .toList()
          ..sort(
            (a, b) => number(b['bandwidth']).compareTo(number(a['bandwidth'])),
          );
    final audios =
        objects(dash['audio'])
            .where((track) => _mediaUrls(track).isNotEmpty)
            .where((track) => '${track['codecs']}'.startsWith('mp4a'))
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
      audioUrl: _mediaUrl(audios.first),
      format: StreamFormat.file,
      headers: mediaHeaders,
      sourceId: instance.id,
      line: ref.data['line'] as String?,
      quality: '${selected['height']}p',
      danmakuProvider: 'bilibili',
      danmakuLocator: locator,
    );
  }
}

/// Search zones (`typeid`) of commentary (动漫杂谈), music, radio, voice
/// acting, painting, games, news and official extras.
const _asideZones = {
  '253',
  '130',
  '28',
  '31',
  '59',
  '193',
  '29',
  '243',
  '267',
  '257',
  '162',
  '17',
  '172',
  '136',
  '51',
  '152',
};

/// The track's Bilibili-hosted `upos-` mirror; the primary URL is often a
/// third-party PCDN edge whose TLS handshakes fail intermittently.
String _mediaUrl(Json track) {
  final urls = _mediaUrls(track);
  return urls.firstWhere(
    (url) => Uri.tryParse(url)?.host.startsWith('upos-') ?? false,
    orElse: () => urls.first,
  );
}

List<String> _mediaUrls(Json track) => [
  for (final url in [
    track['baseUrl'],
    if (track['backupUrl'] case final List backups) ...backups,
  ])
    if (url is String && url.isNotEmpty) url,
];

/// Search rows mark the matched words in `<em>`.
String _text(Object? value) => html.parseFragment('${value ?? ''}').text ?? '';

int? _integer(Object? value) => value is num ? value.toInt() : null;

/// "1:02:03" or "2:03".
String _clock(int seconds) {
  String two(int value) => value.toString().padLeft(2, '0');
  final minutes = seconds ~/ 60 % 60, hours = seconds ~/ 3600;
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds % 60)}'
      : '$minutes:${two(seconds % 60)}';
}
