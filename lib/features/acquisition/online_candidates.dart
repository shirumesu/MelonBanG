import 'dart:async';
import 'dart:convert';

import '../../core/error_message.dart';
import '../../domain/catalog.dart';
import '../../core/network.dart';
import '../../domain/resource_title.dart';
import '../../domain/play_candidate.dart';
import '../../domain/sources.dart';
import '../../integrations/danmaku/matching.dart' show dubbedTitle;
import 'source_registry.dart';
import 'title_matching.dart';

/// Searches every usable online source for one Bangumi chapter, or with no
/// [episode] lists each matching site subject whose entry is chosen later.
/// [onProgress] reports each source's state as its search starts and ends.
///
/// Sources and their site subjects run concurrently; [onUpdate] receives all
/// rows found so far whenever a site subject adds some.
/// Manual-only sources (uploads that need explicit confirmation) are
/// included only when [includeManual].
Future<List<PlayCandidate>> onlineCandidates(
  SourceRegistry registry,
  Subject subject,
  Episode? episode, {
  required List<String> names,
  void Function(SourceProgress)? onProgress,
  void Function(List<PlayCandidate>)? onUpdate,
  RequestCancellation? cancel,
  bool includeManual = true,
}) async {
  final result = <PlayCandidate>[];
  final operation = RequestCancellation();
  final stop = cancel?.listen(operation.cancel);
  final usable = registry
      .usableOf(SourceKind.online)
      .where((rule) => includeManual || !rule.manualOnly)
      .toList();

  bool accepted(SourceSubject site) =>
      siteMatches(subject, episode, site, names);
  final all = Future.wait(
    usable.map((rule) async {
      final id = rule.id;
      final manual = rule.manualOnly;
      var progress = SourceProgress(
        sourceId: id,
        sourceName: rule.name,
        total: 1,
      );
      onProgress?.call(progress);
      int found() => result.where((e) => e.provider == id).length;
      try {
        final matches = await registry.searchSubjects(
          id,
          names,
          cancel: operation,
          enough: manual ? (rows) => rows.any(accepted) : null,
        );
        void publish(Iterable<PlayCandidate> rows) {
          if (rows.isEmpty) return;
          result.addAll(rows);
          onUpdate?.call(List.of(result));
        }

        await Future.wait(
          matches.map((site) async {
            if (!accepted(site)) return;
            final score = sourceMatchScore(subject, site, names);
            if (episode == null || site.choosePart) {
              final label = site.choosePart ? '选择分 P' : '选择集数';
              publish([
                _candidate(
                  rule,
                  site,
                  line: site.line ?? '',
                  target: OnlineTarget(
                    candidateId: '$id:${site.id}:${site.line}:$label',
                    chooseFrom: site,
                    description: site.description,
                  ),
                  possibleMatch: manual || score < .84,
                  order: result.length,
                ),
              ]);
              return;
            }
            final rows = await registry.episodes(id, site, cancel: operation);
            publish([
              for (final (index, row)
                  in rows
                      .where(
                        (row) =>
                            sourceEpisode(subject, row.label)?.id == episode.id,
                      )
                      .indexed)
                _candidate(
                  rule,
                  site,
                  label: row.label,
                  line: row.line,
                  target: OnlineTarget(
                    candidateId: '$id:${site.id}:${row.line}:${row.label}',
                    ref: row.ref,
                    description: site.description,
                  ),
                  possibleMatch: manual || score < .84,
                  order: result.length + index,
                ),
            ]);
          }),
        );
        progress = progress.copyWith(
          completed: 1,
          resultCount: found(),
          status: SearchStatus.ready,
        );
      } catch (error) {
        // A dropped search reports nothing more.
        if (operation.isCancelled) return;
        // Failed sources keep their health while others remain usable.
        progress = progress.copyWith(
          completed: 1,
          failed: 1,
          resultCount: found(),
          status: found() == 0 ? SearchStatus.error : SearchStatus.partial,
          message: errorMessage(error),
        );
      }
      onProgress?.call(progress);
    }),
  );
  try {
    await all;
    cancel?.throwIfCancelled();
    return List.of(result);
  } finally {
    stop?.call();
    operation.cancel();
  }
}

/// One entry an online site lists for an episode of a show, as a
/// subscription caches it.
final class OnlineRelease {
  const OnlineRelease({
    required this.source,
    required this.site,
    required this.entry,
    required this.episode,
    required this.quality,
  });
  final SourceInstance source;
  final SourceSubject site;
  final SourceEpisode entry;
  final Episode episode;

  /// `1080p`, as the stream of the line's latest episode states its
  /// picture size, else as the site's rule gives it: entry names seldom
  /// state one. Null when neither does.
  final String? quality;

  /// `学生会也有洞！  第08集`.
  String get title => '${site.title}  ${entry.label}';

  /// `modum3u8  1080p  魔都资源`, as playing it names the source.
  String get sourceLabel => [
    if (entry.line.isNotEmpty)
      int.tryParse(entry.line) == null ? entry.line : '线路 ${entry.line}',
    ?quality,
    source.name,
  ].join('  ');

  /// Tells this entry apart in a subscription's book, as torrents go by
  /// their identity.
  String get identity =>
      'online:${entry.ref.sourceId}:${jsonEncode(entry.ref.data)}';
}

/// What [onlineReleases] found so far.
typedef OnlineReleaseResult = ({
  List<OnlineRelease> releases,
  List<SourceProgress> sources,
});

