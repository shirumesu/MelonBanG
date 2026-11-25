import 'dart:async';
import 'dart:io';

import '../../core/error_message.dart';
import '../../domain/catalog.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../acquisition/resource_metadata.dart';
import '../../domain/resource_title.dart';
import '../../core/store.dart';
import '../../domain/play_candidate.dart';
import '../../domain/playback_session.dart';
import '../../domain/sources.dart';
import '../../domain/torrent_identity.dart';
import '../../domain/transfer.dart';
import '../acquisition/online_candidates.dart';
import '../acquisition/release_search.dart';
import '../acquisition/source_registry.dart';
import '../acquisition/title_matching.dart';
import '../downloads/download_repository.dart';
import 'play_ranking.dart';
import 'playback_library.dart';

class PlaySelectionRepository {
  PlaySelectionRepository(
    this.store,
    this.library,
    this.downloads,
    this.releases,
    this.registry,
    this.cloud,
  );
  final AppStore store;
  final PlaybackLibrary library;
  final DownloadRepository downloads;
  final ReleaseSearch releases;
  final SourceRegistry registry;
  final CloudIndex cloud;
  final continuity = <int, String>{};
  final _failures = <String, int>{};

  /// Whether played sources are remembered per subject; set by the app from
  /// the playback preference.
  bool Function() remember = () => true;

  /// The releases the user would pick for a subject; set by the app from
  /// its subscription, the filter new subscriptions start from and the
  /// preferred groups.
  ReleaseTaste Function(int subjectId) taste = (_) => const ReleaseTaste();
  final _remembered = <int, RememberedSource?>{};

  /// The source last played for [subjectId], while remembering is on.
  Future<RememberedSource?> remembered(int subjectId) async {
    if (!remember()) return null;
    if (_remembered.containsKey(subjectId)) return _remembered[subjectId];
    final saved = await store.get(rememberedScope, '$subjectId');
    return _remembered[subjectId] = saved == null
        ? null
        : RememberedSource.fromJson(saved);
  }

  Future<void> forget(int subjectId) async {
    _remembered[subjectId] = null;
    await store.remove(rememberedScope, '$subjectId');
    rememberedChanges.add(null);
  }

  static const rememberedScope = 'source_preferences';

  /// Fires when the source remembered for a show changes here.
  final rememberedChanges = StreamController<void>.broadcast(sync: true);

  /// Takes the source another device remembered for [subjectId], or
  /// forgets it for null; [updated] is when it was played there.
  Future<void> adoptRemembered(
    int subjectId,
    Json? value, {
    DateTime? updated,
  }) async {
    if (value == null) {
      _remembered[subjectId] = null;
      await store.remove(rememberedScope, '$subjectId');
      return;
    }
    _remembered[subjectId] = RememberedSource.fromJson(value);
    await store.put(rememberedScope, '$subjectId', value, updated: updated);
  }

