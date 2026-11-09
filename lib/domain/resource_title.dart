import 'package:pinyin/pinyin.dart';

import 'release_traits.dart';
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
    this.bilingual = false,
    this.noChinese = false,
    this.quality,
    this.episodeLabel,
    this.episodeConflict = false,
    this.episode,
    this.absoluteEpisode,
    this.season,
    this.credit,
    this.series,
    this.platforms = const [],
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

  /// Subtitle languages (简体, 繁体, 日文) and forms (内封, 内嵌, 外挂) the
  /// title states.
  final Set<String> languages, subtitleForms;

  /// Whether Japanese lines come beside Chinese ones, as in 简日, 简繁日
  /// and 中日双语 releases; the last leave the script unstated.
  final bool bilingual;

  /// Whether the title says it carries no Chinese subtitles: 无中文字幕,
  /// 生肉, 【生】. Nothing else tells: a streaming platform's rips differ by
  /// title and region (Crunchyroll and B-Global rips carry Chinese for some
  /// shows, not others), so a rip naming its platform alone stays unstated.
  final bool noChinese;

  /// Which of [resourceSubtitleChoices] the release meets.
  List<String> get subtitleChoices => [
    ...resourceLanguages.where(languages.contains),
    if (bilingual) resourceBilingual,
    ...resourceSubtitleForms.where(subtitleForms.contains),
  ];

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
  /// credited group, else the site's, and the season. Quality, platform and
  /// encoding are left out, as groups release several of them side by side
  /// and change encoding mid-season; a group's batches share it with its
  /// single episodes. Null for titles without a group, episode or range.
  final String? series;

  /// The streaming platforms the title names as ripped from, such as `Baha`;
  /// one group's rips of a series from several differ by them.
  final List<String> platforms;

  /// The subtitle languages, forms and wording the title states, empty when
  /// it states none; a series' releases share it where stated.
  final String subtitles;
}

/// Filter vocabularies, in display order.
const resourceQualities = ['4K', '1080p', '720p'];

/// The Chinese scripts of subtitles; a selection of both takes either, and
/// 简繁 releases meet both.
const resourceLanguages = ['简体', '繁体'];

/// Chinese subtitles with Japanese lines beside them, selected among the
/// languages but met on its own, besides the scripts.
const resourceBilingual = '中日双语';

/// Subtitles in a track of their own the player can turn off. External
/// files are left out: streams from a torrent do not load them.
const resourceSubtitleForms = ['内封'];

/// The subtitle filter's choices, in display order.
const resourceSubtitleChoices = [
  ...resourceLanguages,
  resourceBilingual,
  ...resourceSubtitleForms,
];

/// Subtitle selections saved before 中日双语: 日文 selected releases with
/// Japanese lines, now 中日双语, and of the forms only 内封 remains.
Set<String> resourceSubtitleSelection(Iterable<String> saved) => {
  for (final value in saved)
    if (value == '日文')
      resourceBilingual
    else if (resourceSubtitleChoices.contains(value))
      value,
};

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
  '日文': [
    RegExp(r'[简繁中]日|日[语文]|日(?:简|繁)'),
    _token(r'JP|JPN|JPSC|JPTC|JA'),
    // A fansub's 简体双语 puts Japanese lines beside its script.
    RegExp(r'(?:简体|繁体|简中|繁中)双语'),
  ],
};

RegExp _token(String pattern) =>
    RegExp('(?<![a-z0-9])(?:$pattern)(?![a-z0-9])', caseSensitive: false);

/// A title saying it has no Chinese subtitles, in simplified script:
/// `[无中文字幕]`, `(1080P 无中文 多国字幕)`, `生肉`, `无字幕`, `【生】`.
final _noChinese = RegExp(r'无中文|生肉|无字幕|[\[【(（]生[\]】)）]');

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
const _platforms = [
  'ABEMA',
  'Baha',
  'B-Global',
  'Bilibili',
  'CR',
  'Crunchyroll',
  'NF',
  'Netflix',
  'AMZN',
  'CATCHPLAY',
  'Disney+',
  'Disney',
  'U-NEXT',
  'iQIYI',
  'Viu',
  'KKTV',
  'MUSE',
  'Hulu',
  'YouTube',
];
final _platform = _token(_platforms.map(RegExp.escape).join('|'));

