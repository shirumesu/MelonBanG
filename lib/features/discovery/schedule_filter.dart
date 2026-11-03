import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Bangumi's R18 mark, or a TV show its users tag 里番 (or R18) as much as
/// its leading tag, such as an 8-episode short whose uncensored cut is the
/// point. Shows tagged 卖肉 (fanservice) are not R18: those are ordinary TV
/// series whose users weigh the fanservice, from a gag comedy to a romance.
/// Bangumi keeps R18-marked subjects out of TV schedules, so the tags are
/// what tells a schedule's R18 shows apart.
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

  /// Shows nothing away.
  static const none = ScheduleFilter(adult: AdultFilter.show);

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
  SchedulePreference(this._preferences);
  final SharedPreferences _preferences;
  static const _key = 'scheduleFilter';

  ScheduleFilter get value {
    final saved = _preferences.getString(_key);
    if (saved == null) return const ScheduleFilter();
    try {
      return ScheduleFilter.fromJson(object(jsonDecode(saved)));
    } on FormatException {
      return const ScheduleFilter();
    }
  }

  Future<void> set(ScheduleFilter value) async {
    await _preferences.setString(_key, jsonEncode(value.toJson()));
    notifyListeners();
  }
}
