import 'dart:async';

import '../../core/json.dart';
import '../../core/settings.dart';
import '../../core/store.dart';
import '../danmaku/danmaku_repository.dart';
import '../playback/play_selection.dart';
import '../playback/playback_library.dart';
import '../subscriptions/subscription_controller.dart';
import 'settings_sync.dart';

/// What this device does with the subscriptions of the account.
enum SubscriptionSync implements Labeled {
  /// This device's subscriptions stay here and other devices' stay away.
  off('不同步'),

  /// Other devices' subscriptions show here without caching: for a device
  /// used now and then to watch, not to keep a library.
  keep('只同步'),

  /// Other devices' subscriptions cache their new episodes here too: the
  /// default, a device used now and then is set to [keep] by the user.
  cache('同步并缓存');

  const SubscriptionSync(this.label);
  @override
  final String label;
}

/// The subscriptions and what this device remembers per show (the source
/// last played, the danmaku match picked by hand, where each episode was
/// left), synced together with the settings.
///
/// Whether subscriptions sync, and whether those from other devices cache
/// here, is this device's choice ([subscriptionsSetting]); their cached
/// files and book stay with the device that made them.
class LibrarySync implements SyncPart {
  LibrarySync({
    required this.settings,
    required this.store,
    required this.subscriptions,
    required this.selection,
    required this.danmaku,
    required this.playback,
  }) {
    for (final stream in [
      subscriptions.edits.stream,
      selection.rememberedChanges.stream,
      danmaku.followChanges.stream,
    ]) {
      stream.listen((_) => _changes.add(null));
    }
    // A place is saved every few seconds while an episode plays: upload once
    // it has stopped moving for a while, not each time.
    playback.progressChanges.stream.listen((_) {
      _progressTimer?.cancel();
      _progressTimer = Timer(const Duration(seconds: 15), () {
        if (!_changes.isClosed) _changes.add(null);
      });
    });
  }

  /// Whether this device's base already covers these records. Earlier
  /// builds synced them only when turned on; a device that had them off
  /// agreed on a base holding other devices' records as passed through, so
  /// [SettingsSync.forgetBaseOf] runs once before merging them, or they
  /// would read as removed here.
  static const joinedSetting = BoolSetting(
    'sync-library',
    false,
    sync: SettingSync.local,
  );

  static const subscriptionsSetting = EnumSetting(
    'sync-subscriptions',
    SubscriptionSync.values,
    SubscriptionSync.cache,
    sync: SettingSync.local,
  );

  static const _subscription = 'subscription:',
      _source = 'source:',
      _follow = 'danmaku-follow:',
      _progress = 'progress:';

  final Settings settings;
  final AppStore store;
  final SubscriptionController subscriptions;
  final PlaySelectionRepository selection;
  final DanmakuRepository danmaku;
  final PlaybackLibrary playback;
  final _changes = StreamController<void>.broadcast(sync: true);
  Timer? _progressTimer;

  SubscriptionSync get subscriptionSync => settings.get(subscriptionsSetting);

  /// Set by the app once settings sync is built: [SettingsSync.forgetBase].
  late Future<void> Function(bool Function(String key) keys) forgetBase;

  /// Switches what this device does with the account's subscriptions.
  /// Those from other devices follow at once: they cache here or stop, or
  /// leave this device for [SubscriptionSync.off] (what they cached stays).
  /// The other devices keep every subscription either way.
  Future<void> setSubscriptionSync(SubscriptionSync value) async {
    final previous = subscriptionSync;
    if (value == previous) return;
    await settings.set(subscriptionsSetting, value);
    if (value == SubscriptionSync.off) {
      await subscriptions.dropAdopted();
      return;
    }
    await subscriptions.setPaused(
      subscriptions.adoptedIds.toList(),
      value == SubscriptionSync.keep,
    );
    if (previous == SubscriptionSync.off) {
      // While off, the cloud's subscriptions passed through untouched; the
      // copy agreed on then would read those missing here as removed.
      await forgetBase((key) => key.startsWith(_subscription));
      _changes.add(null);
    }
  }

  @override
  bool get enabled => true;

  @override
  bool owns(String key) =>
      (key.startsWith(_subscription) &&
          subscriptionSync != SubscriptionSync.off) ||
      key.startsWith(_source) ||
      key.startsWith(_follow) ||
      key.startsWith(_progress);

  /// Each record is one choice whose fields only make sense together: a
  /// place with its time and length, a source with its site and line, a
  /// danmaku match with its episode.
  @override
  bool atomic(String key) =>
      key.startsWith(_progress) ||
      key.startsWith(_source) ||
      key.startsWith(_follow);

  /// The place saved later wins, as does the source played later: it is
  /// where the user last stopped and what they last chose.
  @override
  bool? preferRemote(SettingConflict conflict) {
    final key = conflict.key;
    if (!key.startsWith(_progress) && !key.startsWith(_source)) return null;
    num at(Object? value) => switch (object(value)['at']) {
      final num at => at,
      _ => 0,
    };
    return at(conflict.remote) > at(conflict.local);
  }

