import 'package:flutter/foundation.dart';

import '../../core/json.dart';
import '../../core/settings.dart';
import '../../domain/catalog.dart';

class PlaybackPreferences extends ChangeNotifier {
  PlaybackPreferences(this.settings) {
    // The group counts change with every search and show nowhere live.
    settings.watch([
      for (final setting in all)
        if (setting != seenGroupsSetting) setting.key,
    ], notifyListeners);
  }
  final Settings settings;

  static const subtitleLanguageSetting = StringSetting(
    'player-subtitle-language',
    'chs',
    sync: SettingSync.synced,
    label: '播放 › 字幕语言',
    valueLabels: {'chs': '简体中文', 'cht': '繁体中文', 'ja': '日语', 'auto': '自动'},
  );
  static const audioLanguageSetting = StringSetting(
    'player-audio-language',
    'auto',
    sync: SettingSync.synced,
    label: '播放 › 音轨语言',
    valueLabels: {'ja': '日语', 'zh': '中文', 'auto': '自动'},
  );
  static const autoplaySetting = BoolSetting(
    'player-autoplay',
    true,
    sync: SettingSync.synced,
    label: '播放 › 自动连播',
  );
  static const autoMarkWatchedSetting = BoolSetting(
    'player-auto-mark-watched',
    true,
    sync: SettingSync.synced,
    label: '播放 › 自动标记为看过',
  );
  static const airingPrioritySetting = StringSetting(
    'player-airing-priority',
    'bt',
    sync: SettingSync.synced,
    label: '资源选择 › 放送中的番',
    valueLabels: {'bt': 'BT 优先', 'online': '在线优先'},
  );
  static const completedPrioritySetting = StringSetting(
    'player-completed-priority',
    'online',
    sync: SettingSync.synced,
    label: '资源选择 › 已完结的番',
    valueLabels: {'bt': 'BT 优先', 'online': '在线优先'},
  );
  static const preferredGroupsSetting = StringSetting(
    'player-preferred-groups',
    '',
    sync: SettingSync.synced,
    label: '资源选择 › 偏好字幕组',
  );
  static const onlyPreferredGroupsSetting = BoolSetting(
    'player-only-preferred-groups',
    false,
    sync: SettingSync.synced,
    label: '资源选择 › 只显示偏好字幕组',
  );

  /// Counts of groups searches found: statistics of this device.
  static const seenGroupsSetting = JsonSetting(
    'resource-seen-groups',
    fallback: <String, dynamic>{},
    sync: SettingSync.local,
  );

  /// Decoding depends on this device's graphics card and driver.
  static const hardwareDecodingSetting = StringSetting(
    'player-hwdec',
    'auto',
    sync: SettingSync.local,
  );

  /// Shaders a weaker graphics card cannot keep up with.
  static const superResolutionSetting = StringSetting(
    'player-super-resolution',
    'off',
    sync: SettingSync.local,
  );
  static const superResolutionChainSetting = StringSetting(
    'player-super-resolution-chain',
    'fast',
    sync: SettingSync.local,
  );
  static const skipOpeningSetting = BoolSetting(
    'player-skip-opening',
    false,
    sync: SettingSync.synced,
    label: '播放 › 自动跳过 OP',
  );
  static const skipEndingSetting = BoolSetting(
    'player-skip-ending',
    false,
    sync: SettingSync.synced,
    label: '播放 › 自动跳过 ED',
  );
  static const rememberSourceSetting = BoolSetting(
    'player-remember-source',
    true,
    sync: SettingSync.synced,
    label: '资源选择 › 记住每部番的来源',
  );
  static const cacheNextSetting = BoolSetting(
    'player-cache-next',
    true,
    sync: SettingSync.synced,
    label: '订阅与缓存 › 播放时缓存下一话',
  );
  static const skipExtrasSetting = BoolSetting(
    'player-skip-extras',
    true,
    sync: SettingSync.synced,
    label: '播放 › 跳过总集篇和特番',
  );

  static const all = <Setting<Object?>>[
    subtitleLanguageSetting,
    audioLanguageSetting,
    autoplaySetting,
    autoMarkWatchedSetting,
    airingPrioritySetting,
    completedPrioritySetting,
    preferredGroupsSetting,
    onlyPreferredGroupsSetting,
    seenGroupsSetting,
    hardwareDecodingSetting,
    superResolutionSetting,
    superResolutionChainSetting,
    skipOpeningSetting,
    skipEndingSetting,
    rememberSourceSetting,
    cacheNextSetting,
    skipExtrasSetting,
  ];

  String get subtitleLanguage => settings.get(subtitleLanguageSetting);
  String get audioLanguage => settings.get(audioLanguageSetting);
  bool get autoplay => settings.get(autoplaySetting);
  bool get autoMarkWatched => settings.get(autoMarkWatchedSetting);
  String get airingPriority => settings.get(airingPrioritySetting);
  String get completedPriority => settings.get(completedPrioritySetting);

  /// Whether [subject] plays online before BT, by whether every episode
  /// has aired.
  bool onlineFirst(Subject subject) =>
      (subject.finished() ? completedPriority : airingPriority) == 'online';

