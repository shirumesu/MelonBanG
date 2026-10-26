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
  bool get series => members.length > 1;
  String get id => series ? key : members.single.$1.id;
}

/// The results as the filters show them, the counts the filter menus offer
/// and the rows of the list.
class ResourceResults {
  /// [annotated] are the ranked results with their parsed titles. With
  /// [grouping], one group's single-episode releases of a series on one site
  /// form an entry; releases holding none of [subject]'s episodes, such as
  /// an earlier season's, follow the rest.
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
    List<String> onlyGroups = const [],
  }) {
    bool kindShown(PlayCandidate candidate) =>
        kind == ResourceFamily.all || ResourceFamily.of(candidate) == kind;
    final fromShownProviders = annotated
        .where((entry) => !entry.$1.providers.every(excludedProviders.contains))
        // With [onlyGroups], torrents credited only to other groups leave;
        // ones crediting none stay.
        .where(
          (entry) =>
              onlyGroups.isEmpty ||
              entry.$1.target is! ReleaseTarget ||
              entry.$2.sourceGroups.isEmpty ||
              preferredGroupIndex(entry.$2.sourceGroups, onlyGroups) != null,
        )
        .toList();
    // Results stating nothing for a selection stay, after confirmed ones.
    _gaps = {
      for (final (candidate, info) in fromShownProviders)
        candidate.id: ?resourceSelectionGaps(
          info,
          qualities: qualities,
          groups: groups,
          languages: languages,
          subtitleForms: subtitleForms,
        ),
    };
    matching = [
      for (final confirmed in [true, false])
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
    groupCounts = tally((info) => info.sourceGroups);
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
    // `[简繁内封字幕]`), so a release stating none joins the series' only
    // stated subtitles.
    final stated = <String, Set<String>>{};
    for (final (candidate, info) in visible) {
      if (seriesOf(candidate, info) case final series?
          when info.subtitles.isNotEmpty) {
        (stated[series] ??= {}).add(info.subtitles);
      }
    }
    for (final (candidate, info) in visible) {
      final release = targets.containsKey(candidate.id);
      final target = targets[candidate.id];
      final member = (candidate, info, target);
      final rest = release && info.episode != null && target == null
          ? unmatched
          : entries;
      final key = switch (seriesOf(candidate, info)) {
        final series? => switch (stated[series]) {
          final subtitles?
              when info.subtitles.isEmpty && subtitles.length == 1 =>
            '$series:${subtitles.single}',
          _ => '$series:${info.subtitles}',
        },
        null => null,
      };
      if (bySeries[key] case final entry?) {
        entry.members.add(member);
      } else {
        final entry = ResourceEntry(key ?? candidate.id, [member]);
        rest.add(entry);
        if (key != null) bySeries[key] = entry;
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
  late final List<(PlayCandidate, ResourceTitleInfo)> matching, visible;
  late final Map<String, int> qualityCounts,
      groupCounts,
      languageCounts,
      formCounts;
  late final Map<ResourceFamily, int> kindCounts;

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
