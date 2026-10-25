import 'dart:isolate';

import 'package:pinyin/pinyin.dart' show ChineseHelper;

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/danmaku.dart';
import 'matching.dart';

/// Bahamut Anime Crazy through its app API: automatic matching takes only
/// the main episode list, manual search every list; locators are video `sn`
/// values or playback URLs.
class BahamutDanmaku implements DanmakuSearch {
  BahamutDanmaku(this.api);
  final ApiClient api;

  @override
  String get id => 'bahamut';
  @override
  String get label => '巴哈姆特';

  @override
  String get description =>
      '动画疯的弹幕，自动匹配只看正片，不含配音版和特别篇；'
      '也可以在播放器的弹幕页搜索，或粘贴播放链接。';
  @override
  String? get unconfigured => null;

  @override
  Future<DanmakuMatch> match(DanmakuQuery query) async {
    final episode = await query.episode();
    final locator = await _locator(episode);
    return locator == null
        ? const DanmakuMatch.none('未匹配到动画疯番剧或章节')
        : DanmakuMatch.found(locator);
  }

  Future<String?> _locator(DanmakuEpisode episode) async {
    final titles = searchTitles(episode);
    if (titles.isEmpty) return null;
    final normalizedTitles = titles.map(normalizedTitle).toSet();
    // animeSn -> one of its videoSn, which addresses the anime's episode list.
    final candidates = <String, String>{};
    final results = await Future.wait(
      titles
          .map(ChineseHelper.convertToTraditionalChinese)
          .toSet()
          .map(_search),
    );
    for (final anime in results.expand((animes) => animes)) {
      final animeSn = positiveId(anime['animeSn']);
      final videoSn = positiveId(anime['videoSn']);
      if (animeSn != null &&
          videoSn != null &&
          normalizedTitles.contains(normalizedTitle('${anime['title']}'))) {
        candidates[animeSn] = videoSn;
      }
    }
    if (candidates.length != 1) return null;
    final lists = await _episodeLists(candidates.values.single);
    // List "0" is the main series; dubbed versions and specials reuse numbers.
    final episodes = {
      for (final item in objects(lists['0']))
        if (number(item['episode']) == episode.number)
          ?positiveId(item['videoSn']),
    };
    return episodes.length == 1 ? 'sn=${episodes.single}' : null;
  }

  @override
  Future<List<DanmakuCandidate>> search(String title) async {
    if (RegExp(r'sn=(\d+)').firstMatch(title)?[1] case final sn?) {
      return _anime(sn);
    }
    return [
      for (final anime in await _search(
        ChineseHelper.convertToTraditionalChinese(title),
      ))
        DanmakuCandidate(
          title: '${anime['title']}',
          subtitle:
              '${'${anime['dateInfo']}'.replaceFirst('年份：', '')}'
              ' · 共 ${anime['totalEpisode']} 集',
          open: () => _anime('${anime['videoSn']}'),
        ),
    ];
  }

  /// The anime a search for [query] finds.
  Future<List<Json>> _search(String query) async {
    final value = await api.map(
      Uri.https('api.gamer.com.tw', '/anime/v1/search.php', {'kw': query}),
    );
    return objects(object(value['data'])['animeList']);
  }

  /// The episode lists, by list number, of the anime holding [videoSn].
  Future<Json> _episodeLists(String videoSn) async {
    final value = await api.map(
      Uri.https('api.gamer.com.tw', '/anime/v1/video.php', {
        'videoSn': videoSn,
      }),
    );
    return object(object(object(value['data'])['anime'])['episodes']);
  }

  /// The episode lists of the anime holding [videoSn], or its episodes when
  /// it has one list.
  Future<List<DanmakuCandidate>> _anime(String videoSn) async {
    final lists = await _episodeLists(videoSn);
    List<DanmakuCandidate> episodes(Object? list) => [
      for (final item in objects(list))
        DanmakuCandidate(
          title: '第 ${item['episode']} 集',
          locator: 'sn=${item['videoSn']}',
        ),
    ];
    if (lists.length == 1) return episodes(lists.values.single);
    return [
      for (final MapEntry(:key, :value) in lists.entries)
        DanmakuCandidate(
          title: _lists[key] ?? '其他版本',
          subtitle: '${objects(value).length} 集',
          open: () async => episodes(value),
        ),
    ];
  }

  @override
  Future<List<DanmakuComment>> load(String locator) async {
    final sn =
        Uri.tryParse(locator)?.queryParameters['sn'] ??
        RegExp(r'^(?:sn=)?(\d+)$').firstMatch(locator)?[1];
    if (sn == null) throw const FormatException('请输入动画疯 sn 或播放链接');
    // The ani.gamer.com.tw pages sit behind a Cloudflare challenge; the app
    // API does not.
    final value = await api.map(
      Uri.https('api.gamer.com.tw', '/anime/v1/danmu.php', {
        'videoSn': sn,
        'geo': 'TW,HK',
      }),
    );
    final rows = objects(object(value['data'])['danmu']);
    return Isolate.run(
      () => sortedComments(
        rows.map(
          (c) => DanmakuComment.parse(
            source: 'bahamut',
            time: number(c['time']) / 10,
            text: c['text'],
            color: hexColor(c['color']),
            mode: switch (c['position']) {
              1 => DanmakuMode.top,
              2 => DanmakuMode.bottom,
              _ => DanmakuMode.scroll,
            },
          ),
        ),
      ),
    );
  }
}

/// Episode list names by key, inferred from the lists anime carry: series
/// 0, 2 and 3, movies 1 and 4, standalone specials 2 and 5.
const _lists = {
  '0': '本篇',
  '1': '电影',
  '2': '特别篇',
  '3': '中文配音',
  '4': '中文配音电影',
  '5': '中文配音特别篇',
};
