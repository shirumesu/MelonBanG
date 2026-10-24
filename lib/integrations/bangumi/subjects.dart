import 'dart:math';

import '../../core/json.dart';
import '../../core/network.dart';

/// Public Bangumi v0 subject reads, mapped to the stored catalogue shapes
/// that `Subject.fromJson` and saved detail documents use.
class BangumiSubjects {
  BangumiSubjects(this.api);
  final ApiClient api;
  static const _origin = 'https://api.bgm.tv';
  static const _episodePage = 200;

  Future<dynamic> _get(String path) => api.json(Uri.parse('$_origin$path'));

  Future<Json> subject(int id) async =>
      _subject(object(await _get('/v0/subjects/$id')));

  /// One page of anime matching [keyword], as `data/total/offset/hasMore`.
  Future<Json> search(
    String keyword, {
    required int limit,
    required int offset,
  }) async {
    final response = object(
      await api.json(
        Uri.parse('$_origin/v0/search/subjects?limit=$limit&offset=$offset'),
        method: 'POST',
        body: {
          'keyword': keyword,
          'sort': 'match',
          'filter': {
            'type': [2],
            'nsfw': false,
          },
        },
      ),
    );
    final data = objects(response['data']).map(_subject).toList();
    final total = number(response['total']).toInt();
    return {
      'data': data,
      'total': total,
      'offset': offset,
      'hasMore': offset + limit < total && offset + limit <= 5000,
    };
  }

  /// Main episodes in order, the first page then the remaining pages, and
  /// last the specials ([_specials]).
  Stream<List<Json>> episodes(int id) async* {
    final main = <Json>[];
    await for (final page in _episodePages(id, 0)) {
      main.addAll(page);
      yield page;
    }
    yield _specials(main, [
      await for (final page in _episodePages(id, 1)) ...page,
    ]);
  }

  Stream<List<Json>> _episodePages(int id, int type) async* {
    String page(int offset) =>
        '/v0/episodes?subject_id=$id&type=$type&limit=$_episodePage&offset=$offset';
    final first = object(await _get(page(0)));
    yield _episodes(first, id);
    final total = number(first['total']).toInt();
    final rest = await Future.wait([
      for (var offset = _episodePage; offset < total; offset += _episodePage)
        _get(page(offset)),
    ]);
    for (final response in rest) {
      yield _episodes(object(response), id);
    }
  }

  /// Every special, by Bangumi's number. Those inside the main run take the
  /// main episodes' numbering, since Bangumi numbers specials across
  /// seasons: a fractional one between or right after main episodes (an
  /// 11.5 recap) as an interlude, and integral ones continuing the last
  /// number (an unaired 13th) as main episodes. The rest, such as
  /// promotional programmes numbered over or before main episodes, keep
  /// Bangumi's number as specials.
  List<Json> _specials(List<Json> main, List<Json> specials) {
    final numbers = {for (final e in main) number(e['absolute'])};
    final first = numbers.isEmpty ? 0 : numbers.reduce(min);
    var last = numbers.isEmpty ? 0 : numbers.reduce(max);
    final offset = main.isEmpty
        ? 0
        : number(main.first['absolute']) - number(main.first['sort']);
    final found = <Json>[];
    for (final e
        in specials..sort(
          (a, b) => number(a['absolute']).compareTo(number(b['absolute'])),
        )) {
      final across = number(e['absolute']);
      final interlude = across != across.roundToDouble();
      if (main.isEmpty ||
          across <= first ||
          numbers.contains(across) ||
          (interlude ? across > last + 1 : across != last + 1)) {
        found.add({...e, 'type': 'special', 'ep': e['sort']});
        continue;
      }
      if (!interlude) last = across;
      final sort = across - offset;
      found.add({
        ...e,
        'type': interlude ? 'interlude' : 'main',
        'sort': sort,
        'ep': sort,
      });
    }
    return found;
  }

