import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'labeled.dart';

export 'labeled.dart';

/// Whether a setting follows the account to other devices.
enum SettingSync {
  /// A preference that means the same on another device: uploaded and
  /// merged by settings sync.
  synced,

  /// Tied to this device (paths, proxy, ports, hardware), or state the app
  /// keeps for itself (recent searches, the last volume): never uploaded.
  local,
}

/// One persisted setting: its key, its value when unset, and whether it
/// syncs. Every setting is declared once next to the feature that owns it
/// and listed in the app's catalog; [Settings] refuses keys it was not given.
///
/// Credentials never live here: they are in the keychain ([Credentials]).
sealed class Setting<T> {
  const Setting(this.key, this.fallback, {required this.sync, this.label});

  final String key;

  /// The value while nothing is saved.
  final T fallback;
  final SettingSync sync;

  /// What the setting is called where it is changed, shown when a sync
  /// conflict asks which side to keep. Required for synced settings.
  final String? label;

  T read(SharedPreferences storage);
  Future<void> write(SharedPreferences storage, T value);

  /// The saved value as JSON for sync; null while unset.
  Object? exported(SharedPreferences storage) =>
      storage.get(key) == null ? null : _export(storage);
  Object? _export(SharedPreferences storage);

  /// Saves [value] from sync, or forgets the setting for null. Returns
  /// whether the value was of this setting's type.
  Future<bool> imported(SharedPreferences storage, Object? value) async {
    if (value == null) {
      await storage.remove(key);
      return true;
    }
    return _import(storage, value);
  }

  Future<bool> _import(SharedPreferences storage, Object value);

  /// A synced [value] as the conflict dialog shows it.
  String describe(Object? value) => describeValue(value);
}

/// A JSON value as people read it: 开 / 关, numbers, text, or a count.
String describeValue(Object? value) => switch (value) {
  null => '默认',
  true => '开',
  false => '关',
  final num number when number == number.roundToDouble() => '${number.toInt()}',
  final num number => number.toStringAsFixed(2),
  final String text when text.isEmpty => '（空）',
  final String text => text,
  final List<Object?> list => '${list.length} 项',
  _ => '另一组值',
};

class BoolSetting extends Setting<bool> {
  const BoolSetting(
    super.key,
    super.fallback, {
    required super.sync,
    super.label,
  });
  @override
  bool read(SharedPreferences storage) => switch (storage.get(key)) {
    final bool value => value,
    _ => fallback,
  };
  @override
  Future<void> write(SharedPreferences storage, bool value) =>
      storage.setBool(key, value);
  @override
  Object? _export(SharedPreferences storage) => read(storage);
  @override
  Future<bool> _import(SharedPreferences storage, Object value) async {
    if (value is! bool) return false;
    await storage.setBool(key, value);
    return true;
  }
}

class IntSetting extends Setting<int> {
  const IntSetting(
    super.key,
    super.fallback, {
    required super.sync,
    super.label,
  });
  @override
  int read(SharedPreferences storage) => switch (storage.get(key)) {
    final int value => value,
    _ => fallback,
  };
  @override
  Future<void> write(SharedPreferences storage, int value) =>
      storage.setInt(key, value);
  @override
  Object? _export(SharedPreferences storage) => read(storage);
  @override
  Future<bool> _import(SharedPreferences storage, Object value) async {
    if (value is! num || value != value.roundToDouble()) return false;
    await storage.setInt(key, value.toInt());
    return true;
  }
}

class DoubleSetting extends Setting<double> {
  const DoubleSetting(
    super.key,
    super.fallback, {
    required super.sync,
    super.label,
  });
  @override
  double read(SharedPreferences storage) => switch (storage.get(key)) {
    final num value => value.toDouble(),
    _ => fallback,
  };
  @override
  Future<void> write(SharedPreferences storage, double value) =>
      storage.setDouble(key, value);
  @override
  Object? _export(SharedPreferences storage) => read(storage);
  @override
  Future<bool> _import(SharedPreferences storage, Object value) async {
    if (value is! num) return false;
    await storage.setDouble(key, value.toDouble());
    return true;
  }
}

class StringSetting extends Setting<String> {
  const StringSetting(
    super.key,
    super.fallback, {
    required super.sync,
    super.label,
    this.valueLabels = const {},
  });

  /// Names of the values offered, as the settings page shows them.
  final Map<String, String> valueLabels;
  @override
  String describe(Object? value) => valueLabels[value] ?? describeValue(value);
  @override
  String read(SharedPreferences storage) => switch (storage.get(key)) {
    final String value => value,
    _ => fallback,
  };
  @override
  Future<void> write(SharedPreferences storage, String value) =>
      storage.setString(key, value);
  @override
  Object? _export(SharedPreferences storage) => read(storage);
  @override
  Future<bool> _import(SharedPreferences storage, Object value) async {
    if (value is! String) return false;
    await storage.setString(key, value);
    return true;
  }
}