  /// Show titles for conflicts about shows not subscribed here, read from
  /// the cached details by [prepare].
  final _titles = <int, String>{};

  @override
  Future<void> prepare(List<SettingConflict> conflicts) async {
    for (final conflict in conflicts) {
      final id = _subjectOf(conflict.key);
      if (id == null ||
          subscriptions.subscriptions.containsKey(id) ||
          _titles.containsKey(id)) {
        continue;
      }
      if (await playback.catalog.cached(id) case final subject?) {
        _titles[id] = subject.title;
      }
    }
  }

  /// The show a record belongs to; its key starts with the subject id.
  int? _subjectOf(String key) {
    for (final prefix in [_subscription, _source, _follow, _progress]) {
      if (key.startsWith(prefix)) {
        return int.tryParse(key.substring(prefix.length).split(':').first);
      }
    }
    return null;
  }

  String _title(int? id) =>
      subscriptions.subscriptions[id]?.title ?? _titles[id] ?? '番剧 $id';

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<Map<String, Object?>> values() async => {
    if (subscriptionSync != SubscriptionSync.off)
      for (final MapEntry(:key, :value) in subscriptions.synced.entries)
        '$_subscription$key': value,
    ...await _stamped(PlaySelectionRepository.rememberedScope, _source),
    for (final MapEntry(:key, :value) in (await store.entries(
      DanmakuRepository.followScope,
    )).entries)
      '$_follow$key': value,
    ...await _stamped(PlaybackLibrary.progressScope, _progress),
  };

  /// The records of [scope] with when each was saved: a place's time orders
  /// 继续观看, and either settles a conflict for the later one.
  Future<Map<String, Object?>> _stamped(String scope, String prefix) async {
    final saved = await store.entries(scope);
    final times = await store.updatedAt(scope);
    return {
      for (final MapEntry(:key, :value) in saved.entries)
        '$prefix$key': {
          ...value,
          'at': times[key]?.millisecondsSinceEpoch ?? 0,
        },
    };
  }

  /// [json]'s save time, taken out of it.
  DateTime? _takeAt(Json json) => switch (json.remove('at')) {
    final num at => DateTime.fromMillisecondsSinceEpoch(at.toInt()),
    _ => null,
  };

  @override
  Future<void> apply(Map<String, Object?> changes) async {
    for (final MapEntry(:key, :value) in changes.entries) {
      final json = value == null ? null : object(value);
      if (key.startsWith(_subscription)) {
        final id = int.tryParse(key.substring(_subscription.length));
        if (id == null) continue;
        await subscriptions.adopt(
          id,
          json,
          cache: subscriptionSync == SubscriptionSync.cache,
        );
      } else if (key.startsWith(_source)) {
        final id = int.tryParse(key.substring(_source.length));
        if (id == null) continue;
        final at = json == null ? null : _takeAt(json);
        await selection.adoptRemembered(id, json, updated: at);
      } else if (key.startsWith(_progress)) {
        final id = key.substring(_progress.length);
        if (json == null) {
          await store.remove(PlaybackLibrary.progressScope, id);
        } else {
          final at = _takeAt(json);
          await store.put(PlaybackLibrary.progressScope, id, json, updated: at);
        }
      } else if (key.startsWith(_follow)) {
        final id = key.substring(_follow.length);
        if (json == null) {
          await store.remove(DanmakuRepository.followScope, id);
        } else {
          await store.put(DanmakuRepository.followScope, id, json);
        }
      }
    }
  }

  @override
  String label(SettingConflict conflict) {
    final key = conflict.key;
    final id = _subjectOf(key);
    if (key.startsWith(_progress)) return '${_title(id)} › 播放位置';
    if (key.startsWith(_subscription)) {
      final title =
          subscriptions.subscriptions[id]?.title ??
          '${object(conflict.remote)['title'] ?? _title(id)}';
      return switch (conflict.field) {
        'filter' => '订阅 › $title › 筛选',
        null => '订阅 › $title',
        final field => '订阅 › $title › $field',
      };
    }
    if (key.startsWith(_source)) return '${_title(id)} › 记住的来源';
    return '${_title(id)} › 手动匹配的弹幕';
  }

  @override
  String describe(SettingConflict conflict, Object? value) {
    if (value == null) return '没有';
    final key = conflict.key;
    if (key.startsWith(_progress)) {
      final seconds = number(object(value)['positionSeconds']).round();
      return '${seconds ~/ 60} 分 ${seconds % 60} 秒';
    }
    if (key.startsWith(_subscription)) {
      return switch (conflict.field) {
        'filter' => SubscriptionFilter.fromJson(object(value)).label,
        null => SubscriptionFilter.fromJson(
          object(object(value)['filter']),
        ).label,
        _ => describeValue(value),
      };
    }
    if (key.startsWith(_source)) {
      return RememberedSource.fromJson(object(value)).label;
    }
    if (conflict.field != null) return describeValue(value);
    return switch (object(value)['number']) {
      final num number => '按第 ${number.toInt()} 话的匹配',
      _ => '另一个匹配',
    };
  }
}
