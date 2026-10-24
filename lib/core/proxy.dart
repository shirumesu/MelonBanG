import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'system_settings.dart';

enum ProxyMode {
  off('不使用代理'),
  system('使用系统代理'),
  custom('自定义 HTTP 代理');

  const ProxyMode(this.label);
  final String label;
}

/// An HTTP proxy server; `user:password@` is optional.
class ProxyServer {
  const ProxyServer(this.host, this.port, {this.userInfo = ''});
  final String host;
  final int port;
  final String userInfo;

  /// `host:port`, `http://host:port` or `http://user:pass@host:port`; throws
  /// a [FormatException] with the reason otherwise.
  static ProxyServer parse(String text) {
    var value = text.trim();
    if (value.isEmpty) throw const FormatException('请填写代理地址');
    final scheme = RegExp(r'^([a-z][a-z0-9+.-]*)://').firstMatch(value);
    if (scheme != null && scheme[1] != 'http') {
      throw const FormatException('只支持 HTTP 代理，例如 http://127.0.0.1:7890');
    }
    if (scheme == null) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('地址格式不正确，例如 127.0.0.1:7890');
    }
    if (!uri.hasPort || uri.port <= 0 || uri.port > 65535) {
      throw const FormatException('请填写端口，例如 127.0.0.1:7890');
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw const FormatException('代理地址不能带路径');
    }
    return ProxyServer(uri.host, uri.port, userInfo: uri.userInfo);
  }

  String get _authority =>
      '${userInfo.isEmpty ? '' : '$userInfo@'}'
      '${host.contains(':') ? '[$host]' : host}:$port';

  /// The proxy as Dart's [HttpClient.findProxy] names it.
  String get directive => 'PROXY $_authority';

  /// The proxy as mpv's `http-proxy` option takes it.
  String get url => 'http://$_authority';

  @override
  String toString() => '$host:$port';
}

/// Routes the app's HTTP requests and online playback through the chosen
/// proxy. Every `HttpClient` created after [install] asks it per request,
/// so changing the setting applies to the next connection without
/// recreating clients. BitTorrent peers connect directly.
class NetworkProxy extends ChangeNotifier {
  NetworkProxy(this.preferences);
  final SharedPreferences preferences;

  ProxyMode get mode =>
      ProxyMode.values.asNameMap()[preferences.getString(
        'network-proxy-mode',
      )] ??
      ProxyMode.system;

  /// The custom proxy address as typed.
  String get address => preferences.getString('network-proxy-address') ?? '';

  SystemProxy system = const SystemProxy();

  /// The custom server, or null while [address] is invalid.
  ProxyServer? get custom {
    try {
      return ProxyServer.parse(address);
    } on FormatException {
      return null;
    }
  }

  /// Reads the system proxy and starts routing requests.
  Future<void> initialize() async {
    await refreshSystem();
    HttpOverrides.global = _ProxyOverrides(this);
  }

  /// Rereads the system proxy, which can change while the app runs.
  Future<void> refreshSystem() async {
    final next = await SystemSettings.proxy();
    final changed =
        next.http != system.http ||
        next.https != system.https ||
        !listEquals(next.exceptions, system.exceptions);
    system = next;
    if (changed) notifyListeners();
  }

  Future<void> setMode(ProxyMode value) async {
    await preferences.setString('network-proxy-mode', value.name);
    if (value == ProxyMode.system) await refreshSystem();
    notifyListeners();
  }

  /// Saves a custom address; throws a [FormatException] for an invalid one.
  Future<void> setAddress(String value) async {
    ProxyServer.parse(value);
    await preferences.setString('network-proxy-address', value.trim());
    notifyListeners();
  }

  /// The server requests to [uri] go through, or null for a direct one.
  ProxyServer? serverFor(Uri uri) {
    if (_loopback(uri.host)) return null;
    switch (mode) {
      case ProxyMode.off:
        return null;
      case ProxyMode.custom:
        return custom;
      case ProxyMode.system:
        if (system.exceptions.any((rule) => _excepted(rule, uri.host))) {
          return null;
        }
        final address = uri.scheme == 'https'
            ? system.https ?? system.http
            : system.http ?? system.https;
        if (address == null) return null;
        try {
          return ProxyServer.parse(address);
        } on FormatException {
          return null;
        }
    }
  }

  /// What the current setting means, for the settings page.
  String describe() => switch (mode) {
    ProxyMode.off => '直接连接',
    ProxyMode.custom => custom == null ? '代理地址无效，暂时直接连接' : '经由 ${custom!}',
    ProxyMode.system =>
      !system.enabled ? '系统未设置代理，直接连接' : '经由 ${system.https ?? system.http}',
  };

  static bool _loopback(String host) {
    final name = host.toLowerCase();
    if (name == 'localhost' || name.endsWith('.localhost')) return true;
    final address = InternetAddress.tryParse(
      name.startsWith('[') ? name.substring(1, name.length - 1) : name,
    );
    return address?.isLoopback ?? false;
  }

  /// Windows and macOS exception notation: `<local>`, `*.domain`, `domain`,
  /// `192.168.*` and `169.254/16`.
  static bool _excepted(String rule, String host) {
    final pattern = rule.trim().toLowerCase();
    final name = host.toLowerCase();
    if (pattern.isEmpty) return false;
    if (pattern == '<local>') return !name.contains('.');
    final cidr = RegExp(r'^(\d+(?:\.\d+){0,3})/(\d+)$').firstMatch(pattern);
    if (cidr != null) {
      final octets = int.parse(cidr[2]!) ~/ 8;
      final prefix = cidr[1]!.split('.').take(octets).join('.');
      return prefix.isNotEmpty && name.startsWith('$prefix.');
    }
    if (pattern.contains('*')) {
      final expression = RegExp(
        '^${pattern.split('*').map(RegExp.escape).join('.*')}\$',
      );
      return expression.hasMatch(name);
    }
    return name == pattern || name.endsWith('.$pattern');
  }
}

class _ProxyOverrides extends HttpOverrides {
  _ProxyOverrides(this.proxy);
  final NetworkProxy proxy;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (uri) => proxy.serverFor(uri)?.directive ?? 'DIRECT';
}
