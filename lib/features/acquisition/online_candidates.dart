import 'dart:async';

import '../../domain/catalog.dart';
import '../../core/network.dart';
import 'resource_metadata.dart';
import '../../domain/resource_title.dart';
import '../../domain/play_candidate.dart';
import '../../domain/sources.dart';
import 'source_registry.dart';
import 'title_matching.dart';

/// Searches every usable online source for one Bangumi chapter, or with no
/// [episode] lists each matching site subject whose entry is chosen later.
/// [onProgress] reports each source's state as its search starts and ends.
///
/// With [firstReady], returns as soon as one confident match exists and falls
/// back to a full search when none does. Manual-only sources (uploads that
/// need explicit confirmation) are included only when [includeManual].
Future<List<PlayCandidate>> onlineCandidates(
  SourceRegistry registry,
  Subject subject,
  Episode? episode, {
  List<String>? names,
  void Function(SourceProgress)? onProgress,
  RequestCancellation? cancel,
  bool firstReady = false,
  bool includeManual = true,
}) async {
  final searchNames = names ?? resourceNames(subject);
  final result = <PlayCandidate>[];
  final operation = RequestCancellation();
  final stop = cancel?.listen(operation.cancel);
  final ready = Completer<List<PlayCandidate>>();
  bool confident(PlayCandidate candidate) => !candidate.possibleMatch;
  final all = Future.wait(
    registry
        .usableOf(SourceKind.online)
        .where((rule) => includeManual || !rule.manualOnly)
        .map((rule) async {
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
              searchNames,
              cancel: operation,
              enough: manual
                  ? (rows) => rows.isNotEmpty
                  : firstReady
                  ? (rows) => rows.any(
                      (site) =>
                          sourceMatchScore(subject, site, searchNames) >= .84,
                    )
                  : null,
            );
            for (final site in matches) {
              final score = sourceMatchScore(subject, site, searchNames);
              if (!manual && score < .55) continue;
              if (episode == null || site.choosePart) {
                final label = site.choosePart ? '选择分 P' : '选择集数';
                result.add(
                  _candidate(
                    rule,
                    site,
                    label: label,
                    line: site.line ?? '',
                    target: OnlineTarget(
                      candidateId: '$id:${site.id}:${site.line}:$label',
                      chooseFrom: site,
                      description: site.description,
                    ),
                    possibleMatch: manual || score < .84,
                    order: result.length,
                  ),
                );
                continue;
              }
              final rows = await registry.episodes(id, site, cancel: operation);
              for (final row in rows.where(
                (row) => sourceEpisodeMatches(row.label, episode),
              )) {
                result.add(
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
                    order: result.length,
                  ),
                );
              }
            }
            if (firstReady && !ready.isCompleted && result.any(confident)) {
              ready.complete(List.of(result));
            }
            progress = progress.copyWith(
              completed: 1,
              resultCount: found(),
              status: SearchStatus.ready,
            );
          } catch (error) {
            // Failed sources keep their health while others remain usable.
            progress = progress.copyWith(
              completed: 1,
              failed: 1,
              resultCount: found(),
              status: found() == 0 ? SearchStatus.error : SearchStatus.partial,
              message: '$error',
            );
          }
          onProgress?.call(progress);
        }),
  ).then((_) => List.of(result));
  try {
    final rows = await (firstReady ? Future.any([ready.future, all]) : all);
    cancel?.throwIfCancelled();
    if (firstReady && !rows.any(confident)) {
      return await onlineCandidates(
        registry,
        subject,
        episode,
        names: names,
        onProgress: onProgress,
        cancel: cancel,
        includeManual: includeManual,
      );
    }
    return rows;
  } finally {
    stop?.call();
    operation.cancel();
  }
}

/// The candidate for one chosen entry of an upload or site subject.
PlayCandidate onlinePartCandidate(
  PlayCandidate parent,
  SourceSubject upload,
  SourceEpisode part,
) => PlayCandidate(
  kind: PlayKind.online,
  provider: parent.provider,
  providerLabel: parent.providerLabel,
  title: '${upload.title} · ${part.label}',
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
  required String label,
  required String line,
  required OnlineTarget target,
  required bool possibleMatch,
  required int order,
}) {
  final title = '${site.title} · $label';
  final info = describeResource(title);
  return PlayCandidate(
    kind: PlayKind.online,
    provider: rule.id,
    providerLabel: rule.name,
    title: title,
    line: line,
    quality: rule.manualOnly ? null : info.quality,
    languages: info.languages,
    target: target,
    instant: true,
    possibleMatch: possibleMatch,
    order: order,
  );
}