  /// Release groups whose releases rank first, most preferred first. Kept
  /// as text split at commas, semicolons and 、, half or full width, as it
  /// was once typed; names themselves may hold spaces (`Nekomoe kissaten`).
  List<String> get preferredGroups => [
    for (final name
        in settings.get(preferredGroupsSetting).split(RegExp('[,，;；、]')))
      if (name.trim().isNotEmpty) name.trim(),
  ];

  /// A resource search starts with the preferred groups selected.
  bool get onlyPreferredGroups => settings.get(onlyPreferredGroupsSetting);

  /// Release groups resource searches have found, with how many releases,
  /// suggested when adding a preferred group.
  Map<String, int> get seenGroups => {
    for (final MapEntry(:key, :value) in object(
      settings.get(seenGroupsSetting),
    ).entries)
      if (value is num) key: value.toInt(),
  };

  /// Counts the groups credited on a search's releases, keeping the 300 seen
  /// most.
  Future<void> recordGroups(Iterable<String> groups) async {
    final counts = seenGroups;
    for (final group in groups) {
      counts[group] = (counts[group] ?? 0) + 1;
    }
    final kept = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    await settings.set(seenGroupsSetting, Map.fromEntries(kept.take(300)));
  }

  /// mpv `hwdec`: `auto`, `auto-copy` (decoded frames copied back to memory,
  /// for drivers whose direct output misbehaves) or `no`.
  String get hardwareDecoding => settings.get(hardwareDecodingSetting);

  /// Anime4K shaders: `off`, `fast` or `quality`.
  String get superResolution => settings.get(superResolutionSetting);

  /// The chain super-resolution turns back on with.
  String get superResolutionChain => settings.get(superResolutionChainSetting);
  bool get skipOpening => settings.get(skipOpeningSetting);
  bool get skipEnding => settings.get(skipEndingSetting);

  /// Each subject keeps the source last played, ahead of the global
  /// priority, until another one is played.
  bool get rememberSource => settings.get(rememberSourceSetting);

  /// Playing an episode starts caching the next aired one from the same
  /// source family.
  bool get cacheNext => settings.get(cacheNextSetting);

  /// Autoplay, the next episode and caching it pass over recaps and
  /// programmes about the show (总集篇, 特番).
  bool get skipExtras => settings.get(skipExtrasSetting);
  Future<void> setHardwareDecoding(String value) =>
      settings.set(hardwareDecodingSetting, value);
  Future<void> setSuperResolution(String value) async {
    if (value != 'off') {
      await settings.set(superResolutionChainSetting, value);
    }
    await settings.set(superResolutionSetting, value);
  }

  Future<void> setSkipOpening(bool value) =>
      settings.set(skipOpeningSetting, value);
  Future<void> setSkipEnding(bool value) =>
      settings.set(skipEndingSetting, value);
  Future<void> setRememberSource(bool value) =>
      settings.set(rememberSourceSetting, value);
  Future<void> setCacheNext(bool value) =>
      settings.set(cacheNextSetting, value);
  Future<void> setSkipExtras(bool value) =>
      settings.set(skipExtrasSetting, value);
  Future<void> setSubtitleLanguage(String value) =>
      settings.set(subtitleLanguageSetting, value);
  Future<void> setAudioLanguage(String value) =>
      settings.set(audioLanguageSetting, value);
  Future<void> setAiringPriority(String value) =>
      settings.set(airingPrioritySetting, value);
  Future<void> setCompletedPriority(String value) =>
      settings.set(completedPrioritySetting, value);
  Future<void> setPreferredGroups(List<String> value) =>
      settings.set(preferredGroupsSetting, value.join(', '));
  Future<void> setOnlyPreferredGroups(bool value) =>
      settings.set(onlyPreferredGroupsSetting, value);
  Future<void> setAutoplay(bool value) => settings.set(autoplaySetting, value);
  Future<void> setAutoMarkWatched(bool value) =>
      settings.set(autoMarkWatchedSetting, value);
}

String languageCodes(String preference) => switch (preference) {
  'chs' => 'chs,sc,zh-hans,zh-cn,zho,chi,zh',
  'cht' => 'cht,tc,zh-hant,zh-tw,zh-hk,zho,chi,zh',
  'ja' => 'jpn,ja',
  'zh' => 'zho,chi,zh,zh-cn,zh-tw',
  _ => '',
};

final _simplified = RegExp(r'简|簡|simplified|chs|\bsc\b|\bgb\b|\.sc\b|\.chs\b');
final _traditional = RegExp(r'繁|traditional|cht|\btc\b|big5|\.tc\b|\.cht\b');
final _japanese = RegExp(r'日|japanese|jpn|\bja\b');
final _chinese = RegExp(r'中|国|國|chinese|chi|zho');

int languageScore(String preference, String? language, String? title) {
  if (preference == 'auto') return 0;
  final code = (language ?? '').toLowerCase();
  final text = (title ?? '').toLowerCase();
  final simplified = _simplified.hasMatch(text);
  final traditional = _traditional.hasMatch(text);
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
  } else if (preference == 'ja' && _japanese.hasMatch(text)) {
    score += 50;
  } else if (preference == 'zh' && _chinese.hasMatch(text)) {
    score += 50;
  }
  return score;
}
