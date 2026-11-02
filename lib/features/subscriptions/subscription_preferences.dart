import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/json.dart';
import '../../domain/transfer.dart';
import 'subscription.dart';

export 'subscription.dart' show RevisionPolicy;

/// What closing the window does while subscriptions run.
enum CloseAction {
  background('留在后台'),
  quit('退出');

  const CloseAction(this.label);
  final String label;
}

/// When a subscription ends by itself; what it cached stays.
enum AutoUnsubscribe {
  never('永不'),
  unwatched('超过三周未观看'),
  finished('完结后');

  const AutoUnsubscribe(this.label);
  final String label;
}

/// Settings shared by every subscription, and the filter the next one
/// starts from.
class SubscriptionPreferences extends ChangeNotifier {
  SubscriptionPreferences(this._preferences);
  final SharedPreferences _preferences;

  /// Null until the first close asks.
  CloseAction? get closeAction => _choice(CloseAction.values, 'closeAction');

  CacheMethod get method =>
      _choice(const [
        CacheMethod.bt,
        CacheMethod.pikpak,
      ], 'subscriptionMethod') ??
      CacheMethod.bt;

  RevisionPolicy get revisions =>
      _choice(RevisionPolicy.values, 'subscriptionRevisions') ??
      RevisionPolicy.skip;

  AutoUnsubscribe get autoUnsubscribe =>
      _choice(AutoUnsubscribe.values, 'subscriptionAutoEnd') ??
      AutoUnsubscribe.finished;

  /// Whether a new subscription also caches the episodes aired before it,
  /// as the last one offered did.
  bool get cacheEarlier => _preferences.getBool('subscriptionEarlier') ?? false;

  /// The filter last subscribed with; 1080p 简体 by the preferred groups,
  /// or by any group while none are set, before the first.
  SubscriptionFilter defaultFilter(List<String> preferredGroups) {
    final saved = _preferences.getString('subscriptionFilter');
    if (saved != null) {
      try {
        return SubscriptionFilter.fromJson(object(jsonDecode(saved)));
      } on FormatException {
        // A damaged value falls back to the first default.
      }
    }
    return SubscriptionFilter(
      preferred: preferredGroups.isNotEmpty,
      qualities: const {'1080p'},
      languages: const {'简体'},
    );
  }

  Future<void> setCloseAction(CloseAction value) =>
      _set('closeAction', value.name);
  Future<void> setMethod(CacheMethod value) =>
      _set('subscriptionMethod', value.name);
  Future<void> setRevisions(RevisionPolicy value) =>
      _set('subscriptionRevisions', value.name);
  Future<void> setAutoUnsubscribe(AutoUnsubscribe value) =>
      _set('subscriptionAutoEnd', value.name);
  Future<void> setCacheEarlier(bool value) async {
    await _preferences.setBool('subscriptionEarlier', value);
    notifyListeners();
  }

  Future<void> setDefaultFilter(SubscriptionFilter value) =>
      _set('subscriptionFilter', jsonEncode(value.toJson()));

  T? _choice<T extends Enum>(List<T> values, String key) {
    final name = _preferences.getString(key);
    return values.where((value) => value.name == name).firstOrNull;
  }

  Future<void> _set(String key, String value) async {
    await _preferences.setString(key, value);
    notifyListeners();
  }
}
