import 'dart:isolate';

import 'package:pinyin/pinyin.dart' show ChineseHelper;

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/danmaku.dart';
import 'matching.dart';

/// Bahamut Anime Crazy through its app API: matches only the main episode
/// list; locators are video `sn` values or playback URLs.
class BahamutDanmaku implements DanmakuMatcher {
  BahamutDanmaku(this.api);
  final ApiClient api;

  @override
  String get id => 'bahamut';
  @override
  String get label => '巴哈姆特';

  @override
  String get description => '动画疯的弹幕，只匹配正片，不含配音版和特别篇。';
  @override
  String? get unconfigured => null;
  @override
  bool get manual => true;

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
    for (final query
        in titles.map(ChineseHelper.convertToTraditionalChinese).toSet()) {
      final value = await api.map(
        Uri.https('api.gamer.com.tw', '/anime/v1/search.php', {'kw': query}),
      );
      for (final anime in objects(object(value['data'])['animeList'])) {
        final animeSn = positiveId(anime['animeSn']);
        final videoSn = positiveId(anime['videoSn']);
        if (animeSn != null &&
            videoSn != null &&
            normalizedTitles.contains(normalizedTitle('${anime['title']}'))) {
          candidates[animeSn] = videoSn;
        }
      }
    }
    if (candidates.length != 1) return null;
    final value = await api.map(
      Uri.https('api.gamer.com.tw', '/anime/v1/video.php', {
        'videoSn': candidates.values.single,
      }),
    );
    final lists = object(object(object(value['data'])['anime'])['episodes']);
    // List "0" is the main series; dubbed versions and specials reuse numbers.
    final episodes = {
      for (final item in objects(lists['0']))
        if (number(item['episode']) == episode.number)
          ?positiveId(item['videoSn']),
    };
    return episodes.length == 1 ? 'sn=${episodes.single}' : null;
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
