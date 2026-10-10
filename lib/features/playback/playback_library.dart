import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/catalog.dart';
import '../../data/json.dart';
import '../../data/store.dart';
import '../../domain/transfer.dart';
import '../downloads/download_repository.dart';

class PlaybackLibrary {
  PlaybackLibrary(this.store, this.downloads, this.catalog);
  final AppStore store;
  final DownloadRepository downloads;
  final CatalogRepository catalog;
  Future<Json> fromDownload(
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
    final session = <String, dynamic>{
      'id': newId(),
      'title': p.basename(path),
      'path': path,
      'source': {
        'url': streamUrl ?? Uri.file(path).toString(),
        if (media.headers != null) 'headers': media.headers,
      },
      'resumeKey': 'download:$id:${media.file.id}',
      'streamId': media.streamId,
      'status': 'ready',
      'subjectId': subjectId,
      'episodeId': episodeId,
      'downloadId': id,
      'fileId': media.file.id,
      'fileSize': media.file.size,
      'remoteSource': streamUrl != null,
    };
    return session;
  }

  Future<Json> online(
    Json source, {
    int? subjectId,
    int? episodeId,
    String? provider,
    String? line,
    String? title,
  }) async {
    final session = <String, dynamic>{
      'id': newId(),
      'title': title ?? '在线视频',
      'source': source,
      'resumeKey': subjectId != null && episodeId != null
          ? 'online:$subjectId:$episodeId'
          : null,
      'status': 'ready',
      'subjectId': subjectId,
      'episodeId': episodeId,
      'provider': provider,
      'line': line,
      'remoteSource': true,
      'standalone': subjectId == null || episodeId == null,
    };
    return session;
  }

  Future<void> activate(Json session) async {
    final subjectId = session['subjectId'], episodeId = session['episodeId'];
    try {
      if (subjectId != null && episodeId != null) {
        if (session['downloadId'] case final String downloadId) {
          await store.put('episode_files', '$subjectId:$episodeId', {
            'downloadId': downloadId,
            'fileId': session['fileId'],
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

  Future<Json> episode(int subjectId, int episodeId) async {
    final localFile = await store.get('episode_files', '$subjectId:$episodeId');
    if (localFile?['downloadId'] case final String downloadId) {
      await downloads.ready;
      if (downloads.contains(downloadId)) {
        return fromDownload(
          downloadId,
          fileId: localFile!['fileId'] as String?,
          subjectId: subjectId,
          episodeId: episodeId,
        );
      }
      await store.remove('episode_files', '$subjectId:$episodeId');
      final replacement = downloads.episodeMedia(subjectId, episodeId);
      return fromDownload(
        replacement.file.downloadId,
        fileId: replacement.file.id,
      );
    }
    final media = downloads.episodeMedia(subjectId, episodeId);
    return fromDownload(media.file.downloadId, fileId: media.file.id);
  }

  Future<Json?> progress(int subjectId, int episodeId) =>
      store.get('playback_progress', '$subjectId:$episodeId');

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

  Future<List<Json>> recent({int limit = 8, int? forSubject}) async {
    final result = <Json>[];
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
        final detail = await cachedSubjectDetail(store, subjectId) ?? {};
        final episodes = objects(detail['episodes'])
            .where((e) => e['episodeId'] == episodeId);
        result.add({
          ...catalog.summary(detail),
          ...value,
          'subjectId': subjectId,
          'episodeId': episodeId,
          'episodeSort': episodes.isEmpty
              ? null
              : episodes.first['ep'] ?? episodes.first['sort'],
        });
        subjects.add(subjectId);
        if (result.length >= limit) return result;
      }
      if (page.length < pageSize) break;
    }
    return result;
  }

  Future<void> save(
    Json session,
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
    if (session['subjectId'] == null || session['episodeId'] == null) return;
    await store.put(
      'playback_progress',
      '${session['subjectId']}:${session['episodeId']}',
      {
        'positionSeconds': ended ? 0 : position.clamp(0, duration),
        'durationSeconds': duration,
        'completed': ended,
      },
    );
  }
}
