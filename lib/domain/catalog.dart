/// Catalogue subjects, episodes and personal collection state.
///
/// `fromJson` reads the Melon API shapes and the locally stored collection
/// rows; stored JSON keeps its original field names.
library;

import 'dart:async';

typedef _Json = Map<String, dynamic>;

_Json _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<_Json> _objects(Object? value) =>
    value is List ? value.map(_object).toList() : [];
int? _int(Object? value) => value is num ? value.toInt() : null;
double? _double(Object? value) => value is num ? value.toDouble() : null;
String? _text(Object? value) => value is String ? value : null;
List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : [];

/// The first non-blank of [values], or 未命名.
String displayTitle(Iterable<String?> values) =>
    values
        .whereType<String>()
        .where((title) => title.trim().isNotEmpty)
        .firstOrNull ??
    '未命名';

enum CollectionStatus {
  watching(3),
  wish(1),
  completed(2),
  onHold(4),
  dropped(5);

  const CollectionStatus(this.remoteValue);
  final int remoteValue;

  /// Stored and mutation-queue key.
  String get key => this == onHold ? 'on_hold' : name;
  static CollectionStatus parse(String key) =>
      values.firstWhere((v) => v.key == key);
  static CollectionStatus? tryParse(Object? key) =>
      values.where((v) => v.key == key).firstOrNull;
  static CollectionStatus fromRemote(int value) =>
      values.firstWhere((v) => v.remoteValue == value);
}

enum EpisodeStatus {
  unwatched(0),
  wish(1),
  watched(2),
  dropped(3);

  const EpisodeStatus(this.remoteValue);
  final int remoteValue;
  String get key => this == wish ? 'queue' : name;
  static EpisodeStatus parse(String key) =>
      values.firstWhere((v) => v.key == key);
}

class SubjectTag {
  const SubjectTag(this.name, [this.count]);
  final String name;
  final int? count;
}

class Season {
  const Season({this.year, this.label});
  final int? year;
  final String? label;
}

class InfoField {
  const InfoField(this.key, this.value);
  final String key, value;
}

/// A character (with voice actors) or a staff member.
class Credit {
  const Credit({
    required this.id,
    required this.name,
    this.nameCn,
    this.role,
    this.imageUrl,
    this.actors = const [],
  });

  factory Credit.fromJson(Map<String, dynamic> value) {
    final images = _object(value['images']);
    return Credit(
      id: _int(value['characterId'] ?? value['personId'] ?? value['id']) ?? 0,
      name: _text(value['name']) ?? '',
      nameCn: _text(value['nameCn']) ?? _text(value['displayName']),
      role: _text(value['role']) ?? _text(value['relation']),
      imageUrl: [
        value['imageUrl'],
        value['coverUrl'],
        images['medium'],
        images['common'],
        images['large'],
        images['small'],
        images['grid'],
      ].whereType<String>().where((url) => url.isNotEmpty).firstOrNull,
      actors: _objects(value['actors']).map(Credit.fromJson).toList(),
    );
  }

  final int id;
  final String name;
  final String? nameCn, role, imageUrl;
  final List<Credit> actors;
  String get title => displayTitle([nameCn, name]);

  Credit withRole(String? role, {String? imageUrl}) => Credit(
    id: id,
    name: name,
    nameCn: nameCn,
    role: role,
    imageUrl: imageUrl ?? this.imageUrl,
    actors: actors,
  );
}

class Episode {
  const Episode({
    required this.id,
    required this.subjectId,
    required this.sort,
    this.absolute,
    this.main = true,
    this.follows,
    this.name,
    this.nameCn,
    this.airDate,
    this.durationSeconds,
    this.status = EpisodeStatus.unwatched,
  });

  factory Episode.fromJson(Map<String, dynamic> value) => Episode(
    id: _int(value['episodeId']) ?? 0,
    subjectId: _int(value['subjectId']) ?? 0,
    sort: _double(value['ep'] ?? value['sort']) ?? 0,
    absolute: _double(value['absolute']),
    main: const [null, 0, 'main'].contains(value['type']),
    follows: _double(value['follows']),
    name: _text(value['name']),
    nameCn: _text(value['nameCn']) ?? _text(value['displayName']),
    airDate: _text(value['airdate']) ?? _text(value['airDate']),
    durationSeconds: _int(value['duration']),
    status: value['status'] is String
        ? EpisodeStatus.parse(value['status'] as String)
        : EpisodeStatus.unwatched,
  );

