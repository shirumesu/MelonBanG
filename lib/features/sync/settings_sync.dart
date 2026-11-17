import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/error_message.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../../core/settings.dart';
import '../../integrations/melon_api/source_rules.dart' show melonApiOrigin;
import 'settings_merge.dart';

export 'settings_merge.dart' show SettingConflict;

enum SettingsSyncStatus {
  /// Turned off on this device.
  off,

  /// Waits for a Bangumi sign-in.
  signedOut,
  idle,
  syncing,

  /// Settings changed differently here and elsewhere; [SettingsSync.conflicts]
  /// waits for the user to pick, and syncing pauses until then.
  conflict,
  failed,
}

/// One kind of data in the synced document, by key: the settings, or the
/// subscriptions and per-show records. Keys a part does not own, or a part
/// turned off on this device, pass through the cloud copy untouched.
abstract interface class SyncPart {
  /// Whether this device syncs the part now.
  bool get enabled;
  bool owns(String key);

  /// This device's values, as JSON by key.
  Future<Map<String, Object?>> values();

  /// Saves values that arrived by sync, null removing one.
  Future<void> apply(Map<String, Object?> changes);

  /// Fires when this device changes something the part syncs.
  Stream<void> get changes;

  /// Whether [key]'s object merges as a whole rather than field by field.
  bool atomic(String key);

  /// Settles a conflict without asking: true for the cloud's value, false
  /// for this device's, null to ask the user.
  bool? preferRemote(SettingConflict conflict);

  /// Reads what [label] and [describe] need for [conflicts] before the
  /// user is asked, such as the titles of the shows they are about.
  Future<void> prepare(List<SettingConflict> conflicts);

  /// What a conflicting value is called, and how its values read.
  String label(SettingConflict conflict);
  String describe(SettingConflict conflict, Object? value);
}

/// The synced settings, as a [SyncPart].
class SettingsPart implements SyncPart {
  SettingsPart(this.settings);
  final Settings settings;
  @override
  bool get enabled => true;
  @override
  bool owns(String key) =>
      (settings.familyOf(key)?.sync ?? settings.declaration(key)?.sync) ==
      SettingSync.synced;
  @override
  Future<Map<String, Object?>> values() async => settings.syncedValues();
  @override
  Future<void> apply(Map<String, Object?> changes) =>
      settings.applySynced(changes);
  @override
  Stream<void> get changes => settings.localChanges;
  @override
  bool atomic(String key) => false;
  @override
  bool? preferRemote(SettingConflict conflict) => null;
  @override
  Future<void> prepare(List<SettingConflict> conflicts) async {}
  @override
  String label(SettingConflict conflict) =>
      settings.labelOf(conflict.key, conflict.field);
  @override
  String describe(SettingConflict conflict, Object? value) =>
      settings.describe(conflict.key, conflict.field, value);
}

/// Keeps the synced settings (and, when turned on, the subscriptions and
/// per-show records) the same on every device signed in to the same
/// Bangumi account, through Melon API.
///
/// Each sync reads the cloud copy, merges it three ways with the copy this
/// device last agreed on ([mergeSettings]), applies the result here and
/// uploads it if it differs. Uploads name the revision they were based on;
/// when another device got in first, the merge runs again on its copy.
///
/// One account is expected to be used on one device at a time, so it syncs
/// when the app starts, on sign-in, and as soon as something synced changes
/// here; nothing polls. A change is kept here whether or not the upload
/// works; a failed one is retried with the next sync.
class SettingsSync extends ChangeNotifier {
  SettingsSync({
    required this.api,
    required this.settings,
    required this.token,
    required this.userId,
    required Stream<void> accountChanges,
    List<SyncPart> parts = const [],
    this.origin = melonApiOrigin,
  }) : parts = [SettingsPart(settings), ...parts] {
    _subscriptions = [
      accountChanges.listen((_) => _accountChanged()),
      for (final part in this.parts)
        part.changes.listen((_) {
          if (part.enabled) _changed();
        }),
    ];
  }

  static const enabledSetting = BoolSetting(
    'sync-settings',
    true,
    sync: SettingSync.local,
  );

  /// The copy this device and the cloud last agreed on: `user`, `rev`,
  /// `data` and `at` (milliseconds).
  static const baseSetting = JsonSetting(
    'sync-settings-base',
    sync: SettingSync.local,
  );

  final ApiClient api;
  final Settings settings;
  final List<SyncPart> parts;

  /// Melon API, or a local copy of it in tests.
  final String origin;

  /// The Bangumi access token; throws while signed out.
  final Future<String> Function() token;

  /// The signed-in Bangumi user, null while signed out.
  final String? Function() userId;

  /// Told when a sync this device's change or the user started fails; one
  /// at startup only shows in Settings.
  void Function(String message)? onFailed;

  late final List<StreamSubscription<void>> _subscriptions;
  Timer? _timer;
  Future<void>? _running;
  bool _again = false, _closed = false, _report = false;
  String? _lastUser;

