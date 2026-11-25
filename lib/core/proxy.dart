import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'network_routes.dart';
import 'system_settings.dart';
import 'settings.dart';

export 'network_routes.dart';

/// How requests find their way out. There is no "off": automatic detection
/// connects direct when it finds no proxy, and a saved `off` reads as
/// automatic.
enum ProxyMode {
  auto('自动检测'),
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
        // A literal % that starts no escape is part of the password.
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

/// What automatic mode found, looked for in this order.
enum AutoRoute {
  /// Not looked yet: requests go direct meanwhile.
  detecting,

  /// The system proxy is set: requests follow it as [ProxyMode.system].
  system,

  /// A TUN adapter takes every connection, so direct ones reach it too.
  tun,

  /// A proxy app listens on one of its usual ports without being made the
  /// system proxy.
  local,

  /// None of these.
  direct,
}

/// Routes the app's HTTP requests and online playback through the chosen
/// proxy. Every `HttpClient` made after [initialize] asks it per request, so
/// a changed setting applies to the next connection; `RoutedClient`s also
/// send a site direct once it connects only that way. BT peers go direct.
class NetworkProxy extends ChangeNotifier {
  NetworkProxy(this.settings) : routes = NetworkRoutes(settings);
  final Settings settings;

  /// Sites the proxy cannot reach, sent direct.
  final NetworkRoutes routes;

  /// The proxy the app's clients route by, set by [initialize].
  static NetworkProxy? get installed => _installed;
  static NetworkProxy? _installed;

  /// This device's network: never synced. The address can hold a password.
  static const modeSetting = EnumSetting(
    'network-proxy-mode',
    ProxyMode.values,
    ProxyMode.auto,
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

  /// What automatic mode found the last time it looked, and the local proxy
  /// when that is what it found.
  AutoRoute _autoRoute = AutoRoute.detecting;
  ProxyServer? _local;
  Future<void>? _refreshing;

  /// The custom server, or null while [address] is invalid.
  ProxyServer? get custom {
    try {
      return ProxyServer.parse(address);
    } on FormatException {
      return null;
    }
  }

  /// Starts routing requests, then looks for the proxy. A local port slow
  /// to answer holds the window back no more than a second; requests sent
  /// before it answers go direct.
  Future<void> initialize() async {
    _installed = this;
    HttpOverrides.global = _ProxyOverrides(this);
    await Future.any([
      refresh(),
      Future<void>.delayed(const Duration(seconds: 1)),
    ]);
  }

  /// Rereads the system proxy and, in automatic mode, looks again for a TUN
  /// and a local proxy: any of them can change while the app runs.
  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    final next = await SystemSettings.proxy();
    var changed =
        next.http != system.http ||
        next.https != system.https ||
        !listEquals(next.exceptions, system.exceptions);
    system = next;
    if (mode == ProxyMode.auto) {
      final (route, local) = next.enabled
          ? (AutoRoute.system, null)
          : await _detect();
      changed |= route != _autoRoute || '$local' != '$_local';
      _autoRoute = route;
      _local = local;
    }
    if (changed) notifyListeners();
  }

  Future<void> setMode(ProxyMode value) async {
    await settings.set(modeSetting, value);
    notifyListeners();
    if (value == ProxyMode.system || value == ProxyMode.auto) await refresh();
  }

  /// The host a TUN's fake address and a local proxy's tunnel are tried
  /// with: the one the app needs most.
  static const _probeHost = 'api.bgm.tv';

  /// Where proxy apps listen by default, the most common first: Clash and
  /// Mihomo, Clash Verge, v2rayN (mixed, then HTTP), NekoBox, Hiddify,
  /// v2rayA, Shadowsocks, ShadowsocksX-NG, Qv2ray and Surge.
  static const _localPorts = [
    7890,
    7897,
    10808,
    10809,
    2080,
    12334,
    20171,
    1080,
    1087,
    8889,
    6152,
  ];

  /// Addresses a detected local proxy is not used for: the LAN.
  static const _privateRanges = [
    '<local>',
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '169.254.0.0/16',
  ];

  static Future<(AutoRoute, ProxyServer?)> _detect() async {
    final (tun, local) = await (_tunActive(), _localProxy()).wait;
    if (tun) return (AutoRoute.tun, null);
    if (local != null) return (AutoRoute.local, local);
    return (AutoRoute.direct, null);
  }

