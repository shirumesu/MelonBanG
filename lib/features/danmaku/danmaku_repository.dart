import 'package:path/path.dart' as p;

import '../../core/json.dart';
import '../acquisition/resource_metadata.dart';
import '../../core/store.dart';
import '../../domain/catalog.dart';
import '../../domain/danmaku.dart';

/// What a playback session offers danmaku matching.
class DanmakuTarget {
  const DanmakuTarget({
    this.matchKey,
    this.offsetKey,
    this.embedded,
    this.subjectId,
    this.episodeId,
    this.path,
    this.fileSize,
    this.remote = false,
  });

  /// Saved manual matches: file path, or the stable online resume key.
  final String? matchKey;

  /// Source offsets: resume key, or the media URL.
  final String? offsetKey;

  /// A locator supplied by the stream itself, as (provider, locator).
  final (String, String)? embedded;
  final int? subjectId, episodeId;
  final String? path;
  final int? fileSize;

  /// Streamed or remote media: match by file name only.
  final bool remote;
}

/// Danmaku providers plus their persisted manual matches and source offsets.
class DanmakuRepository {
  DanmakuRepository(this.store, this.catalog, this.matchers, this.local);
  final AppStore store;
  final Catalog catalog;

  /// Automatic sources in display order.
  final List<DanmakuMatcher> matchers;
  final DanmakuProvider local;
  Future<void>? _offsetTable;

  DanmakuProvider provider(String id) => id == local.id ? local : matcher(id);
  DanmakuMatcher matcher(String id) =>
      matchers.firstWhere((provider) => provider.id == id);

  Future<String?> savedLocator(String key, String provider) async =>
      (await store.get('danmaku_matches', '$key:$provider'))?['locator']
          as String?;

  Future<void> saveLocator(String key, String provider, String locator) =>
      store.put('danmaku_matches', '$key:$provider', {'locator': locator});

  Future<void> _ensureOffsetTable() => _offsetTable ??= store.database.execute(
    'CREATE TABLE IF NOT EXISTS danmaku_offsets (resume_key TEXT NOT NULL, source TEXT NOT NULL, seconds REAL NOT NULL, PRIMARY KEY(resume_key,source))',
  );

  Future<Map<String, double>> offsets(String key) async {
    try {
      await _ensureOffsetTable();
      final rows = await store.database.query(
        'danmaku_offsets',
        where: 'resume_key=?',
        whereArgs: [key],
      );
      return {
        for (final row in rows) '${row['source']}': number(row['seconds']),
      };
    } catch (_) {
      _offsetTable = null;
      rethrow;
    }
  }

  Future<void> saveOffset(String key, String provider, double seconds) async {
    await _ensureOffsetTable();
    await store.database.rawInsert(
      'INSERT OR REPLACE INTO danmaku_offsets (resume_key,source,seconds) VALUES (?,?,?)',
      [key, provider, seconds],
    );
  }

  Future<DanmakuEpisode> episode(DanmakuTarget target) async {
    final subjectId = target.subjectId;
    if (subjectId == null) throw const DanmakuUnmatched('缺少番剧信息');
    final detail = await catalog.subject(subjectId);
    return DanmakuEpisode(
      subjectId: subjectId,
      title: detail.title,
      names: resourceNames(detail),
      number: _matchingEpisode(target, detail).sort,
    );
  }
}

Episode _matchingEpisode(DanmakuTarget target, Subject detail) {
  final episodeId = target.episodeId;
  Iterable<Episode> matches;
  if (episodeId != null) {
    matches = detail.episodes.where((episode) => episode.id == episodeId);
  } else {
    // Infer only the danmaku lookup; progress/file associations require explicit identity.
    final filename = p.basenameWithoutExtension('${target.path}');
    final numbers = [
      ...RegExp(r'\s-\s(\d+(?:\.\d+)?)(?:v\d+)?(?=\s*(?:\[|\(|$))')
          .allMatches(filename),
      ...RegExp(r'\[(\d{1,3}(?:\.\d+)?)(?:v\d+)?\]').allMatches(filename),
    ];
    if (numbers.length != 1) {
      throw const DanmakuUnmatched('缺少章节信息，无法从文件名识别集数');
    }
    final sort = double.parse(numbers.single[1]!);
    matches = detail.episodes.where((episode) => episode.sort == sort);
  }
  if (matches.length != 1) throw const DanmakuUnmatched('未找到唯一对应的番剧章节');
  return matches.single;
}