  Future<List<Json>> characters(int id) async => [
    for (final character in objects(await _get('/v0/subjects/$id/characters')))
      {
        'characterId': character['id'],
        'name': character['name'],
        'role': character['relation'],
        'imageUrl': ?_image(character['images']),
        'actors': objects(character['actors']).map(_person).toList(),
      },
  ];

  Future<List<Json>> persons(int id) async =>
      objects(await _get('/v0/subjects/$id/persons')).map(_person).toList();

  Json _person(Json person) => {
    'personId': person['id'],
    'name': person['name'],
    'role': person['relation'],
    'imageUrl': ?_image(person['images']),
  };

  List<Json> _episodes(Json response, int subjectId) => [
    for (final episode in objects(response['data']))
      if (number(episode['id']) > 0)
        {
          'episodeId': episode['id'],
          'subjectId': episode['subject_id'] ?? subjectId,
          'type': 'main',
          'sort': number(episode['ep']) > 0 ? episode['ep'] : episode['sort'],
          'ep': episode['ep'],
          'absolute': episode['sort'],
          'name': episode['name'],
          'nameCn': ?_text(episode['name_cn']),
          'airdate': ?_text(episode['airdate']),
          if (number(episode['duration_seconds']) > 0)
            'duration': episode['duration_seconds'],
        },
  ];

  Json _subject(Json subject) {
    final rating = object(subject['rating']);
    final collection = subject['collection'];
    final nameCn = _text(subject['name_cn']);
    final airDate = _text(subject['date']);
    return {
      'subjectId': subject['id'],
      'name': subject['name'],
      'nameCn': ?nameCn,
      'displayName': nameCn ?? subject['name'],
      'coverUrl': ?_image(subject['images']),
      'summary': ?_text(subject['summary']) ?? _text(subject['short_summary']),
      'airDate': ?airDate,
      'season': ?_season(airDate),
      'platform': ?_text(subject['platform']),
      'episodeTotal': ?_positive(subject['eps'] ?? subject['total_episodes']),
      'score': ?_positive(rating['score']),
      'rank': ?_positive(rating['rank']),
      'ratingCount': ?_positive(rating['total']),
      'tags': [
        for (final tag in objects(subject['tags']))
          if (_text(tag['name']) != null)
            {'name': tag['name'], 'count': tag['count']},
      ],
      'metaTags': [
        for (final tag in subject['meta_tags'] as List? ?? const [])
          if (_text(tag) != null) tag,
      ],
      'infoBox': [
        for (final row in objects(subject['infobox']))
          if (_infoValue(row['value']) case final value?)
            {'key': row['key'], 'value': value},
      ],
      if (collection is Map)
        'collectionStats': {
          'wish': collection['wish'] ?? 0,
          'watching': collection['doing'] ?? 0,
          'completed': collection['collect'] ?? 0,
          'on_hold': collection['on_hold'] ?? 0,
          'dropped': collection['dropped'] ?? 0,
        },
    };
  }

  String? _infoValue(Object? value) {
    final text = value is String
        ? value.trim()
        : [
            for (final entry in objects(value))
              if (_text(entry['k']) case final key?)
                '$key: ${entry['v'] ?? ''}'
              else
                '${entry['v'] ?? ''}',
          ].where((entry) => entry.isNotEmpty).join(' / ');
    return text.isEmpty ? null : text;
  }

  Json? _season(String? date) {
    final match = RegExp(r'^(\d{4})-(\d{2})-\d{2}$').firstMatch(date ?? '');
    if (match == null) return null;
    final quarter = (int.parse(match[2]!) - 1) ~/ 3;
    return {
      'year': int.parse(match[1]!),
      'label':
          '${match[1]} ${const ['WINTER', 'SPRING', 'SUMMER', 'FALL'][quarter]}',
    };
  }

  String? _image(Object? images) {
    final set = object(images);
    return [
      set['common'],
      set['medium'],
      set['large'],
      set['small'],
      set['grid'],
    ].map(_text).nonNulls.firstOrNull;
  }

  num? _positive(Object? value) => value is num && value > 0 ? value : null;
  String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;
}