/// A choice saved by its enum name; an unknown name reads as [fallback].
class EnumSetting<T extends Enum> extends Setting<T> {
  const EnumSetting(
    super.key,
    this.values,
    super.fallback, {
    required super.sync,
    super.label,
  });
  final List<T> values;
  @override
  String describe(Object? value) {
    final choice = values.where((item) => item.name == value).firstOrNull;
    return switch (choice) {
      final Labeled labeled => labeled.label,
      null => describeValue(value),
      final choice => choice.name,
    };
  }

  @override
  T read(SharedPreferences storage) => readOrNull(storage) ?? fallback;

  /// The saved choice, null while unset or unknown.
  T? readOrNull(SharedPreferences storage) {
    final name = storage.get(key);
    return values.where((value) => value.name == name).firstOrNull;
  }

  @override
  Future<void> write(SharedPreferences storage, T value) =>
      storage.setString(key, value.name);
  @override
  Object? _export(SharedPreferences storage) => storage.get(key);
  @override
  Future<bool> _import(SharedPreferences storage, Object value) async {
    if (value is! String) return false;
    await storage.setString(key, value);
    return true;
  }
}

class StringListSetting extends Setting<List<String>> {
  const StringListSetting(
    super.key,
    super.fallback, {
    required super.sync,
    super.label,
  });
  @override
  List<String> read(SharedPreferences storage) =>
      storage.getStringList(key) ?? fallback;
  @override
  Future<void> write(SharedPreferences storage, List<String> value) =>
      storage.setStringList(key, value);
  @override
  Object? _export(SharedPreferences storage) => read(storage);
  @override
  Future<bool> _import(SharedPreferences storage, Object value) async {
    if (value is! List || value.any((item) => item is! String)) return false;
    await storage.setStringList(key, value.cast<String>());
    return true;
  }
}

/// A JSON object or list saved as text. Sync merges an object field by
/// field; [localFields] stay on this device and keep their value when a
/// synced copy arrives.
class JsonSetting extends Setting<Object?> {
  const JsonSetting(
    String key, {
    Object? fallback,
    required SettingSync sync,
    String? label,
    this.localFields = const {},
    this.fieldLabels = const {},
  }) : super(key, fallback, sync: sync, label: label);
  final Set<String> localFields;

  /// Names of an object's fields for the conflict dialog, by field.
  final Map<String, String> fieldLabels;

  @override
  Object? read(SharedPreferences storage) {
    final text = storage.get(key);
    if (text is! String) return fallback;
    try {
      return jsonDecode(text);
    } on FormatException {
      return fallback;
    }
  }

  @override
  Future<void> write(SharedPreferences storage, Object? value) => value == null
      ? storage.remove(key)
      : storage.setString(key, jsonEncode(value));
  @override
  Object? _export(SharedPreferences storage) => switch (read(storage)) {
    final Map<String, dynamic> map when localFields.isNotEmpty => {
      for (final MapEntry(:key, :value) in map.entries)
        if (!localFields.contains(key)) key: value,
    },
    final value => value,
  };
  @override
  Future<bool> _import(SharedPreferences storage, Object value) async {
    if (value is! Map && value is! List) return false;
    var merged = value;
    if (value is Map && localFields.isNotEmpty) {
      final current = read(storage);
      merged = {
        for (final MapEntry(:key, :value) in value.entries)
          if (!localFields.contains(key)) '$key': value,
        if (current is Map)
          for (final field in localFields)
            if (current.containsKey(field)) field: current[field],
      };
    }
    await storage.setString(key, jsonEncode(merged));
    return true;
  }
}

/// Settings named by a prefix and an id, one per source or episode:
/// `source-enabled-<id>`.
class SettingFamily<T> {
  const SettingFamily(this.prefix, this.make, {required this.sync, this.label});
  final String prefix;
  final Setting<T> Function(String key) make;
  final SettingSync sync;

  /// What the member [id] is called in a sync conflict.
  final String Function(String id)? label;

  Setting<T> of(String id) => make('$prefix$id');

  /// The id of a key in this family, or null.
  String? idOf(String key) =>
      key.startsWith(prefix) ? key.substring(prefix.length) : null;
}