  SettingsSyncStatus status = SettingsSyncStatus.off;
  String? error;

  /// Settings waiting for the user to pick a side.
  List<SettingConflict> get conflicts => _pending?.merge.conflicts ?? const [];
  ({SettingsMerge merge, _Remote remote})? _pending;

  bool get enabled => settings.get(enabledSetting);

  /// When this device last agreed with the cloud.
  DateTime? get syncedAt {
    final base = _base;
    if (base == null || base['user'] != userId()) return null;
    final at = base['at'];
    return at is num ? DateTime.fromMillisecondsSinceEpoch(at.toInt()) : null;
  }

  Json? get _base => switch (settings.get(baseSetting)) {
    final Map<String, dynamic> value => value,
    _ => null,
  };

  SyncPart _partOf(String key) =>
      parts.firstWhere((part) => part.owns(key), orElse: () => parts.first);

  String labelOf(SettingConflict conflict) =>
      _partOf(conflict.key).label(conflict);
  String describe(SettingConflict conflict, Object? value) =>
      _partOf(conflict.key).describe(conflict, value);

  /// Syncs once, as the app starts.
  void start() {
    _lastUser = userId();
    _refreshStatus();
    _schedule();
  }

  Future<void> setEnabled(bool value) async {
    await settings.set(enabledSetting, value);
    _pending = null;
    _refreshStatus();
    if (value) await syncNow();
  }

  /// Turns [part] on again after it was off: what this device and the cloud
  /// agreed on back then no longer holds, so its keys merge as on a first
  /// sync, keeping what either side has rather than removing anything.
  Future<void> forgetBaseOf(SyncPart part) => forgetBase(part.owns);

  /// [forgetBaseOf] for the [keys] alone.
  Future<void> forgetBase(bool Function(String key) keys) async {
    final base = _base;
    if (base == null) return;
    final data = _map(base['data'])..removeWhere((key, _) => keys(key));
    // Without the revision the next sync reads the whole cloud copy: the
    // base no longer is it, so an unchanged answer would lose the part.
    await settings.set(baseSetting, {
      for (final MapEntry(:key, :value) in base.entries)
        if (key != 'rev') key: value,
      'data': data,
    });
  }

  /// Syncs now, after any sync already running; a failure is reported.
  Future<void> syncNow() {
    _timer?.cancel();
    _report = true;
    return _start();
  }

  /// Settles [conflicts]: the ids in [useRemote] take the cloud's value, the
  /// rest keep this device's, then syncing carries on.
  Future<void> resolve(Set<String> useRemote) async {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    status = SettingsSyncStatus.syncing;
    notifyListeners();
    try {
      if (!await _finish(pending.merge.resolve(useRemote), pending.remote)) {
        await _sync();
      }
      if (_pending != null) {
        status = SettingsSyncStatus.conflict;
        notifyListeners();
        return;
      }
      _settled();
    } catch (failure) {
      _failed(failure, report: true);
    }
  }

  /// Something synced changed here: upload it now. Changes made together
  /// (one save writing two settings) go up together.
  void _changed() {
    _report = true;
    _schedule();
  }

  void _accountChanged() {
    final user = userId();
    if (user == _lastUser) return;
    _lastUser = user;
    _pending = null;
    _refreshStatus();
    _schedule();
  }

  void _refreshStatus() {
    final next = !enabled
        ? SettingsSyncStatus.off
        : userId() == null
        ? SettingsSyncStatus.signedOut
        : _pending != null
        ? SettingsSyncStatus.conflict
        : status == SettingsSyncStatus.off ||
              status == SettingsSyncStatus.signedOut
        ? SettingsSyncStatus.idle
        : status;
    if (next == status) return;
    status = next;
    if (next != SettingsSyncStatus.failed) error = null;
    notifyListeners();
  }

  void _schedule() {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer(Duration.zero, () => unawaited(_start()));
  }

