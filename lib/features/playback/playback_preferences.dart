import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/json.dart';

class PlaybackPreferences extends ChangeNotifier {
  PlaybackPreferences(this.storage);
  final SharedPreferences storage;
  String get subtitleLanguage =>
      storage.getString('player-subtitle-language') ?? 'auto';
  String get audioLanguage =>
      storage.getString('player-audio-language') ?? 'auto';
  bool get autoplay => storage.getBool('player-autoplay') ?? true;
  String get airingPriority =>
      storage.getString('player-airing-priority') ?? 'bt';
  String get completedPriority =>
      storage.getString('player-completed-priority') ?? 'online';
  Future<void> setSubtitleLanguage(String value) =>
      _string('player-subtitle-language', value);
  Future<void> setAudioLanguage(String value) =>
      _string('player-audio-language', value);
  Future<void> setAiringPriority(String value) =>
      _string('player-airing-priority', value);
  Future<void> setCompletedPriority(String value) =>
      _string('player-completed-priority', value);
  Future<void> _string(String key, String value) async {
    await storage.setString(key, value);
    notifyListeners();
  }

  Future<void> setAutoplay(bool value) async {
    await storage.setBool('player-autoplay', value);
    notifyListeners();
  }

  Future<void> resetLanguages() async {
    await storage.remove('player-subtitle-language');
    await storage.remove('player-audio-language');
    notifyListeners();
  }
}

class DanmakuFilter {
  DanmakuFilter(this.pattern, {this.isRegex = false, this.enabled = true}) {
    if (isRegex) {
      try {
        expression = RegExp(pattern, caseSensitive: false);
      } on FormatException catch (_) {
        invalid = true;
      }
    }
  }
  final String pattern;
  final bool isRegex, enabled;
  RegExp? expression;
  bool invalid = false;
  bool matches(String text) =>
      enabled &&
      !invalid &&
      (isRegex
          ? expression!.hasMatch(text)
          : text.toLowerCase().contains(pattern.toLowerCase()));
  Json toJson() => {'pattern': pattern, 'isRegex': isRegex, 'enabled': enabled};
}

class DanmakuPreferences extends ChangeNotifier {
  DanmakuPreferences(this.storage) {
    try {
      final saved = object(
        jsonDecode(storage.getString('danmaku-preferences') ?? '{}'),
      );
      enabled = saved['enabled'] as bool? ?? true;
      size = number(saved['size'] ?? 25).clamp(14, 36).toDouble();
      opacity = number(saved['opacity'] ?? .9).clamp(.1, 1).toDouble();
      area = number(saved['area'] ?? .6).clamp(.2, 1).toDouble();
      density = number(saved['density'] ?? 1).toInt().clamp(0, 3);
      scroll = saved['scroll'] as bool? ?? true;
      top = saved['top'] as bool? ?? true;
      bottom = saved['bottom'] as bool? ?? true;
      colorful = saved['colorful'] as bool? ?? true;
      stroke = saved['stroke'] as bool? ?? true;
      providers = object(saved['providers'])
          .map((key, value) => MapEntry(key, value == true));
      filters =
          objects(jsonDecode(storage.getString('danmaku-filters') ?? '[]'))
              .map(
                (rule) => DanmakuFilter(
                  '${rule['pattern'] ?? ''}',
                  isRegex: rule['isRegex'] == true,
                  enabled: rule['enabled'] != false,
                ),
              )
              .where((rule) => rule.pattern.isNotEmpty)
              .toList();
    } on FormatException catch (_) {
      /* Keep defaults if old preferences are unreadable. */
    }
  }
  final SharedPreferences storage;
  bool enabled = true,
      scroll = true,
      top = true,
      bottom = true,
      colorful = true,
      stroke = true;
  double size = 25, opacity = .9, area = .6;
  int density = 1;
  Map<String, bool> providers = {};
  List<DanmakuFilter> filters = [];
  bool sourceEnabled(String provider) => providers[provider] ?? true;
  void update(VoidCallback change) {
    change();
    storage.setString(
      'danmaku-preferences',
      jsonEncode({
        'enabled': enabled,
        'size': size,
        'opacity': opacity,
        'area': area,
        'density': density,
        'scroll': scroll,
        'top': top,
        'bottom': bottom,
        'colorful': colorful,
        'stroke': stroke,
        'providers': providers,
      }),
    );
    storage.setString(
      'danmaku-filters',
      jsonEncode(filters.map((rule) => rule.toJson()).toList()),
    );
    notifyListeners();
  }

