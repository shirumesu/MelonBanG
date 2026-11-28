import 'package:flutter/foundation.dart';

import '../../core/json.dart';
import '../../core/settings.dart';
import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';
import 'schedule_week.dart';

/// What the schedule shows of R18 shows.
enum AdultFilter {
  show('显示'),
  hide('隐藏'),
  only('仅限');

  const AdultFilter(this.label);
  final String label;
}

/// Bangumi's R18 mark, or 里番, R18 and 18禁 tags counting at least 5 and
/// 30% of the leading tag. Bangumi keeps R18-marked subjects out of TV
/// schedules, so the tags tell a schedule's R18 shows apart; 卖肉
/// (fanservice) does not count, as it marks ordinary series.
bool isAdult(Subject subject) {
  if (subject.nsfw) return true;
  final lead = subject.tags.fold(0, (most, tag) => _max(most, tag.count));
  final adult = subject.tags
      .where((tag) => const {'里番', 'R18', '18禁'}.contains(tag.name))
      .fold(0, (sum, tag) => sum + (tag.count ?? 0));
  return adult >= 5 && adult * 10 >= lead * 3;
}

int _max(int a, int? b) => b != null && b > a ? b : a;

/// A show of 40 episodes or more, or one airing for over a year: the
/// children's and family shows that air all year (柯南, 宝可梦, 光之美少女).
bool isLongRunning(Subject subject, DateTime now) {
  if ((subject.episodeTotal ?? 0) >= 40) return true;
  final began = DateTime.tryParse(subject.airDate ?? '');
  return began != null &&
      began.isBefore(now.subtract(const Duration(days: 365)));
}

/// A show that began in an earlier season and is still airing. Premieres
/// in the last three weeks before a season are that season's.
bool isFromPastSeason(Subject subject, DateTime now) {
  final began = DateTime.tryParse(subject.airDate ?? '');
  return began != null &&
      began.isBefore(seasonStart(now).subtract(const Duration(days: 21)));
}

/// TV, WEB or 其他 (OVA, films): how a show airs.
String scheduleKind(Subject subject) =>
    switch (subject.platform?.toUpperCase()) {
      'TV' || null => 'TV',
      'WEB' => 'WEB',
      _ => '其他',
    };

/// 日本, 中国 or 其他 by Bangumi's meta tags; null without any.
String? scheduleRegion(Subject subject) {
  final tags = {...subject.metaTags};
  if (tags.contains('日本')) return '日本';
  if (tags.contains('中国') || tags.contains('国产')) return '中国';
  return tags.isEmpty ? null : '其他';
}

/// What a show is adapted from, among Bangumi's meta tags.
const scheduleSources = ['漫画改', '小说改', '游戏改', '原创'];

const _notTopics = {
  'TV',
  'WEB',
  'OVA',
  '剧场版',
  '日本',
  '中国',
  '国产',
  '欧美',
  '韩国',
  '子供向',
};

/// The meta tags that say what a show is (漫画改, 奇幻), in Bangumi's order:
/// not its kind, region or audience, which the schedule shows otherwise.
List<String> scheduleTopics(Subject subject) =>
    subject.metaTags.where((tag) => !_notTopics.contains(tag)).toSet().toList();

/// [scheduleTopics] but the source: the genres.
Iterable<String> scheduleGenres(Subject subject) =>
    scheduleTopics(subject).where((tag) => !scheduleSources.contains(tag));

Set<String> _names(Object? value) => {
  ...(value as List? ?? const []).whereType<String>(),
};

/// The schedule's filter: kinds, regions, sources and genres to list (all
/// while empty), what to hide, a score below which rated shows are hidden,
/// which quiet shows fold to the end of their day, and R18 shows.
class ScheduleFilter {
  const ScheduleFilter({
    this.kinds = const {},
    this.regions = const {},
    this.sources = const {},
    this.genres = const {},
    this.hideLongRunning = false,
    this.hidePastSeasons = false,
    this.minScore = 0,
    this.folds = const {...ScheduleFold.values},
    this.adult = AdultFilter.hide,
  });

  factory ScheduleFilter.fromJson(Json value) => ScheduleFilter(
    kinds: _names(value['kinds']),
    regions: _names(value['regions']),
    sources: _names(value['sources']),
    genres: _names(value['genres']),
    hideLongRunning: value['hideLongRunning'] == true,
    hidePastSeasons: value['hidePastSeasons'] == true,
    minScore: switch (value['minScore']) {
      final num score => score.toDouble(),
      _ => 0,
    },
    // Filters saved before folding existed fold every kind.
    folds: value['folds'] is List
        ? {
            for (final fold in ScheduleFold.values)
              if (_names(value['folds']).contains(fold.key)) fold,
          }
        : const {...ScheduleFold.values},
    adult: AdultFilter.values.asNameMap()[value['adult']] ?? AdultFilter.hide,
  );

  static const kindOptions = ['TV', 'WEB', '其他'];
  static const regionOptions = ['日本', '中国', '其他'];

  final Set<String> kinds, regions, sources, genres;
  final bool hideLongRunning, hidePastSeasons;

