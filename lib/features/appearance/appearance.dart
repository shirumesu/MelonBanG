import 'dart:ui' show Brightness, Color;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/system_settings.dart';

enum ThemeChoice {
  light('浅色'),
  dark('深色'),
  system('跟随系统');

  const ThemeChoice(this.label);
  final String label;
}

/// A theme colour offered in settings.
typedef AccentPreset = ({String id, String name, Color color});

/// The default first; mint is the brand colour.
const accentPresets = <AccentPreset>[
  (id: 'mint', name: '薄荷', color: Color(0xff22b388)),
  (id: 'ocean', name: '海蓝', color: Color(0xff3b82e6)),
  (id: 'grape', name: '葡萄', color: Color(0xff8b6cf0)),
  (id: 'sakura', name: '樱花', color: Color(0xffe8628a)),
  (id: 'orange', name: '橘子', color: Color(0xffef8a2f)),
  (id: 'ink', name: '墨灰', color: Color(0xff6b7a8f)),
];

/// The chosen theme mode, theme colour and whether subject pages take their
/// cover's colour. The system accent is reread when the window regains
/// focus, since it can change while the app runs.
class Appearance extends ChangeNotifier {
  Appearance(this.preferences);
  final SharedPreferences preferences;

  /// Before theme modes there was only a light/dark switch.
  ThemeChoice get mode =>
      ThemeChoice.values.asNameMap()[preferences.getString('theme-mode')] ??
      switch (preferences.getBool('dark')) {
        true => ThemeChoice.dark,
        false => ThemeChoice.light,
        null => ThemeChoice.system,
      };

  /// A preset id, or `system` for the system accent colour.
  String get accent => preferences.getString('theme-accent') ?? 'mint';

  /// Subject details and the player take their cover's colour.
  bool get coverColor => preferences.getBool('theme-cover-color') ?? false;

  /// The system accent colour, once read; null where there is none.
  Color? systemAccent;

  /// The colour the theme is seeded with outside cover-coloured pages.
  Color get seed {
    if (accent == 'system') return systemAccent ?? accentPresets.first.color;
    return accentPresets
        .firstWhere(
          (preset) => preset.id == accent,
          orElse: () => accentPresets.first,
        )
        .color;
  }

  bool dark(Brightness platform) => switch (mode) {
    ThemeChoice.light => false,
    ThemeChoice.dark => true,
    ThemeChoice.system => platform == Brightness.dark,
  };

  Future<void> refreshSystemAccent() async {
    final value = await SystemSettings.accentColor();
    if (value == systemAccent) return;
    systemAccent = value;
    notifyListeners();
  }

  Future<void> setMode(ThemeChoice value) async {
    await preferences.setString('theme-mode', value.name);
    notifyListeners();
  }

  Future<void> setAccent(String value) async {
    await preferences.setString('theme-accent', value);
    if (value == 'system') await refreshSystemAccent();
    notifyListeners();
  }

  Future<void> setCoverColor(bool value) async {
    await preferences.setBool('theme-cover-color', value);
    notifyListeners();
  }
}
