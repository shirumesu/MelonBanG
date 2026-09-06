import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'danmaku_repository.dart';
import 'catalog.dart';
import 'downloads.dart';
import 'json.dart';
import 'store.dart';

class PlaybackLibrary {
  PlaybackLibrary(this.store, this.downloads, this.danmaku, this.catalog);
  final AppStore store;
  final DownloadRepository downloads;
  final DanmakuRepository danmaku;
  final CatalogRepository catalog;
  final changes = StreamController<Json>.broadcast();
  Json? current;
  final _comments = <String, List<Json>>{};
  final _loads = <String, Object>{};
  Future<Json> local(String path, {int? subjectId, int? episodeId}) async {
    if (!await File(path).exists()) throw StateError('视频文件不存在');
    current = {
      'id': newId(),
      'title': p.basename(path),
      'path': path,
      'source': {'url': Uri.file(path).toString()},
      'status': 'ready',
      'subjectId': subjectId,
      'episodeId': episodeId,
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
            'enabled': true,
            'status': 'idle',
            'count': 0,
          },
      ],
    };
    _comments.clear();
    _loads.clear();
    if (subjectId != null && episodeId != null) {
      await store.put('episode_files', '$subjectId:$episodeId', {'path': path});
    }
    return current!;
  }

  Future<Json> fromDownload(String id, {String? fileId}) async {
    final media = downloads.media(id, fileId: fileId);
    return local(
      '${media['path']}',
      subjectId: media['subjectId'] as int?,
      episodeId: media['episodeId'] as int?,
    );
  }

  Future<Json> episode(int subjectId, int episodeId) async {
    final localFile = await store.get('episode_files', '$subjectId:$episodeId');
    if (localFile != null && await File('${localFile['path']}').exists()) {
      return local(
        '${localFile['path']}',
        subjectId: subjectId,
        episodeId: episodeId,
      );
    }
    final media = downloads.episodeMedia(subjectId, episodeId);
    return local(
      '${media['path']}',
      subjectId: subjectId,
      episodeId: episodeId,
    );
  }

  Future<Json?> progress(int subjectId, int episodeId) =>
      store.get('playback_progress', '$subjectId:$episodeId');
  Future<void> save(
    Json session,
    double position,
    double duration,
    bool ended,
  ) async {
    if (!position.isFinite || position < 0 || !duration.isFinite) return;
    if (session['subjectId'] == null || session['episodeId'] == null) return;
    await store.put(
      'playback_progress',
      '${session['subjectId']}:${session['episodeId']}',
      {
        'positionSeconds': ended ? 0 : position,
        'durationSeconds': duration,
        'completed': ended,
      },
    );
  }

  Future<void> autoMatch(double duration) async {
    final session = current;
    if (session == null) return;
    final enabled = objects(session['danmakuSources'])
        .where((s) => s['enabled'] == true)
        .map((s) => '${s['id']}');
    await Future.wait(
      enabled.map(
        (provider) => _load(provider, () async {
          final saved = await store.get(
            'danmaku_matches',
            '${session['path']}:$provider',
          );
          if (saved != null) {
            return _fetch(provider, '${saved['locator']}');
          }
          if (provider == 'dandanplay') {
            return danmaku.dandan(
              await danmaku.matchFile('${session['path']}', duration),
            );
          }
          if (session['subjectId'] == null || session['episodeId'] == null) {
            throw StateError('请关联番剧章节，或手动选择弹幕来源');
          }
          final detail = await catalog.subject(session['subjectId'] as int);
          final episode = objects(detail['episodes'])
              .firstWhere((e) => e['episodeId'] == session['episodeId']);
          final locator = await danmaku.automaticLocator(
            provider,
            titleOf(detail),
            number(episode['sort']),
          );
          return _fetch(provider, locator);
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

  Future<void> _load(
    String provider,
    Future<List<Json>> Function() fetch, {
    String? locator,
  }) async {
    final session = current;
    if (session == null) return;
    final ticket = Object();
    _loads[provider] = ticket;
    _sourceState(session, provider, {
      'status': 'loading',
      'errorMessage': null,
    });
    changes.add(session);
    try {
      final comments = await fetch();
      if (!identical(current, session) || _loads[provider] != ticket) return;
      if (locator != null) {
        await store.put('danmaku_matches', '${session['path']}:$provider', {
          'locator': locator,
        });
        if (!identical(current, session) || _loads[provider] != ticket) return;
      }
      _comments[provider] = comments;
      _sourceState(session, provider, {
        'status': 'ready',
        'count': comments.length,
      });
    } catch (e) {
      if (!identical(current, session) || _loads[provider] != ticket) return;
      _sourceState(session, provider, {
        'status': 'error',
        'errorMessage': e.toString(),
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
    current!['danmaku'] = normalizeComments(
      objects(current!['danmakuSources'])
          .where((s) => s['enabled'] == true)
          .expand((s) => _comments[s['id']] ?? <Json>[]),
    );
    changes.add(Map<String, dynamic>.from(current!));
  }

  Future<void> close() async {
    current = null;
    await changes.close();
  }
}
