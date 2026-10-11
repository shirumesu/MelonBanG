import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackPreferences extends ChangeNotifier {
  PlaybackPreferences(this.storage);
  final SharedPreferences storage;
  String get subtitleLanguage =>
      storage.getString('player-subtitle-language') ?? 'auto';
  String get audioLanguage =>
      storage.getString('player-audio-language') ?? 'auto';
  bool get autoplay => storage.getBool('player-autoplay') ?? true;
  bool get autoMarkWatched =>
      storage.getBool('player-auto-mark-watched') ?? true;
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

  Future<void> setAutoMarkWatched(bool value) async {
    await storage.setBool('player-auto-mark-watched', value);
    notifyListeners();
  }

  Future<void> resetLanguages() async {
    await storage.remove('player-subtitle-language');
    await storage.remove('player-audio-language');
    notifyListeners();
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
