import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'danmaku_repository.dart';
import 'catalog.dart';
import 'downloads.dart';
import 'json.dart';
import 'resource_metadata.dart';
import 'store.dart';

class PlaybackLibrary {
  PlaybackLibrary(this.store, this.downloads, this.danmaku, this.catalog);
  final AppStore store;
  final DownloadRepository downloads;
  final DanmakuRepository danmaku;
  final CatalogRepository catalog;
  bool Function(String provider)? providerEnabled;
  final changes = StreamController<Json>.broadcast();
  Json? current;
  final _comments = <String, List<Json>>{};
  final _loads = <String, Object>{};
  Future<Json> fromDownload(
    String id, {
    String? fileId,
    int? subjectId,
    int? episodeId,
  }) async {
    final media = await downloads.openMedia(id, fileId: fileId);
    subjectId ??= media['subjectId'] as int?;
    episodeId ??= media['episodeId'] as int?;
    final path = '${media['path']}';
    final streamUrl = media['streamUrl'] as String?;
    if (streamUrl == null && !await File(path).exists()) {
      throw StateError('视频文件不存在');
    }
    final session = <String, dynamic>{
      'id': newId(),
      'title': p.basename(path),
      'path': path,
      'source': {
        'url': streamUrl ?? Uri.file(path).toString(),
        if (media['sourceHeaders'] != null) 'headers': media['sourceHeaders'],
      },
      'resumeKey': 'download:$id:${media['id']}',
      'streamId': media['streamId'],
      'status': 'ready',
      'subjectId': subjectId,
      'episodeId': episodeId,
      'downloadId': id,
      'fileId': media['id'],
      'fileSize': media['size'],
      'remoteSource': streamUrl != null,
      'danmaku': <Json>[],
      'danmakuSources': [
        for (final source in [
          ('dandanplay', '弹弹play'),
          ('bilibili', 'Bilibili'),
          ('bahamut', '巴哈姆特'),
        ])
          {
            'id': source.$1,
            'label': source.$2,
            'enabled': providerEnabled?.call(source.$1) ?? true,
            'status': 'idle',
            'count': 0,
          },
      ],
    };
    return session;
  }

