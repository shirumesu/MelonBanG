import '../../domain/catalog.dart';
import '../../domain/play_candidate.dart';
import '../../domain/resource_title.dart';
import '../../features/acquisition/title_matching.dart';

/// The kind segment, like the Sources page groups: online entries, torrents
/// over BT and torrents PikPak's index holds.
enum ResourceFamily {
  all('全部'),
  online('在线'),
  torrent('BT'),
  pikpak('PikPak');

  const ResourceFamily(this.label);
  final String label;

  static ResourceFamily of(PlayCandidate candidate) => switch (candidate.kind) {
    PlayKind.online => online,
    PlayKind.pikpak => pikpak,
    _ => torrent,
  };
}

/// A result, with the episode a whole-subject search matched it to.
typedef ResourceMember = (
  PlayCandidate candidate,
  ResourceTitleInfo info,
  Episode? episode,
);

/// One row of the list: a result, or a series of single-episode releases
/// shown as one expandable entry.
class ResourceEntry {
  ResourceEntry(this.key, this.members);
  final String key;
  final List<ResourceMember> members;

  /// A series' releases by the subtitles they carry, as [subtitleName]
  /// words them, and the platform they were ripped from where those differ,
  /// the best-ranked first; one group often releases a series in several,
  /// such as 简日 and 简繁, or rips of Baha and CR.
  final versions = <String, List<ResourceMember>>{};
  bool get series => members.length > 1;
  String get id => series ? key : members.single.$1.id;
}

/// `简繁内封`, as [info]'s title words its subtitles; `未标明字幕` when it
/// states none.
String subtitleName(ResourceTitleInfo info) {
  final stated = info.subtitles.split('|').toSet();
  final words = info.labels.where(stated.contains);
  if (words.isNotEmpty) return words.join(' ');
  final named = [...info.languages, ...info.subtitleForms];
  return named.isEmpty ? '未标明字幕' : named.join();
}

