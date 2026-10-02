import 'dart:io';

import 'cache_method.dart';
import 'downloads.dart';
import 'json.dart';
import 'online_sources/repository.dart';
import 'play_candidates.dart';
import 'playback_library.dart';
import 'resource_metadata.dart';
import 'resource_title.dart';
import 'sources.dart';
import 'store.dart';

class PlaySelectionRepository {
  PlaySelectionRepository(
    this.store,
    this.library,
    this.downloads,
    this.sources,
    this.online,
  );
  final AppStore store;
  final PlaybackLibrary library;
  final DownloadRepository downloads;
  final SourceRepository sources;
  final OnlineSourceRepository online;
  final continuity = <int, String>{};
  final _failures = <String, int>{};

  Future<List<PlayCandidate>> candidates(
    Json subject,
    Json episode, {
    bool instantOnly = false,
    bool includeOnline = true,
    bool onlineFirst = false,
    String language = 'auto',
    bool useContinuity = false,
    void Function(List<PlayCandidate>)? onUpdate,
  }) async {
    final subjectId = subject['subjectId'] as int;
    final episodeId = episode['episodeId'] as int;
    final found = <String, PlayCandidate>{};
    List<PlayCandidate> ranked() => rankPlayCandidates(
      found.values,
      onlineFirst: onlineFirst,
      language: language,
      continuity: useContinuity ? continuity[subjectId] : null,
    );
    void add(Iterable<PlayCandidate> values) {
      for (final candidate in values) {
        candidate.health = -(_failures[candidate.id] ?? 0);
        found[candidate.id] = candidate;
      }
      onUpdate?.call(ranked());
    }

    final binding = await store.get('episode_files', '$subjectId:$episodeId');
    if (binding != null &&
        binding['downloadId'] == null &&
        await File('${binding['path']}').exists()) {
      add([
        PlayCandidate(
          kind: PlayKind.local,
          provider: 'local',
          providerLabel: '本地文件',
          title: Uri.file('${binding['path']}').pathSegments.last,
          ref: binding,
          instant: true,
          existing: true,
        ),
      ]);
    }
    final snapshot = downloads.snapshot();
    for (final task in objects(snapshot['tasks'])) {
      final bound = binding?['downloadId'] == task['id'];
      if (task['subjectId'] != subjectId ||
          (!bound && task['episodeId'] != episodeId)) {
        continue;
      }
      try {
        final media = downloads.media(
          '${task['id']}',
          fileId: bound ? binding!['fileId'] as String? : null,
        );
        if (media['incomplete'] == true &&
            task['provider'] == 'pikpak' &&
            !online.isEnabled('pikpak')) {
          continue;
        }
        if (media['incomplete'] != true &&
            !await File('${media['path']}').exists()) {
          continue;
        }
        final info = describeResource(task);
        add([
          PlayCandidate(
            kind: media['incomplete'] != true
                ? PlayKind.local
                : task['provider'] == 'pikpak'
                ? PlayKind.pikpak
                : PlayKind.bt,
            provider: task['provider'] == 'pikpak' ? 'pikpak' : 'bt',
            providerLabel: task['provider'] == 'pikpak' ? 'PikPak' : 'BT 缓存',
            title: '${task['title'] ?? media['name']}',
            line: info.sourceGroups.join(' & '),
            quality: info.quality,
            languages: info.languages,
            ref: {...task, 'downloadId': task['id'], 'fileId': media['id']},
            instant: true,
            existing: true,
          ),
        ]);
      } on StateError {
        // A task awaiting metadata cannot supply a playable file yet.
      }
    }
    await Future.wait([
      if (includeOnline)
        online
            .candidates(subject, episode)
            .then(
              (rows) => add([
                for (var i = 0; i < rows.length; i++)
                  PlayCandidate.online(rows[i], i),
              ]),
            ),
      if (!instantOnly)
        sources
            .search(
              subjectId,
              titleOf(subject),
              alternativeNames: resourceNames(subject),
              episodeId: episodeId,
              episodeKeyword: resourceEpisodeKeyword(episode),
              coverUrl: subject['coverUrl'] as String?,
              onUpdate: (result) => add([
                for (final (index, row) in objects(
                  result['candidates'],
                ).indexed)
                  PlayCandidate.release(row, index),
              ]),
            )
            .then(
              (result) => add([
                for (final (index, row) in objects(
                  result['candidates'],
                ).indexed)
                  PlayCandidate.release(row, index),
              ]),
            ),
    ]);
    return ranked();
  }

  Future<Json> load(
    PlayCandidate candidate,
    int subjectId,
    int episodeId,
  ) async {
    if (candidate.kind == PlayKind.online) {
      return library.online(
        await online.resolve(candidate.ref),
        subjectId: subjectId,
        episodeId: episodeId,
        provider: candidate.provider,
        line: candidate.line,
        ref: candidate.ref,
        title: candidate.title,
      );
    }
    if (candidate.ref['downloadId'] case final String id) {
      return library.fromDownload(
        id,
        fileId: candidate.ref['fileId'] as String?,
        subjectId: subjectId,
        episodeId: episodeId,
      );
    }
    if (candidate.kind == PlayKind.local) {
      return library.local(
        '${candidate.ref['path']}',
        subjectId: subjectId,
        episodeId: episodeId,
      );
    }
    final task = await sources.enqueue(
      '${candidate.ref['candidateId']}',
      method: candidate.kind == PlayKind.pikpak
          ? CacheMethod.pikpak
          : CacheMethod.bt,
    );
    final id = '${task['id']}';
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      try {
        downloads.media(id);
        return await library.fromDownload(id);
      } on StateError catch (e) {
        final current = objects(downloads.snapshot()['tasks'])
            .where((task) => task['id'] == id)
            .firstOrNull;
        if (current == null ||
            current['status'] == 'failed' ||
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