  final int id, subjectId;
  final double sort;

  /// Bangumi's number across seasons (`sort`), which releases of a sequel
  /// often use instead of [sort]: season 2 episode 1 can be episode 29.
  final double? absolute;

  /// False for a special: an SP, OVA, 番外 or 总集篇 that Bangumi lists
  /// apart from the main episodes. Subjects list episodes in broadcast
  /// order, so a special sits where it aired.
  final bool main;

  /// For a special aired between main episodes, the number of the one
  /// before it: 17 for SP1 aired between episodes 17 and 18.
  final double? follows;
  final String? name, nameCn, airDate;
  final int? durationSeconds;
  final EpisodeStatus status;
  String get title => displayTitle([nameCn, name]);

  /// The episode number as shown: `12`, or `12.5`.
  String get number =>
      sort == sort.roundToDouble() ? '${sort.toInt()}' : '$sort';

  /// A special whose number main episodes also use (SP1 beside episode 1),
  /// so it is named and matched as a special rather than by its number.
  bool get numberedApart => !main && sort == sort.roundToDouble();

  /// `第 12 话`, or `SP1` for a special.
  String get label => main ? '第 $number 话' : 'SP$number';

  /// [label] with where a special aired: `SP1（17.5）`.
  String get placedLabel => between == null ? label : '$label（$between）';

  /// Where a special aired among the main episodes, `17.5` for one
  /// between 17 and 18; null when that is its own number (SP 11.5).
  String? get between {
    final value = follows == null ? null : follows! + .5;
    if (value == null || value == sort) return null;
    return value == value.roundToDouble() ? '${value.toInt()}' : '$value';
  }

  /// A recap or a programme about the show rather than part of it, which
  /// autoplay can pass over. Specials are judged by name (総集編,
  /// 振り返り特番, 放送直前特番, トーク); a main episode only when it is
  /// named a recap, since story titles use words such as 配信 and イベント.
  bool get extra => RegExp(
    main
        ? r'総集|总集|總集'
        : r'総集|总集|總集|振り返り|回顧|回顾|ダイジェスト|特番|特別番組|特别节目|直前|トーク|発表会|recap|digest',
    caseSensitive: false,
  ).hasMatch('$name $nameCn');
  bool get watched => status == EpisodeStatus.watched;
  DateTime? get aired => DateTime.tryParse(airDate ?? '');

  Episode withStatus(EpisodeStatus status) => Episode(
    id: id,
    subjectId: subjectId,
    sort: sort,
    absolute: absolute,
    main: main,
    follows: follows,
    name: name,
    nameCn: nameCn,
    airDate: airDate,
    durationSeconds: durationSeconds,
    status: status,
  );
}

/// The signed-in user's collection entry for a subject.
class SubjectCollection {
  const SubjectCollection({
    this.status,
    this.score = 0,
    this.tags = const [],
    this.comment = '',
    this.collectedAt,
  });

  /// Null while a subject is outside the collection.
  final CollectionStatus? status;
  final int score;
  final List<String> tags;
  final String comment;

  /// When the entry was collected or its status last changed, as Bangumi
  /// records it; entries collected here keep the local time until a pull.
  final DateTime? collectedAt;

  SubjectCollection apply(CollectionChange change) => SubjectCollection(
    status: change.status ?? status,
    score: change.status == CollectionStatus.wish ? 0 : change.score ?? score,
    tags: change.tags ?? tags,
    comment: change.comment ?? comment,
    collectedAt: collectedAt,
  );
}

/// Fields to change on a collection entry; null fields stay as they are.
class CollectionChange {
  const CollectionChange({
    this.status,
    this.score,
    this.tags,
    this.comment,
    this.completeEpisodes = false,
  });
  final CollectionStatus? status;
  final int? score;
  final List<String>? tags;
  final String? comment;

  /// Marks every main episode watched; only with [CollectionStatus.completed].
  final bool completeEpisodes;
  bool get isEmpty =>
      status == null &&
      score == null &&
      tags == null &&
      comment == null &&
      !completeEpisodes;
}

