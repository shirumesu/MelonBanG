import 'catalog.dart';

/// The calendar day of [instant] in UTC+8, the schedule's time zone.
DateTime shanghaiDay(DateTime instant) {
  final time = instant.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(time.year, time.month, time.day);
}

/// When an episode airs; [timed] when the schedule gives the hour, otherwise
/// [at] is the start of its air date.
typedef Release = ({DateTime at, bool timed});

/// When [episode] airs. Bangumi's air date decides the day, so a skipped
/// week stays right; the schedule's [airings] of its subject, a weekly rule,
/// only add the time when one falls within a day of that date.
Release? episodeRelease(Episode episode, List<DateTime> airings) {
  final date = episode.aired;
  if (date == null) return null;
  final day = DateTime.utc(date.year, date.month, date.day);
  DateTime? timed;
  var nearest = 2;
  for (final at in airings) {
    final gap = shanghaiDay(at).difference(day).inDays.abs();
    if (gap < nearest) {
      nearest = gap;
      timed = at;
    }
  }
  return timed == null ? (at: date, timed: false) : (at: timed, timed: true);
}

bool episodeAired(Episode episode, List<DateTime> airings) =>
    !(episodeRelease(episode, airings)?.at.isAfter(DateTime.now()) ?? false);

/// The first day of the quarter [at] falls in: January, April, July or
/// October, when seasons start.
DateTime seasonStart(DateTime at) =>
    DateTime(at.year, (at.month - 1) ~/ 3 * 3 + 1);
