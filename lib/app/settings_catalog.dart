import 'package:shared_preferences/shared_preferences.dart';

import '../core/proxy.dart';
import '../core/settings.dart';
import '../features/acquisition/source_registry.dart';
import '../features/appearance/appearance.dart';
import '../features/danmaku/danmaku_preferences.dart';
import '../features/discovery/continue_range.dart';
import '../features/discovery/schedule_filter.dart';
import '../features/playback/playback.dart';
import '../features/playback/playback_preferences.dart';
import '../features/subscriptions/subscription_preferences.dart';
import '../features/sync/library_sync.dart';
import '../features/sync/settings_sync.dart';
import '../features/update/app_update.dart';
import '../integrations/transfer/libtorrent.dart';

/// Every setting the app saves. A setting is declared next to the feature
/// that owns it, with whether it syncs, and listed here; [Settings] refuses
/// any key missing from this list, so nothing is saved outside it.
///
/// Not here: credentials (the keychain), where files live (`storage.json`),
/// and per-show data in the database (subscriptions, progress, the source
/// each show last played).
const List<Setting<Object?>> settingsCatalog = [
  // 外观与首页
  ...Appearance.all,
  ContinuePreference.setting,
  SchedulePreference.setting,
  // 播放与资源选择
  ...PlaybackPreferences.all,
  Playback.rateSetting,
  Playback.volumeSetting,
  Playback.mutedSetting,
  // 弹幕
  DanmakuPreferences.displaySetting,
  DanmakuPreferences.filtersSetting,
  // 订阅与下载
  ...SubscriptionPreferences.all,
  LibtorrentTransfer.settingsSetting,
  // 数据源
  SourceRegistry.rulesSetting,
  SourceRegistry.rulesEtagSetting,
  // 网络、更新与本机状态
  NetworkProxy.modeSetting,
  NetworkProxy.addressSetting,
  NetworkRoutes.setting,
  AppUpdate.autoCheckSetting,
  AppUpdate.autoDownloadSetting,
  AppUpdate.betaSetting,
  recentSearchesSetting,
  trackingPosterZoomSetting,
  // 设置同步自己的状态
  SettingsSync.enabledSetting,
  SettingsSync.baseSetting,
  LibrarySync.joinedSetting,
  LibrarySync.subscriptionsSetting,
];

/// Settings named by an id: one switch per source, one place per file.
final List<SettingFamily<Object?>> settingFamilies = [
  SourceRegistry.enabledFamily,
  Playback.progressFamily,
];

/// The title bar's recent searches, newest first: this device's history.
const recentSearchesSetting = StringListSetting(
  'recentSearches',
  [],
  sync: SettingSync.local,
);

/// How many more posters a row of the tracking page holds than standard;
/// the same level is another size on another screen, so it stays here.
const trackingPosterZoomSetting = IntSetting(
  'tracking-poster-zoom',
  0,
  sync: SettingSync.local,
);

Settings openSettings(SharedPreferences preferences) =>
    Settings(preferences, settings: settingsCatalog, families: settingFamilies);
