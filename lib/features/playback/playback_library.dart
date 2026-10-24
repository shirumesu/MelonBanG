import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/json.dart';
import '../../core/store.dart';
import '../../domain/catalog.dart';
import '../../domain/playback_session.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';
import '../acquisition/title_matching.dart';
import '../downloads/download_repository.dart';

/// Saved position of an episode.
typedef EpisodeProgress = ({double position, double duration, bool completed});

/// A recently watched, unfinished episode that can still be played.
class PlaybackResume {
  const PlaybackResume({
    required this.subject,
    required this.episodeId,
    required this.position,
    required this.duration,
    this.episodeSort,
  });
  final Subject subject;
  final int episodeId;
  final double position, duration;
  final String? episodeSort;
}

class PlaybackLibrary {
  PlaybackLibrary(this.store, this.downloads, this.catalog);
  final AppStore store;
  final DownloadRepository downloads;
  final Catalog catalog;
  Future<PlaybackSession> fromDownload(
    String id, {
    String? fileId,
    int? subjectId,
    int? episodeId,
  }) async {
    final media = await downloads.openMedia(id, fileId: fileId);
    subjectId ??= media.subjectId;
    episodeId ??= media.episodeId;
    // A video of a batch plays as the episode its name gives.
    if (episodeId == null && subjectId != null) {
      if (await catalog.cached(subjectId) case final subject?) {
        episodeId = episodeFiles(subject, downloads.snapshot().task(id)!)
            .entries
            .where((entry) => entry.value.id == media.file.id)
            .firstOrNull
            ?.key;
      }
    }
    if (media.online case final stream?) {
      return online(
        stream,
        subjectId: subjectId,
        episodeId: episodeId,
        title: downloads.snapshot().task(id)?.title,
      );
    }
    final path = media.file.path;
    final streamUrl = media.streamUrl;
    if (streamUrl == null && !await File(path).exists()) {
      throw StateError(
        await downloads.forgetDeleted(id) ? '视频文件已被删除，已从缓存中移除' : '视频文件不存在',
      );
    }
    return PlaybackSession(
      id: newId(),
      title: p.basename(path),
      path: path,
      url: streamUrl ?? Uri.file(path).toString(),
      audioUrl: switch (media.audioPath) {
        final audio? => Uri.file(audio).toString(),
        null => null,
      },
      danmaku: media.danmaku,
      headers: media.headers ?? const {},
      resumeKey: 'download:$id:${media.file.id}',
      streamId: media.streamId,
      subjectId: subjectId,
      episodeId: episodeId,
      downloadId: id,
      fileId: media.file.id,
      fileSize: media.file.size,
      remote: streamUrl != null,
    );
  }

  PlaybackSession online(
    ResolvedStream stream, {
    int? subjectId,
    int? episodeId,
    String? title,
  }) => PlaybackSession(
    id: newId(),
    title: title ?? '在线视频',
    url: stream.url,
    headers: stream.headers,
    format: stream.format,
    playlist: stream.playlist,
    audioUrl: stream.audioUrl,
    danmaku: stream.danmakuProvider == null
        ? null
        : (stream.danmakuProvider!, '${stream.danmakuLocator}'),
    resumeKey: subjectId != null && episodeId != null
        ? 'online:$subjectId:$episodeId'
        : null,
    subjectId: subjectId,
    episodeId: episodeId,
    remote: true,
    standalone: subjectId == null || episodeId == null,
  );

  Future<void> activate(PlaybackSession session) async {
    final subjectId = session.subjectId, episodeId = session.episodeId;
    if (subjectId == null || episodeId == null) return;
    if (session.downloadId case final downloadId?) {
      await store.put('episode_files', '$subjectId:$episodeId', {
        'downloadId': downloadId,
        'fileId': session.fileId,
      });
    } else {
      await store.put('online_episodes', '$subjectId:$episodeId', {
        'online': true,
      });
    }
  }

  Future<EpisodeProgress?> progress(int subjectId, int episodeId) async {
    final saved = await store.get('playback_progress', '$subjectId:$episodeId');
    return saved == null
        ? null
        : (
            position: number(saved['positionSeconds']),
            duration: number(saved['durationSeconds']),
            completed: saved['completed'] == true,
          );
  }

  Future<bool> _available(
    Subject? subject,
    int subjectId,
    int episodeId, {
    Json? binding,
    bool lookupBinding = true,
  }) async {
    if (lookupBinding) {
      binding = await store.get('episode_files', '$subjectId:$episodeId');
    }
    try {
      final TransferMedia media;
      if (binding?['downloadId'] case final String id
          when downloads.contains(id)) {
        media = downloads.media(id, fileId: binding!['fileId'] as String?);
      } else {
        media = _episodeMedia(subject, subjectId, episodeId);
      }
      return media.incomplete || await File(media.file.path).exists();
    } on StateError {
      return false;
    }
  }

