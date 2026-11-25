import 'package:flutter/foundation.dart';

import '../../core/settings.dart';

import '../../core/json.dart';
import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';

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

/// The schedule's filter: kinds and regions to list (all while empty),
/// what to hide, and R18 shows.
class ScheduleFilter {
  const ScheduleFilter({
    this.kinds = const {},
    this.regions = const {},
    this.hideLongRunning = false,
    this.hidePastSeasons = false,
    this.adult = AdultFilter.hide,
  });

  factory ScheduleFilter.fromJson(Json value) => ScheduleFilter(
    kinds: {...(value['kinds'] as List? ?? const []).whereType<String>()},
    regions: {...(value['regions'] as List? ?? const []).whereType<String>()},
    hideLongRunning: value['hideLongRunning'] == true,
    hidePastSeasons: value['hidePastSeasons'] == true,
    adult: AdultFilter.values.asNameMap()[value['adult']] ?? AdultFilter.hide,
  );

  static const kindOptions = ['TV', 'WEB', '其他'];
  static const regionOptions = ['日本', '中国', '其他'];

  final Set<String> kinds, regions;
  final bool hideLongRunning, hidePastSeasons;
  final AdultFilter adult;

  /// Whether it can leave anything out.
  bool get active =>
      kinds.isNotEmpty ||
      regions.isNotEmpty ||
      hideLongRunning ||
      hidePastSeasons ||
      adult != AdultFilter.show;

  /// Whether [subject] is listed. A show whose tags name no country passes
  /// any region.
  bool accepts(Subject subject, DateTime now) {
    final region = scheduleRegion(subject);
    return (kinds.isEmpty || kinds.contains(scheduleKind(subject))) &&
        (regions.isEmpty || region == null || regions.contains(region)) &&
        !(hideLongRunning && isLongRunning(subject, now)) &&
        !(hidePastSeasons && isFromPastSeason(subject, now)) &&
        switch (adult) {
          AdultFilter.show => true,
          AdultFilter.hide => !isAdult(subject),
          AdultFilter.only => isAdult(subject),
        };
  }

  ScheduleFilter copyWith({
    Set<String>? kinds,
    Set<String>? regions,
    bool? hideLongRunning,
    bool? hidePastSeasons,
    AdultFilter? adult,
  }) => ScheduleFilter(
    kinds: kinds ?? this.kinds,
    regions: regions ?? this.regions,
    hideLongRunning: hideLongRunning ?? this.hideLongRunning,
    hidePastSeasons: hidePastSeasons ?? this.hidePastSeasons,
    adult: adult ?? this.adult,
  );

  Json toJson() => {
    'kinds': [...kinds],
    'regions': [...regions],
    'hideLongRunning': hideLongRunning,
    'hidePastSeasons': hidePastSeasons,
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
      'hideLongRunning': '时间表 › 隐藏长篇',
      'hidePastSeasons': '时间表 › 隐藏往季',
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
