import 'package:html/parser.dart' as html;
import 'package:pinyin/pinyin.dart' show ChineseHelper;

import '../../domain/danmaku.dart';

String normalizedTitle(String value) =>
    ChineseHelper.convertToSimplifiedChinese(
      html.parseFragment(value).text ?? '',
    ).toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

String? positiveId(dynamic value) {
  final id = int.tryParse('$value');
  return id != null && id > 0 ? '$id' : null;
}

double? episodeNumber(String value) {
  final match = RegExp(r'^(?:第\s*)?(\d+(?:\.\d+)?)(?:\s*[話话集])?$')
      .firstMatch(value.trim());
  return match == null ? null : double.tryParse(match[1]!);
}

/// Trimmed, distinct titles; empty when the episode cannot be searched.
Set<String> searchTitles(DanmakuEpisode episode) {
  if (!episode.number.isFinite || episode.number <= 0) return const {};
  return {
    episode.title,
    ...episode.names,
  }.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
}

/// Bilibili/dandanplay numeric comment modes.
DanmakuMode? danmakuMode(int value) => switch (value) {
  1 || 2 || 3 => DanmakuMode.scroll,
  4 => DanmakuMode.bottom,
  5 => DanmakuMode.top,
  _ => null,
};
