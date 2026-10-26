import 'package:pinyin/pinyin.dart';

import 'sources.dart';

/// Read-only release annotations. These never establish episode/file identity.
class ResourceTitleInfo {
  const ResourceTitleInfo({
    required this.title,
    required this.displayTitle,
    required this.labels,
    required this.warnings,
    required this.sourceGroups,
    required this.titleCredits,
    this.qualities = const {},
    this.languages = const {},
    this.subtitleForms = const {},
    this.quality,
    this.episodeLabel,
    this.episodeConflict = false,
    this.episode,
    this.absoluteEpisode,
    this.season,
    this.credit,
    this.series,
    this.subtitles = '',
  });

  final String title, displayTitle;
  final String? quality, episodeLabel;
  final List<String> labels, sourceGroups, titleCredits;

  /// Whether the release covers a range of episodes.
  bool get batch => episodeLabel?.contains('–') ?? false;

  /// Doubts about the title's annotations, such as several qualities.
  final List<String> warnings;
  final bool episodeConflict;

  /// Every output quality the title mentions; [quality] is set only when unique.
  final Set<String> qualities;

  /// Subtitle languages ([resourceLanguages]) and forms ([resourceSubtitleForms]).
  final Set<String> languages, subtitleForms;

  /// The number of a single-episode release as written, and the number in
  /// parentheses some groups add across seasons: `03(51)`.
  final double? episode, absoluteEpisode;

  /// The season the title names: 第二季, S2, 2nd Season.
  final int? season;

  /// The leading bracket crediting the release: `[北宇治字幕组]`.
  final String? credit;

  /// The groups of the release: the site's, else those the title credits,
  /// as sites without group pages, or whose pages have not arrived, leave
  /// only the title to go by.
  List<String> get groups => sourceGroups.isNotEmpty
      ? sourceGroups
      : titleCredits.isNotEmpty
      ? titleCredits
      : [?credit];

  /// What releases of one series by one group share across episodes: the
  /// credited group, season, quality, encoding and platform. Null for
  /// batches and titles without a credited group or episode.
  final String? series;

  /// The subtitle languages, forms and wording the title states, empty when
  /// it states none; a series' releases share it where stated.
  final String subtitles;
}

/// Filter vocabularies, in display order.
const resourceQualities = ['4K', '1080p', '720p'];
const resourceLanguages = ['简体', '繁体', '日文'];
const resourceSubtitleForms = ['内封', '内嵌', '外挂'];

final _languagePatterns = {
  '简体': [
    RegExp(r'简(?:繁|日|体|中|英)|[繁中]简|(?:^|[\[【(（\s_/&])简(?=$|[\]】)）\s_/&])'),
    _token(r'CHS|SC|JPSC|ZHS|ZH-?HANS'),
    // "GB" is also a size unit ("1.2 GB").
    RegExp(r'(?<![a-z0-9.]|\d\s{1,2})GB(?![a-z0-9])', caseSensitive: false),
  ],
  '繁体': [
    RegExp(r'繁(?:简|日|体|中|英)|[简中]繁|(?:^|[\[【(（\s_/&])繁(?=$|[\]】)）\s_/&])'),
    _token(r'CHT|BIG5|TC|JPTC|ZHT|ZH-?HANT'),
  ],
  '日文': [RegExp(r'[简繁中]日|日[语文]|日(?:简|繁)'), _token(r'JP|JPN|JPSC|JPTC|JA')],
};

RegExp _token(String pattern) =>
    RegExp('(?<![a-z0-9])(?:$pattern)(?![a-z0-9])', caseSensitive: false);

final _numerals = {
  for (final (i, c) in '一二三四五六七八九十'.split('').indexed) c: i + 1,
};
final _seasons = [
  RegExp(r'第([一二三四五六七八九十]|\d{1,2})[季期]'),
  _token(r'S(\d{1,2})(?:E\d{1,3})?'),
  RegExp(
    r'(\d{1,2})(?:st|nd|rd|th)\s+Season|Season\s*(\d{1,2})',
    caseSensitive: false,
  ),
];

/// [text] in simplified Chinese. Release titles repeat the same blocks
/// (`[1080p]`, `[简繁内封]`) and the conversion is slow on long text, so
/// results are kept.
String simplifiedChinese(String text) {
  if (_simplified[text] case final value?) return value;
  if (_simplified.length >= 8192) _simplified.clear();
  return _simplified[text] = ChineseHelper.convertToSimplifiedChinese(text);
}

final _simplified = <String, String>{};

