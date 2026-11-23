import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'json.dart';
import 'settings.dart';

/// Second-level names under which each name is a site of its own:
/// `bgm.com.cn` is a site, `com.cn` is not, and neither is `github.io`.
const _sharedSuffixes = {
  'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'edu.cn', 'ac.cn', //
  'com.tw', 'net.tw', 'org.tw', 'idv.tw', 'com.hk', 'net.hk', 'org.hk',
  'co.jp', 'ne.jp', 'or.jp', 'ac.jp', 'co.kr', 'or.kr',
  'co.uk', 'org.uk', 'ac.uk', 'com.au', 'net.au', 'com.sg', 'co.nz',
  'github.io', 'workers.dev', 'pages.dev', 'vercel.app', 'netlify.app',
};

/// The site [host] belongs to, which a route is remembered for: `lain.bgm.tv`
/// and `api.bgm.tv` are both `bgm.tv`. Addresses stay whole.
String siteOf(String host) {
  final name = host.toLowerCase();
  if (InternetAddress.tryParse(name) != null) return name;
  final labels = name.split('.');
  final keep =
      labels.length > 2 &&
          _sharedSuffixes.contains(labels.sublist(labels.length - 2).join('.'))
      ? 3
      : 2;
  return labels.length <= keep
      ? name
      : labels.sublist(labels.length - keep).join('.');
}

/// Sites the proxy cannot reach that answer directly, learned when a request
/// through the proxy failed to connect and the same request sent direct
/// went through. Every other site goes the way the proxy setting says, so
/// the proxy app's own rules still decide. This device's network: never
/// synced.
class NetworkRoutes extends ChangeNotifier {
  NetworkRoutes(this.settings) {
    for (final MapEntry(:key, :value) in object(
      settings.get(setting),
    ).entries) {
      if (value is int) {
        _direct[key] = DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
    }
  }
  final Settings settings;

  /// Site → when it was found to need a direct connection, in seconds.
  static const setting = JsonSetting(
    'network-direct-sites',
    sync: SettingSync.local,
  );

  /// Kept to the latest this many: a site out of the list costs one failed
  /// attempt to learn again.
  static const limit = 200;

  /// Oldest first.
  final _direct = <String, DateTime>{};

  /// The sites sent direct and when each was learned, oldest first.
  Map<String, DateTime> get direct => Map.unmodifiable(_direct);

  bool sendsDirect(String host) => _direct.containsKey(siteOf(host));

  /// Remembers that [host]'s site connects only direct, or, with [direct]
  /// false, again through the proxy.
  void learn(String host, {required bool direct}) {
    final site = siteOf(host);
    if (_direct.containsKey(site) == direct) return;
    if (direct) {
      _direct[site] = DateTime.now();
      while (_direct.length > limit) {
        _direct.remove(_direct.keys.first);
      }
    } else {
      _direct.remove(site);
    }
    unawaited(_save());
    notifyListeners();
  }

  Future<void> clear() async {
    if (_direct.isEmpty) return;
    _direct.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() => settings.set(setting, {
    for (final MapEntry(:key, :value) in _direct.entries)
      key: value.millisecondsSinceEpoch ~/ 1000,
  });
}
