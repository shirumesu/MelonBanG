import 'dart:async';

import '../../core/notices.dart';
import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';

/// Tells when a new episode of a show being watched airs, by the weekly
/// schedule's times, for the shows no running subscription caches: those
/// tell once the episode is cached instead.
///
/// Only airings that pass while the app runs are told; one from before it
/// started, or from more than [_late] ago when the computer wakes, is not.
class AiringReminders {
  AiringReminders({
    required this.calendar,
    required this.watching,
    required this.subscribed,
    required this.episodes,
    required this.enabled,
    required this.reloadCalendar,
    required this.notices,
    required this.onOpen,
  });

  /// The schedule's coming days, each show with the time it airs.
  final List<ScheduleDay> Function() calendar;

  /// The shows marked 在看.
  final List<Subject> Function() watching;

  /// Whether a running subscription caches the show of this id.
  final bool Function(int subjectId) subscribed;

  /// The episodes of a show being watched, when its detail is known.
  final List<Episode>? Function(int subjectId) episodes;
  final bool Function() enabled;

  /// Loads the schedule again; it covers seven days from the one it was
  /// loaded on.
  final Future<void> Function() reloadCalendar;
  final Notices notices;

  /// Opens the show a reminder is about.
  final void Function(Subject subject) onOpen;

  /// How late a reminder may still come, as after the computer slept
  /// through the airing.
  static const _late = Duration(hours: 6);

  static const _reload = Duration(hours: 6);

  Timer? _timer;
  late DateTime _since, _loaded;
  final _told = <String>{};

  void start() {
    _since = _loaded = DateTime.now();
    // Wall-clock checks rather than one timer per airing: a timer stops
    // while the computer sleeps, the clock does not.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => check());
  }

  void check() {
    final now = DateTime.now();
    final since = _since;
    _since = now;
    if (now.difference(_loaded) >= _reload) {
      _loaded = now;
      unawaited(reloadCalendar());
    }
    if (!enabled()) return;
    final watched = {for (final item in watching()) item.id: item};
    for (final day in calendar()) {
      for (final item in day.items) {
        final at = item.airingAt;
        if (at == null ||
            !at.isAfter(since) ||
            at.isAfter(now) ||
            now.difference(at) > _late) {
          continue;
        }
        final show = watched[item.id];
        if (show == null || subscribed(item.id)) continue;
        if (!_told.add('${item.id}@${at.toIso8601String()}')) continue;
        final episode = _episodeAt(item.id, at);
        notices.show(
          Notice(
            '${show.title} ${episode?.label ?? '新一话'}已更新',
            key: 'airing:${item.id}',
            onOpen: () => onOpen(show),
            actions: [NoticeAction('番剧详情', () => onOpen(show))],
          ),
        );
      }
    }
  }

  /// The main episode Bangumi dates nearest the day of [at], within a day.
  Episode? _episodeAt(int subjectId, DateTime at) {
    final day = shanghaiDay(at);
    Episode? nearest;
    var gap = 2;
    for (final episode in episodes(subjectId) ?? const <Episode>[]) {
      final date = episode.aired;
      if (!episode.main || date == null) continue;
      final days = DateTime.utc(
        date.year,
        date.month,
        date.day,
      ).difference(day).inDays.abs();
      if (days < gap) {
        gap = days;
        nearest = episode;
      }
    }
    return nearest;
  }

  void dispose() => _timer?.cancel();
}