/// The season [text] names, such as 第二季, 第3期, S2 or 2nd Season.
int? resourceSeason(String text) {
  final normalized = simplifiedChinese(text);
  for (final pattern in _seasons) {
    if (pattern.firstMatch(normalized) case final match?) {
      final value = match
          .groups([1, if (match.groupCount > 1) 2])
          .nonNulls
          .first;
      return int.tryParse(value) ?? _numerals[value];
    }
  }
  return null;
}

// Streaming platforms releases are ripped from; two rips of one episode by
// one group differ by them.
final _platform = _token(
  r'ABEMA|Baha|B-Global|Bilibili|CR|Crunchyroll|NF|Netflix|AMZN|CATCHPLAY|Disney\+?|U-NEXT|iQIYI|Viu|KKTV|MUSE|Hulu|YouTube',
);

final _brackets = RegExp(r'\[([^\]]+)\]|【([^】]+)】|〖([^〗]+)〗');
final _sourceQuality = RegExp(
  r'4k\s*(?:重扫(?:版)?|扫描(?:版)?|片源|母带|修复(?:版)?|重制(?:版)?)',
  caseSensitive: false,
);
final _format = _token(r'BDRemux|BDRip|BD|WebRip|WEB[- ]DL');
final _technical = RegExp(
  r'^(?:(?:BDRemux|BDRip|BD|WEBRip|WEB(?:[- ]DL)?|HDTV|REMUX|HEVC|AVC|AV1|H[ ._-]?26[45]|x26[45]|AAC|FLAC|OPUS|TRUEHD|DTS|MP4|MKV|PGS|SRT|ASS|1080p|720p|2160p|(?:3840|1920|1280)\s*[x×*]\s*\d+|4K|10[- ]?BIT|8[- ]?BIT|GB|BIG5|CHS|CHT|JPN|FIN|END|V\d|RESEED|MOVIE|SP|OVA|ONA)(?=$|[\s_/+(.-])|(?:REMAKE重制版|国漫|合集)$|(?:简繁|简体|繁体|简中|繁中|简日|繁日|粤日|内封|外挂))',
  caseSensitive: false,
);

/// Parsed titles by title and release groups. A search ranks and filters its
/// results again on every update, so each title is parsed once.
final _described = <String, ResourceTitleInfo>{};

ResourceTitleInfo describeResource(
  String original, {
  Iterable<String> releaseGroups = const [],
}) {
  final key = _describedKey(original, releaseGroups);
  if (_described[key] case final info?) return info;
  if (_described.length >= 4096) _described.clear();
  return _described[key] = _describe(original, releaseGroups);
}

String _describedKey(String original, Iterable<String> releaseGroups) =>
    [original, ...releaseGroups].join('\u0000');

/// Parsed titles of [releases], worked out where they were parsed, off the
/// UI isolate, for that isolate to [keepDescribed].
Map<String, ResourceTitleInfo> describeReleases(
  Iterable<TorrentRelease> releases,
) => {
  for (final release in releases)
    _describedKey(release.title, release.releaseGroups): describeResource(
      release.title,
      releaseGroups: release.releaseGroups,
    ),
};

void keepDescribed(Map<String, ResourceTitleInfo> described) =>
    _described.addAll(described);

