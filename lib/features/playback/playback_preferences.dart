import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackPreferences extends ChangeNotifier {
  PlaybackPreferences(this.storage);
  final SharedPreferences storage;
  String get subtitleLanguage =>
      storage.getString('player-subtitle-language') ?? 'chs';
  String get audioLanguage =>
      storage.getString('player-audio-language') ?? 'auto';
  bool get autoplay => storage.getBool('player-autoplay') ?? true;
  bool get autoMarkWatched =>
      storage.getBool('player-auto-mark-watched') ?? true;
  String get airingPriority =>
      storage.getString('player-airing-priority') ?? 'bt';
  String get completedPriority =>
      storage.getString('player-completed-priority') ?? 'online';

  /// mpv `hwdec`: `auto`, `auto-copy` (decoded frames copied back to memory,
  /// for drivers whose direct output misbehaves) or `no`.
  String get hardwareDecoding => storage.getString('player-hwdec') ?? 'auto';

  /// Anime4K shaders: `off`, `fast` or `quality`.
  String get superResolution =>
      storage.getString('player-super-resolution') ?? 'off';

  /// The chain super-resolution turns back on with.
  String get superResolutionChain =>
      storage.getString('player-super-resolution-chain') ?? 'fast';
  bool get skipOpening => storage.getBool('player-skip-opening') ?? false;
  bool get skipEnding => storage.getBool('player-skip-ending') ?? false;

  /// Each subject keeps the source last played, ahead of the global
  /// priority, until another one is played.
  bool get rememberSource => storage.getBool('player-remember-source') ?? true;

  /// Playing an episode starts caching the next aired one from the same
  /// source family.
  bool get cacheNext => storage.getBool('player-cache-next') ?? false;

  /// Autoplay, the next episode and caching it pass over recaps and
  /// programmes about the show (总集篇, 特番).
  bool get skipExtras => storage.getBool('player-skip-extras') ?? true;
  Future<void> setHardwareDecoding(String value) =>
      _string('player-hwdec', value);
  Future<void> setSuperResolution(String value) async {
    if (value != 'off') {
      await storage.setString('player-super-resolution-chain', value);
    }
    await _string('player-super-resolution', value);
  }

  Future<void> setSkipOpening(bool value) =>
      _bool('player-skip-opening', value);
  Future<void> setSkipEnding(bool value) => _bool('player-skip-ending', value);
  Future<void> setRememberSource(bool value) =>
      _bool('player-remember-source', value);
  Future<void> setCacheNext(bool value) => _bool('player-cache-next', value);
  Future<void> setSkipExtras(bool value) => _bool('player-skip-extras', value);
  Future<void> _bool(String key, bool value) async {
    await storage.setBool(key, value);
    notifyListeners();
  }

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

  Future<void> setAutoplay(bool value) => _bool('player-autoplay', value);

  Future<void> setAutoMarkWatched(bool value) =>
      _bool('player-auto-mark-watched', value);
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
