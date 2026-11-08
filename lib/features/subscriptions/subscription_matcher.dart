import 'dart:math' as math;

import '../../domain/catalog.dart';
import '../../domain/release_traits.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../../domain/torrent_identity.dart';
import '../acquisition/title_matching.dart';
import 'subscription.dart';

/// Why a release is cached or left.
enum Verdict {
  download,
  otherGroup,
  known,
  batch,
  rebroadcast,
  unknownEpisode,
  filtered,
  revision,
  held,
  early,
  duplicate,
  unclear,
}

/// What a check makes of one release.
class ReleaseJudgement {
  const ReleaseJudgement(
    this.candidate,
    this.info, {
    required this.verdict,
    required this.reason,
    this.episode,
    this.replaces = false,
  });
  final Verdict verdict;
  final ReleaseCandidate candidate;
  final ResourceTitleInfo info;
  final Episode? episode;

  /// Why it is cached or not, as the subscription's events show it.
  final String reason;
  bool get download => verdict == Verdict.download;

  /// A corrected release replacing the episode's unwatched cache.
  final bool replaces;

  /// Whether it is by a subscribed group; others go unmentioned.
  bool get ours => verdict != Verdict.otherGroup;

  String get identity => torrentIdentity(candidate.release.locator);
}

/// Judges [candidates] for a subscription with [filter]: at most one
/// release per episode is cached, only of episodes [wanted] and not [held]
/// (cached already, by the subscription or by hand). [replaceable] episodes,
/// with the title of the file cached, take that group's corrected release
/// when [revisions] allows. Releases are taken in publishing order, so the
/// first of an episode's matching files is kept, whichever subscribed group
/// it is by; following the preferred groups, of files found together the
/// one by the group listed first is kept. Of that group's files of the
/// episode found together, one with subtitles the player can turn off goes
/// first, as the resource search ranks them, so episodes found together
/// take the same version rather than whichever was posted a minute earlier.
/// A smart filter takes the groups
/// [smartGroups] picks from [candidates], with episodes timed by [aired].
/// Subtitles are read across a group's series as the resource search reads
/// them; a release still stating nothing for a selection only counts while
/// the filter names one group, whose releases word it their own way.
List<ReleaseJudgement> judgeReleases({
  required Subject subject,
  required SubscriptionFilter filter,
  required Iterable<ReleaseCandidate> candidates,
  required bool Function(Episode) wanted,
  List<String> preferredGroups = const [],
  DateTime? Function(Episode)? aired,
  RevisionPolicy revisions = RevisionPolicy.skip,
  Set<int> held = const {},
  Map<int, String> replaceable = const {},
  Set<String> known = const {},
}) {
  final names = filter.smart
      ? [
          for (final record in smartGroups(
            groupRecords(
              subject: subject,
              filter: filter,
              candidates: candidates,
              aired: aired ?? (_) => null,
            ).values,
            preferredGroups,
          ))
            record.name,
        ]
      : filter.groupNames(preferredGroups);
  // Preferred groups while none are set leave every group in.
  final anyGroup = filter.anyGroup || (!filter.smart && names.isEmpty);
  final loosely = !anyGroup && names.length == 1;
  final subtitlesOf = seriesSubtitles([
    for (final candidate in candidates)
      describeResource(
        candidate.release.title,
        releaseGroups: candidate.release.releaseGroups,
      ),
  ]);
  final ordered = candidates.toList()
    ..sort((a, b) {
      final x = releasePublished(a.release.publishedAt);
      final y = releasePublished(b.release.publishedAt);
      // Undated releases go last, keeping the order consistent.
      if (x == null || y == null) {
        return (x == null ? 1 : 0) - (y == null ? 1 : 0);
      }
      return x.compareTo(y);
    });
  final judged = <ReleaseJudgement>[];
  // Releases left for each episode: those meeting the filter, then those
  // stating nothing for part of it.
  final exact = <int, List<ReleaseJudgement>>{};
  final loose = <int, List<ReleaseJudgement>>{};
  for (final candidate in ordered) {
    final release = candidate.release;
    final info = describeResource(
      release.title,
      releaseGroups: release.releaseGroups,
    );
    ReleaseJudgement skip(Verdict verdict, String reason, {Episode? episode}) =>
        ReleaseJudgement(
          candidate,
          info,
          verdict: verdict,
          reason: reason,
          episode: episode,
        );
    if (!anyGroup && !groupsMatch(creditedGroups(info), names)) {
      judged.add(skip(Verdict.otherGroup, '不是订阅的字幕组'));
      continue;
    }
    if (known.contains(torrentIdentity(release.locator))) {
      judged.add(skip(Verdict.known, '已经缓存过这个文件'));
      continue;
    }
    if (info.batch) {
      judged.add(skip(Verdict.batch, '合集'));
      continue;
    }
    if (releaseRebroadcast(release.title)) {
      judged.add(skip(Verdict.rebroadcast, '重映，对应的是往期集'));
      continue;
    }
    final episode = releaseEpisode(subject, info);
    if (episode == null) {
      judged.add(
        skip(
          Verdict.unknownEpisode,
          info.episode == null ? '认不出集数' : '对不上 Bangumi 的剧集',
        ),
      );
      continue;
    }
    final gaps = filter.gaps(info, subtitlesOf);
    if (gaps == null || (gaps.isNotEmpty && !loosely)) {
      judged.add(
        skip(
          Verdict.filtered,
          gaps == null ? '不符合筛选' : '没写明${gaps.join('、')}',
          episode: episode,
        ),
      );
      continue;
    }
    final same = gaps.isEmpty;
    final revision = releaseRevision(release.title);
    final label = episode.label;
    if (revision && held.contains(episode.id)) {
      if (revisions == RevisionPolicy.skip) {
        judged.add(skip(Verdict.revision, '$label的修正版', episode: episode));
        continue;
      }
      final cached = replaceable[episode.id];
      if (cached == null) {
        judged.add(
          skip(
            Verdict.revision,
            '$label的修正版；这一集已经看过或不是订阅缓存的',
            episode: episode,
          ),
        );
        continue;
      }
      // Another group's v2 corrects that group's file, not the one cached.
      final cachedGroups = creditedGroups(describeResource(cached));
      if (cachedGroups.isNotEmpty &&
          !groupsMatch(creditedGroups(info), cachedGroups)) {
        judged.add(
          skip(Verdict.revision, '$label的修正版，但缓存的是别的字幕组的文件', episode: episode),
        );
        continue;
      }
    } else if (held.contains(episode.id)) {
      judged.add(skip(Verdict.held, '$label已经有缓存', episode: episode));
      continue;
    }
    if (!wanted(episode)) {
      judged.add(skip(Verdict.early, '$label在订阅之前播出', episode: episode));
      continue;
    }
    (same ? exact : loose)
        .putIfAbsent(episode.id, () => [])
        .add(skip(Verdict.download, '', episode: episode));
  }
  for (final episode in {...exact.keys, ...loose.keys}) {
    final options = exact[episode] ?? loose[episode]!;
    final label = options.first.episode!.label;
    if (exact[episode] == null && options.length > 1) {
      for (final option in options) {
        judged.add(
          ReleaseJudgement(
            option.candidate,
            option.info,
            episode: option.episode,
            verdict: Verdict.unclear,
            reason: '$label有 ${options.length} 个没写清字幕或画质的文件，不知道该选哪个',
          ),
        );
      }
      continue;
    }
    // Following the preferred groups, the earliest of them out with the
    // episode in their order; otherwise whichever came first. Of that
    // group's files, the earliest with subtitles in a track of their own,
    // else the earliest; a corrected release goes before the others when
    // both are new, the latest of them.
    final order = filter.preferred ? preferredGroups : const <String>[];
    int rank(ReleaseJudgement option) =>
        preferredGroupIndex(creditedGroups(option.info), order) ?? order.length;
    final best = options.map(rank).reduce(math.min);
    final ranked = options.where((option) => rank(option) == best);
    final group = creditedGroups(ranked.first.info);
    final versions = ranked
        .where((option) => groupsMatch(creditedGroups(option.info), group))
        .toList();
    final corrected = versions
        .where((option) => releaseRevision(option.candidate.release.title))
        .toList()
        .reversed
        .toList();
    final pool = corrected.isEmpty ? versions : corrected;
    final chosen =
        pool
            .where(
              (option) => resourceSubtitleForms.any(
                subtitlesOf(option.info).subtitleForms.contains,
              ),
            )
            .firstOrNull ??
        pool.first;
    for (final option in options) {
      final replaces = held.contains(episode);
      judged.add(
        identical(option, chosen)
            ? ReleaseJudgement(
                option.candidate,
                option.info,
                episode: option.episode,
                verdict: Verdict.download,
                replaces: replaces,
                reason: replaces ? '$label的修正版，替换还没看的旧文件' : '符合筛选',
              )
            : ReleaseJudgement(
                option.candidate,
                option.info,
                episode: option.episode,
                verdict: Verdict.duplicate,
                reason: '$label已选定另一个文件',
              ),
      );
    }
  }
  return judged;
}

