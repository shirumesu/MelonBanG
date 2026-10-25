import 'package:path/path.dart' as p;

import '../acquisition/resource_metadata.dart';
import '../../core/store.dart';
import '../../domain/catalog.dart';
import '../../domain/danmaku.dart';

/// What a playback session offers danmaku matching.
class DanmakuTarget {
  const DanmakuTarget({
    this.matchKey,
    this.embedded,
    this.subjectId,
    this.episodeId,
    this.path,
    this.fileSize,
    this.remote = false,
  });

  /// Saved manual matches: file path, or the stable online resume key.
  final String? matchKey;

  /// A locator supplied by the stream itself, as (provider, locator).
  final (String, String)? embedded;
  final int? subjectId, episodeId;
  final String? path;
  final int? fileSize;

  /// Streamed or remote media: match by file name only.
  final bool remote;
}

/// Danmaku providers plus their persisted manual matches.
class DanmakuRepository {
  DanmakuRepository(this.store, this.catalog, this.matchers, this.local);
  final AppStore store;
  final Catalog catalog;

  /// Automatic sources in display order.
  final List<DanmakuMatcher> matchers;
  final DanmakuProvider local;

  DanmakuProvider provider(String id) => id == local.id ? local : matcher(id);
  DanmakuMatcher matcher(String id) =>
      matchers.firstWhere((provider) => provider.id == id);

  Future<String?> savedLocator(String key, String provider) async =>
      (await store.get('danmaku_matches', '$key:$provider'))?['locator']
          as String?;

  Future<void> saveLocator(String key, String provider, String locator) =>
      store.put('danmaku_matches', '$key:$provider', {'locator': locator});

  /// The episode last picked by hand for the subject, as (locator, episode
  /// number), which its other episodes follow.
  Future<(String, double)?> followed(int subjectId, String provider) async =>
      switch (await store.get('danmaku_follow', '$subjectId:$provider')) {
        {'locator': final String locator, 'number': final num number} => (
          locator,
          number.toDouble(),
        ),
        _ => null,
      };

  Future<void> saveFollowed(
    int subjectId,
    String provider,
    String locator,
    double number,
  ) => store.put('danmaku_follow', '$subjectId:$provider', {
    'locator': locator,
    'number': number,
  });

  Future<DanmakuEpisode> episode(DanmakuTarget target) async {
    final subjectId = target.subjectId;
    if (subjectId == null) throw const DanmakuUnmatched('缺少番剧信息');
    final detail = await catalog.subject(subjectId);
    final episode = _matchingEpisode(target, detail);
    // Matchers find episodes by number, which SP1 shares with episode 1.
    if (episode.numberedApart) throw const DanmakuUnmatched('特别篇暂不匹配弹幕');
    return DanmakuEpisode(
      subjectId: subjectId,
      title: detail.title,
      names: resourceNames(detail),
      number: episode.sort,
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
