import 'dart:io';
import 'dart:math';

import '../../domain/catalog.dart';
import '../../core/network.dart';
import '../acquisition/resource_metadata.dart';
import '../../domain/resource_title.dart';
import '../../core/store.dart';
import '../../domain/play_candidate.dart';
import '../../domain/playback_session.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';
import '../acquisition/online_candidates.dart';
import '../acquisition/release_search.dart';
import '../acquisition/source_registry.dart';
import '../downloads/download_repository.dart';
import 'playback_library.dart';

class PlaySelectionRepository {
  PlaySelectionRepository(
    this.store,
    this.library,
    this.downloads,
    this.releases,
    this.registry,
  );
  final AppStore store;
  final PlaybackLibrary library;
  final DownloadRepository downloads;
  final ReleaseSearch releases;
  final SourceRegistry registry;
  final continuity = <int, String>{};
  final _failures = <String, int>{};

  /// Cached files, online entries and torrents for [episode], or for the
  /// whole subject without one, ranked for playback. [terms] default to the
  /// catalogue names and the chapter number; [onProgress] reports each online
  /// and torrent source's search state.
  Future<List<PlayCandidate>> candidates(
    Subject subject,
    Episode? episode, {
    ResourceTerms? terms,
    bool instantOnly = false,
    bool includeOnline = true,
    bool onlineFirst = false,
    bool forPlayback = false,
    String language = 'auto',
    bool useContinuity = false,
    void Function(List<PlayCandidate>)? onUpdate,
    void Function(SourceProgress)? onProgress,
    RequestCancellation? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final subjectId = subject.id;
    final episodeId = episode?.id;
    final search = terms ?? ResourceTerms.of(subject, episode);
    final found = <String, PlayCandidate>{};
    List<PlayCandidate> ranked() => rankPlayCandidates(
      found.values,
      onlineFirst: onlineFirst,
      language: language,
      continuity: useContinuity ? continuity[subjectId] : null,
      singleEpisode: episode != null,
    );
    void add(Iterable<PlayCandidate> values) {
      if (cancel?.isCancelled == true) return;
      for (final candidate in values) {
        candidate.health = -(_failures[candidate.id] ?? 0);
        found[candidate.id] = candidate;
      }
      onUpdate?.call(ranked());
    }

    final binding = episodeId == null
        ? null
        : await store.get('episode_files', '$subjectId:$episodeId');
    for (final task in downloads.snapshot().forSubject(subjectId)) {
      final bound = binding?['downloadId'] == task.id;
      if (episodeId != null && !bound && task.episodeId != episodeId) continue;
      try {
        final media = downloads.media(
          task.id,
          fileId: bound ? binding!['fileId'] as String? : null,
        );
        if (media.incomplete && task.cloud && !registry.isEnabled('pikpak')) {
          continue;
        }
        if (!media.incomplete && !await File(media.file.path).exists()) {
          continue;
        }
        final info = describeResource(
          task.title,
          releaseGroups: task.releaseGroups,
        );
        add([
          PlayCandidate(
            kind: !media.incomplete
                ? PlayKind.local
                : task.cloud
                ? PlayKind.pikpak
                : PlayKind.bt,
            provider: task.method.name,
            providerLabel: task.cloud ? 'PikPak' : 'BT 缓存',
            title: task.title,
            line: info.sourceGroups.join(' & '),
            quality: info.quality,
            languages: info.languages,
            target: DownloadTarget(task.id, media.file.id, task),
            instant: true,
            existing: true,
          ),
        ]);
      } on StateError {
        // A task awaiting metadata cannot supply a playable file yet.
      }
    }
    if (forPlayback && ranked().firstOrNull?.kind == PlayKind.local) {
      return ranked();
    }
    final onlineRequest = includeOnline
        ? onlineCandidates(
            registry,
            subject,
            episode,
            names: search.searchNames,
            onProgress: onProgress,
            cancel: cancel,
            firstReady: forPlayback && !useContinuity,
            includeManual: !forPlayback && !instantOnly,
          ).then(add)
        : Future<void>.value();
    void addReleases(ReleaseSearchResult result) {
      if (onProgress != null) result.sources.forEach(onProgress);
      add([
        for (final (index, candidate) in result.candidates.indexed)
          releaseCandidate(candidate, index),
      ]);
    }

    final sourceRequest = instantOnly
        ? Future<void>.value()
        : releases
              .search(
                subjectId,
                search.keyword,
                alternativeNames: search.names,
                episodeId: episodeId,
                episodeKeyword: search.episodeKeyword,
                coverUrl: subject.coverUrl,
                cancel: cancel,
                includeMetadata: !forPlayback,
                isCurrent: () => cancel?.isCancelled != true,
                onUpdate: addReleases,
              )
              .then(addReleases);
    if (forPlayback && onlineFirst) {
      // Search in parallel, but do not delay ready online playback for metadata.
      sourceRequest.ignore();
      await onlineRequest;
      final preferred = ranked().firstOrNull;
      if (preferred?.kind == PlayKind.online && !preferred!.possibleMatch) {
        return ranked();
      }
    }
    await Future.wait([onlineRequest, sourceRequest]);
    cancel?.throwIfCancelled();
    return ranked();
  }

  Future<PlaybackSession> load(
    PlayCandidate candidate,
    int subjectId,
    int episodeId, {
    RequestCancellation? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final ReleaseCandidate release;
    switch (candidate.target) {
      case OnlineTarget(:final ref?):
        final resolved = await registry.resolve(ref, cancel: cancel);
        return library.online(
          resolved,
          subjectId: subjectId,
          episodeId: episodeId,
          title: candidate.title,
        );
      case OnlineTarget():
        throw StateError('请先选择分 P');
      case DownloadTarget(:final downloadId, :final fileId):
        return library.fromDownload(
          downloadId,
          fileId: fileId,
          subjectId: subjectId,
          episodeId: episodeId,
        );
      case ReleaseTarget(candidate: final found):
        release = found;
    }
    final task = await releases.enqueue(
      release,
      method: candidate.kind == PlayKind.pikpak
          ? CacheMethod.pikpak
          : CacheMethod.bt,
    );
    final id = task.id;
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      cancel?.throwIfCancelled();
      try {
        downloads.media(id);
        return await library.fromDownload(id);
      } on StateError catch (e) {
        final current = downloads.snapshot().task(id);
        if (current == null ||
            current.status == DownloadStatus.failed ||
            '$e'.contains('多个视频')) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw StateError('资源正在获取文件信息，请稍后从缓存列表播放');
  }

  void played(int subjectId, PlayCandidate candidate) =>
      continuity[subjectId] = candidate.continuityKey;
  void failed(PlayCandidate candidate) {
    _failures[candidate.id] = (_failures[candidate.id] ?? 0) + 1;
    candidate.health = -_failures[candidate.id]!;
  }
}

PlayCandidate releaseCandidate(ReleaseCandidate candidate, int order) {
  final release = candidate.release;
  final info = describeResource(
    release.title,
    releaseGroups: release.releaseGroups,
  );
  return PlayCandidate(
    kind: PlayKind.bt,
    provider: candidate.sourceId,
    providerLabel: candidate.sourceName,
    title: info.title,
    line: info.sourceGroups.join(' & '),
    quality: info.quality,
    languages: info.languages,
    target: ReleaseTarget(candidate),
    instant: false,
    order: order,
  );
}

/// Ranks candidates for playback and recommendation: cached files first, then
/// online or torrent by [onlineFirst], PikPak last. Within a tier confident
/// matches precede possible ones, recently failed sources drop, the subject's
/// previous choice continues, and [resourceScores] orders the rest.
List<PlayCandidate> rankPlayCandidates(
  Iterable<PlayCandidate> candidates, {
  required bool onlineFirst,
  String? continuity,
  String language = 'auto',
  bool singleEpisode = true,
}) {
  int tier(PlayCandidate c) => switch (c.kind) {
    PlayKind.local => 0,
    PlayKind.online => onlineFirst ? 1 : 2,
    PlayKind.bt => onlineFirst ? 2 : 1,
    PlayKind.pikpak => 3,
  };
  final result = candidates.toList();
  final scores = resourceScores(
    result,
    language: language,
    singleEpisode: singleEpisode,
  );
  result.sort((a, b) {
    for (final comparison in [
      tier(a).compareTo(tier(b)),
      (a.possibleMatch ? 1 : 0).compareTo(b.possibleMatch ? 1 : 0),
      b.health.compareTo(a.health),
      (b.continuityKey == continuity ? 1 : 0).compareTo(
        a.continuityKey == continuity ? 1 : 0,
      ),
      scores[b.id]!.compareTo(scores[a.id]!),
      a.order.compareTo(b.order),
      a.provider.compareTo(b.provider),
      a.title.compareTo(b.title),
      a.id.compareTo(b.id),
    ]) {
      if (comparison != 0) return comparison;
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
}) {
  final preferred = switch (language) {
    'traditional' || 'cht' => '繁体',
    'japanese' || 'ja' => '日文',
    _ => '简体',
  };
  final details = {
    for (final candidate in candidates)
      candidate.id: (
        describeCandidate(candidate),
        switch (candidate.target) {
          ReleaseTarget(candidate: ReleaseCandidate(:final release)) =>
            releaseBytes(release),
          _ => null,
        },
      ),
  };
  bool batch(ResourceTitleInfo info) =>
      info.episodeLabel?.contains('–') ?? false;
  final sizes = <String?, List<int>>{};
  for (final (info, size) in details.values) {
    if (size != null && !batch(info)) (sizes[info.quality] ??= []).add(size);
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
    if (median != null && !batch(info)) {
      value += size == null
          ? -4
          : (6 - 12 * (log(size / median) / ln2).abs()).clamp(-20, 6);
    }
    if (info.episodeConflict) value -= 400;
    if (singleEpisode && batch(info)) value -= 40;
    return value;
  }

  return {
    for (final MapEntry(key: id, value: (info, size)) in details.entries)
      id: score(info, size),
  };
}

/// Release size in bytes from the site's byte count or its size label.
int? releaseBytes(TorrentRelease release) {
  if ((release.sizeBytes ?? 0) > 1) return release.sizeBytes;
  final match = RegExp(
    r'(\d+(?:\.\d+)?)\s*([KMGT])i?B',
    caseSensitive: false,
  ).firstMatch(release.sizeLabel ?? '');
  if (match == null) return null;
  final unit = 'KMGT'.indexOf(match[2]!.toUpperCase()) + 1;
  return (double.parse(match[1]!) * pow(1024, unit)).round();
}