/// Every entry the online sources list for [subject]'s episodes, for
/// subscriptions to cache unattended: manual-only sources, whose uploads
/// need the user to confirm them, are left out, and so are site subjects
/// short of a confident match. A site re-encodes some shows smaller than
/// its rule says, so each line's latest episode is asked for its picture
/// size, which the line's entries take as their [OnlineRelease.quality].
/// Entries go in the order of the sources, then of each source's best
/// matching site subject, then as the site lists them. [onUpdate] receives
/// everything found so far as each site subject adds some and as each
/// source finishes.
Future<OnlineReleaseResult> onlineReleases(
  SourceRegistry registry,
  Subject subject, {
  required List<String> names,
  void Function(OnlineReleaseResult)? onUpdate,
  RequestCancellation? cancel,
}) async {
  final usable = registry
      .usableOf(SourceKind.online)
      .where((rule) => !rule.manualOnly)
      .toList();
  final found = {
    for (final rule in usable) rule.id: <(double, int, OnlineRelease)>[],
  };
  final progress = {
    for (final rule in usable)
      rule.id: SourceProgress(
        sourceId: rule.id,
        sourceName: rule.name,
        total: 1,
      ),
  };
  OnlineReleaseResult snapshot() => (
    releases: [
      for (final rule in usable)
        for (final (_, _, release) in [
          ...found[rule.id]!,
        ]..sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2 - b.$2))
          release,
    ],
    sources: progress.values.toList(),
  );
  void emit() {
    if (cancel?.isCancelled != true) onUpdate?.call(snapshot());
  }

  await Future.wait(
    usable.map((rule) async {
      final rows = found[rule.id]!;
      try {
        // Checks run often while an episode is due, so the names are
        // tried one at a time until one finds the show.
        final sites = await registry.searchSubjects(
          rule.id,
          names,
          cancel: cancel,
          enough: (rows) =>
              rows.any((site) => sourceMatchScore(subject, site, names) >= .84),
        );
        await Future.wait(
          sites.map((site) async {
            final score = sourceMatchScore(subject, site, names);
            // A dub is listed as a show of its own, scoring close to the
            // original by name.
            if (site.choosePart ||
                score < .84 ||
                (dubbedTitle.hasMatch(site.title) &&
                    !names.any(dubbedTitle.hasMatch))) {
              return;
            }
            final lines = <String, List<(SourceEpisode, Episode)>>{};
            for (final entry in await registry.episodes(
              rule.id,
              site,
              cancel: cancel,
            )) {
              if (sourceEpisode(subject, entry.label) case final episode?) {
                (lines[entry.line] ??= []).add((entry, episode));
              }
            }
            final qualities = await Future.wait(
              lines.values.map((entries) async {
                final (latest, _) = entries.reduce(
                  (a, b) => b.$2.sort > a.$2.sort ? b : a,
                );
                return switch (await registry.streamResolution(
                  latest.ref,
                  cancel: cancel,
                )) {
                  final size? => _resolutionQuality(size),
                  null => switch (rule.config['quality']) {
                    final String quality => quality,
                    _ => null,
                  },
                };
              }),
            );
            for (final (index, entries) in lines.values.indexed) {
              final quality = qualities[index];
              for (final (entry, episode) in entries) {
                rows.add((
                  score,
                  rows.length,
                  OnlineRelease(
                    source: rule,
                    site: site,
                    entry: entry,
                    episode: episode,
                    quality: quality,
                  ),
                ));
              }
            }
            emit();
          }),
        );
        progress[rule.id] = progress[rule.id]!.copyWith(
          completed: 1,
          resultCount: rows.length,
          status: SearchStatus.ready,
        );
      } catch (error) {
        cancel?.throwIfCancelled();
        progress[rule.id] = progress[rule.id]!.copyWith(
          completed: 1,
          failed: 1,
          resultCount: rows.length,
          status: rows.isEmpty ? SearchStatus.error : SearchStatus.partial,
          message: errorMessage(error),
        );
      }
      emit();
    }),
  );
  cancel?.throwIfCancelled();
  return snapshot();
}

/// `1080p` for a 1920×1080 picture, or a 1920×800 one cropped to the
/// film's shape: the class its width or height reaches.
String _resolutionQuality(({int width, int height}) size) => switch (size) {
  (:final width, :final height) when width >= 3800 || height >= 2100 => '4K',
  (:final width, :final height) when width >= 1900 || height >= 1060 => '1080p',
  (:final width, :final height) when width >= 1260 || height >= 700 => '720p',
  (:final height, width: _) => '${height}p',
};

/// The candidate for one chosen entry of an upload or site subject.
PlayCandidate onlinePartCandidate(
  PlayCandidate parent,
  SourceSubject upload,
  SourceEpisode part,
) => PlayCandidate(
  kind: PlayKind.online,
  provider: parent.provider,
  providerLabel: parent.providerLabel,
  title: '${upload.title}  ${part.label}',
  line: part.line,
  languages: parent.languages,
  target: OnlineTarget(
    candidateId: '${parent.id}:${part.line}:${part.label}',
    ref: part.ref,
    description: upload.description,
  ),
  instant: true,
  possibleMatch: parent.possibleMatch,
  order: parent.order,
);

PlayCandidate _candidate(
  SourceInstance rule,
  SourceSubject site, {
  String? label,
  required String line,
  required OnlineTarget target,
  required bool possibleMatch,
  required int order,
}) {
  final title = label == null ? site.title : '${site.title}  $label';
  final info = describeResource(title);
  return PlayCandidate(
    kind: PlayKind.online,
    provider: rule.id,
    providerLabel: rule.name,
    title: title,
    line: line,
    // A site's titles seldom state quality; its rule gives the usual one.
    quality: rule.manualOnly
        ? null
        : info.quality ??
              switch (rule.config['quality']) {
                final String quality => quality,
                _ => null,
              },
    languages: info.languages,
    target: target,
    instant: true,
    possibleMatch: possibleMatch,
    order: order,
  );
}