final _brackets = RegExp(r'\[([^\]]+)\]|【([^】]+)】|〖([^〗]+)〗');
final _sourceQuality = RegExp(
  r'4k\s*(?:重扫(?:版)?|扫描(?:版)?|片源|母带|修复(?:版)?|重制(?:版)?)',
  caseSensitive: false,
);
final _repost = RegExp(r'^[\[【〖]\s*(?:搬运|转载)\s*[\]】〗]$');
final _format = _token(r'BDRemux|BDRip|BD|WebRip|WEB[- ]DL');
final _technical = RegExp(
  r'^(?:(?:BDRemux|BDRip|BD|WEBRip|WEB(?:[- ]DL)?|HDTV|REMUX|HEVC|AVC|AV1|H[ ._-]?26[45]|x26[45]|AAC|FLAC|OPUS|TRUEHD|DTS|MP4|MKV|PGS|SRT|ASS|1080p|720p|2160p|(?:3840|1920|1280)\s*[x×*]\s*\d+|4K|10[- ]?BIT|8[- ]?BIT|GB|BIG5|CHS|CHT|JPN|FIN|END|V\d|RESEED|MOVIE|SP|OVA|ONA)(?=$|[\s_/+(.-])|(?:REMAKE重制版|国漫|合集|搬运|转载|生)$|(?:简繁|简体|繁体|简中|繁中|简日|繁日|粤日|内封|外挂|无中文|生肉|无字幕))',
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

void keepDescribed(Map<String, ResourceTitleInfo> described) {
  if (_described.length + described.length > 4096) _described.clear();
  _described.addAll(described);
}

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
    if (_token(r'(?:AI)?(?:2160p|4k)|(?:3840|4096)\s*[x×*]\s*2160')
        .hasMatch(outputText))
      '4K',
  };
  final quality = qualities.length == 1 ? qualities.single : null;
  final noChinese = _noChinese.hasMatch(normalized);
  final languages = {
    for (final entry in _languagePatterns.entries)
      if (entry.value.any((pattern) => pattern.hasMatch(normalized)))
        if (!(noChinese && resourceLanguages.contains(entry.key))) entry.key,
  };
  final subtitleForms = {
    for (final form in const ['内封', '内嵌', '外挂'])
      if (normalized.contains(form)) form,
  };
  labels.addAll(qualities);
  // Upscaled rips: `[CR WebRip AI2160p]` beside the group's own 1080p.
  if (_token(r'AI(?:2160p|4k)').hasMatch(outputText)) labels.add('AI 超分');
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
  // The forms describe Chinese subtitles, which it has none of.
  if (noChinese) {
    subtitleForms.clear();
    subtitleLabels
      ..clear()
      ..add('无中文字幕');
  }
  // Bahamut streams carry burned-in traditional subtitles, which rips of
  // them seldom state in full.
  if (!noChinese && _token('Baha').hasMatch(normalized)) {
    final stated = [
      if (languages.isEmpty) '繁体',
      if (subtitleForms.isEmpty) '内嵌',
    ];
    if (languages.isEmpty) languages.add('繁体');
    if (subtitleForms.isEmpty) subtitleForms.add('内嵌');
    if (stated.isNotEmpty) subtitleLabels.add(stated.join());
  }
  labels.addAll(subtitleLabels);
  final blocks = _brackets.allMatches(title).toList();
  // Reposts lead with a marker before the group's own title: [搬運][ANi].
  var lead = 0;
  while (lead < blocks.length - 1 &&
      _repost.hasMatch(simplifiedChinese(blocks[lead].group(0)!)) &&
      title
          .substring(blocks[lead].end, blocks[lead + 1].start)
          .trim()
          .isEmpty) {
    lead++;
  }
  final first = blocks.elementAtOrNull(lead);
  final prefix =
      first != null &&
          title
              .substring(0, first.start)
              .replaceAll(_brackets, '')
              .trim()
              .isEmpty
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
  // Long-running shows reach four digits, which only count written as
  // 第1218集 so a year such as [2026] is not taken for an episode.
  final range =
      RegExp(
        r'(?:[\[【〖|]\s*第?)(\d{1,3})\s*[-–~～]\s*(\d{1,3})(?:话|集)?(?:\s*\+\s*SP[x×]?(\d+))?',
        caseSensitive: false,
      ).firstMatch(normalized) ??
      RegExp(
        r'[\[【〖|]\s*第(\d{4})\s*[-–~～]\s*(\d{4})\s*[话集](?:\s*\+\s*SP[x×]?(\d+))?',
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
    // [12] [第12话] [03(51)] [12 END], [07+ES07] with an extra short after
    // the episode, " - 12", " - 03(51) " and EP12.
    final single =
        RegExp(
              r'[\[【〖]\s*第?(\d{1,3}(?:\.5)?)(?:\((\d{1,4})\))?(?:话|集|(?:\s*(?:v\d|END|完))?(?:\s*\+\s*[a-z]{1,3}\d{0,3})?(?:\s*[\]】〗]|\s*[-–]\s*[^\d]))|\s-\s?(\d{1,3}(?:\.5)?)(?:\((\d{1,4})\))?(?:\s*(?:v\d|END|完))?(?=[\s\[(【]|$)|(?<![a-z])EP\s?(\d{1,3})(?!\d)',
              caseSensitive: false,
            )
            .allMatches(normalized)
            .where((match) => match.start != first?.start)
            .firstOrNull;
    final long = RegExp(r'[\[【〖]\s*第(\d{4})[话集]')
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
    } else if (long != null) {
      episode = double.parse(long.group(1)!);
      episodeLabel = '第 ${long.group(1)} 话';
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
  final platforms = {
    for (final match in _platform.allMatches(normalized))
      _platforms.firstWhere(
        (name) => name.toLowerCase() == match.group(0)!.toLowerCase(),
      ),
  }.toList()..sort();
  final releaser = credit ?? sourceGroups.firstOrNull;
  final series =
      (episode == null && range == null) || releaser == null || releaser.isEmpty
      ? null
      : [simplifiedChinese(releaser).toLowerCase(), season ?? ''].join('|');
  return ResourceTitleInfo(
    title: title,
    displayTitle: display,
    quality: quality,
    qualities: qualities,
    languages: languages,
    subtitleForms: subtitleForms,
    bilingual:
        !noChinese &&
        languages.contains('日文') &&
        (languages.any(resourceLanguages.contains) ||
            RegExp(r'中日|日中').hasMatch(normalized)),
    noChinese: noChinese,
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
    platforms: platforms,
    subtitles: ([
      ...languages,
      ...subtitleForms,
      ...subtitleLabels.toSet(),
    ]..sort()).join('|'),
  );
}

