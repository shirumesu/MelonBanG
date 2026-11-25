import 'dart:math';

import '../../core/json.dart';
import '../../domain/play_candidate.dart';
import '../../domain/release_traits.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';

/// The source a subject was last played from: its site and line online,
/// its release group for BT and PikPak.
class RememberedSource {
  const RememberedSource({
    required this.family,
    required this.provider,
    required this.line,
    required this.key,
    required this.label,
  });

  factory RememberedSource.of(PlayCandidate candidate) {
    return RememberedSource(
      family: candidate.family,
      provider: candidate.provider,
      line: candidate.line,
      key: candidate.continuityKey,
      label: candidate.sourceLabel,
    );
  }

  // Sources saved by older builds join lines such as B 站's 投稿  作者 with
  // ' · '; they are read with two spaces so they still match.
  factory RememberedSource.fromJson(Json json) => RememberedSource(
    family: '${json['family'] ?? ''}',
    provider: '${json['provider'] ?? ''}',
    line: '${json['line'] ?? ''}'.replaceAll(' · ', '  '),
    key: '${json['key'] ?? ''}'.replaceAll(' · ', '  '),
    label: '${json['label'] ?? ''}'.replaceAll(' · ', '  '),
  );

  /// `online`, `bt` or `pikpak`.
  final String family;
  final String provider, line, key, label;

  /// 2 for the same site and line or group and quality, 1 for the same site
  /// or the same release group, otherwise 0.
  int affinity(PlayCandidate candidate) {
    if (candidate.continuityKey == key) return 2;
    if (candidate.kind == PlayKind.online) {
      return family == 'online' && candidate.provider == provider ? 1 : 0;
    }
    return family != 'online' && line.isNotEmpty && candidate.line == line
        ? 1
        : 0;
  }

  Json toJson() => {
    'family': family,
    'provider': provider,
    'line': line,
    'key': key,
    'label': label,
  };
}

/// The releases the user would pick for a subject: release [groups] in
/// order, and the qualities, subtitle languages and forms a subscription
/// filter selects.
class ReleaseTaste {
  const ReleaseTaste({
    this.groups = const [],
    this.qualities = const {},
    this.languages = const {},
    this.forms = const {},
  });
  final List<String> groups;
  final Set<String> qualities, languages, forms;

  /// 0 when [info] meets every selection, 1 when it states nothing for
  /// some, 2 when it fails one.
  int fit(ResourceTitleInfo info) => switch (resourceSelectionGaps(
    info,
    qualities: qualities,
    languages: languages,
    subtitleForms: forms,
  )) {
    null => 2,
    final gaps => gaps.isEmpty ? 0 : 1,
  };
}

/// Ranks candidates for playback and recommendation: cached files first, then
/// online or torrent by [onlineFirst], PikPak last unless it was [remembered].
/// Within a tier: confident matches, fewer failures, the [remembered] source,
/// this run's [continuity], single episodes before batches when
/// [singleEpisode], the [taste]'s groups in order, releases meeting its
/// selections; [resourceScores] orders the rest.
List<PlayCandidate> rankPlayCandidates(
  Iterable<PlayCandidate> candidates, {
  required bool onlineFirst,
  RememberedSource? remembered,
  String? continuity,
  String language = 'auto',
  bool singleEpisode = true,
  ReleaseTaste taste = const ReleaseTaste(),
}) {
  final torrents = onlineFirst ? 2.0 : 1.0;
  double tier(PlayCandidate c) => switch (c.kind) {
    PlayKind.local => 0,
    PlayKind.online => onlineFirst ? 1 : 2,
    PlayKind.bt => torrents,
    PlayKind.pikpak => remembered?.family == 'pikpak' ? torrents - .5 : 3,
  };
  int affinity(PlayCandidate c) => remembered?.affinity(c) ?? 0;
  final groups = taste.groups;
  final result = candidates.toList();
  final described = {for (final c in result) c: describeCandidate(c)};
  int preference(PlayCandidate c) => c.kind == PlayKind.online
      ? groups.length
      : preferredGroupIndex(creditedGroups(described[c]!), groups) ??
            groups.length;
  final scores = resourceScores(
    result,
    language: language,
    singleEpisode: singleEpisode,
    described: described,
  );
  // Each candidate's keys are worked out once, smaller first; sorting
  // compares hundreds of results many times over.
  final keys = <PlayCandidate, List<num>>{
    for (final c in result)
      c: [
        tier(c),
        c.possibleMatch ? 1 : 0,
        -c.health,
        -affinity(c),
        c.continuityKey == continuity ? 0 : 1,
        singleEpisode && described[c]!.batch ? 1 : 0,
        preference(c),
        taste.fit(described[c]!),
        -scores[c.id]!,
        c.order,
      ],
  };
  result.sort((a, b) {
    final x = keys[a]!, y = keys[b]!;
    for (var i = 0; i < x.length; i++) {
      final value = x[i].compareTo(y[i]);
      if (value != 0) return value;
    }
    for (final value in [
      a.provider.compareTo(b.provider),
      a.title.compareTo(b.title),
      a.id.compareTo(b.id),
    ]) {
      if (value != 0) return value;
    }
    return 0;
  });
  return result;
}

