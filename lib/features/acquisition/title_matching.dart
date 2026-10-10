import 'package:pinyin/pinyin.dart';

import '../../data/json.dart';
import '../../data/resource_title.dart';
import '../../domain/sources.dart';

/// Simplified, width-folded title without punctuation, plus its season.
(String, int) normalizeSourceTitle(String input) {
  var title = ChineseHelper.convertToSimplifiedChinese(
    String.fromCharCodes(
      input.runes.map(
        (c) => c == 0x3000
            ? 32
            : c >= 0xff01 && c <= 0xff5e
            ? c - 0xfee0
            : c,
      ),
    ),
  ).toLowerCase();
  final season = RegExp(
    r'第\s*([一二三四五六七八九十\d]+)\s*[季期]|season\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(title);
  final raw = season?[1] ?? season?[2] ?? '1';
  final number =
      int.tryParse(raw) ??
      ({
            '一': 1,
            '二': 2,
            '三': 3,
            '四': 4,
            '五': 5,
            '六': 6,
            '七': 7,
            '八': 8,
            '九': 9,
            '十': 10,
          }[raw] ??
          1);
  if (season != null) title = title.replaceRange(season.start, season.end, '');
  return (
    title.replaceAll(RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff]'), ''),
    number,
  );
}

/// Dice similarity of the best catalogue name, penalizing season mismatch and
/// adjusted by year and episode count. Calibrated thresholds: .84 automatic,
/// .55 possible match.
double sourceMatchScore(
  Json subject,
  SourceSubject site,
  Iterable<String> names,
) {
  final target = normalizeSourceTitle(site.title);
  var best = 0.0;
  for (final name in names) {
    final expected = normalizeSourceTitle(name);
    double dice(String a, String b) {
      if (a == b) return 1;
      if (a.length < 2 || b.length < 2) return 0;
      final left = <String>{
        for (var i = 0; i < a.length - 1; i++) a.substring(i, i + 2),
      };
      final right = <String>{
        for (var i = 0; i < b.length - 1; i++) b.substring(i, i + 2),
      };
      return 2 * left.intersection(right).length / (left.length + right.length);
    }

    final score =
        dice(expected.$1, target.$1) - (expected.$2 != target.$2 ? .4 : 0);
    if (score > best) best = score;
  }
  final year = int.tryParse('${subject['airDate'] ?? ''}'.split('-').first);
  if (year != null && site.year != null) {
    best += year == site.year ? .03 : -.12;
  }
  final count = site.episodeTotal;
  if (count != null && (count - number(subject['episodeTotal'])).abs() <= 2) {
    best += .02;
  }
  return best.clamp(0, 1);
}

bool sourceEpisodeMatches(String label, Json episode) {
  final normalized = ChineseHelper.convertToSimplifiedChinese(label)
      .toUpperCase();
  final special = RegExp(r'SP|OVA|OAD|特别').hasMatch(normalized);
  final main =
      episode['type'] == 'main' ||
      episode['type'] == 0 ||
      episode['type'] == null;
  if (special == main) return false;
  final parsed = describeResource('[$normalized]').episodeLabel;
  final match = RegExp(r'(?:第|EP\s*|SP\s*|OVA\s*|OAD\s*)?(\d+(?:\.\d+)?)')
      .firstMatch(normalized);
  if (match == null) {
    return !main && number(episode['sort']) == 1 && parsed != null;
  }
  return double.tryParse(match[1]!) == number(episode['sort']);
}