/// A catalogue subject: a list card, a schedule entry, a related subject, a
/// collection row, or a full detail with episodes and credits.
class Subject {
  const Subject({
    required this.id,
    this.name,
    this.nameCn,
    this.displayName,
    this.coverUrl,
    this.summary,
    this.airDate,
    this.platform,
    this.season,
    this.episodeTotal,
    this.score,
    this.rank,
    this.ratingCount,
    this.collectionTotal,
    this.tags = const [],
    this.metaTags = const [],
    this.aliases = const [],
    this.infoBox = const [],
    this.collectionStats = const {},
    this.characters = const [],
    this.staff = const [],
    this.episodes = const [],
    this.detailed = false,
    this.pending,
    this.collection,
    this.watchedEpisodes,
    this.airingAt,
    this.relation,
  });

  factory Subject.fromJson(Map<String, dynamic> value) {
    final rating = _object(value['rating']);
    final season = _object(value['season']);
    final stats = _object(value['collectionStats']);
    final collection = value['collection'];
    return Subject(
      id: _int(value['subjectId'] ?? value['id']) ?? 0,
      name: _text(value['name']),
      nameCn: _text(value['nameCn']) ?? _text(value['displayName']),
      displayName: _text(value['displayName']),
      coverUrl: _text(value['coverUrl']),
      summary: _text(value['summary']),
      airDate: _text(value['airDate']),
      platform: _text(value['platform']),
      season: season.isEmpty
          ? null
          : Season(
              year: _int(season['year']) ?? int.tryParse('${season['year']}'),
              label: _text(season['label']),
            ),
      episodeTotal: _int(value['episodeTotal']),
      score: _double(value['score'] ?? rating['score']),
      rank: _int(value['rank']),
      ratingCount: _int(value['ratingCount']),
      collectionTotal: _int(value['collectionTotal']),
      tags: [
        for (final tag in _objects(value['tags']))
          SubjectTag('${tag['name']}', _int(tag['count'])),
      ],
      metaTags: _strings(value['metaTags']),
      aliases: [
        for (final alias in value['aliases'] is List ? value['aliases'] : [])
          if (alias is String)
            alias
          else if (alias is Map && alias['name'] is String)
            alias['name'] as String,
      ],
      infoBox: [
        for (final row in _objects(value['infoBox']))
          InfoField('${row['key']}', '${row['value']}'),
      ],
      collectionStats: {
        for (final status in CollectionStatus.values)
          status: ?_int(stats[status.key]),
      },
      characters: _objects(value['characters']).map(Credit.fromJson).toList(),
      staff: _objects(value['staff']).map(Credit.fromJson).toList(),
      episodes: _objects(value['episodes']).map(Episode.fromJson).toList(),
      detailed: value.containsKey('episodes'),
      pending: value['_pending'] is List
          ? _strings(value['_pending']).toSet()
          : null,
      collection: collection is Map
          ? SubjectCollection(
              status: CollectionStatus.tryParse(collection['status']),
              score: _int(collection['score']) ?? 0,
              tags: _strings(collection['tags']),
              comment: _text(collection['comment']) ?? '',
            )
          : _collectionRow(value),
      // Bangumi as its pages show it: progress another client set beyond
      // the episode count reads as the count.
      watchedEpisodes: switch ((
        _int(value['watchedEpisodes']),
        _int(value['episodeTotal']),
      )) {
        (final watched?, final total?) when watched > total => total,
        (final watched, _) => watched,
      },
      airingAt: DateTime.tryParse('${value['airingAt'] ?? ''}'),
      relation: _text(value['relation']),
    );
  }

  final int id;
  final String? name, nameCn, displayName, coverUrl, summary, airDate;
  final String? platform;
  final Season? season;
  final int? episodeTotal, rank, ratingCount;

  /// Bangumi users who collected the subject; stored collection rows only.
  final int? collectionTotal;
  final double? score;
  final List<SubjectTag> tags;
  final List<String> metaTags, aliases;
  final List<InfoField> infoBox;
  final Map<CollectionStatus, int> collectionStats;
  final List<Credit> characters, staff;

  /// Main episodes only.
  final List<Episode> episodes;

  /// Whether the detail (with an episode list) has been received.
  final bool detailed;