  /// Clash, Mihomo and sing-box in TUN mode bring up an adapter of their
  /// own, which Mihomo addresses in 198.18.0.0/15; with fake-ip they also
  /// answer every name with an address in that range.
  static Future<bool> _tunActive() async {
    bool fake(InternetAddress address) =>
        _excepted('198.18.0.0/15', address.address);
    final adapters = await NetworkInterface.list();
    if (adapters.any(
      (adapter) =>
          _tunAdapter.hasMatch(adapter.name) || adapter.addresses.any(fake),
    )) {
      return true;
    }
    try {
      final addresses = await InternetAddress.lookup(_probeHost)
          .timeout(const Duration(seconds: 2));
      return addresses.any(fake);
    } on SocketException {
      // Offline or without DNS: no fake answer either.
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// The names Mihomo, Clash and sing-box's Windows and Linux builds give
  /// their adapter; macOS names every tunnel utun, its own included.
  static final _tunAdapter = RegExp(
    r'^(mihomo|meta|clash|sing-?box|singbox_tun|wintun)$',
    caseSensitive: false,
  );

  static Future<ProxyServer?> _localProxy() async {
    final answers = await Future.wait(_localPorts.map(_answersAsProxy));
    for (final (i, port) in _localPorts.indexed) {
      if (answers[i]) return ProxyServer('127.0.0.1', port);
    }
    return null;
  }

  /// Whether a proxy listens on [port] here: it opens a tunnel when asked,
  /// which any other server listening there refuses.
  static Future<bool> _answersAsProxy(int port) async {
    final Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 500),
      );
    } on SocketException {
      return false;
    }
    // A write the port refuses shows below as no reply.
    socket.done.ignore();
    try {
      socket.write(
        'CONNECT $_probeHost:443 HTTP/1.1\r\n'
        'Host: $_probeHost:443\r\n\r\n',
      );
      final reply = await socket.first.timeout(const Duration(seconds: 3));
      return RegExp(r'^HTTP/1\.[01] 200').hasMatch(latin1.decode(reply));
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } on StateError {
      // Closed without a word.
      return false;
    } finally {
      socket.destroy();
    }
  }

  /// Saves a custom address; throws a [FormatException] for an invalid one.
  Future<void> setAddress(String value) async {
    ProxyServer.parse(value);
    await settings.set(addressSetting, value.trim());
    notifyListeners();
  }

  /// The server requests to [uri] go through, or null for a direct one: the
  /// proxy setting's, except for a site learned to connect only direct.
  ProxyServer? serverFor(Uri uri) =>
      routes.sendsDirect(uri.host) ? null : configuredFor(uri);

  /// The server the proxy setting names for [uri], whatever was learned.
  ProxyServer? configuredFor(Uri uri) {
    if (_loopback(uri.host)) return null;
    switch (mode) {
      case ProxyMode.custom:
        return custom;
      case ProxyMode.system:
        return _systemServer(uri);
      case ProxyMode.auto:
        return switch ((_autoRoute, _local)) {
          (AutoRoute.system, _) => _systemServer(uri),
          (AutoRoute.local, final server?)
              when !_privateRanges.any((rule) => _excepted(rule, uri.host)) =>
            server,
          _ => null,
        };
    }
  }

  ProxyServer? _systemServer(Uri uri) {
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

  /// What the current setting means, for the settings page.
  String describe() => switch (mode) {
    ProxyMode.custom => custom == null ? '代理地址无效，暂时直接连接' : '经由 ${custom!}',
    ProxyMode.system =>
      !system.enabled ? '系统未设置代理，直接连接' : '经由 ${system.https ?? system.http}',
    ProxyMode.auto => switch ((_autoRoute, _local)) {
      (AutoRoute.detecting, _) => '正在检测代理',
      (AutoRoute.system, _) => '经由系统代理 ${system.https ?? system.http}',
      (AutoRoute.tun, _) => '检测到 TUN 模式，直接连接',
      (AutoRoute.local, final server?) => '经由本机代理 $server',
      _ => '未检测到代理，直接连接',
    },
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
    final cidr = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){0,3})/(\d{1,2})$')
        .firstMatch(pattern);
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
