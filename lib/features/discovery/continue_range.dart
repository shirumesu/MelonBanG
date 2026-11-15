import 'package:flutter/foundation.dart';

import '../../core/settings.dart';

import '../../domain/episode_release.dart';

/// Which shows the home page's 继续观看 lists, by when they air.
enum ContinueRange implements Labeled {
  all('全部'),
  season('当季'),
  twoSeasons('近两季');

  const ContinueRange(this.label);
  @override
  final String label;

  /// The first day a show must air on or after to be listed; null for all.
  DateTime? from(DateTime now) => switch (this) {
    all => null,
    season => seasonStart(now),
    twoSeasons => seasonStart(
      seasonStart(now).subtract(const Duration(days: 1)),
    ),
  };
}

/// The saved [ContinueRange].
class ContinuePreference extends ChangeNotifier {
  ContinuePreference(this._settings) {
    _settings.watch([setting.key], notifyListeners);
  }
  final Settings _settings;

  static const setting = EnumSetting(
    'continueRange',
    ContinueRange.values,
    ContinueRange.twoSeasons,
    sync: SettingSync.synced,
    label: '外观 › 首页继续观看',
  );

  ContinueRange get value => _settings.get(setting);

  Future<void> set(ContinueRange value) => _settings.set(setting, value);
}
