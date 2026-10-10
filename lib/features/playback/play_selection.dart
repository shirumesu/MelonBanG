import 'dart:io';

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

List<PlayCandidate> rankPlayCandidates(
  Iterable<PlayCandidate> candidates, {
  required bool onlineFirst,
  String? continuity,
  String language = 'auto',
}) {
  int tier(PlayCandidate c) => c.kind == PlayKind.local
      ? 0
      : switch (c.kind) {
          PlayKind.online => onlineFirst ? 1 : 2,
          PlayKind.bt => onlineFirst ? 2 : 1,
          PlayKind.pikpak => 3,
          PlayKind.local => 0,
        };
  int languageMatch(PlayCandidate c) =>
      c.languages.contains(switch (language) {
        'simplified' || 'chs' => '简体',
        'traditional' || 'cht' => '繁体',
        'japanese' || 'ja' => '日文',
        _ => '',
      })
      ? 1
      : 0;
  int quality(PlayCandidate c) => switch (c.quality) {
    '4K' || '2160p' => 3,
    '1080p' => 2,
    '720p' => 1,
    _ => 0,
  };
  final result = candidates.toList();
  result.sort((a, b) {
    for (final comparison in [
      tier(a).compareTo(tier(b)),
      (b.continuityKey == continuity ? 1 : 0).compareTo(
        a.continuityKey == continuity ? 1 : 0,
      ),
      languageMatch(b).compareTo(languageMatch(a)),
      quality(b).compareTo(quality(a)),
      b.health.compareTo(a.health),
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
