import 'package:pinyin/pinyin.dart';

import 'json.dart';

/// Read-only release annotations. These never establish episode/file identity.
class ResourceTitleInfo {
  const ResourceTitleInfo({
    required this.title,
    required this.displayTitle,
    required this.labels,
    required this.notes,
    required this.sourceGroups,
    required this.titleCredits,
    this.quality,
    this.episodeLabel,
    this.episodeConflict = false,
  });

  final String title, displayTitle;
  final String? quality, episodeLabel;
  final List<String> labels, notes, sourceGroups, titleCredits;
  final bool episodeConflict;
}

RegExp _token(String pattern) =>
    RegExp('(?<![a-z0-9])(?:$pattern)(?![a-z0-9])', caseSensitive: false);

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

ResourceTitleInfo describeResource(Json candidate) {
  final title = '${candidate['title'] ?? '未命名资源'}'.trim();
  final normalized = ChineseHelper.convertToSimplifiedChinese(title);
  final sourceGroups =
      (candidate['releaseGroups'] is List
              ? candidate['releaseGroups'] as List
              : const [])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
  final labels = <String>[], notes = <String>[];
  final outputText = normalized.replaceAll(_sourceQuality, '');
  final qualities = <String>{
    if (_token(r'720p|1280\s*[x×*]\s*720').hasMatch(outputText)) '720p',
    if (_token(r'1080p|1920\s*[x×*]\s*1080').hasMatch(outputText)) '1080p',
    if (_token(r'2160p|(?:3840|4096)\s*[x×*]\s*2160|4k').hasMatch(outputText))
      '4K',
  };
  final quality = qualities.length == 1 ? qualities.single : null;
  labels.addAll(qualities);
  if (_sourceQuality.hasMatch(normalized)) {
    labels.add('${_sourceQuality.firstMatch(normalized)!.group(0)}（片源）');
    notes.add('4K片源说明不代表输出画质');
  }
  if (qualities.length > 1) {
    notes.add('标题含多种画质，输出待确认');
  } else if (quality == null) {
    notes.add('画质未标明');
  }
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
  labels.addAll(subtitle.allMatches(normalized).map((m) => m.group(0)!));
  if (!subtitle.hasMatch(normalized)) {
    for (final language in ['CHS', 'CHT', 'GB', 'BIG5', 'VOSTFR']) {
      if (_token(language).hasMatch(normalized)) labels.add(language);
    }
  }
  final blocks = _brackets.allMatches(title).toList();
  final first = blocks.firstOrNull;
  final prefix = first != null && title.substring(0, first.start).trim().isEmpty
      ? (first.group(1) ?? first.group(2) ?? first.group(3))!
      : null;
  final titleCredits =
      prefix != null &&
          !_technical.hasMatch(
            ChineseHelper.convertToSimplifiedChinese(prefix),
          ) &&
          RegExp(r'[&＆]').hasMatch(prefix)
      ? prefix.split(RegExp(r'\s*[&＆]\s*')).where((e) => e.isNotEmpty).toList()
      : <String>[];
  if (titleCredits.length > 1) {
    notes.add('标题联合署名：${titleCredits.join(' & ')}');
  }

  String? episodeLabel;
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
    notes.add(
      episodeConflict ? '$episodeLabel 范围倒置，集数待确认' : '合集 · $episodeLabel（标题）',
    );
  } else if (special != null) {
    episodeLabel = '特别篇 ${special.group(0)}';
    notes.add('$episodeLabel（标题）');
  } else {
    final seasonEpisode = RegExp(
      r'\bS(\d{1,2})E(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    final single =
        RegExp(
              r'[\[【〖]\s*(?:第)?(\d{1,3})(?:话|集|\s*[-–]\s*[^\d]|\s*[\]】〗])|\s-\s(\d{1,3})(?:\((\d{1,4})\))?(?=\s|$)',
            )
            .allMatches(normalized)
            .where((match) => match.start != first?.start)
            .firstOrNull;
    if (seasonEpisode != null) {
      episodeLabel =
          'S${seasonEpisode.group(1)} · 第 ${seasonEpisode.group(2)} 话';
    } else if (single != null) {
      episodeLabel = single.group(3) == null
          ? '第 ${single.group(1) ?? single.group(2)} 话'
          : '${single.group(2)}(${single.group(3)})';
    } else if (_token('MOVIE').hasMatch(normalized) ||
        normalized.contains('剧场版')) {
      episodeLabel = '剧场版';
    }
  }

  if (episodeLabel != null && range == null && special == null) {
    labels.insert(0, '$episodeLabel（标题）');
  }

  var display = title.replaceAllMapped(_brackets, (match) {
    final text = (match.group(1) ?? match.group(2) ?? match.group(3))!.trim();
    final normalizedBlock = ChineseHelper.convertToSimplifiedChinese(text);
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
  return ResourceTitleInfo(
    title: title,
    displayTitle: display,
    quality: quality,
    labels: labels.toSet().toList(),
    notes: notes,
    sourceGroups: sourceGroups,
    titleCredits: titleCredits,
    episodeLabel: episodeLabel,
    episodeConflict: episodeConflict,
  );
}

bool matchesResourceSelection(
  ResourceTitleInfo info, {
  String quality = 'all',
  String group = '',
  bool includeUnknown = true,
}) =>
    (quality == 'all' ||
        info.quality == quality ||
        (includeUnknown && info.quality == null)) &&
    (group.isEmpty ||
        info.sourceGroups.contains(group) ||
        (includeUnknown && info.sourceGroups.isEmpty));