  /// The most complete playable download of an episode: a task cached for
  /// it, or a video of one of the subject's batches named after it.
  TransferMedia _episodeMedia(Subject? subject, int subjectId, int episodeId) {
    final found = <TransferMedia>[];
    for (final task in downloads.snapshot().forSubject(subjectId)) {
      final file = subject == null
          ? null
          : episodeFiles(subject, task)[episodeId];
      if (file == null && task.episodeId != episodeId) continue;
      try {
        found.add(downloads.media(task.id, fileId: file?.id));
      } on StateError {
        continue;
      }
    }
    found.sort((a, b) => b.file.progress.compareTo(a.file.progress));
    return found.firstOrNull ?? (throw StateError('该章节尚无可播放下载，请选择资源或具体视频文件'));
  }

  Future<Set<int>> playableEpisodes(int subjectId) async {
    final subject = await catalog.cached(subjectId);
    final ids = <int>{};
    final bindings = await store.entries(
      'episode_files',
      idPrefix: '$subjectId:',
    );
    for (final key in bindings.keys) {
      final parts = key.split(':');
      if (parts.length == 2 && int.tryParse(parts.first) == subjectId) {
        final id = int.tryParse(parts.last);
        if (id != null) ids.add(id);
      }
    }
    for (final task in downloads.snapshot().forSubject(subjectId)) {
      if (task.episodeId case final int episodeId) ids.add(episodeId);
      if (subject != null) ids.addAll(episodeFiles(subject, task).keys);
    }
    final available = <int>{};
    for (final id in ids) {
      if (await _available(
        subject,
        subjectId,
        id,
        binding: bindings['$subjectId:$id'],
        lookupBinding: false,
      )) {
        available.add(id);
      }
    }
    return available;
  }

  /// The episode of [subjectId] that played last, with its saved progress.
  Future<({int episodeId, EpisodeProgress progress})?> lastPlayed(
    int subjectId,
  ) async {
    final page = await store.entries(
      'playback_progress',
      idPrefix: '$subjectId:',
      limit: 1,
    );
    for (final MapEntry(:key, :value) in page.entries) {
      final episodeId = int.tryParse(key.split(':').last);
      if (episodeId == null) continue;
      return (
        episodeId: episodeId,
        progress: (
          position: number(value['positionSeconds']),
          duration: number(value['durationSeconds']),
          completed: value['completed'] == true,
        ),
      );
    }
    return null;
  }

  /// Subjects by when an episode of theirs last played, most recent first.
  Future<List<int>> playedSubjects() async => {
    for (final key in (await store.entries('playback_progress')).keys)
      ?int.tryParse(key.split(':').first),
  }.toList();

  /// The latest unfinished episode of each recently played subject; with
  /// [accept], a subject whose latest one it rejects is left out.
  Future<List<PlaybackResume>> recent({
    int limit = 8,
    int? forSubject,
    Future<bool> Function(Subject subject, int episodeId)? accept,
  }) async {
    final result = <PlaybackResume>[];
    final subjects = <int>{};
    if (limit <= 0) return result;
    const pageSize = 32;
    for (var offset = 0; ; offset += pageSize) {
      final page = await store.entries(
        'playback_progress',
        idPrefix: forSubject == null ? null : '$forSubject:',
        limit: pageSize,
        offset: offset,
      );
      for (final entry in page.entries) {
        final parts = entry.key.split(':');
        if (parts.length != 2) continue;
        final subjectId = int.tryParse(parts.first);
        final episodeId = int.tryParse(parts.last);
        if (forSubject != null && subjectId != forSubject) continue;
        final value = entry.value;
        final position = number(value['positionSeconds']);
        final duration = number(value['durationSeconds']);
        if (subjectId == null ||
            episodeId == null ||
            subjects.contains(subjectId) ||
            value['completed'] == true ||
            !position.isFinite ||
            !duration.isFinite ||
            position <= 0 ||
            duration <= position) {
          continue;
        }
        final cached = await catalog.cached(subjectId);
        if (!await _available(cached, subjectId, episodeId) &&
            await store.get('online_episodes', '$subjectId:$episodeId') ==
                null) {
          continue;
        }
        final detail = cached ?? Subject(id: subjectId);
        subjects.add(subjectId);
        if (accept != null && !await accept(detail, episodeId)) continue;
        result.add(
          PlaybackResume(
            subject: detail,
            episodeId: episodeId,
            position: position,
            duration: duration,
            episodeSort: detail.episode(episodeId)?.number,
          ),
        );
        if (result.length >= limit) return result;
      }
      if (page.length < pageSize) break;
    }
    return result;
  }

  Future<void> save(
    PlaybackSession session,
    double position,
    double duration,
    bool ended,
  ) async {
    if (!position.isFinite ||
        position < 0 ||
        !duration.isFinite ||
        duration <= 0) {
      return;
    }
    if (session.subjectId == null || session.episodeId == null) return;
    await store.put(
      'playback_progress',
      '${session.subjectId}:${session.episodeId}',
      {
        'positionSeconds': ended ? 0 : position.clamp(0, duration),
        'durationSeconds': duration,
        'completed': ended,
      },
    );
  }
}