  /// Cached files, online entries and torrents for [episode], or for the
  /// whole subject without one, ranked for playback; with [includeCloud],
  /// torrents PikPak's index holds are PikPak candidates too. [terms] default
  /// to the catalogue names and chapter number. [onUpdate] gets the ranking
  /// of what is found so far, worked out when shown. [automatic] playback
  /// leaves out sources needing a manual choice and optional site pages, and
  /// with [settleOn] stops waiting [settleGrace] after a result it accepts.
  Future<List<PlayCandidate>> candidates(
    Subject subject,
    Episode? episode, {
    ResourceTerms? terms,
    bool includeDownloads = true,
    bool includeOnline = true,
    bool includeTorrents = true,
    bool includeCloud = true,
    bool onlineFirst = false,
    bool automatic = false,
    String language = 'auto',
    bool useContinuity = false,
    bool Function(PlayCandidate)? settleOn,
    void Function(List<PlayCandidate> Function() ranked)? onUpdate,
    void Function(SourceProgress)? onProgress,
    RequestCancellation? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final subjectId = subject.id;
    final episodeId = episode?.id;
    final search = terms ?? ResourceTerms.of(subject, episode);
    final found = <String, PlayCandidate>{};
    // The subject's own last choice outranks the global priority.
    final preferred = await remembered(subjectId);
    cancel?.throwIfCancelled();
    if (preferred != null) onlineFirst = preferred.family == 'online';
    // The taste is read on each ranking: the resource page ranks again as
    // the preferred groups are dragged in its group filter.
    List<PlayCandidate> ranked() => rankPlayCandidates(
      found.values,
      onlineFirst: onlineFirst,
      language: language,
      remembered: preferred,
      continuity: useContinuity ? continuity[subjectId] : null,
      singleEpisode: episode != null,
      taste: taste(subjectId),
    );
    // Searches still running once the result is settled are dropped.
    final searches = RequestCancellation();
    final settled = Completer<void>();
    // Cancelling stops waiting at once, PikPak lookups included.
    final unlink = cancel?.listen(() {
      searches.cancel();
      if (!settled.isCompleted) settled.complete();
    });
    Timer? grace;
    void add(Iterable<PlayCandidate> values) {
      if (searches.isCancelled) return;
      for (final candidate in values) {
        candidate.health = -(_failures[candidate.id] ?? 0);
        found[candidate.id] = candidate;
      }
      if (settleOn != null && grace == null && values.any(settleOn)) {
        grace = Timer(settleGrace, () {
          if (!settled.isCompleted) settled.complete();
        });
      }
      onUpdate?.call(ranked);
    }

    final binding = episodeId == null || !includeDownloads
        ? null
        : await store.get('episode_files', '$subjectId:$episodeId');
    final snapshot = downloads.snapshot();
    final tasks = includeDownloads
        ? [
            ...snapshot.forSubject(subjectId),
            // A torrent added before without this subject, as by hand, that
            // [load] played as the episode.
            if (binding?['downloadId'] case final String id)
              if (snapshot.task(id) case final task?
                  when task.subjectId != subjectId)
                task,
          ]
        : const <DownloadTask>[];
    for (final task in tasks) {
      final bound = binding?['downloadId'] == task.id;
      final file = episode == null
          ? null
          : episodeFiles(subject, task)[episode.id];
      if (episodeId != null &&
          !bound &&
          file == null &&
          task.episodeId != episodeId) {
        continue;
      }
      try {
        final media = downloads.media(
          task.id,
          fileId: bound ? binding!['fileId'] as String? : file?.id,
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
                : switch (task.method) {
                    CacheMethod.bt => PlayKind.bt,
                    CacheMethod.pikpak => PlayKind.pikpak,
                    CacheMethod.online => PlayKind.online,
                  },
            provider: task.method.name,
            providerLabel: switch (task.method) {
              CacheMethod.bt => 'BT 缓存',
              CacheMethod.pikpak => 'PikPak',
              CacheMethod.online => task.source ?? '在线缓存',
            },
            title: task.title,
            line: info.groups.join(' & '),
            quality: info.quality,
            languages: info.languages,
            target: DownloadTarget(task.id, media.file.id, task),
            instant: true,
          ),
        ]);
      } on StateError {
        // A task awaiting metadata cannot supply a playable file yet.
      }
    }
    final Future<void> onlineRequest = includeOnline
        ? onlineCandidates(
            registry,
            subject,
            episode,
            names: search.searchNames,
            onProgress: onProgress,
            onUpdate: add,
            cancel: searches,
            includeManual: !automatic,
          )
        : Future<void>.value();
    final searchCloud =
        includeTorrents &&
        includeCloud &&
        cloud.available &&
        registry.isEnabled('pikpak');
    // Torrents by info hash: checked against the index, and held there.
    final checked = <String>{}, held = <String>{};
    final cloudChecks = <Future<void>>[];
    // Lookups at a time; a page of results at once would flood the API.
    var cloudDone = 0, cloudFailed = 0, cloudSlots = 8;
    String? cloudIssue;
    final cloudTurns = <Completer<void>>[];
    var sourcesDone = false;
    void reportCloud() => onProgress?.call(
      SourceProgress(
        sourceId: 'pikpak',
        sourceName: 'PikPak',
        total: checked.length,
        completed: cloudDone,
        failed: cloudFailed,
        resultCount: held.length,
        message: cloudIssue,
        status: cloudDone < checked.length || !sourcesDone
            ? SearchStatus.loading
            : cloudFailed == 0
            ? SearchStatus.ready
            : cloudFailed == cloudDone
            ? SearchStatus.error
            : SearchStatus.partial,
      ),
    );
    Future<void> checkCloud(
      ReleaseCandidate release,
      String hash,
      int order,
    ) async {
      // A finished lookup hands its slot to the next waiting one.
      if (cloudSlots == 0) {
        final turn = Completer<void>();
        cloudTurns.add(turn);
        await turn.future;
      } else {
        cloudSlots--;
      }
      try {
        if (!searches.isCancelled && await cloud.holds(hash)) {
          held.add(hash);
          add([_releaseCandidate(release, order, kind: PlayKind.pikpak)]);
        }
      } catch (error) {
        cloudFailed++;
        cloudIssue = errorMessage(error);
      } finally {
        if (cloudTurns.isNotEmpty) {
          cloudTurns.removeAt(0).complete();
        } else {
          cloudSlots++;
        }
        cloudDone++;
        reportCloud();
      }
    }