/// Every setting the app saves, behind one [SharedPreferences]: reads and
/// writes go through declared [Setting]s, and listeners learn which keys
/// changed and whether the change came from sync.
class Settings extends ChangeNotifier {
  Settings(
    this.storage, {
    required List<Setting<Object?>> settings,
    List<SettingFamily<Object?>> families = const [],
  }) : _settings = {for (final setting in settings) setting.key: setting},
       _families = List.unmodifiable(families) {
    assert(
      _settings.length == settings.length,
      'A settings key is declared twice',
    );
  }

  final SharedPreferences storage;
  final Map<String, Setting<Object?>> _settings;
  final List<SettingFamily<Object?>> _families;

  /// Keys changed by the latest notification.
  Set<String> changed = const {};

  /// Whether the latest notification came from sync rather than this device.
  bool changedBySync = false;

  final _local = StreamController<Set<String>>.broadcast(sync: true);

  /// Keys of synced settings changed on this device, as they change.
  Stream<Set<String>> get localChanges => _local.stream;

  Iterable<Setting<Object?>> get declared => _settings.values;

  /// The declared setting behind [key], a family member included.
  Setting<Object?>? declaration(String key) {
    if (_settings[key] case final setting?) return setting;
    for (final family in _families) {
      if (family.idOf(key) != null) return family.make(key);
    }
    return null;
  }

  /// The family [key] belongs to, if any.
  SettingFamily<Object?>? familyOf(String key) =>
      _families.where((family) => family.idOf(key) != null).firstOrNull;

  bool _known(Setting<Object?> setting) =>
      _settings.containsKey(setting.key) || familyOf(setting.key) != null;

  T get<T>(Setting<T> setting) {
    assert(_known(setting), 'Undeclared setting ${setting.key}');
    return setting.read(storage);
  }

  bool isSet(Setting<Object?> setting) => storage.get(setting.key) != null;

  Future<void> set<T>(Setting<T> setting, T value) async {
    assert(_known(setting), 'Undeclared setting ${setting.key}');
    await setting.write(storage, value);
    _notify({setting.key}, bySync: false);
  }

  Future<void> remove(Setting<Object?> setting) async {
    assert(_known(setting), 'Undeclared setting ${setting.key}');
    await storage.remove(setting.key);
    _notify({setting.key}, bySync: false);
  }

  bool _synced(String key) =>
      (familyOf(key)?.sync ?? _settings[key]?.sync) == SettingSync.synced;

  void _notify(Set<String> keys, {required bool bySync}) {
    changed = keys;
    changedBySync = bySync;
    notifyListeners();
    if (!bySync) {
      final synced = keys.where(_synced).toSet();
      if (synced.isNotEmpty) _local.add(synced);
    }
  }

  /// Calls [listener] when any of [keys] changes; returns the remover.
  VoidCallback watch(Iterable<String> keys, VoidCallback listener) {
    final watched = keys.toSet();
    void filtered() {
      if (changed.any(watched.contains)) listener();
    }

    addListener(filtered);
    return () => removeListener(filtered);
  }

  /// Like [watch], for every key starting with [prefix].
  VoidCallback watchPrefix(String prefix, VoidCallback listener) {
    void filtered() {
      if (changed.any((key) => key.startsWith(prefix))) listener();
    }

    addListener(filtered);
    return () => removeListener(filtered);
  }

  /// Every synced setting saved on this device, as JSON values by key.
  Map<String, Object?> syncedValues() => {
    for (final setting in _settings.values)
      if (setting.sync == SettingSync.synced)
        setting.key: ?setting.exported(storage),
    for (final key in storage.getKeys())
      if (familyOf(key) case final family?
          when family.sync == SettingSync.synced)
        key: ?family.make(key).exported(storage),
  };

  /// Saves values that arrived by sync, null removing a setting. Keys that
  /// are not synced settings here, or values of the wrong type, are left
  /// alone; returns the keys that were saved.
  Future<Set<String>> applySynced(Map<String, Object?> values) async {
    final applied = <String>{};
    for (final MapEntry(:key, :value) in values.entries) {
      if (!_synced(key)) continue;
      final setting = declaration(key)!;
      if (await setting.imported(storage, value)) applied.add(key);
    }
    if (applied.isNotEmpty) _notify(applied, bySync: true);
    return applied;
  }

  /// What [key] (and its [field], for an object) is called where it is
  /// changed, for a sync conflict.
  String labelOf(String key, [String? field]) {
    if (familyOf(key) case final family?) {
      return family.label?.call(family.idOf(key)!) ?? key;
    }
    final setting = _settings[key];
    if (field != null && setting is JsonSetting) {
      if (setting.fieldLabels[field] case final label?) return label;
    }
    final name = setting?.label ?? key;
    return field == null ? name : '$name › $field';
  }

  @override
  void dispose() {
    _local.close();
    super.dispose();
  }
}