/// What a title leaves unstated of the selections: each non-empty selection
/// must overlap its annotations or find none stated; [resourceBilingual]
/// among [languages] is a selection of its own. Null when it fails one;
/// otherwise the names of the selections it states nothing for, so such
/// titles can follow confirmed ones. Every subtitle choice is of Chinese
/// subtitles, so a title saying it has none fails any.
List<String>? resourceSelectionGaps(
  ResourceTitleInfo info, {
  Set<String> qualities = const {},
  Set<String> groups = const {},
  Set<String> languages = const {},
  Set<String> subtitleForms = const {},
}) {
  if (info.noChinese && (languages.isNotEmpty || subtitleForms.isNotEmpty)) {
    return null;
  }
  final gaps = <String>{};
  for (final (name, selected, values) in [
    ('画质', qualities, [?info.quality]),
    ('字幕组', groups, info.groups),
    (
      '字幕',
      languages.intersection(resourceLanguages.toSet()),
      info.bilingual ? info.languages.difference(const {'日文'}) : info.languages,
    ),
    // Releases stating their languages state whether they are bilingual.
    (
      '字幕',
      languages.intersection(const {resourceBilingual}),
      [
        if (info.bilingual)
          resourceBilingual
        else if (info.languages.isNotEmpty)
          '单语',
      ],
    ),
    ('字幕', subtitleForms, info.subtitleForms),
  ]) {
    if (selected.isEmpty) continue;
    // Group names are compared as preferred groups are, so a typed 喵萌
    // finds 喵萌奶茶屋.
    if (name == '字幕组'
        ? groupsMatch(values, selected)
        : values.any(selected.contains)) {
      continue;
    }
    if (values.isNotEmpty) return null;
    gaps.add(name);
  }
  return gaps.toList();
}

/// `简繁内封`, as [info]'s title words its subtitles; `未标明字幕` when it
/// states none.
String subtitleName(ResourceTitleInfo info) {
  final stated = info.subtitles.split('|').toSet();
  final words = info.labels.where(stated.contains);
  if (words.isNotEmpty) return words.join(' ');
  final named = [...info.languages, ...info.subtitleForms];
  return named.isEmpty ? '未标明字幕' : named.join();
}

/// Reads subtitles across [releases]: a group leaves them out of some titles
/// of a series (`ASSx2` against `[简繁内封字幕]`), so a release stating none
/// takes what the group's other releases of the series from the same
/// platform state, where they agree. The release returned stands for the
/// given one's subtitles only.
ResourceTitleInfo Function(ResourceTitleInfo) seriesSubtitles(
  Iterable<ResourceTitleInfo> releases,
) {
  String key(ResourceTitleInfo info) =>
      '${info.series}|${info.platforms.join(' ')}';
  bool states(ResourceTitleInfo info) =>
      info.noChinese ||
      info.languages.isNotEmpty ||
      info.subtitleForms.isNotEmpty;
  final stated = <String, Map<String, ResourceTitleInfo>>{};
  for (final info in releases) {
    if (info.series != null && states(info)) {
      (stated[key(info)] ??= {})[subtitleName(info)] ??= info;
    }
  }
  return (info) => info.series != null && !states(info)
      ? switch (stated[key(info)]) {
          final named? when named.length == 1 => named.values.single,
          _ => info,
        }
      : info;
}
