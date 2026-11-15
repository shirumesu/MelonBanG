import 'dart:async';

import '../../core/json.dart';
import '../../core/settings.dart';
import '../../core/store.dart';
import '../danmaku/danmaku_repository.dart';
import '../playback/play_selection.dart';
import '../playback/playback_library.dart';
import '../subscriptions/subscription_controller.dart';
import 'settings_sync.dart';

/// The subscriptions and what this device remembers per show (the source
/// last played, the danmaku match picked by hand, where each episode was
/// left), synced together with the settings.
///
/// A subscription arriving from another device does not cache here until
/// the user says so ([onArrived]); its cached files and book stay with the
/// device that made them.
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

  /// Told of subscriptions that came from another device, waiting for the
  /// user to say whether this device caches them too.
  void Function(List<Subscription> arrived)? onArrived;

  @override
  bool get enabled => true;

  @override
  bool owns(String key) =>
      key.startsWith(_subscription) ||
      key.startsWith(_source) ||
      key.startsWith(_follow) ||
      key.startsWith(_progress);

  /// A place in an episode goes with its time and length.
  @override
  bool atomic(String key) => key.startsWith(_progress);

  /// The place saved later wins: it is where the user last stopped.
  @override
  bool? preferRemote(SettingConflict conflict) {
    if (!conflict.key.startsWith(_progress)) return null;
    num at(Object? value) => switch (object(value)['at']) {
      final num at => at,
      _ => 0,
    };
    return at(conflict.remote) > at(conflict.local);
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<Map<String, Object?>> values() async => {
    for (final MapEntry(:key, :value) in subscriptions.synced.entries)
      '$_subscription$key': value,
    for (final MapEntry(:key, :value) in (await store.entries(
      PlaySelectionRepository.rememberedScope,
    )).entries)
      '$_source$key': value,
    for (final MapEntry(:key, :value) in (await store.entries(
      DanmakuRepository.followScope,
    )).entries)
      '$_follow$key': value,
    ...await _places(),
  };

  /// Each episode's place with when it was saved, which orders 继续观看.
  Future<Map<String, Object?>> _places() async {
    final saved = await store.entries(PlaybackLibrary.progressScope);
    final times = await store.updatedAt(PlaybackLibrary.progressScope);
    return {
      for (final MapEntry(:key, :value) in saved.entries)
        '$_progress$key': {
          ...value,
          'at': times[key]?.millisecondsSinceEpoch ?? 0,
        },
    };
  }

  @override
  Future<void> apply(Map<String, Object?> changes) async {
    final arrived = <Subscription>[];
    for (final MapEntry(:key, :value) in changes.entries) {
      final json = value == null ? null : object(value);
      if (key.startsWith(_subscription)) {
        final id = int.tryParse(key.substring(_subscription.length));
        if (id == null) continue;
        if (await subscriptions.adopt(id, json)) {
          arrived.add(subscriptions.subscriptions[id]!);
        }
      } else if (key.startsWith(_source)) {
        final id = int.tryParse(key.substring(_source.length));
        if (id != null) await selection.adoptRemembered(id, json);
      } else if (key.startsWith(_progress)) {
        final id = key.substring(_progress.length);
        if (json == null) {
          await store.remove(PlaybackLibrary.progressScope, id);
        } else {
          final at = json.remove('at');
          await store.put(
            PlaybackLibrary.progressScope,
            id,
            json,
            updated: at is num
                ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
                : null,
          );
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
    if (arrived.isNotEmpty) onArrived?.call(arrived);
  }

  @override
  String label(SettingConflict conflict) {
    final key = conflict.key;
    if (key.startsWith(_progress)) {
      final id = int.tryParse(key.substring(_progress.length).split(':').first);
      final title = subscriptions.subscriptions[id]?.title ?? '番剧 $id';
      return '$title › 播放位置';
    }
    if (key.startsWith(_subscription)) {
      final id = int.tryParse(key.substring(_subscription.length));
      final title =
          subscriptions.subscriptions[id]?.title ??
          '${object(conflict.remote)['title'] ?? '番剧 $id'}';
      return switch (conflict.field) {
        'filter' => '订阅 › $title › 筛选',
        null => '订阅 › $title',
        final field => '订阅 › $title › $field',
      };
    }
    if (key.startsWith(_source)) {
      final id = int.tryParse(key.substring(_source.length));
      final title = subscriptions.subscriptions[id]?.title ?? '番剧 $id';
      return '$title › 记住的来源';
    }
    final id = int.tryParse(key.substring(_follow.length).split(':').first);
    final title = subscriptions.subscriptions[id]?.title ?? '番剧 $id';
    return '$title › 手动匹配的弹幕';
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
      if (conflict.field != null) return describeValue(value);
      return '${object(value)['label'] ?? '另一个来源'}';
    }
    if (conflict.field != null) return describeValue(value);
    return switch (object(value)['number']) {
      final num number => '按第 ${number.toInt()} 话的匹配',
      _ => '另一个匹配',
    };
  }
}