  void resetDisplay() => update(() {
    enabled = scroll = top = bottom = colorful = stroke = true;
    size = 25;
    opacity = .9;
    area = .6;
    density = 1;
  });
  void setProvider(String provider, bool value) =>
      update(() => providers[provider] = value);
  void addFilter(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    final regex = text.length > 2 && text.startsWith('/') && text.endsWith('/');
    update(
      () => filters.add(
        DanmakuFilter(
          regex ? text.substring(1, text.length - 1) : text,
          isRegex: regex,
        ),
      ),
    );
  }

  List<Json> visible(List<Json> comments, Map<String, double> offsets) {
    final result = <Json>[];
    for (final item in comments) {
      final mode = item['mode'] ?? 'scroll';
      if ((mode == 'scroll' && !scroll) ||
          (mode == 'top' && !top) ||
          (mode == 'bottom' && !bottom)) {
        continue;
      }
      final color = '${item['color'] ?? '#ffffff'}'
          .replaceFirst('#', '')
          .toLowerCase();
      if (!colorful && color != 'ffffff' && color != '16777215') continue;
      if (filters.any((rule) => rule.matches('${item['text'] ?? ''}'))) {
        continue;
      }
      result.add({
        ...item,
        'timeSeconds':
            number(item['timeSeconds']) + (offsets[item['sourceId']] ?? 0),
      });
    }
    result.sort(
      (a, b) => number(a['timeSeconds']).compareTo(number(b['timeSeconds'])),
    );
    return result;
  }
}

String languageCodes(String preference) => switch (preference) {
  'chs' => 'chs,sc,zh-hans,zh-cn,zho,chi,zh',
  'cht' => 'cht,tc,zh-hant,zh-tw,zh-hk,zho,chi,zh',
  'ja' => 'jpn,ja',
  'zh' => 'zho,chi,zh,zh-cn,zh-tw',
  _ => '',
};

int languageScore(String preference, String? language, String? title) {
  if (preference == 'auto') return 0;
  final code = (language ?? '').toLowerCase();
  final text = (title ?? '').toLowerCase();
  final simplified = RegExp(r'简|簡|simplified|chs|\bsc\b|\bgb\b|\.sc\b|\.chs\b')
      .hasMatch(text);
  final traditional = RegExp(r'繁|traditional|cht|\btc\b|big5|\.tc\b|\.cht\b')
      .hasMatch(text);
  final exact = languageCodes(preference).split(',');
  var score = code.isNotEmpty && exact.contains(code) ? 20 : 0;
  if (preference == 'chs' || preference == 'cht') {
    final wanted = preference == 'chs' ? simplified : traditional;
    final other = preference == 'chs' ? traditional : simplified;
    if (wanted) score += 100;
    if (other && !wanted) score -= 100;
    if ((preference == 'chs' &&
            ['chs', 'sc', 'zh-hans', 'zh-cn'].contains(code)) ||
        (preference == 'cht' &&
            ['cht', 'tc', 'zh-hant', 'zh-tw', 'zh-hk'].contains(code))) {
      score += 40;
    }
  } else if (preference == 'ja' &&
      RegExp(r'日|japanese|jpn|\bja\b').hasMatch(text)) {
    score += 50;
  } else if (preference == 'zh' &&
      RegExp(r'中|国|國|chinese|chi|zho').hasMatch(text)) {
    score += 50;
  }
  return score;
}