  Future<Json> online(
    Json source, {
    int? subjectId,
    int? episodeId,
    String? provider,
    String? line,
    Json? ref,
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
      'onlineRef': ref,
      'remoteSource': true,
      'standalone': subjectId == null || episodeId == null,
      'danmaku': <Json>[],
      'danmakuSources': [
        for (final entry in [
          ('dandanplay', '弹弹play'),
          ('bilibili', 'Bilibili'),
          ('bahamut', '巴哈姆特'),
        ])
          {
            'id': entry.$1,
            'label': entry.$2,
            'enabled': providerEnabled?.call(entry.$1) ?? true,
            'status': 'idle',
            'count': 0,
          },
      ],
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
    current = session;
    _comments.clear();
    _loads.clear();
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
        '${replacement['downloadId']}',
        fileId: '${replacement['id']}',
      );
    }
    final media = downloads.episodeMedia(subjectId, episodeId);
    return fromDownload('${media['downloadId']}', fileId: '${media['id']}');
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
      final Json media;
      if (binding?['downloadId'] case final String id) {
        media = downloads.contains(id)
            ? downloads.media(id, fileId: binding!['fileId'] as String?)
            : downloads.episodeMedia(subjectId, episodeId);
      } else {
        media = downloads.episodeMedia(subjectId, episodeId);
      }
      return media['incomplete'] == true ||
          await File('${media['path']}').exists();
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
    for (final task in downloads.tasksForSubject(subjectId)) {
      if (task['subjectId'] == subjectId && task['episodeId'] is int) {
        ids.add(task['episodeId'] as int);
      }
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
        final cached =
            await store.get('catalog', 'detail:$subjectId') ??
            await store.get('catalog', 'playback-detail:$subjectId');
        final detail = object(object(cached?['value'])['data']);
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

  Future<void> autoMatch(double duration, {String? sessionId}) async {
    final session = current;
    if (session == null || (sessionId != null && session['id'] != sessionId)) {
      return;
    }
    Future<Json>? detailRequest;
    final enabled = objects(session['danmakuSources'])
        .where((s) => s['enabled'] == true && s['id'] != 'local')
        .map((s) => '${s['id']}');
    await Future.wait(
      enabled.map(
        (provider) => _load(provider, () async {
          final saved = await store.get(
            'danmaku_matches',
            '${session['path'] ?? session['resumeKey']}:$provider',
          );
          if (saved != null) {
            return _fetch(provider, '${saved['locator']}');
          }
          if (provider == 'dandanplay') {
            DandanMatch? match;
            if (session['subjectId'] case final int subjectId) {
              try {
                final detail = await (detailRequest ??= catalog.subject(
                  subjectId,
                ));
                final episode = _matchingEpisode(session, detail);
                try {
                  match = await danmaku.matchBangumi(
                    subjectId,
                    number(episode['sort']),
                  );
                } catch (_) {
                  // Mapping availability is independent of episode search.
                }
                if (match?.episodeId == null &&
                    (match?.candidates.isEmpty ?? true)) {
                  match = await danmaku.matchTitles(
                    resourceNames(detail),
                    number(episode['sort']),
                  );
                }
              } catch (_) {
                // A missing catalog/mapping must not prevent filename fallback.
              }
            }
            if (match?.episodeId == null &&
                (match?.candidates.isEmpty ?? true)) {
              match = await danmaku.matchFile(
                '${session['path']}',
                duration,
                filenameOnly:
                    session['remoteSource'] == true ||
                    session['streamId'] != null,
                fileSize: session['fileSize'] as int?,
              );
            }
            if (match!.episodeId != null) {
              return danmaku.dandan(match.episodeId!);
            }
            if (match.candidates.isNotEmpty) {
              throw _DandanSuggestions(match.candidates);
            }
            return null;
          }
          if (session['subjectId'] == null) {
            throw const _Unmatched('缺少番剧信息');
          }
          final detail = await (detailRequest ??= catalog.subject(
            session['subjectId'] as int,
          ));
          final episode = _matchingEpisode(session, detail);
          final locator = await danmaku.automaticLocator(
            provider,
            titleOf(detail),
            number(episode['sort']),
            alternativeTitles: resourceNames(detail),
          );
          return locator == null ? null : _fetch(provider, locator);
        }),
      ),
    );
  }

  Future<List<Json>> _fetch(String provider, String locator) =>
      switch (provider) {
        'dandanplay' => danmaku.dandan(int.parse(locator)),
        'bilibili' => danmaku.bilibili(locator),
        'bahamut' => danmaku.bahamut(locator),
        _ => throw ArgumentError.value(provider),
      };
  Future<void> selectEpisode(int episodeId) =>
      loadSource('dandanplay', '$episodeId');
  Future<void> loadSource(String provider, String locator) {
    return _load(provider, () => _fetch(provider, locator), locator: locator);
  }

  bool importComments(String sessionId, List<Json> comments) {
    final session = current;
    if (session == null || session['id'] != sessionId) return false;
    final imported = normalizeComments(
      comments.map((comment) => {...comment, 'sourceId': 'local'}),
    );
    _comments['local'] = imported;
    final sources = objects(session['danmakuSources']);
    if (!sources.any((source) => source['id'] == 'local')) {
      sources.add({'id': 'local', 'label': '本地 JSON'});
    }
    sources.firstWhere((source) => source['id'] == 'local').addAll({
      'enabled': true,
      'status': 'ready',
      'count': imported.length,
    });
    session['danmakuSources'] = sources;
    _merge();
    return true;
  }

  Future<void> _load(
    String provider,
    Future<List<Json>?> Function() fetch, {
    String? locator,
  }) async {
    final session = current;
    if (session == null) return;
    final ticket = Object();
    _loads[provider] = ticket;
    _comments.remove(provider);
    _sourceState(session, provider, {
      'status': 'loading',
      'count': 0,
      'errorMessage': null,
      'statusMessage': null,
      'candidates': <Json>[],
    });
    _merge();
    try {
      final comments = await fetch();
      if (!identical(current, session) || _loads[provider] != ticket) return;
      if (locator != null) {
        await store.put(
          'danmaku_matches',
          '${session['path'] ?? session['resumeKey']}:$provider',
          {'locator': locator},
        );
        if (!identical(current, session) || _loads[provider] != ticket) return;
      }
      _comments[provider] = comments ?? [];
      _sourceState(session, provider, {
        'status': comments == null ? 'unmatched' : 'ready',
        'count': comments?.length ?? 0,
        'statusMessage': comments == null
            ? switch (provider) {
                'bilibili' => '未匹配到官方番剧或章节',
                'bahamut' => '未匹配到动画疯番剧或章节',
                _ => '文件未匹配到唯一章节',
              }
            : null,
      });
    } catch (e) {
      if (!identical(current, session) || _loads[provider] != ticket) return;
      _sourceState(session, provider, {
        'status': e is _Unmatched ? 'unmatched' : 'error',
        'candidates': e is _DandanSuggestions ? e.candidates : <Json>[],
        'statusMessage': e is _Unmatched ? e.message : null,
        'errorMessage': e is _Unmatched ? null : e.toString(),
      });
    }
    _merge();
  }

  void enable(String provider, bool enabled) {
    if (current == null) return;
    final sources = objects(current!['danmakuSources']);
    sources.firstWhere((s) => s['id'] == provider)['enabled'] = enabled;
    current!['danmakuSources'] = sources;
    _merge();
  }

  void _sourceState(Json session, String provider, Json patch) {
    final sources = objects(session['danmakuSources']);
    sources.firstWhere((s) => s['id'] == provider).addAll(patch);
    session['danmakuSources'] = sources;
  }

  void _merge() {
    if (current == null) return;
    final enabled = objects(current!['danmakuSources'])
        .where((source) => source['enabled'] == true)
        .map((source) => '${source['id']}')
        .toList();
    final positions = List<int>.filled(enabled.length, 0);
    final merged = <Json>[];
    while (true) {
      var earliest = -1;
      for (var i = 0; i < enabled.length; i++) {
        final rows = _comments[enabled[i]] ?? const <Json>[];
        if (positions[i] >= rows.length) continue;
        if (earliest == -1 ||
            number(rows[positions[i]]['timeSeconds']) <
                number(
                  _comments[enabled[earliest]]![positions[earliest]]['timeSeconds'],
                )) {
          earliest = i;
        }
      }
      if (earliest == -1) break;
      final provider = enabled[earliest];
      merged.add({
        ..._comments[provider]![positions[earliest]++],
        'sourceId': provider,
      });
    }
    current!['danmaku'] = merged;
    changes.add(Map<String, dynamic>.from(current!));
  }

  Future<void> close() async {
    current = null;
    await changes.close();
  }
}

class _DandanSuggestions extends _Unmatched {
  const _DandanSuggestions(this.candidates) : super('找到候选剧集，请选择确认');
  final List<Json> candidates;
}

class _Unmatched implements Exception {
  const _Unmatched(this.message);
  final String message;
}

Json _matchingEpisode(Json session, Json detail) {
  final episodes = objects(detail['episodes']);
  final episodeId = session['episodeId'];
  Iterable<Json> matches;
  if (episodeId != null) {
    matches = episodes.where((episode) => episode['episodeId'] == episodeId);
  } else {
    // Infer only the danmaku lookup; progress/file associations require explicit identity.
    final filename = p.basenameWithoutExtension('${session['path']}');
    final numbers = [
      ...RegExp(r'\s-\s(\d+(?:\.\d+)?)(?:v\d+)?(?=\s*(?:\[|\(|$))')
          .allMatches(filename),
      ...RegExp(r'\[(\d{1,3}(?:\.\d+)?)(?:v\d+)?\]').allMatches(filename),
    ];
    if (numbers.length != 1) throw const _Unmatched('缺少章节信息，无法从文件名识别集数');
    final sort = double.parse(numbers.single[1]!);
    matches = episodes.where((episode) => number(episode['sort']) == sort);
  }
  if (matches.length != 1) throw const _Unmatched('未找到唯一对应的番剧章节');
  return matches.single;
}
