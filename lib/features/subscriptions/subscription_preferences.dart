import 'package:flutter/foundation.dart';

import '../../core/settings.dart';
import '../../domain/resource_title.dart';
import '../../domain/transfer.dart';
import 'subscription.dart';

export 'subscription.dart' show RevisionPolicy;

/// What closing the window does while subscriptions run.
enum CloseAction implements Labeled {
  background('留在后台'),
  quit('退出');

  const CloseAction(this.label);
  @override
  final String label;
}

/// When a subscription ends by itself; what it cached stays.
enum AutoUnsubscribe implements Labeled {
  never('永不'),
  unwatched('超过三周未观看'),
  finished('完结后');

  const AutoUnsubscribe(this.label);
  @override
  final String label;
}

/// Settings shared by every subscription, and the filter the next one
/// starts from.
class SubscriptionPreferences extends ChangeNotifier {
  SubscriptionPreferences(this._settings, {required this.subtitleLanguage}) {
    _settings.watch([for (final setting in all) setting.key], notifyListeners);
  }
  final Settings _settings;

  /// The player's subtitle language, which the first filter selects.
  final String Function() subtitleLanguage;

  /// Staying in the tray is up to each computer.
  static const closeActionSetting = EnumSetting(
    'closeAction',
    CloseAction.values,
    CloseAction.background,
    sync: SettingSync.local,
  );
  static const methodSetting = EnumSetting(
    'subscriptionMethod',
    [CacheMethod.bt, CacheMethod.pikpak],
    CacheMethod.bt,
    sync: SettingSync.synced,
    label: '订阅与缓存 › 缓存到',
  );
  static const revisionsSetting = EnumSetting(
    'subscriptionRevisions',
    RevisionPolicy.values,
    RevisionPolicy.skip,
    sync: SettingSync.synced,
    label: '订阅与缓存 › 修正版',
  );
  static const autoUnsubscribeSetting = EnumSetting(
    'subscriptionAutoEnd',
    AutoUnsubscribe.values,
    AutoUnsubscribe.finished,
    sync: SettingSync.synced,
    label: '订阅与缓存 › 自动取消订阅',
  );

  /// The last answer of the subscribe dialog's checkbox on this device.
  static const cacheEarlierSetting = BoolSetting(
    'subscriptionEarlier',
    false,
    sync: SettingSync.local,
  );

  /// What a new subscription starts from: the filter last subscribed with.
  static const filterSetting = JsonSetting(
    'subscriptionFilter',
    sync: SettingSync.synced,
    label: '订阅 › 新订阅的默认筛选',
  );
  static const all = <Setting<Object?>>[
    closeActionSetting,
    methodSetting,
    revisionsSetting,
    autoUnsubscribeSetting,
    cacheEarlierSetting,
    filterSetting,
  ];

  /// Null until the first close asks.
  CloseAction? get closeAction =>
      closeActionSetting.readOrNull(_settings.storage);

  CacheMethod get method => _settings.get(methodSetting);

  RevisionPolicy get revisions => _settings.get(revisionsSetting);

  AutoUnsubscribe get autoUnsubscribe => _settings.get(autoUnsubscribeSetting);

  /// Whether a new subscription also caches the episodes aired before it,
  /// as the last one offered did.
  bool get cacheEarlier => _settings.get(cacheEarlierSetting);

  /// The filter last subscribed with, without the groups it named: those
  /// were that show's, and another show's groups differ. Naming groups
  /// carries over as the preferred ones while any are set. Before the
  /// first, 1080p in the player's [subtitleLanguage] by the preferred
  /// groups, or by any group while none are set.
  SubscriptionFilter defaultFilter(List<String> preferredGroups) {
    if (_settings.get(filterSetting) case final Map<String, dynamic> saved) {
      try {
        final filter = SubscriptionFilter.fromJson(saved);
        return filter.copyWith(
          groups: const {},
          preferred:
              !filter.smart &&
              preferredGroups.isNotEmpty &&
              (filter.preferred || filter.groups.isNotEmpty),
        );
      } on FormatException {
        // A damaged value falls back to the first default.
      }
    }
    return SubscriptionFilter(
      preferred: preferredGroups.isNotEmpty,
      qualities: const {'1080p'},
      languages: switch (subtitleLanguage()) {
        'cht' => const {'繁体'},
        'ja' => const {resourceBilingual},
        'auto' => const {},
        _ => const {'简体'},
      },
    );
  }

  Future<void> setCloseAction(CloseAction value) =>
      _settings.set(closeActionSetting, value);
  Future<void> setMethod(CacheMethod value) =>
      _settings.set(methodSetting, value);
  Future<void> setRevisions(RevisionPolicy value) =>
      _settings.set(revisionsSetting, value);
  Future<void> setAutoUnsubscribe(AutoUnsubscribe value) =>
      _settings.set(autoUnsubscribeSetting, value);
  Future<void> setCacheEarlier(bool value) =>
      _settings.set(cacheEarlierSetting, value);
  Future<void> setDefaultFilter(SubscriptionFilter value) =>
      _settings.set(filterSetting, value.toJson());
}
