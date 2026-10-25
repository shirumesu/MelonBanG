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

/// The one row named for episode [to] the way [anchor] is named for episode
/// [from]: the same text before a number moved by [to] − [from], punctuation
/// aside. Numbers equal to [from] are the anchor's episode number; without
/// one, any number may be (a series numbered apart from the catalogue).
/// Null unless exactly one row matches.
T? followRow<T>(
  Iterable<T> rows,
  String Function(T) name,
  T anchor,
  double from,
  double to,
) {
  final step = to - from;
  if (step != step.roundToDouble()) return null;
  final numbers = _numbers(name(anchor));
  final own = numbers.where((number) => number.$2 == from).toList();
  final keys = {
    for (final (prefix, value) in own.isEmpty ? numbers : own)
      (prefix, value + step.toInt()),
  };
  final found = rows
      .where((row) => _numbers(name(row)).any(keys.contains))
      .toList();
  return found.length == 1 ? found.single : null;
}

/// Each number in [title], in digits or Chinese up to 99, with the
/// normalized text before it. Both ends of a range such as "1-3" are left
/// out: such a row holds several episodes, or one episode's part.
List<(String, int)> _numbers(String title) {
  final matches = RegExp(r'\d{1,9}|[一二三四五六七八九]?十[一二三四五六七八九]?|[一二三四五六七八九]')
      .allMatches(title)
      .toList();
  bool joined(int i) =>
      i + 1 < matches.length &&
      RegExp(r'^\s*[-~～〜至到—–]\s*$')
          .hasMatch(title.substring(matches[i].end, matches[i + 1].start));
  return [
    for (var i = 0; i < matches.length; i++)
      if (!joined(i) && (i == 0 || !joined(i - 1)))
        (
          normalizedTitle(title.substring(0, matches[i].start)),
          _value(matches[i][0]!),
        ),
  ];
}

int _value(String number) {
  const digits = '一二三四五六七八九';
  if (int.tryParse(number) case final value?) return value;
  final ten = number.indexOf('十');
  if (ten < 0) return digits.indexOf(number) + 1;
  return (ten == 0 ? 1 : digits.indexOf(number[0]) + 1) * 10 +
      (ten == number.length - 1 ? 0 : digits.indexOf(number[ten + 1]) + 1);
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
