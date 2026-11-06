import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../core/error_message.dart';
import '../../domain/catalog.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../acquisition/resource_metadata.dart';
import '../../domain/release_traits.dart';
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
    final saved = await store.get(_rememberedScope, '$subjectId');
    return _remembered[subjectId] = saved == null
        ? null
        : RememberedSource.fromJson(saved);
  }

  Future<void> forget(int subjectId) async {
    _remembered[subjectId] = null;
    await store.remove(_rememberedScope, '$subjectId');
  }

  static const _rememberedScope = 'source_preferences';

  /// Cached files, online entries and torrents for [episode], or for the
  /// whole subject without one, ranked for playback. With [includeCloud],
  /// torrents PikPak's index holds are also PikPak candidates.
  /// [terms] default to the catalogue names and the chapter number;
  /// [onUpdate] hands over the ranking of what is found so far each time
  /// results arrive, to be worked out when shown; [onProgress] reports each
  /// online, torrent and PikPak search state.
  ///
  /// [automatic] playback leaves out sources that need a manual choice and
  /// optional site pages, and with [settleOn] stops waiting for the slowest
  /// sources [settleGrace] after a result it accepts turned up.
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
    final releaseTaste = taste(subjectId);
    List<PlayCandidate> ranked() => rankPlayCandidates(
      found.values,
      onlineFirst: onlineFirst,
      language: language,
      remembered: preferred,
      continuity: useContinuity ? continuity[subjectId] : null,
      singleEpisode: episode != null,
      taste: releaseTaste,
    );
    // Searches still running once the result is settled are dropped.
    final searches = RequestCancellation();
    final unlink = cancel?.listen(searches.cancel);
    final settled = Completer<void>();
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
    for (final task
        in includeDownloads
            ? downloads.snapshot().forSubject(subjectId)
            : const <DownloadTask>[]) {
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
            existing: true,
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
          add([releaseCandidate(release, order, kind: PlayKind.pikpak)]);
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
            releaseCandidate(candidate, index),
            if (held.contains(torrentIdentity(candidate.release.locator)))
              releaseCandidate(candidate, index, kind: PlayKind.pikpak),
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

  /// What automatic playback opens for [episode] when it has no cache: by
  /// the subject's remembered source family, else by [onlineFirst]. Online
  /// first never downloads: only online entries are searched. BT first
  /// takes the best torrent, as [rankPlayCandidates] orders them by the
  /// subject's [taste], and plays online only when no torrent has the
  /// episode. A forced [family] (caching the next episode from the one
  /// playing) takes that family alone. Only confident matches are picked;
  /// `uncertain` says some possible ones were left for the user, `online`
  /// that only online sources were searched.
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
    );
    final id = task.id;
    onTask?.call(id);
    // A magnet plays once its metadata names the files; that takes as long
    // as the swarm takes, so wait for it rather than for a fixed time.
    final changes = StreamIterator(downloads.changes.stream);
    try {
      while (true) {
        cancel?.throwIfCancelled();
        try {
          downloads.media(id);
          return await library.fromDownload(id);
        } on StateError catch (e) {
          final current = downloads.snapshot().task(id);
          if (current == null ||
              current.status == DownloadStatus.failed ||
              e is MultipleVideos) {
            rethrow;
          }
          await changes.moveNext();
        }
      }
    } finally {
      await changes.cancel();
    }
  }

  /// Records [candidate] as the subject's source for the next episodes, and
  /// for later runs while remembering is on. Cached files are not choices.
  Future<void> played(int subjectId, PlayCandidate candidate) async {
    continuity[subjectId] = candidate.continuityKey;
    if (!remember() || candidate.kind == PlayKind.local) return;
    final source = RememberedSource.of(candidate);
    _remembered[subjectId] = source;
    await store.put(_rememberedScope, '$subjectId', source.toJson());
  }

  void failed(PlayCandidate candidate) {
    _failures[candidate.id] = (_failures[candidate.id] ?? 0) + 1;
    candidate.health = -_failures[candidate.id]!;
  }
}

final _infoHash = RegExp(r'^[0-9a-f]{40}$');

/// A torrent fetched over BT, or through PikPak when its index holds it; both
/// belong to the site that listed the torrent.
PlayCandidate releaseCandidate(
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

  factory RememberedSource.fromJson(Json json) => RememberedSource(
    family: '${json['family'] ?? ''}',
    provider: '${json['provider'] ?? ''}',
    line: '${json['line'] ?? ''}',
    key: '${json['key'] ?? ''}',
    label: '${json['label'] ?? ''}',
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
/// Within a tier confident matches precede possible ones, recently failed
/// sources drop, the subject's remembered source and then this run's choice
/// continue; single episodes come before batches when [singleEpisode], then
/// releases of the [taste]'s groups in their order, those meeting its
/// selections, and [resourceScores] orders the rest.
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
