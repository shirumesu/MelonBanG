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
/// (cached already, by the subscription or by hand). [replaceable] episodes
/// take a corrected release when [revisions] allows. Releases are taken in
/// publishing order, so the first of an episode's matching files is kept;
/// with the preferred groups, a preferred group's file comes before them.
/// A release stating nothing for a selection only counts while the filter
/// names one group, whose releases word it their own way.
List<ReleaseJudgement> judgeReleases({
  required Subject subject,
  required SubscriptionFilter filter,
  required Iterable<ReleaseCandidate> candidates,
  required bool Function(Episode) wanted,
  List<String> preferredGroups = const [],
  RevisionPolicy revisions = RevisionPolicy.skip,
  Set<int> held = const {},
  Set<int> replaceable = const {},
  Set<String> known = const {},
}) {
  final names = filter.groupNames(preferredGroups);
  final loosely = !filter.anyGroup && names.length == 1;
  final ordered = candidates.toList()
    ..sort((a, b) {
      final x = releasePublished(a.release.publishedAt);
      final y = releasePublished(b.release.publishedAt);
      if (x == null || y == null) return 0;
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
    if (!filter.anyGroup && !groupsMatch(creditedGroups(info), names)) {
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
    final gaps = resourceSelectionGaps(
      info,
      qualities: filter.qualities,
      languages: filter.languages,
      subtitleForms: filter.forms,
    );
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
      if (!replaceable.contains(episode.id)) {
        judged.add(
          skip(
            Verdict.revision,
            '$label的修正版；这一集已经看过或不是订阅缓存的',
            episode: episode,
          ),
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
  int rank(ReleaseJudgement option) => filter.preferred
      ? preferredGroupIndex(creditedGroups(option.info), preferredGroups) ??
            preferredGroups.length
      : 0;
  for (final episode in {...exact.keys, ...loose.keys}) {
    final found = exact[episode] ?? loose[episode]!;
    // Publishing order decides within a rank.
    final options = [...found]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0
            ? byRank
            : found.indexOf(a).compareTo(found.indexOf(b));
      });
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
    // A corrected release goes before the first one when both are new.
    final chosen =
        options
            .where((option) => releaseRevision(option.candidate.release.title))
            .lastOrNull ??
        options.first;
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
