import 'dart:async';
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

/// A recently watched, unfinished episode, here or on a device whose places
/// synced here. It need not have a cache: playing it picks a source as any
/// episode does, and the place is kept by episode, whatever played it.
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

  /// Whether it played long enough to be watching, not a look: such a
  /// place is resumed even away from the episode the watched marks lead to.
  bool get engaged =>
      position >= 180 || (duration > 0 && position >= duration * .15);
}

class PlaybackLibrary {
  PlaybackLibrary(this.store, this.downloads, this.catalog);
  final AppStore store;

  static const progressScope = 'playback_progress';

  /// Fires as an episode's place is saved here, every few seconds while it
  /// plays.
  final progressChanges = StreamController<void>.broadcast(sync: true);
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
      if ((await catalog.cached(subjectId), downloads.snapshot().task(id))
          case (final subject?, final task?)) {
        episodeId = episodeFiles(subject, task).entries
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

  /// Binds a cached file that opened as an episode to it, so the episode
  /// plays that file first.
  Future<void> activate(PlaybackSession session) async {
    final subjectId = session.subjectId, episodeId = session.episodeId;
    if (subjectId == null || episodeId == null) return;
    if (session.downloadId case final downloadId?) {
      await store.put('episode_files', '$subjectId:$episodeId', {
        'downloadId': downloadId,
        'fileId': session.fileId,
      });
    }
  }

  Future<EpisodeProgress?> progress(int subjectId, int episodeId) async {
    final saved = await store.get('playback_progress', '$subjectId:$episodeId');
    return saved == null ? null : _progress(saved);
  }

  static EpisodeProgress _progress(Json row) => (
    position: number(row['positionSeconds']),
    duration: number(row['durationSeconds']),
    completed: row['completed'] == true,
  );

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
    // A bound file that no longer plays, as after deleting it from a batch,
    // leaves the episode to its other downloads, such as one cached later.
    if (binding?['downloadId'] case final String id
        when downloads.contains(id)) {
      final fileId = binding!['fileId'] as String?;
      if (await _playable(() => downloads.media(id, fileId: fileId))) {
        return true;
      }
    }
    // A task cached for the episode, or a video of one of the subject's
    // batches named after it.
    for (final task in downloads.snapshot().forSubject(subjectId)) {
      final file = subject == null
          ? null
          : episodeFiles(subject, task)[episodeId];
      if (file == null && task.episodeId != episodeId) continue;
      if (await _playable(() => downloads.media(task.id, fileId: file?.id))) {
        return true;
      }
    }
    return false;
  }

  /// Whether [media] names a video that plays now: one still downloading
  /// streams, a finished one needs its file. A download that cannot supply
  /// it, not yet knowing its files or checking them, says so with a
  /// [StateError].
  Future<bool> _playable(TransferMedia Function() media) async {
    final TransferMedia found;
    try {
      found = media();
    } on StateError {
      return false;
    }
    return found.incomplete || await File(found.file.path).exists();
  }

  Future<Set<int>> playableEpisodes(int subjectId) async {
    final subject = await catalog.cached(subjectId);
    final ids = <int>{};
    final bindings = await store.entries(
      'episode_files',
      idPrefix: '$subjectId:',
    );
    for (final key in bindings.keys) {
      ids.add(int.parse(key.split(':').last));
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
    return switch (page.entries.firstOrNull) {
      MapEntry(:final key, :final value) => (
        episodeId: int.parse(key.split(':').last),
        progress: _progress(value),
      ),
      null => null,
    };
  }

  /// When an episode of each subject last played, most recent first.
  Future<Map<int, DateTime>> playedSubjects() async {
    final played = <int, DateTime>{};
    for (final MapEntry(:key, :value) in (await store.updatedAt(
      'playback_progress',
    )).entries) {
      if (int.tryParse(key.split(':').first) case final id?) {
        played.putIfAbsent(id, () => value);
      }
    }
    return played;
  }

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
        final subjectId = int.parse(parts.first);
        final episodeId = int.parse(parts.last);
        final (:position, :duration, :completed) = _progress(entry.value);
        if (subjects.contains(subjectId) ||
            completed ||
            position <= 0 ||
            duration <= position) {
          continue;
        }
        final detail =
            await catalog.cached(subjectId) ?? Subject(id: subjectId);
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
    progressChanges.add(null);
  }
}