/// How one group releases a show: the episodes of its single-episode
/// releases meeting a filter's quality and subtitles, and how long after
/// airing each came out.
class GroupRecord {
  GroupRecord(this.name);

  /// The group, as the first of its releases names it.
  final String name;

  /// Every group its releases credit, the title's leading bracket too.
  final credits = <String>{};

  /// Bangumi episode ids it released.
  final episodes = <int>{};

  /// How soon after airing each episode's first release came out, for
  /// episodes whose airing hour and publishing time are known.
  final delays = <int, Duration>{};

  /// How soon after airing its releases usually come out.
  Duration? get lag => _median(delays.values);
}

/// The groups releasing [candidates] of [subject] that meet [filter]'s
/// quality and subtitles, by [groupKey] of their name; [aired] gives an
/// episode's airing time when its hour is known. Batches and rebroadcasts
/// say nothing of how a group follows the show.
Map<String, GroupRecord> groupRecords({
  required Subject subject,
  required SubscriptionFilter filter,
  required Iterable<ReleaseCandidate> candidates,
  required DateTime? Function(Episode) aired,
}) {
  final records = <String, GroupRecord>{};
  final described = [
    for (final candidate in candidates)
      (
        candidate.release,
        describeResource(
          candidate.release.title,
          releaseGroups: candidate.release.releaseGroups,
        ),
      ),
  ];
  final subtitlesOf = seriesSubtitles([
    for (final (_, info) in described) info,
  ]);
  for (final (release, info) in described) {
    if (info.batch || releaseRebroadcast(release.title)) continue;
    final episode = releaseEpisode(subject, info);
    if (episode == null) continue;
    if (filter.gaps(info, subtitlesOf) == null) continue;
    // A bare date says nothing about the hour.
    final raw = release.publishedAt ?? '';
    final published = raw.length > 10 ? releasePublished(raw) : null;
    final at = aired(episode);
    final delay = published == null || at == null
        ? null
        : published.difference(at);
    for (final name in info.groups) {
      final record =
          records.putIfAbsent(groupKey(name), () => GroupRecord(name))
            ..credits.addAll(creditedGroups(info))
            ..episodes.add(episode.id);
      if (delay != null && !delay.isNegative) {
        final earlier = record.delays[episode.id];
        if (earlier == null || delay < earlier) {
          record.delays[episode.id] = delay;
        }
      }
    }
  }
  return records;
}

