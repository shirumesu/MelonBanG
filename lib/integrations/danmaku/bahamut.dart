import 'dart:convert';
import 'dart:isolate';

import 'package:html/parser.dart' as html;
import 'package:pinyin/pinyin.dart' show ChineseHelper;

import '../../data/json.dart';
import '../../data/network.dart';
import '../../domain/danmaku.dart';
import 'matching.dart';

/// Bahamut Anime Crazy: matches only the main episode list; locators are
/// `sn` values or playback URLs.
class BahamutDanmaku implements DanmakuMatcher {
  BahamutDanmaku(this.api);
  final ApiClient api;

  @override
  String get id => 'bahamut';
  @override
  String get label => '巴哈姆特';

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
    final candidates = <String>{};
    for (final query
        in titles.map(ChineseHelper.convertToTraditionalChinese).toSet()) {
      final response = await api.send(
        Uri.https('ani.gamer.com.tw', '/search.php', {'keyword': query}),
      );
      final document = html.parse(utf8.decode(response.bodyBytes));
      for (final link in document.querySelectorAll('a[href]')) {
        final uri = Uri.tryParse(link.attributes['href']!);
        if (uri == null || !uri.path.endsWith('animeRef.php')) continue;
        final names = [
          if (link.querySelector('.theme-name') case final name?) name.text,
          ...link
              .querySelectorAll('img[alt]')
              .map((img) => img.attributes['alt']!),
          if (link.children.isEmpty) link.text,
        ];
        if (names.any(
          (name) => normalizedTitles.contains(normalizedTitle(name)),
        )) {
          final sn = positiveId(uri.queryParameters['sn']);
          if (sn != null) candidates.add(sn);
        }
      }
    }
    if (candidates.length != 1) return null;
    final page = await api.send(
      Uri.https('ani.gamer.com.tw', '/animeRef.php', {'sn': candidates.single}),
    );
    final document = html.parse(utf8.decode(page.bodyBytes));
    final episodes = <String>{};
    // Main episodes have their own list; dubbed versions and specials reuse numbers.
    for (final list in document.querySelectorAll('.season > ul')) {
      final heading = list.previousElementSibling;
      final isMain = heading?.localName == 'p' && heading!.text.trim() == '本篇';
      final isOnlyUnlabelled =
          heading == null &&
          list.parent!.children.length == 1 &&
          document.querySelectorAll('.season').length == 1;
      if (!isMain && !isOnlyUnlabelled) continue;
      for (final link in list.querySelectorAll('a[href]')) {
        final uri = Uri.tryParse(link.attributes['href']!);
        final sn = positiveId(
          link.attributes['data-ani-video-sn'] ?? uri?.queryParameters['sn'],
        );
        if (episodeNumber(link.text) == episode.number && sn != null) {
          episodes.add(sn);
        }
      }
    }
    return episodes.length == 1 ? 'sn=${episodes.single}' : null;
  }

  @override
  Future<List<DanmakuComment>> load(String locator) async {
    final sn =
        Uri.tryParse(locator)?.queryParameters['sn'] ??
        RegExp(r'^(?:sn=)?(\d+)$').firstMatch(locator)?[1];
    if (sn == null) throw const FormatException('请输入动画疯 sn 或播放链接');
    final value = await api.json(
      Uri.https('ani.gamer.com.tw', '/ajax/danmuGet.php'),
      method: 'POST',
      body: <String, String>{'sn': sn},
      headers: {
        'Origin': 'https://ani.gamer.com.tw',
        'Referer': 'https://ani.gamer.com.tw/animeVideo.php?sn=$sn',
      },
    );
    final rows = objects(value);
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
