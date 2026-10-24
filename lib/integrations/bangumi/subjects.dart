import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/catalog.dart';

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

  /// One page of anime matching [query], as `data/total/offset/hasMore`.
  /// Kind, source, region and genres are Bangumi's public tags (`meta_tags`);
  /// [SubjectQuery.tag] is a user tag.
  Future<Json> search(
    SubjectQuery query, {
    required int limit,
    required int offset,
  }) async {
    String day(int year, [int month = 1]) =>
        '$year-${'$month'.padLeft(2, '0')}-01';
    final year = query.year;
    final month = query.month;
    final metaTags = [
      ?query.kind,
      ?query.source,
      ?query.region,
      ...query.genres,
    ];
    final response = object(
      await api.json(
        Uri.parse('$_origin/v0/search/subjects?limit=$limit&offset=$offset'),
        method: 'POST',
        body: {
          'keyword': query.keyword,
          'sort': query.order.name,
          'filter': {
            'type': [2],
            'nsfw': false,
            if (query.tag case final tag?) 'tag': [tag],
            if (metaTags.isNotEmpty) 'meta_tags': metaTags,
            if (year != null)
              'air_date': query.before
                  ? ['<${day(year)}']
                  : month == null
                  ? ['>=${day(year)}', '<${day(year + 1)}']
                  : [
                      '>=${day(year, month)}',
                      '<${month > 9 ? day(year + 1) : day(year, month + 3)}',
                    ],
            // Unranked subjects would otherwise lead the ranking.
            if (query.order == SubjectSort.rank) 'rank': ['>0'],
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

  /// Every special (SP, OVA, 番外, 总集篇) by Bangumi's number, placed in
  /// broadcast order by its air date: `order` puts it after the last main
  /// episode aired before that day, and `follows` names that episode when
  /// another main episode comes after it (SP1 aired between 17 and 18
  /// follows 17). Specials without a date come last.
  List<Json> _specials(List<Json> main, List<Json> specials) {
    final run = [...main]
      ..sort((a, b) => number(a['absolute']).compareTo(number(b['absolute'])));
    final found = <Json>[];
    for (final e in specials) {
      final date = _text(e['airdate']);
      final special = {...e, 'type': 'special', 'ep': e['sort']};
      found.add(special);
      if (date == null || run.isEmpty) continue;
      final before = run.lastIndexWhere(
        (m) => (_text(m['airdate']) ?? '9999').compareTo(date) < 0,
      );
      if (before < 0) {
        special['order'] = number(run.first['absolute']) - .5;
        continue;
      }
      special['order'] = number(run[before]['absolute']) + .5;
      if (before < run.length - 1) special['follows'] = run[before]['sort'];
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