  /// Detail parts still streaming in, or failed when loading has ended.
  final Set<String>? pending;
  final SubjectCollection? collection;
  final int? watchedEpisodes;

  /// Schedule entries: when the episode airs.
  final DateTime? airingAt;

  /// Related subjects: how this one relates.
  final String? relation;

  String get title => displayTitle([nameCn, displayName, name]);
  CollectionStatus? get status => collection?.status;

  /// True while any main episode aired within 90 days of [now].
  bool airing({DateTime? now}) {
    final today = now ?? DateTime.now();
    return episodes.any(
      (episode) =>
          episode.main &&
          (episode.aired?.isAfter(today.subtract(const Duration(days: 90))) ??
              false),
    );
  }

  Episode? episode(int id) =>
      episodes.where((episode) => episode.id == id).firstOrNull;

  /// The episode broadcast after [id], specials included, passing over
  /// recaps and programmes ([Episode.extra]) when [skipExtras].
  Episode? after(int id, {required bool skipExtras}) {
    final index = episodes.indexWhere((episode) => episode.id == id);
    if (index < 0) return null;
    return episodes
        .skip(index + 1)
        .where((episode) => !skipExtras || !episode.extra)
        .firstOrNull;
  }

  Subject copyWith({
    SubjectCollection? collection,
    List<Episode>? episodes,
    bool clearCollection = false,
  }) => Subject(
    id: id,
    name: name,
    nameCn: nameCn,
    displayName: displayName,
    coverUrl: coverUrl,
    summary: summary,
    airDate: airDate,
    platform: platform,
    season: season,
    episodeTotal: episodeTotal,
    score: score,
    rank: rank,
    ratingCount: ratingCount,
    collectionTotal: collectionTotal,
    tags: tags,
    metaTags: metaTags,
    aliases: aliases,
    infoBox: infoBox,
    collectionStats: collectionStats,
    characters: characters,
    staff: staff,
    episodes: episodes ?? this.episodes,
    detailed: detailed,
    pending: pending,
    collection: clearCollection ? null : collection ?? this.collection,
    watchedEpisodes: watchedEpisodes,
    airingAt: airingAt,
    relation: relation,
  );
}

/// A stored collection row keeps its fields at the top level.
SubjectCollection? _collectionRow(Map<String, dynamic> value) {
  final status = CollectionStatus.tryParse(value['status']);
  return status == null
      ? null
      : SubjectCollection(
          status: status,
          score: _int(value['userScore']) ?? 0,
          tags: _strings(value['collectionTags']),
          comment: _text(value['comment']) ?? '',
          collectedAt: DateTime.tryParse('${value['collectedAt'] ?? ''}'),
        );
}

class SchedulePage {
  const SchedulePage({required this.date, required this.items});
  final String? date;
  final List<Subject> items;
}

class ScheduleDay {
  const ScheduleDay({
    required this.date,
    required this.weekday,
    required this.items,
  });
  final String date, weekday;
  final List<Subject> items;
}

enum SubjectSort {
  match('最佳匹配'),
  heat('按热度'),
  rank('按排名'),
  score('按评分');

  const SubjectSort(this.label);
  final String label;
}

const _same = Object();

/// A catalogue search: a title keyword or a Bangumi tag, narrowed by
/// Bangumi's public tags (kind, source, region, genres) and air time.
class SubjectQuery {
  const SubjectQuery({
    this.keyword = '',
    this.tag,
    this.kind,
    this.source,
    this.region,
    this.genres = const {},
    this.year,
    this.month,
    this.before = false,
    this.sort,
  });

  /// Typed text; `#百合` searches the tag 百合.
  factory SubjectQuery.parse(String text) {
    final value = text.trim();
    return value.startsWith('#') && value.length > 1
        ? SubjectQuery(tag: value.substring(1).trim())
        : SubjectQuery(keyword: value);
  }

  /// The quarter [date] belongs to (see [airDates]).
  factory SubjectQuery.season(DateTime date) {
    final start = DateTime(date.year, date.month + (date.day >= 25 ? 1 : 0));
    return SubjectQuery(
      year: start.year,
      month: (start.month - 1) ~/ 3 * 3 + 1,
    );
  }