ResourceTitleInfo _describe(String original, Iterable<String> releaseGroups) {
  final title = original.trim();
  final normalized = simplifiedChinese(title);
  final sourceGroups = releaseGroups
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
  final labels = <String>[], warnings = <String>[];
  final outputText = normalized.replaceAll(_sourceQuality, '');
  final qualities = <String>{
    if (_token(r'720p|1280\s*[x×*]\s*720').hasMatch(outputText)) '720p',
    if (_token(r'1080p|1920\s*[x×*]\s*1080').hasMatch(outputText)) '1080p',
    if (_token(r'2160p|(?:3840|4096)\s*[x×*]\s*2160|4k').hasMatch(outputText))
      '4K',
  };
  final quality = qualities.length == 1 ? qualities.single : null;
  final languages = {
    for (final entry in _languagePatterns.entries)
      if (entry.value.any((pattern) => pattern.hasMatch(normalized))) entry.key,
  };
  final subtitleForms = {
    for (final form in resourceSubtitleForms)
      if (normalized.contains(form)) form,
  };
  labels.addAll(qualities);
  if (_sourceQuality.hasMatch(normalized)) {
    labels.add('${_sourceQuality.firstMatch(normalized)!.group(0)}（片源）');
  }
  if (qualities.length > 1) warnings.add('画质不确定');
  final format = _format.firstMatch(normalized)?.group(0)?.toUpperCase();
  if (format != null) {
    labels.add(switch (format) {
      'BDRIP' => 'BDRip',
      'BDREMUX' => 'BDRemux',
      'WEBRIP' => 'WebRip',
      'WEB DL' => 'WEB-DL',
      _ => format,
    });
  }
  for (final codec in [
    ('HEVC', r'HEVC|x265|H[ ._-]?265'),
    ('AVC', r'AVC|x264|H[ ._-]?264'),
    ('AV1', r'AV1'),
    ('10bit', r'10[- ]?bit|yuv420p10'),
    ('8bit', r'8[- ]?bit|yuv420p8'),
  ]) {
    if (_token(codec.$2).hasMatch(normalized)) labels.add(codec.$1);
  }
  final subtitle = RegExp(
    r'(?:内封)?(?:简繁日|简繁|简日|繁日|简体中文|繁体中文|简体|繁体|简中|繁中|粤日)(?:中文)?(?:双语|多语)?(?:内封|内嵌|外挂)?(?:字幕)?',
  );
  final subtitleLabels = [
    ...subtitle.allMatches(normalized).map((m) => m.group(0)!),
    if (!subtitle.hasMatch(normalized))
      for (final language in ['CHS', 'CHT', 'GB', 'BIG5', 'VOSTFR'])
        if (_token(language).hasMatch(normalized)) language,
  ];
  labels.addAll(subtitleLabels);
  final blocks = _brackets.allMatches(title).toList();
  final first = blocks.firstOrNull;
  final prefix = first != null && title.substring(0, first.start).trim().isEmpty
      ? (first.group(1) ?? first.group(2) ?? first.group(3))!
      : null;
  final titleCredits =
      prefix != null &&
          !_technical.hasMatch(simplifiedChinese(prefix)) &&
          RegExp(r'[&＆]').hasMatch(prefix)
      ? prefix.split(RegExp(r'\s*[&＆]\s*')).where((e) => e.isNotEmpty).toList()
      : <String>[];

  String? episodeLabel;
  double? episode, absoluteEpisode;
  var episodeConflict = false;
  final range = RegExp(
    r'(?:[\[【〖|]\s*第?)(\d{1,3})\s*[-–~～]\s*(\d{1,3})(?:话|集)?(?:\s*\+\s*SP[x×]?(\d+))?',
    caseSensitive: false,
  ).firstMatch(normalized);
  final special = _token(r'SP(?:v\d+)?').firstMatch(normalized);
  if (range != null) {
    final start = int.parse(range.group(1)!);
    final end = int.parse(range.group(2)!);
    episodeConflict = start > end;
    episodeLabel =
        '${range.group(1)}–${range.group(2)}'
        '${range.group(3) == null ? '' : ' + SP×${range.group(3)}'}';
    if (episodeConflict) warnings.add('集数范围有误');
  } else if (special != null) {
    episodeLabel = '特别篇 ${special.group(0)}';
  } else {
    final seasonEpisode = RegExp(
      r'\bS(\d{1,2})E(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    // [12] [第12话] [03(51)] [12 END], " - 12", " - 03(51) " and EP12.
    final single =
        RegExp(
              r'[\[【〖]\s*第?(\d{1,3}(?:\.5)?)(?:\((\d{1,4})\))?(?:话|集|(?:\s*(?:v\d|END|完))?(?:\s*[\]】〗]|\s*[-–]\s*[^\d]))|\s-\s?(\d{1,3}(?:\.5)?)(?:\((\d{1,4})\))?(?:\s*(?:v\d|END|完))?(?=[\s\[(【]|$)|(?<![a-z])EP\s?(\d{1,3})(?!\d)',
              caseSensitive: false,
            )
            .allMatches(normalized)
            .where((match) => match.start != first?.start)
            .firstOrNull;
    if (seasonEpisode != null) {
      episodeLabel = 'S${seasonEpisode.group(1)} 第 ${seasonEpisode.group(2)} 话';
      episode = double.parse(seasonEpisode.group(2)!);
    } else if (single != null) {
      final number = single.group(1) ?? single.group(3) ?? single.group(5)!;
      final across = single.group(2) ?? single.group(4);
      episode = double.parse(number);
      absoluteEpisode = across == null ? null : double.parse(across);
      episodeLabel = across == null ? '第 $number 话' : '$number($across)';
    } else if (_token('MOVIE').hasMatch(normalized) ||
        normalized.contains('剧场版')) {
      episodeLabel = '剧场版';
    }
  }

  var display = title.replaceAllMapped(_brackets, (match) {
    final text = (match.group(1) ?? match.group(2) ?? match.group(3))!.trim();
    final normalizedBlock = simplifiedChinese(text);
    final credit =
        match.start == first?.start &&
        (titleCredits.isNotEmpty ||
            sourceGroups.contains(text) ||
            RegExp(
              r'字幕组|字幕組|汉化组|漢化組|工作室|Raws|Studio',
              caseSensitive: false,
            ).hasMatch(text));
    final episodeBlock =
        match.start != first?.start &&
        RegExp(
          r'^(?:第?\d{1,3}(?:\s*[-–~～]\s*\d{1,3})?(?:话|集)?(?:\s*\+\s*SP[x×]?\d+)?|20\d{2})$',
          caseSensitive: false,
        ).hasMatch(normalizedBlock);
    return credit || episodeBlock || _technical.hasMatch(normalizedBlock)
        ? ' '
        : ' $text ';
  });
  display = display.replaceAll(
    RegExp(r'\((?:BD|WEB)\s[^)]*\)', caseSensitive: false),
    ' ',
  );
  display = display.replaceAll(
    RegExp(
      r'\s+(?:10[- ]?bit|8[- ]?bit|1080p|720p|2160p|4k|HEVC|AVC|AV1|BDRip|BD|WebRip|x26[45]|AAC|FLAC|OPUS|\d\.\d)(?:\s+(?:10[- ]?bit|8[- ]?bit|1080p|720p|2160p|4k|HEVC|AVC|AV1|BDRip|BD|WebRip|x26[45]|AAC|FLAC|OPUS|\d\.\d))*\s*$',
      caseSensitive: false,
    ),
    '',
  );
  display = display.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (display.isEmpty) display = title;
  final season = resourceSeason(normalized);
  final credit =
      prefix == null || _technical.hasMatch(simplifiedChinese(prefix))
      ? null
      : prefix.trim();
  final series = episode == null || credit == null || credit.isEmpty
      ? null
      : [
          simplifiedChinese(credit).toLowerCase(),
          season ?? '',
          quality ?? '',
          labels.where((e) => !subtitleLabels.contains(e)).toSet().toList()
            ..sort(),
          {
            for (final match in _platform.allMatches(normalized))
              match.group(0)!.toUpperCase(),
          }.toList()..sort(),
        ].join('|');
  return ResourceTitleInfo(
    title: title,
    displayTitle: display,
    quality: quality,
    qualities: qualities,
    languages: languages,
    subtitleForms: subtitleForms,
    labels: labels.toSet().toList(),
    warnings: warnings,
    sourceGroups: sourceGroups,
    titleCredits: titleCredits,
    episodeLabel: episodeLabel,
    episodeConflict: episodeConflict,
    episode: episode,
    absoluteEpisode: absoluteEpisode,
    season: season,
    credit: credit,
    series: series,
    subtitles: ([
      ...languages,
      ...subtitleForms,
      ...subtitleLabels.toSet(),
    ]..sort()).join('|'),
  );
}

/// The place in [preferred] of the first name one of the credited [groups]
/// holds, by part and ignoring case, so `喵萌` finds 喵萌奶茶屋; null when
/// none does.
int? preferredGroupIndex(Iterable<String> groups, List<String> preferred) {
  final credited = [for (final group in groups) group.toLowerCase()];
  for (final (index, name) in preferred.indexed) {
    final wanted = name.toLowerCase();
    if (credited.any((group) => group.contains(wanted))) return index;
  }
  return null;
}

/// What a title leaves unstated of the selections: each non-empty selection
/// must overlap its annotations or find none stated. Null when it fails one;
/// otherwise the names of the selections it states nothing for, so such
/// titles can follow confirmed ones.
List<String>? resourceSelectionGaps(
  ResourceTitleInfo info, {
  Set<String> qualities = const {},
  Set<String> groups = const {},
  Set<String> languages = const {},
  Set<String> subtitleForms = const {},
}) {
  final gaps = <String>{};
  for (final (name, selected, values) in [
    ('画质', qualities, [?info.quality]),
    ('字幕组', groups, info.groups),
    ('字幕', languages, info.languages),
    ('字幕', subtitleForms, info.subtitleForms),
  ]) {
    if (selected.isEmpty || values.any(selected.contains)) continue;
    if (values.isNotEmpty) return null;
    gaps.add(name);
  }
  return gaps.toList();
}