/// How soon after airing the first of [records]' releases of an episode
/// usually comes out: what subscribing to all of them waits.
Duration? fastestLag(Iterable<GroupRecord> records) {
  final firsts = <int, Duration>{};
  for (final record in records) {
    for (final MapEntry(key: episode, value: delay) in record.delays.entries) {
      final first = firsts[episode];
      if (first == null || delay < first) firsts[episode] = delay;
    }
  }
  return _median(firsts.values);
}

/// Groups whose releases usually come later than this are not worth
/// following.
const slowGroupLag = Duration(days: 7);

/// The groups worth following of [records], the best first: those scoring
/// close to the best on how many of the show's episodes they released, how
/// soon after airing, and whether they are among [preferredGroups], at
/// most three. Groups usually a week late are left out.
List<GroupRecord> smartGroups(
  Iterable<GroupRecord> records,
  List<String> preferredGroups,
) {
  final released = {for (final record in records) ...record.episodes};
  if (released.isEmpty) return const [];
  double score(GroupRecord record) {
    final lag = record.lag;
    // Twelve hours late halves the speed score; an unknown lag counts so.
    final speed = lag == null ? .5 : 1 / (1 + lag.inMinutes / (12 * 60));
    final preferred = groupsMatch(record.credits, preferredGroups) ? 1 : 0;
    return .45 * record.episodes.length / released.length +
        .35 * speed +
        .2 * preferred;
  }

  final scored = [
    for (final record in records)
      if (!((record.lag ?? Duration.zero) > slowGroupLag))
        (record, score(record)),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  if (scored.isEmpty) return const [];
  final best = scored.first.$2;
  return [
    for (final (record, value) in scored.take(3))
      if (value >= best * .85) record,
  ];
}

Duration? _median(Iterable<Duration> values) {
  final sorted = values.toList()..sort();
  return sorted.isEmpty ? null : sorted[sorted.length ~/ 2];
}

/// When a release was published, from the site's ISO or RSS date. A date
/// without a zone, as Mikan gives, is China time.
DateTime? releasePublished(String? value) {
  if (value == null) return null;
  final text = value.trim();
  if (DateTime.tryParse(text) case final iso?) {
    return iso.isUtc
        ? iso
        : DateTime.utc(
            iso.year,
            iso.month,
            iso.day,
            iso.hour,
            iso.minute,
            iso.second,
          ).subtract(const Duration(hours: 8));
  }
  // RFC 822, as `Mon, 02 Nov 2026 16:00:34 +0800`.
  final match = _rfc822.firstMatch(text);
  final month = match == null ? -1 : _months.indexOf(match[2]!.toLowerCase());
  if (match == null || month < 0) return null;
  final offset = switch (match[7] ?? '') {
    final zone when zone.startsWith('+') || zone.startsWith('-') =>
      Duration(
            hours: int.parse(zone.substring(1, 3)),
            minutes: int.parse(zone.substring(3)),
          ) *
          (zone.startsWith('-') ? -1 : 1),
    _ => Duration.zero,
  };
  return DateTime.utc(
    int.parse(match[3]!),
    month + 1,
    int.parse(match[1]!),
    int.parse(match[4]!),
    int.parse(match[5]!),
    int.parse(match[6] ?? '0'),
  ).subtract(offset);
}

final _rfc822 = RegExp(
  r'(\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d\d):(\d\d)(?::(\d\d))? ?([+-]\d{4}|GMT|UTC|UT|Z)?',
);
const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];