/// The results as the filters show them, the counts the filter menus offer
/// and the rows of the list.
class ResourceResults {
  /// [annotated] are the ranked results with their parsed titles. With
  /// [grouping], one group's single-episode releases of a series on one site
  /// form an entry, in each subtitle version and platform rip the group
  /// made. Results not stating a selection show, after the rest, only with
  /// [unstated]; releases
  /// holding none of [subject]'s episodes, such as an earlier season's,
  /// follow the rest.
  ResourceResults(
    List<(PlayCandidate, ResourceTitleInfo)> annotated, {
    required Set<String> excludedProviders,
    required Set<String> qualities,
    required Set<String> groups,
    required Set<String> languages,
    required Set<String> subtitleForms,
    required ResourceFamily kind,
    required Subject? subject,
    required this.grouping,
    bool unstated = false,
  }) {
    bool kindShown(PlayCandidate candidate) =>
        kind == ResourceFamily.all || ResourceFamily.of(candidate) == kind;
    final fromShownProviders = annotated
        .where((entry) => !entry.$1.providers.every(excludedProviders.contains))
        .toList();
    String platformOf(ResourceTitleInfo info) => info.platforms.join(' ');
    // A group leaves its subtitles out of some titles of a series, so a
    // release stating none takes those its other releases of the series
    // from the same platform state, where they agree.
    final statedSubtitles = <String, Map<String, ResourceTitleInfo>>{};
    for (final (_, info) in fromShownProviders) {
      if (info.series case final series?
          when info.languages.isNotEmpty || info.subtitleForms.isNotEmpty) {
        final key = '$series|${platformOf(info)}';
        (statedSubtitles[key] ??= {})[subtitleName(info)] ??= info;
      }
    }
    ResourceTitleInfo subtitlesOf(ResourceTitleInfo info) =>
        info.series != null &&
            info.languages.isEmpty &&
            info.subtitleForms.isEmpty
        ? switch (statedSubtitles['${info.series}|${platformOf(info)}']) {
            final stated? when stated.length == 1 => stated.values.single,
            _ => info,
          }
        : info;
    _gaps = {
      for (final (candidate, info) in fromShownProviders)
        if ((
              resourceSelectionGaps(info, qualities: qualities, groups: groups),
              resourceSelectionGaps(
                subtitlesOf(info),
                languages: languages,
                subtitleForms: subtitleForms,
              ),
            )
            case (final rest?, final subtitles?))
          candidate.id: [...rest, ...subtitles],
    };
    unstatedCount = fromShownProviders
        .where((e) => kindShown(e.$1) && _gaps[e.$1.id]?.isNotEmpty == true)
        .length;
    matching = [
      for (final confirmed in [true, if (unstated) false])
        for (final entry in fromShownProviders)
          if (_gaps[entry.$1.id]?.isEmpty == confirmed) entry,
    ];
    visible = matching.where((entry) => kindShown(entry.$1)).toList();
    // Option counts cover results of the shown sites and kind, before other
    // filters; kind counts cover every other filter.
    Map<String, int> tally(Iterable<String> Function(ResourceTitleInfo) of) {
      final counts = <String, int>{};
      for (final entry in fromShownProviders.where((e) => kindShown(e.$1))) {
        for (final value in of(entry.$2)) {
          counts[value] = (counts[value] ?? 0) + 1;
        }
      }
      return counts;
    }

    qualityCounts = tally(
      (info) => info.quality == null ? const [] : [info.quality!],
    );
    groupCounts = tally((info) => info.groups);
    languageCounts = tally((info) => info.languages);
    formCounts = tally((info) => info.subtitleForms);
    groupNames = {...groupCounts.keys, ...groups}.toList()
      ..sort((a, b) {
        final byCount = (groupCounts[b] ?? 0).compareTo(groupCounts[a] ?? 0);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    kindCounts = {
      for (final value in ResourceFamily.values)
        value: value == ResourceFamily.all
            ? matching.length
            : matching.where((e) => ResourceFamily.of(e.$1) == value).length,
    };
    // Results are ranked, so the first shown confident match is the best of
    // what the filters leave.
    final recommended = visible.firstOrNull?.$1;
    recommendedId = recommended == null || recommended.possibleMatch
        ? null
        : recommended.id;
    final unmatched = <ResourceEntry>[];
    final bySeries = <String, ResourceEntry>{};
    final targets = {
      for (final (candidate, info) in visible)
        if (grouping && candidate.target is ReleaseTarget)
          candidate.id: releaseEpisode(subject!, info),
    };
    String? seriesOf(PlayCandidate candidate, ResourceTitleInfo info) =>
        switch (info.series) {
          final series? when targets.containsKey(candidate.id) =>
            'series:${candidate.kind.name}:${candidate.provider}:'
                '${targets[candidate.id] != null}:$series',
          _ => null,
        };
    // Groups word subtitles differently across episodes (`ASSx2` against
    // `[简繁内封字幕]`), so a release stating none joins the only version
    // stated for the series on its platform.
    final stated = <String, Set<String>>{};
    for (final (candidate, info) in visible) {
      if (seriesOf(candidate, info) case final series?
          when info.subtitles.isNotEmpty) {
        (stated['$series|${platformOf(info)}'] ??= {}).add(subtitleName(info));
      }
    }
    final split =
        <ResourceEntry, Map<(String, String), List<ResourceMember>>>{};
    for (final (candidate, info) in visible) {
      final release = targets.containsKey(candidate.id);
      final target = targets[candidate.id];
      final member = (candidate, info, target);
      final rest = release && info.episode != null && target == null
          ? unmatched
          : entries;
      final key = seriesOf(candidate, info);
      final version = switch (stated['$key|${platformOf(info)}']) {
        final names? when info.subtitles.isEmpty && names.length == 1 =>
          names.single,
        _ => subtitleName(info),
      };
      final entry = bySeries[key] ?? ResourceEntry(key ?? candidate.id, []);
      if (entry.members.isEmpty) {
        rest.add(entry);
        if (key != null) bySeries[key] = entry;
      }
      entry.members.add(member);
      ((split[entry] ??= {})[(platformOf(info), version)] ??= []).add(member);
    }
    for (final MapEntry(key: entry, value: parts) in split.entries) {
      final platforms = {for (final (platform, _) in parts.keys) platform};
      for (final MapEntry(key: (platform, name), value: members)
          in parts.entries) {
        entry.versions[platforms.length < 2
                ? name
                : [
                    if (platform.isNotEmpty) platform,
                    if (platform.isEmpty || name != '未标明字幕') name,
                  ].join(' ')] =
            members;
      }
    }
    entries.addAll(unmatched);
  }

  /// Whether series entries are formed: a whole-subject search.
  final bool grouping;

  /// The filter selections each result does not state, by candidate id.
  late final Map<String, List<String>> _gaps;

  /// Results of the shown sites passing the filters, confirmed ones first;
  /// [visible] also passes the kind segment.
  ///
  /// [unstatedCount] are those of the shown kind not stating a selection,
  /// shown or not.
  late final List<(PlayCandidate, ResourceTitleInfo)> matching, visible;
  late final Map<String, int> qualityCounts,
      groupCounts,
      languageCounts,
      formCounts;
  late final Map<ResourceFamily, int> kindCounts;
  late final int unstatedCount;

  /// Release groups, the most common first.
  late final List<String> groupNames;
  late final String? recommendedId;
  final entries = <ResourceEntry>[];

  /// A note naming the selections [candidate] does not state.
  List<String> unstated(PlayCandidate candidate) => [
    if (_gaps[candidate.id]! case final missing when missing.isNotEmpty)
      '未标明${missing.join('、')}',
  ];

  /// Whether [member] holds one of the subject's episodes.
  bool belongs(ResourceMember member) =>
      !grouping ||
      member.$3 != null ||
      member.$2.episode == null ||
      member.$1.target is! ReleaseTarget;
}