  /// Shows rated below it are hidden; 0 hides none. Shows without a score
  /// yet stay.
  final double minScore;
  final Set<ScheduleFold> folds;
  final AdultFilter adult;

  /// Lists every show but R18 ones, folding as before.
  ScheduleFilter get cleared => ScheduleFilter(folds: folds);

  @override
  bool operator ==(Object other) =>
      other is ScheduleFilter &&
      setEquals(kinds, other.kinds) &&
      setEquals(regions, other.regions) &&
      setEquals(sources, other.sources) &&
      setEquals(genres, other.genres) &&
      hideLongRunning == other.hideLongRunning &&
      hidePastSeasons == other.hidePastSeasons &&
      minScore == other.minScore &&
      setEquals(folds, other.folds) &&
      adult == other.adult;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(kinds),
    Object.hashAllUnordered(regions),
    Object.hashAllUnordered(sources),
    Object.hashAllUnordered(genres),
    hideLongRunning,
    hidePastSeasons,
    minScore,
    Object.hashAllUnordered(folds),
    adult,
  );

  /// Whether it can leave anything out.
  bool get active =>
      kinds.isNotEmpty ||
      regions.isNotEmpty ||
      sources.isNotEmpty ||
      genres.isNotEmpty ||
      hideLongRunning ||
      hidePastSeasons ||
      minScore > 0 ||
      adult != AdultFilter.show;

  /// Whether [subject] is listed. A show whose tags name no country passes
  /// any region.
  bool accepts(Subject subject, DateTime now) {
    final region = scheduleRegion(subject);
    return (kinds.isEmpty || kinds.contains(scheduleKind(subject))) &&
        (regions.isEmpty || region == null || regions.contains(region)) &&
        (sources.isEmpty || subject.metaTags.any(sources.contains)) &&
        (genres.isEmpty || subject.metaTags.any(genres.contains)) &&
        !(hideLongRunning && isLongRunning(subject, now)) &&
        !(hidePastSeasons && isFromPastSeason(subject, now)) &&
        !scoredBelow(subject) &&
        switch (adult) {
          AdultFilter.show => true,
          AdultFilter.hide => !isAdult(subject),
          AdultFilter.only => isAdult(subject),
        };
  }

  /// Whether [subject] is rated below [minScore].
  bool scoredBelow(Subject subject) {
    final score = subject.score;
    return minScore > 0 && score != null && score > 0 && score < minScore;
  }

  /// Why [subject] folds under the chosen [folds], or null to list it.
  /// Shows in the user's collection never fold.
  ScheduleFold? fold(Subject subject, DateTime now, {required bool collected}) {
    if (collected) return null;
    final fold = scheduleFold(subject, now);
    return folds.contains(fold) ? fold : null;
  }

  ScheduleFilter copyWith({
    Set<String>? kinds,
    Set<String>? regions,
    Set<String>? sources,
    Set<String>? genres,
    bool? hideLongRunning,
    bool? hidePastSeasons,
    double? minScore,
    Set<ScheduleFold>? folds,
    AdultFilter? adult,
  }) => ScheduleFilter(
    kinds: kinds ?? this.kinds,
    regions: regions ?? this.regions,
    sources: sources ?? this.sources,
    genres: genres ?? this.genres,
    hideLongRunning: hideLongRunning ?? this.hideLongRunning,
    hidePastSeasons: hidePastSeasons ?? this.hidePastSeasons,
    minScore: minScore ?? this.minScore,
    folds: folds ?? this.folds,
    adult: adult ?? this.adult,
  );

  Json toJson() => {
    'kinds': [...kinds],
    'regions': [...regions],
    'sources': [...sources],
    'genres': [...genres],
    'hideLongRunning': hideLongRunning,
    'hidePastSeasons': hidePastSeasons,
    'minScore': minScore,
    'folds': [for (final fold in folds) fold.key],
    'adult': adult.name,
  };
}

/// The saved [ScheduleFilter]; R18 shows are hidden until changed.
class SchedulePreference extends ChangeNotifier {
  SchedulePreference(this._settings) {
    _settings.watch([setting.key], notifyListeners);
  }
  final Settings _settings;

  static const setting = JsonSetting(
    'scheduleFilter',
    sync: SettingSync.synced,
    label: '时间表 › 筛选',
    fieldLabels: {
      'kinds': '时间表 › 类型',
      'regions': '时间表 › 地区',
      'sources': '时间表 › 来源',
      'genres': '时间表 › 题材',
      'hideLongRunning': '时间表 › 隐藏长篇',
      'hidePastSeasons': '时间表 › 隐藏往季',
      'minScore': '时间表 › 最低评分',
      'folds': '时间表 › 收起',
      'adult': '时间表 › R18',
    },
  );

  ScheduleFilter get value => switch (_settings.get(setting)) {
    final Map<String, dynamic> saved => ScheduleFilter.fromJson(saved),
    _ => const ScheduleFilter(),
  };

  Future<void> set(ScheduleFilter value) =>
      _settings.set(setting, value.toJson());
}
