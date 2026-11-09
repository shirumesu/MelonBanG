import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:pinyin/pinyin.dart' show ChineseHelper;

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/danmaku.dart';
import 'matching.dart';

/// Tencent Video: automatic matching takes a series of the same title and
/// season, dubs aside; locators are video ids (`vid=…`). Comments of a whole
/// episode, members-only ones included, are public.
class TencentDanmaku implements DanmakuSearch {
  TencentDanmaku(this.api);
  final ApiClient api;

  @override
  String get id => 'tencent';
  @override
  String get label => '腾讯视频';

  @override
  String get description =>
      '腾讯视频正版番剧的弹幕，自动匹配同名同季的正片，不含配音版；'
      '也可以在播放器的弹幕页搜索。';
  @override
  String? get unconfigured => null;

  static const _headers = {
    'Origin': 'https://v.qq.com',
    'Referer': 'https://v.qq.com/',
  };

  @override
  Future<DanmakuMatch> match(DanmakuQuery query) async {
    final episode = await query.episode();
    final titles = searchTitles(episode);
    final wanted = titles.map(seasonedTitle).toSet();
    final series = <String>{};
    for (final found in await Future.wait(
      titles.map(ChineseHelper.convertToSimplifiedChinese).toSet().map(_search),
    )) {
      for (final (:cid, :title, year: _) in found) {
        if (!dubbedTitle.hasMatch(title) &&
            wanted.contains(seasonedTitle(title))) {
          series.add(cid);
        }
      }
    }
    if (series.length != 1) {
      return const DanmakuMatch.none('未匹配到腾讯视频番剧');
    }
    final rows = await _episodes(series.single, around: episode.number);
    final vids = {
      for (final row in rows)
        if (episodeNumber(row.title) == episode.number) row.vid,
    };
    return vids.length == 1
        ? DanmakuMatch.found('vid=${vids.single}')
        : const DanmakuMatch.none('未匹配到腾讯视频章节');
  }

  @override
  Future<List<DanmakuCandidate>> search(String title) async => [
    for (final (:cid, :title, :year) in await _search(
      ChineseHelper.convertToSimplifiedChinese(title),
    ))
      DanmakuCandidate(title: title, subtitle: year, open: () => _listed(cid)),
  ];

  /// The series a search for [query] finds: 15-character cids playing on
  /// Tencent itself, not short clips nor `sdp` links to other sites.
  /// Films (video type 1) are included for manual search.
  Future<List<({String cid, String title, String? year})>> _search(
    String query,
  ) async {
    final value = await api.map(
      Uri.https(
        'pbaccess.video.qq.com',
        '/trpc.videosearch.mobile_search.MultiTerminalSearch/MbSearch',
        {'vplatform': '2'},
      ),
      method: 'POST',
      headers: _headers,
      body: {
        'version': '25042201',
        'clientType': 1,
        'filterValue': '',
        'retry': 0,
        'query': query,
        'pagenum': 0,
        'pagesize': 20,
        'queryFrom': 0,
        'isneedQc': true,
        'extraInfo': {'multi_terminal_pc': '1'},
      },
    );
    final data = object(value['data']);
    // The main results and the box of series the query names; other boxes
    // recommend unrelated shows, or the same series under another cid.
    final items = [
      ...objects(object(data['normalList'])['itemList']),
      for (final box in objects(data['areaBoxList']))
        if (box['boxId'] == 'MainNeed') ...objects(box['itemList']),
    ];
    final seen = <String>{};
    return [
      for (final item in items)
        if ('${object(item['doc'])['id'] ?? ''}' case final cid
            when cid.length == 15 && !cid.startsWith('sdp') && seen.add(cid))
          if (object(item['videoInfo']) case final info
              when const {1, 3}.contains(info['videoType']))
            (
              cid: cid,
              title: _plain('${info['title'] ?? ''}'),
              year: switch (info['year']) {
                final int year when year > 0 => '$year',
                _ => null,
              },
            ),
    ];
  }

  /// The episodes of series [cid], from the tab holding episode [around]
  /// when the list is split into tabs.
  Future<List<({String vid, String title})>> _episodes(
    String cid, {
    double? around,
  }) async {
    var page = await _page(cid, '');
    if (around != null) {
      for (final tab in page.tabs) {
        if (around >= tab.begin && around <= tab.end) {
          if (tab.context.isNotEmpty) page = await _page(cid, tab.context);
          break;
        }
      }
    }
    return page.rows;
  }

