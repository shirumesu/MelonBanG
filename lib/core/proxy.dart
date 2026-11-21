import 'dart:io';

import 'package:flutter/foundation.dart';

import 'system_settings.dart';
import 'settings.dart';

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

  /// `user:password`, percent-encoded as in the address.
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
      if ('@'.allMatches(value).length > 1) {
        throw const FormatException('用户名或密码里的 @ 请写成 %40');
      }
      throw const FormatException('地址格式不正确，例如 127.0.0.1:7890');
    }
    // A parsed address leaves out HTTP's default port 80 even when written,
    // so whether one was given is read from the text.
    final authority = value.substring(value.indexOf('://') + 3).split('/')[0];
    if (!RegExp(r':\d+$').hasMatch(authority) ||
        uri.port <= 0 ||
        uri.port > 65535) {
      throw const FormatException('请填写端口，例如 127.0.0.1:7890');
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw const FormatException('代理地址不能带路径');
    }
    final server = ProxyServer(uri.host, uri.port, userInfo: uri.userInfo);
    if (server.userInfo.isNotEmpty) {
      // Dart's proxy directive takes the account as it is, split at the
      // first colon, and separates proxies with semicolons.
      final (user, password) = server._credentials;
      if (user.isEmpty || password.isEmpty) {
        throw const FormatException(
          '账号需要同时填写用户名和密码，例如 http://用户名:密码@127.0.0.1:7890',
        );
      }
      if (user.contains(':')) {
        throw const FormatException('用户名不能包含冒号');
      }
      if ('$user$password'.contains(';')) {
        throw const FormatException('用户名和密码不能包含分号');
      }
    }
    return server;
  }

  /// The user name and password, decoded.
  (String, String) get _credentials {
    final colon = userInfo.indexOf(':');
    String decode(String part) {
      try {
        return Uri.decodeComponent(part);
      } on ArgumentError {
        return part;
      }
    }

    return colon < 0
        ? (decode(userInfo), '')
        : (
            decode(userInfo.substring(0, colon)),
            decode(userInfo.substring(colon + 1)),
          );
  }

  String get _hostPort => '${host.contains(':') ? '[$host]' : host}:$port';

  /// The proxy as Dart's [HttpClient.findProxy] names it, with the account
  /// decoded: Dart sends it as written.
  String get directive {
    if (userInfo.isEmpty) return 'PROXY $_hostPort';
    final (user, password) = _credentials;
    return 'PROXY $user:$password@$_hostPort';
  }

  /// The proxy as mpv's `http-proxy` option takes it; FFmpeg decodes the
  /// percent-encoded account itself.
  String get url => 'http://${userInfo.isEmpty ? '' : '$userInfo@'}$_hostPort';

  @override
  String toString() => '$host:$port';
}

/// Routes the app's HTTP requests and online playback through the chosen
/// proxy. Every `HttpClient` created after [install] asks it per request,
/// so changing the setting applies to the next connection without
/// recreating clients. BitTorrent peers connect directly.
class NetworkProxy extends ChangeNotifier {
  NetworkProxy(this.settings);
  final Settings settings;

  /// This device's network: never synced. The address can hold a password.
  static const modeSetting = EnumSetting(
    'network-proxy-mode',
    ProxyMode.values,
    ProxyMode.off,
    sync: SettingSync.local,
  );
  static const addressSetting = StringSetting(
    'network-proxy-address',
    '',
    sync: SettingSync.local,
  );

  ProxyMode get mode => settings.get(modeSetting);

  /// The custom proxy address as typed.
  String get address => settings.get(addressSetting);

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
    await settings.set(modeSetting, value);
    if (value == ProxyMode.system) await refreshSystem();
    notifyListeners();
  }

  /// Saves a custom address; throws a [FormatException] for an invalid one.
  Future<void> setAddress(String value) async {
    ProxyServer.parse(value);
    await settings.set(addressSetting, value.trim());
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
  /// `192.168.*` and IPv4 ranges such as `169.254/16`, `172.16.0.0/12` or
  /// `10.0.0.5/32`, which hold only addresses, not names.
  static bool _excepted(String rule, String host) {
    final pattern = rule.trim().toLowerCase();
    final name = host.toLowerCase();
    if (pattern.isEmpty) return false;
    if (pattern == '<local>') return !name.contains('.');
    final cidr = RegExp(
      r'^(\d{1,3}(?:\.\d{1,3}){0,3})/(\d{1,2})$',
    ).firstMatch(pattern);
    if (cidr != null) {
      final address = InternetAddress.tryParse(name);
      final bits = int.parse(cidr[2]!);
      // Octets left out are zero: 169.254/16 is 169.254.0.0/16.
      final network = [...cidr[1]!.split('.').map(int.parse), 0, 0, 0].take(4);
      if (address == null ||
          address.type != InternetAddressType.IPv4 ||
          bits > 32 ||
          network.any((octet) => octet > 255)) {
        return false;
      }
      int value(Iterable<int> octets) =>
          octets.fold(0, (value, octet) => value << 8 | octet);
      final mask = (0xffffffff << (32 - bits)) & 0xffffffff;
      return (value(address.rawAddress) & mask) == (value(network) & mask);
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
