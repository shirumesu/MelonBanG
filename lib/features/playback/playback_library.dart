import 'dart:io';

import 'package:path/path.dart' as p;

import '../../integrations/melon_api/catalog.dart';
import '../../core/json.dart';
import '../../core/store.dart';
import '../../domain/catalog.dart';
import '../../domain/playback_session.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';
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
  final CatalogRepository catalog;
  Future<PlaybackSession> fromDownload(
    String id, {
    String? fileId,
    int? subjectId,
    int? episodeId,
  }) async {
    final media = await downloads.openMedia(id, fileId: fileId);
    subjectId ??= media.subjectId;
    episodeId ??= media.episodeId;
    final path = media.file.path;
    final streamUrl = media.streamUrl;
    if (streamUrl == null && !await File(path).exists()) {
      throw StateError('视频文件不存在');
    }
    return PlaybackSession(
      id: newId(),
      title: p.basename(path),
      path: path,
      url: streamUrl ?? Uri.file(path).toString(),
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
    try {
      if (subjectId != null && episodeId != null) {
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
    } catch (_) {
      // Playback remains usable when its library binding cannot be saved.
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
      if (binding?['downloadId'] case final String id) {
        media = downloads.contains(id)
            ? downloads.media(id, fileId: binding!['fileId'] as String?)
            : downloads.episodeMedia(subjectId, episodeId);
      } else {
        media = downloads.episodeMedia(subjectId, episodeId);
      }
      return media.incomplete || await File(media.file.path).exists();
    } on StateError {
      return false;
    }
  }

  Future<Set<int>> playableEpisodes(int subjectId) async {
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
    }
    final available = <int>{};
    for (final id in ids) {
      if (await _available(
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

  Future<List<PlaybackResume>> recent({int limit = 8, int? forSubject}) async {
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
            duration <= position ||
            (!await _available(subjectId, episodeId) &&
                await store.get('online_episodes', '$subjectId:$episodeId') ==
                    null)) {
          continue;
        }
        final detail =
            await catalog.cached(subjectId) ?? Subject(id: subjectId);
        result.add(
          PlaybackResume(
            subject: detail,
            episodeId: episodeId,
            position: position,
            duration: duration,
            episodeSort: detail.episode(episodeId)?.number,
          ),
        );
        subjects.add(subjectId);
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
