import '../../domain/catalog.dart';
import 'schedule_filter.dart';

/// Which of a day's shows the schedule lists.
enum ScheduleScope {
  all('全部'),
  watching('在追'),
  fresh('新番'),
  continuing('跨季');

  const ScheduleScope(this.label);
  final String label;

  /// [watching] are the shows the user is watching; 新番 began this season
  /// and 跨季 earlier ([isFromPastSeason]).
  bool includes(Subject subject, DateTime now, Set<int> watching) =>
      switch (this) {
        all => true,
        ScheduleScope.watching => watching.contains(subject.id),
        fresh => !isFromPastSeason(subject, now),
        continuing => isFromPastSeason(subject, now),
      };
}

/// Why a show waits at the end of its day, folded, rather than in the
/// timeline: shows few of the schedule's viewers follow. Popular ones of
/// each kind, such as 柯南 or 宝可梦, stay in the timeline.
enum ScheduleFold {
  kids('儿童向', '儿童向的番剧，Bangumi 上在看不到 200 人'),
  longRunning('长篇', '40 话以上或播出一年以上，Bangumi 上在看不到 200 人'),
  quiet('关注较少', 'Bangumi 上收藏不到 150 人，且开播已满 3 周');

  const ScheduleFold(this.label, this.reason);
  final String label;

  /// What sets it apart, for a tooltip.
  final String reason;

  /// The value saved in the schedule's filter.
  String get key => name;

  /// Bangumi users watching below which a children's or long-running show
  /// folds. The week of 2026-11-23 split there: 柯南 11,058, 宝可梦 1,677,
  /// 蜡笔小新 702, 哆啦A梦 615 above; 面包超人 7, 神秘面包小子 25 below.
  static const watchingFloor = 200;

  /// Collections below which a show folds once three weeks old. That week's
  /// shows thinned out between 138 and 157: below were short and children's
  /// shows and 动态漫画, above 海螺小姐 and 新网球王子. Newer shows keep their
  /// place while they gather viewers.
  static const collectionFloor = 150;
  static const settleTime = Duration(days: 21);
}

/// Tagged 子供向 (for children) on Bangumi.
bool isForChildren(Subject subject) =>
    subject.metaTags.contains('子供向') ||
    subject.tags.take(12).any((tag) => tag.name == '子供向');

/// Why [subject] folds, or null to list it; a show without counts yet
/// stays listed.
ScheduleFold? scheduleFold(Subject subject, DateTime now) {
  final stats = subject.collectionStats;
  if (stats.isEmpty) return null;
  final watching = stats[CollectionStatus.watching] ?? 0;
  if (watching < ScheduleFold.watchingFloor) {
    if (isForChildren(subject)) return ScheduleFold.kids;
    if (isLongRunning(subject, now)) return ScheduleFold.longRunning;
  }
  final began = DateTime.tryParse(subject.airDate ?? '');
  final total = stats.values.fold(0, (sum, count) => sum + count);
  return total < ScheduleFold.collectionFloor &&
          began != null &&
          now.difference(began) >= ScheduleFold.settleTime
      ? ScheduleFold.quiet
      : null;
}

/// A show's place in the week's heat chart, and its move since the week
/// before: positive up, null for a show not ranked then.
typedef ChartEntry = ({ScheduleSlot slot, int rank, int? move});

/// The week's shows by heat, among those [accepts] lists; [ChartEntry.move]
/// compares with the week before's heat among the same shows.
List<ChartEntry> weeklyChart(
  ScheduleWeek week,
  bool Function(Subject) accepts,
) {
  final shows = <int, ScheduleSlot>{};
  for (final day in week.days) {
    for (final slot in day) {
      if (accepts(slot.subject)) shows.putIfAbsent(slot.subject.id, () => slot);
    }
  }
  List<ScheduleSlot> ranked(double? Function(ScheduleSlot) heat) =>
      shows.values.where((slot) => heat(slot) != null).toList()
        ..sort((a, b) => heat(b)!.compareTo(heat(a)!));
  final previous = {
    for (final (i, slot) in ranked((s) => s.previousHeat).indexed)
      slot.subject.id: i + 1,
  };
  return [
    for (final (i, slot) in ranked((s) => s.heat).indexed)
      (
        slot: slot,
        rank: i + 1,
        move: switch (previous[slot.subject.id]) {
          final before? => before - (i + 1),
          null => null,
        },
      ),
  ];
}

/// Whether the week before has heat, so a show missing from it is new to
/// the chart rather than unknown.
bool chartComparable(ScheduleWeek week) =>
    week.days.any((day) => day.any((slot) => slot.previousHeat != null));

/// The week's final episodes in air order, one per show.
List<ScheduleSlot> weekFinales(
  ScheduleWeek week,
  bool Function(Subject) accepts,
) {
  final seen = <int>{};
  return [
    for (final day in week.days)
      for (final slot in day)
        if (slot.finale && accepts(slot.subject) && seen.add(slot.subject.id))
          slot,
  ];
}