  /// Series [cid]'s episodes, or its tabs when the list is split.
  Future<List<DanmakuCandidate>> _listed(String cid) async {
    final page = await _page(cid, '');
    List<DanmakuCandidate> episodes(List<({String vid, String title})> rows) =>
        [
          for (final row in rows)
            DanmakuCandidate(
              title: switch (episodeNumber(row.title)) {
                final number? => '第 ${number.toStringAsFixed(0)} 集',
                null => row.title,
              },
              locator: 'vid=${row.vid}',
            ),
        ];
    if (page.tabs.length < 2) return episodes(page.rows);
    return [
      for (final tab in page.tabs)
        DanmakuCandidate(
          title: '第 ${tab.begin}–${tab.end} 集',
          open: () async => episodes((await _page(cid, tab.context)).rows),
        ),
    ];
  }

  Future<
    ({
      List<({String vid, String title})> rows,
      List<({int begin, int end, String context})> tabs,
    })
  >
  _page(String cid, String context) async {
    final value = await api.map(
      Uri.https(
        'pbaccess.video.qq.com',
        '/trpc.universal_backend_service.page_server_rpc.PageServer/GetPageData',
        {'video_appid': '3000010', 'vplatform': '2'},
      ),
      method: 'POST',
      headers: _headers,
      body: {
        'page_params': {
          'req_from': 'web_vsite',
          'page_id': 'vsite_episode_list',
          'page_type': 'detail_operation',
          'id_type': '1',
          'page_size': '',
          'cid': cid,
          'vid': '',
          'lid': '',
          'page_num': '',
          'page_context': context,
          'detail_page_type': '1',
        },
        'has_cache': 1,
      },
    );
    final module = object(
      objects(
        object(
          objects(object(value['data'])['module_list_datas']).firstOrNull,
        )['module_datas'],
      ).firstOrNull,
    );
    final tabs = '${object(module['module_params'])['tabs'] ?? ''}';
    return (
      rows: [
        for (final item in objects(
          object(module['item_data_lists'])['item_datas'],
        ))
          if (object(item['item_params']) case final params
              when params['is_trailer'] != '1' &&
                  '${params['vid'] ?? ''}'.isNotEmpty)
            (vid: '${params['vid']}', title: '${params['title'] ?? ''}'),
      ],
      tabs: [
        if (tabs.isNotEmpty)
          for (final tab in objects(jsonDecode(tabs)))
            (
              begin: number(tab['begin']).toInt(),
              end: number(tab['end']).toInt(),
              context: '${tab['page_context'] ?? ''}',
            ),
      ],
    );
  }

  @override
  Future<List<DanmakuComment>> load(String locator) async {
    final vid = RegExp(r'^(?:vid=)?([0-9a-z]{11})$').firstMatch(locator)?[1];
    if (vid == null) throw const FormatException('请输入腾讯视频的 vid');
    final base = await api.map(
      Uri.https('dm.video.qq.com', '/barrage/base/$vid'),
    );
    // Thirty-second segments over the whole episode, a film's hundreds of
    // them a few at a time.
    final names = [
      for (final segment in object(base['segment_index']).values)
        '${object(segment)['segment_name']}',
    ];
    final segments = await fetchParts(
      names.length,
      (index) => api.map(
        Uri.https('dm.video.qq.com', '/barrage/segment/$vid/${names[index]}'),
      ),
      width: 8,
    );
    final rows = [
      for (final segment in segments) ...objects(segment['barrage_list']),
    ];
    return compute(_comments, rows);
  }
}

/// [text] with highlight tags removed and spaces collapsed.
String _plain(String text) => text
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The comments of [rows], each with its time in milliseconds and a style
/// that may set its colour.
List<DanmakuComment> _comments(List<Json> rows) => sortedComments(
  rows.map((row) {
    final style = switch (row['content_style']) {
      final String text when text.startsWith('{') => _style(text),
      _ => const <String, dynamic>{},
    };
    return DanmakuComment.parse(
      source: 'tencent',
      time: (int.tryParse('${row['time_offset']}') ?? -1000) / 1000,
      text: row['content'],
      color: hexColor('#${style['color'] ?? ''}'),
      mode: DanmakuMode.scroll,
    );
  }),
);

/// A comment's style; a malformed one only loses its colour.
Json _style(String text) {
  try {
    return object(jsonDecode(text));
  } on FormatException {
    return const {};
  }
}