  /// A tag clicked on a subject: one of Bangumi's public tags offered below
  /// becomes that filter, any other searches by tag.
  factory SubjectQuery.ofTag(String name) => kinds.contains(name)
      ? SubjectQuery(kind: name)
      : sources.contains(name)
      ? SubjectQuery(source: name)
      : regions.contains(name)
      ? SubjectQuery(region: name)
      : genreTags.contains(name)
      ? SubjectQuery(genres: {name})
      : SubjectQuery(tag: name);

  /// Bangumi's public tags offered as filters, as bgm.tv's browser lists
  /// them, without ones that match almost nothing.
  static const kinds = ['TV', 'WEB', 'OVA', '剧场版', '动态漫画'];
  static const sources = ['原创', '漫画改', '小说改', '游戏改', '影视改'];
  static const regions = ['日本', '中国', '欧美', '韩国'];
  static const genreTags = [
    '科幻', '喜剧', '同人', '百合', '校园', '惊悚', '后宫', '机战', // bgm.tv order
    '悬疑', '恋爱', '奇幻', '推理', '运动', '耽美', '音乐', '战斗',
    '冒险', '萌系', '穿越', '玄幻', '乙女', '恐怖', '历史', '日常',
    '剧情', '武侠', '短片集', '美食', '职场',
  ];

  final String keyword;
  final String? tag, kind, source, region;

  /// All of them apply.
  final Set<String> genres;

  /// Air year; with [month], the quarter starting that month.
  final int? year, month;

  /// Aired before [year] instead of within it.
  final bool before;

  /// Bangumi `air_date` conditions for the chosen time. Shows premiering in
  /// the last week of the month before belong to a season (葬送的芙莉莲,
  /// 2023-09-29, is an October show), so a quarter starts on the 25th of that
  /// month; a year spans its four quarters.
  List<String> get airDates {
    final year = this.year;
    if (year == null) return const [];
    String start(int year, int month) =>
        DateTime(year, month - 1, 25).toIso8601String().substring(0, 10);
    final month = this.month;
    return before
        ? ['<${start(year, 1)}']
        : month == null
        ? ['>=${start(year, 1)}', '<${start(year + 1, 1)}']
        : ['>=${start(year, month)}', '<${start(year, month + 3)}'];
  }

  final SubjectSort? sort;

  /// Matching only ranks title hits; without a keyword results go by heat.
  SubjectSort get order => keyword.isEmpty
      ? (sort == null || sort == SubjectSort.match ? SubjectSort.heat : sort!)
      : sort ?? SubjectSort.match;

  /// The text the search field shows for this query.
  String get text => keyword.isNotEmpty
      ? keyword
      : tag == null
      ? ''
      : '#$tag';

  bool get filtered =>
      kind != null ||
      source != null ||
      region != null ||
      genres.isNotEmpty ||
      year != null;

  String get key => [
    keyword.toLowerCase(),
    tag ?? '',
    kind ?? '',
    source ?? '',
    region ?? '',
    (genres.toList()..sort()).join('+'),
    '${before ? '<' : ''}${year ?? ''}-${month ?? ''}',
    order.name,
  ].join('|');

  SubjectQuery copyWith({
    String? keyword,
    Object? tag = _same,
    Object? kind = _same,
    Object? source = _same,
    Object? region = _same,
    Set<String>? genres,
    Object? year = _same,
    Object? month = _same,
    bool? before,
    SubjectSort? sort,
  }) => SubjectQuery(
    keyword: keyword ?? this.keyword,
    tag: tag == _same ? this.tag : tag as String?,
    kind: kind == _same ? this.kind : kind as String?,
    source: source == _same ? this.source : source as String?,
    region: region == _same ? this.region : region as String?,
    genres: genres ?? this.genres,
    year: year == _same ? this.year : year as int?,
    month: month == _same ? this.month : month as int?,
    before: before ?? this.before,
    sort: sort ?? this.sort,
  );

  /// The same keyword, tag and order without filters.
  SubjectQuery get unfiltered =>
      SubjectQuery(keyword: keyword, tag: tag, sort: sort);
}

class SubjectResults {
  const SubjectResults({
    required this.items,
    required this.offset,
    required this.total,
    required this.hasMore,
  });
  final List<Subject> items;
  final int offset, total;
  final bool hasMore;
}