    // For one episode, releases stating other episodes are left out.
    bool holds(ReleaseCandidate candidate) =>
        episode == null ||
        releaseMayHold(
          subject,
          episode,
          describeResource(candidate.release.title),
        );
    void addReleases(ReleaseSearchResult result) {
      if (searches.isCancelled) return;
      if (onProgress != null) result.sources.forEach(onProgress);
      add([
        for (final (index, candidate) in result.candidates.indexed)
          if (holds(candidate)) ...[
            _releaseCandidate(candidate, index),
            if (held.contains(torrentIdentity(candidate.release.locator)))
              _releaseCandidate(candidate, index, kind: PlayKind.pikpak),
          ],
      ]);
      if (!searchCloud) return;
      for (final (index, candidate) in result.candidates.indexed) {
        final hash = torrentIdentity(candidate.release.locator);
        if (holds(candidate) && _infoHash.hasMatch(hash) && checked.add(hash)) {
          cloudChecks.add(checkCloud(candidate, hash, index));
        }
      }
      reportCloud();
    }

    final sourceRequest = includeTorrents
        ? releases
              .search(
                subjectId,
                search,
                episodeId: episodeId,
                coverUrl: subject.coverUrl,
                cancel: searches,
                includeMetadata: !automatic,
                onUpdate: addReleases,
              )
              .then(addReleases)
        : Future<void>.value();
    Future<void> everything() async {
      await Future.wait([onlineRequest, sourceRequest]);
      sourcesDone = true;
      if (searchCloud) {
        reportCloud();
        await Future.wait(cloudChecks);
      }
    }

