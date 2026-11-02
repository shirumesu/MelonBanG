import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/episode_release.dart';

/// Which shows the home page's 继续观看 lists, by when they air.
enum ContinueRange {
  all('全部'),
  season('当季'),
  twoSeasons('近两季');

  const ContinueRange(this.label);
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
  ContinuePreference(this._preferences);
  final SharedPreferences _preferences;
  static const _key = 'continueRange';

  ContinueRange get value =>
      ContinueRange.values
          .where((range) => range.name == _preferences.getString(_key))
          .firstOrNull ??
      ContinueRange.all;

  Future<void> set(ContinueRange value) async {
    await _preferences.setString(_key, value.name);
    notifyListeners();
  }
}