class AccountProfile {
  const AccountProfile({
    required this.userId,
    this.username,
    this.nickname,
    this.avatarUrl,
  });
  factory AccountProfile.fromJson(Map<String, dynamic> value) => AccountProfile(
    userId: '${value['userId'] ?? 'local'}',
    username: _text(value['username']),
    nickname: _text(value['nickname']),
    avatarUrl: _text(value['avatarUrl']),
  );
  final String userId;
  final String? username, nickname, avatarUrl;
}

class SyncState {
  const SyncState({this.pending = 0, this.error, this.syncedAt});
  final int pending;
  final String? error, syncedAt;
}

/// A post on a subject's community tab.
class CommunityEntry {
  const CommunityEntry({
    required this.id,
    required this.userId,
    required this.author,
    this.avatarUrl,
    this.score = 0,
    this.status,
    this.replies = 0,
    this.title,
    this.text = '',
    this.time,
  });
  final int id;
  final String userId, author;
  final String? avatarUrl, title;
  final int score, replies;
  final CollectionStatus? status;
  final String text;

  /// Unix seconds.
  final int? time;
}

/// A post in a discussion topic, with the replies nested under it.
class TopicPost {
  const TopicPost({
    required this.id,
    required this.author,
    this.avatarUrl,
    this.time,
    this.content = '',
    this.replies = const [],
  });
  final int id;
  final String author;
  final String? avatarUrl;

  /// Unix seconds.
  final int? time;

  /// Bangumi BBCode.
  final String content;
  final List<TopicPost> replies;
}

class CommunityPage {
  const CommunityPage({required this.entries, required this.total});
  final List<CommunityEntry> entries;
  final int total;
}

/// A subject's community posts and related subjects, as the signed-in
/// account sees them.
abstract interface class SubjectCommunitySource {
  /// The account whose view is shown; changes on sign-in and sign-out.
  String get userId;
  AccountProfile? get profile;

  /// One page of `comments`, `reviews` or `topics`.
  Future<CommunityPage> page(
    int subjectId,
    String segment, {
    int offset = 0,
    bool refresh = false,
  });

  /// A discussion topic: its opening post, then the replies.
  Future<List<TopicPost>> topic(int topicId);

  /// The full BBCode of a review, whose listing holds only its start.
  Future<String> blog(int entryId);

  /// An episode's comments, oldest first, each with its replies.
  Future<List<TopicPost>> episodeComments(
    int episodeId, {
    bool refresh = false,
  });
  Future<List<Subject>> relations(int subjectId, {bool refresh = false});
}

/// Cover addresses known for subjects, shared across pages.
abstract interface class SubjectCovers {
  String? coverFor(int id);

  /// Resolves the cover for [id] from cached or basic catalogue metadata.
  Future<void> resolveCover(int id);

  /// Ids whose cover became known.
  Stream<int> get coverUpdates;
}

/// Public catalogue reads. An `onCached` callback receives the cached value
/// before the request completes.
abstract interface class Catalog implements SubjectCovers {
  /// A list card or stored row; remembers its cover for other pages.
  Subject card(Map<String, dynamic> value);

  /// The locally cached detail, without a request.
  Future<Subject?> cached(int id);
  Future<SubjectResults> search(
    SubjectQuery query, {
    int offset = 0,
    void Function(SubjectResults)? onCached,
  });
  Future<List<Subject>> trending({
    bool refresh = false,
    int? limit,
    void Function(List<Subject>)? onCached,
  });

  /// The schedule's current day, `yyyy-MM-dd`.
  String get scheduleDate;
  Future<SchedulePage> today({
    bool refresh = false,
    void Function(SchedulePage)? onCached,
  });
  Future<List<ScheduleDay>> calendar({
    void Function(List<ScheduleDay>)? onCached,
  });
  Future<Subject> subject(
    int id, {
    FutureOr<void> Function(Subject)? onAvailable,
    bool forPlayback = false,
  });
}

/// The account collection edits sync to; `local` while signed out.
abstract interface class Account {
  String get userId;

  /// Present while signed in.
  AccountProfile? get profile;

  /// Saved credentials must be unlocked before requests are authorized.
  bool get needsAuthorization;

  /// An authorized API request; throws once the account changes.
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  });
  Future<void> signIn();
  Future<void> cancelSignIn();
  Future<void> signOut();
}
