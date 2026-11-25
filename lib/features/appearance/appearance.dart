import 'dart:ui' show Brightness, Color;

import 'package:flutter/foundation.dart';

import '../../core/settings.dart';
import '../../core/system_settings.dart';

enum ThemeChoice implements Labeled {
  light('浅色'),
  dark('深色'),
  system('跟随系统');

  const ThemeChoice(this.label);
  @override
  final String label;
}

/// How sizes and speeds are counted: KiB and MiB step by 1024, KB and MB
/// by 1000.
enum ByteUnits implements Labeled {
  binary('KiB、MiB', 1024, ['KiB', 'MiB', 'GiB', 'TiB']),
  decimal('KB、MB', 1000, ['KB', 'MB', 'GB', 'TB']);

  const ByteUnits(this.label, this.base, this.names);
  @override
  final String label;
  final int base;
  final List<String> names;

  /// [bytes] in the largest unit that keeps the number at least 1.
  String format(int bytes) {
    if (bytes < base) return '$bytes B';
    var value = bytes / base;
    var unit = 0;
    while (value >= base && unit < names.length - 1) {
      value /= base;
      unit++;
    }
    return '${value.toStringAsFixed(1)} ${names[unit]}';
  }

  /// A speed of [bytes] per second.
  String rate(int bytes) => '${format(bytes)}/s';
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

/// Theme mode, theme colour, cover-coloured subject pages and byte units.
/// The system accent is reread when the window regains focus, since it can
/// change while the app runs.
class Appearance extends ChangeNotifier {
  Appearance(this.settings) {
    settings.watch([for (final setting in all) setting.key], notifyListeners);
  }
  final Settings settings;

  static const modeSetting = EnumSetting(
    'theme-mode',
    ThemeChoice.values,
    ThemeChoice.light,
    sync: SettingSync.synced,
    label: '外观 › 主题模式',
  );
  static const accentSetting = StringSetting(
    'theme-accent',
    'mint',
    sync: SettingSync.synced,
    label: '外观 › 主题色',
  );
  static const coverColorSetting = BoolSetting(
    'theme-cover-color',
    false,
    sync: SettingSync.synced,
    label: '外观 › 封面取色',
  );
  static const byteUnitsSetting = EnumSetting(
    'byte-units',
    ByteUnits.values,
    ByteUnits.decimal,
    sync: SettingSync.synced,
    label: '外观 › 容量单位',
  );
  static const all = <Setting<Object?>>[
    modeSetting,
    accentSetting,
    coverColorSetting,
    byteUnitsSetting,
  ];

  ThemeChoice get mode => settings.get(modeSetting);

  /// A preset id, or `system` for the system accent colour.
  String get accent => settings.get(accentSetting);

  /// Subject details and the player take their cover's colour.
  bool get coverColor => settings.get(coverColorSetting);

  ByteUnits get byteUnits => settings.get(byteUnitsSetting);

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
    final Color? value;
    try {
      value = await SystemSettings.accentColor();
    } on Exception {
      // Read on every focus; a failed read keeps the colour last read.
      return;
    }
    if (value == systemAccent) return;
    systemAccent = value;
    notifyListeners();
  }

  Future<void> setMode(ThemeChoice value) => settings.set(modeSetting, value);

  Future<void> setAccent(String value) async {
    if (value == 'system') await refreshSystemAccent();
    await settings.set(accentSetting, value);
  }

  Future<void> setCoverColor(bool value) =>
      settings.set(coverColorSetting, value);

  Future<void> setByteUnits(ByteUnits value) =>
      settings.set(byteUnitsSetting, value);
}