    try {
      await Future.any([everything(), settled.future]);
    } on RequestCancelled {
      cancel?.throwIfCancelled();
      // A settled search cancelled the sources still running.
    } finally {
      grace?.cancel();
      unlink?.call();
      searches.cancel();
    }
    cancel?.throwIfCancelled();
    return ranked();
  }

  /// How long automatic playback still waits for slower sources once one
  /// has what it wants: long enough for most sites to answer, short of
  /// feeling stuck.
  static const settleGrace = Duration(seconds: 4);

  /// What automatic playback opens for [episode] without a cache, by the
  /// subject's remembered source family, else [onlineFirst]: online first
  /// searches only online entries; BT first takes the best torrent by the
  /// subject's [taste] and plays online only when no torrent has the episode.
  /// A forced [family] (caching the next episode) searches that family alone.
  /// Only confident matches are chosen; `uncertain` says possible ones were
  /// left for the user, `online` that only online sources were searched.
  Future<({PlayCandidate? chosen, bool uncertain, bool online})> pick(
    Subject subject,
    Episode episode, {
    required bool onlineFirst,
    String language = 'auto',
    String? family,
    void Function(SourceProgress)? onProgress,
    RequestCancellation? cancel,
  }) async {
    final preferred = family == null ? await remembered(subject.id) : null;
    final want = family ?? preferred?.family ?? (onlineFirst ? 'online' : 'bt');
    final online = want == 'online';
    bool allowed(PlayCandidate c) => family == null || c.family == family;
    final ranked = await candidates(
      subject,
      episode,
      includeDownloads: false,
      includeOnline: online || family == null,
      includeTorrents: !online,
      // PikPak's index is looked up only for a subject played through it.
      includeCloud: want == 'pikpak',
      onlineFirst: online,
      automatic: true,
      language: language,
      useContinuity: true,
      settleOn: (c) =>
          c.family == want &&
          !c.possibleMatch &&
          !describeCandidate(c).batch &&
          switch (c.target) {
            OnlineTarget(:final ref) => ref != null,
            _ => true,
          },
      onProgress: onProgress,
      cancel: cancel,
    );
    final playable = ranked.where(
      (c) =>
          allowed(c) &&
          switch (c.target) {
            OnlineTarget(:final ref) => ref != null,
            _ => true,
          },
    );
    return (
      chosen: playable.where((c) => !c.possibleMatch).firstOrNull,
      uncertain: playable.any((c) => c.possibleMatch),
      online: online,
    );
  }

  /// Opens [candidate] as the episode; a torrent is added first and plays
  /// once its files are known, reporting its task through [onTask].
  Future<PlaybackSession> load(
    PlayCandidate candidate,
    int subjectId,
    int episodeId, {
    RequestCancellation? cancel,
    void Function(String downloadId)? onTask,
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
      cancel: cancel,
    );
    final id = task.id;
    onTask?.call(id);
    // A magnet plays once its metadata names the files; that takes as long
    // as the swarm takes, so wait for it rather than for a fixed time. A
    // swarm that never answers sends no change, so cancelling must end the
    // wait by itself: playback queues behind it.
    final changes = StreamIterator(downloads.changes.stream);
    final cancelled = Completer<bool>();
    final unlink = cancel?.listen(() {
      if (!cancelled.isCompleted) cancelled.complete(true);
    });
    try {
      while (true) {
        cancel?.throwIfCancelled();
        try {
          downloads.media(id);
          // The torrent may already be a task added without this episode, or
          // for another one: transfers hand back the task they hold for it.
          return await library.fromDownload(
            id,
            subjectId: subjectId,
            episodeId: episodeId,
          );
        } on StateError catch (e) {
          final current = downloads.snapshot().task(id);
          if (current == null ||
              current.status == DownloadStatus.failed ||
              e is MultipleVideos) {
            rethrow;
          }
          if (!await Future.any([changes.moveNext(), cancelled.future])) {
            throw StateError('下载已停止');
          }
        }
      }
    } finally {
      unlink?.call();
      await changes.cancel();
    }
  }

  /// Records [candidate] as the subject's source for the next episodes, and
  /// for later runs while remembering is on. Cached files are not choices.
  Future<void> played(int subjectId, PlayCandidate candidate) async {
    continuity[subjectId] = candidate.continuityKey;
    if (!remember() || candidate.kind == PlayKind.local) return;
    final source = RememberedSource.of(candidate);
    final previous = _remembered[subjectId];
    _remembered[subjectId] = source;
    await store.put(rememberedScope, '$subjectId', source.toJson());
    if (previous?.key != source.key) rememberedChanges.add(null);
  }

  void failed(PlayCandidate candidate) {
    _failures[candidate.id] = (_failures[candidate.id] ?? 0) + 1;
    candidate.health = -_failures[candidate.id]!;
  }
}

final _infoHash = RegExp(r'^[0-9a-f]{40}$');

/// A torrent fetched over BT, or through PikPak when its index holds it; both
/// belong to the site that listed the torrent.
PlayCandidate _releaseCandidate(
  ReleaseCandidate candidate,
  int order, {
  PlayKind kind = PlayKind.bt,
}) {
  final release = candidate.release;
  final info = describeResource(
    release.title,
    releaseGroups: release.releaseGroups,
  );
  final cloud = kind == PlayKind.pikpak;
  return PlayCandidate(
    kind: kind,
    provider: candidate.sourceId,
    providerLabel: cloud ? 'PikPak' : candidate.sourceName,
    title: info.title,
    line: info.groups.join(' & '),
    quality: info.quality,
    languages: info.languages,
    target: ReleaseTarget(candidate),
    instant: false,
    order: order,
  );
}