  Future<void> _start() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      final report = _report;
      _report = false;
      if (_closed || !enabled || userId() == null || _pending != null) {
        _refreshStatus();
        return;
      }
      status = SettingsSyncStatus.syncing;
      notifyListeners();
      try {
        await _sync();
        if (_pending != null) {
          status = SettingsSyncStatus.conflict;
          notifyListeners();
          return;
        }
        _settled();
      } catch (failure) {
        _failed(failure, report: report || _report);
        return;
      }
    } while (_again && !_closed);
  }

  void _settled() {
    if (_closed) return;
    status = SettingsSyncStatus.idle;
    error = null;
    notifyListeners();
  }

  void _failed(Object failure, {required bool report}) {
    if (_closed) return;
    status = SettingsSyncStatus.failed;
    error = errorMessage(failure);
    notifyListeners();
    if (report) onFailed?.call(error!);
  }

  /// The values of the parts this device syncs.
  Future<Map<String, Object?>> _local() async => {
    for (final part in parts)
      if (part.enabled) ...await part.values(),
  };

  bool _owned(String key) =>
      parts.any((part) => part.enabled && part.owns(key));

  Map<String, Object?> _ownedOf(Map<String, Object?> values) => {
    for (final MapEntry(:key, :value) in values.entries)
      if (_owned(key)) key: value,
  };

  Future<void> _sync() async {
    final user = userId()!;
    for (var attempt = 0; attempt < 3; attempt++) {
      final base = _base?['user'] == user ? _base : null;
      final baseData = _map(base?['data']);
      final remote = await _download(
        knownRev: base?['rev'],
        baseData: baseData,
      );
      if (userId() != user) throw StateError('账号已经切换');
      final found = mergeSettings(
        base: _ownedOf(baseData),
        local: await _local(),
        remote: _ownedOf(remote.data),
        atomic: (key) => _partOf(key).atomic(key),
      );
      // Conflicts a part settles itself, such as the later of two places
      // in an episode, never ask.
      final settled = {
        for (final conflict in found.conflicts)
          conflict.id: ?_partOf(conflict.key).preferRemote(conflict),
      };
      final merge = SettingsMerge(
        found.resolve({
          for (final MapEntry(:key, :value) in settled.entries)
            if (value) key,
        }),
        [
          for (final conflict in found.conflicts)
            if (!settled.containsKey(conflict.id)) conflict,
        ],
      );
      if (merge.conflicts.isNotEmpty) {
        for (final part in parts) {
          await part.prepare([
            for (final conflict in merge.conflicts)
              if (part.owns(conflict.key)) conflict,
          ]);
        }
        _pending = (merge: merge, remote: remote);
        return;
      }
      if (await _finish(merge.merged, remote)) return;
    }
    throw StateError('云端设置一直在变化，稍后再试');
  }

  /// Applies [merged] here and uploads it against [remote]'s revision.
  /// Returns false when another device uploaded first: [remote] becomes the
  /// base and the caller merges again with the newer copy.
  Future<bool> _finish(Map<String, Object?> merged, _Remote remote) async {
    final user = userId();
    if (user == null) throw StateError('请先登录 Bangumi');
    final local = await _local();
    final changes = {
      for (final key in {...local.keys, ...merged.keys})
        if (!sameJson(local[key], merged[key])) key: merged[key],
    };
    for (final part in parts) {
      if (!part.enabled) continue;
      final own = {
        for (final MapEntry(:key, :value) in changes.entries)
          if (part.owns(key)) key: value,
      };
      if (own.isNotEmpty) await part.apply(own);
    }
    // What this device does not sync (a part turned off here, a setting
    // this version does not know) stays in the cloud copy as it was.
    final upload = {
      for (final MapEntry(:key, :value) in remote.data.entries)
        if (!_owned(key)) key: value,
      ...await _local(),
    };
    if (sameJson(upload, remote.data)) {
      await _remember(user, remote.rev, remote.data);
      return true;
    }
    final response = await api.send(
      Uri.parse('$origin/v1/sync/settings'),
      method: 'PUT',
      body: {'data': upload},
      headers: {
        'Authorization': 'Bearer ${await token()}',
        'If-Match': '"${remote.rev}"',
      },
      acceptedStatuses: const {412},
    );
    if (response.statusCode == 412) {
      // Merged into this device already: the old cloud copy is now what
      // both agree on, and the newer one merges against it.
      await _remember(user, remote.rev, remote.data);
      return false;
    }
    final saved = _Remote.fromJson(_decode(response.bodyBytes));
    await _remember(user, saved.rev, upload);
    return true;
  }

  Future<_Remote> _download({
    required Object? knownRev,
    required Map<String, Object?> baseData,
  }) async {
    final response = await api.send(
      Uri.parse('$origin/v1/sync/settings'),
      headers: {
        'Authorization': 'Bearer ${await token()}',
        if (knownRev is num) 'If-None-Match': '"${knownRev.toInt()}"',
      },
      acceptedStatuses: const {304},
    );
    if (response.statusCode == 304) {
      return _Remote((knownRev as num).toInt(), baseData);
    }
    return _Remote.fromJson(_decode(response.bodyBytes));
  }

  Future<void> _remember(String user, int rev, Map<String, Object?> data) =>
      settings.set(baseSetting, {
        'user': user,
        'rev': rev,
        'data': data,
        'at': DateTime.now().millisecondsSinceEpoch,
      });

  static Json _decode(List<int> bytes) =>
      object(jsonDecode(utf8.decode(bytes)));

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? {for (final e in value.entries) '${e.key}': e.value} : {};

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}

class _Remote {
  const _Remote(this.rev, this.data);
  factory _Remote.fromJson(Json value) => _Remote(
    number(value['rev'] ?? 0).toInt(),
    SettingsSync._map(value['data']),
  );
  final int rev;
  final Map<String, Object?> data;
}