/// Title annotations of a candidate: the original release or task title with
/// its site release groups.
ResourceTitleInfo describeCandidate(PlayCandidate candidate) =>
    switch (candidate.target) {
      ReleaseTarget(candidate: ReleaseCandidate(:final release)) =>
        describeResource(release.title, releaseGroups: release.releaseGroups),
      DownloadTarget(:final task) => describeResource(
        task.title,
        releaseGroups: task.releaseGroups,
      ),
      OnlineTarget() => describeResource(candidate.title),
    };

/// Quality-first value of each candidate, by id. Output quality dominates;
/// subtitle language and form, source format, codec and size relative to
/// releases of the same quality balance the rest, so a reasonably sized
/// release with preferred subtitles beats a bloated or starved one. Episode
/// conflicts, and batches when [singleEpisode], score far lower.
Map<String, double> resourceScores(
  List<PlayCandidate> candidates, {
  String language = 'auto',
  bool singleEpisode = true,
  Map<PlayCandidate, ResourceTitleInfo>? described,
}) {
  // The player's subtitle language; 自动 prefers no script.
  final preferred = switch (language) {
    'chs' => '简体',
    'cht' => '繁体',
    'ja' => '日文',
    _ => null,
  };
  final details = {
    for (final candidate in candidates)
      candidate.id: (
        described?[candidate] ?? describeCandidate(candidate),
        switch (candidate.target) {
          ReleaseTarget(candidate: ReleaseCandidate(:final release)) =>
            releaseBytes(release),
          _ => null,
        },
      ),
  };
  final sizes = <String?, List<int>>{};
  for (final (info, size) in details.values) {
    if (size != null && !info.batch) (sizes[info.quality] ??= []).add(size);
  }
  final medians = {
    for (final MapEntry(key: quality, value: values) in sizes.entries)
      quality: (values..sort())[values.length ~/ 2],
  };
  double score(ResourceTitleInfo info, int? size) {
    final labels = info.labels;
    final languages = info.languages;
    final median = medians[info.quality];
    var value = switch (info.quality) {
      '4K' => 300.0,
      '1080p' => 200.0,
      '720p' => 100.0,
      _ => 80.0,
    };
    value += languages.contains(preferred)
        ? 30
        : languages.any((e) => e != '日文')
        ? 18
        : languages.isNotEmpty
        ? 5
        : 0;
    value += info.subtitleForms.contains('内封')
        ? 10
        : info.subtitleForms.isNotEmpty
        ? 6
        : 3;
    value += labels.any((e) => e.startsWith('BD'))
        ? 8
        : labels.contains('WEB-DL')
        ? 6
        : labels.contains('WebRip')
        ? 5
        : 3;
    value += labels.contains('HEVC')
        ? 6
        : labels.contains('AVC')
        ? 4
        : 3;
    if (labels.contains('10bit')) value += 2;
    if (median != null && !info.batch) {
      value += size == null
          ? -4
          : (6 - 12 * (log(size / median) / ln2).abs()).clamp(-20, 6);
    }
    if (info.episodeConflict) value -= 400;
    if (singleEpisode && info.batch) value -= 40;
    return value;
  }

  return {
    for (final MapEntry(key: id, value: (info, size)) in details.entries)
      id: score(info, size),
  };
}

final _sizeLabel = RegExp(
  r'(\d+(?:\.\d+)?)\s*([KMGT])i?B',
  caseSensitive: false,
);

/// Release size in bytes from the site's byte count or its size label.
int? releaseBytes(TorrentRelease release) {
  if ((release.sizeBytes ?? 0) > 1) return release.sizeBytes;
  final match = _sizeLabel.firstMatch(release.sizeLabel ?? '');
  if (match == null) return null;
  final unit = 'KMGT'.indexOf(match[2]!.toUpperCase()) + 1;
  return (double.parse(match[1]!) * pow(1024, unit)).round();
}
