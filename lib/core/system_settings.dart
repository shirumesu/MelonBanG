import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// The proxy servers the operating system is set to, as `host:port`.
class SystemProxy {
  const SystemProxy({this.http, this.https, this.exceptions = const []});

  /// Used for plain HTTP; null when the system sends it directly.
  final String? http;

  /// Used for HTTPS; null when the system sends it directly.
  final String? https;

  /// Hosts the system sends directly, in the system's own notation
  /// (`*.local`, `192.168.*`, `169.254/16`, `<local>`).
  final List<String> exceptions;

  bool get enabled => http != null || https != null;
}

/// Reads appearance and network settings of the operating system: macOS
/// through the runner's `org.melonbang/system` channel, Windows from the
/// current user's registry.
abstract final class SystemSettings {
  static const _channel = MethodChannel('org.melonbang/system');

  /// The system accent colour, or null when it cannot be read.
  static Future<Color?> accentColor() async {
    if (Platform.isMacOS) {
      final value = await _channel.invokeMethod<int>('accentColor');
      return value == null ? null : Color(value);
    }
    // ABGR, as DWM stores it.
    final value = _Registry.dword(
      r'Software\Microsoft\Windows\DWM',
      'AccentColor',
    );
    if (value == null) return null;
    return Color.fromARGB(
      0xff,
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
    );
  }

  /// The system's manual proxy configuration; automatic configuration
  /// scripts (PAC) are not evaluated.
  static Future<SystemProxy> proxy() async {
    if (Platform.isWindows) return _windowsProxy();
    final value = await _channel.invokeMapMethod<String, Object?>('proxy');
    if (value == null) return const SystemProxy();
    return SystemProxy(
      http: value['http'] as String?,
      https: value['https'] as String?,
      exceptions: [
        for (final item in value['exceptions'] as List? ?? const []) '$item',
      ],
    );
  }

  static SystemProxy _windowsProxy() {
    const key = r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    if (_Registry.dword(key, 'ProxyEnable') != 1) return const SystemProxy();
    final server = _Registry.string(key, 'ProxyServer')?.trim() ?? '';
    if (server.isEmpty) return const SystemProxy();
    String? http, https;
    if (server.contains('=')) {
      // Per protocol: "http=host:port;https=host:port;socks=host:port".
      for (final part in server.split(';')) {
        final pair = part.split('=');
        if (pair.length != 2) continue;
        final scheme = pair[0].trim().toLowerCase();
        final address = pair[1].trim();
        if (address.isEmpty) continue;
        if (scheme == 'http') http = address;
        if (scheme == 'https') https = address;
      }
    } else {
      http = https = server;
    }
    return SystemProxy(
      http: http,
      https: https,
      exceptions: (_Registry.string(key, 'ProxyOverride') ?? '')
          .split(';')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }
}

typedef _RegGetValueNative = Int32 Function(
  IntPtr,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Uint32,
  Pointer<Uint32>,
  Pointer<Void>,
  Pointer<Uint32>,
);
typedef _RegGetValueDart = int Function(
  int,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Uint32>,
  Pointer<Void>,
  Pointer<Uint32>,
);

/// Values under HKEY_CURRENT_USER.
abstract final class _Registry {
  // (HKEY)(ULONG_PTR)(LONG)0x80000001: sign-extended on 64-bit Windows.
  static const _currentUser = -0x7fffffff;
  static const _dword = 0x10, _string = 0x02;
  static final _get = DynamicLibrary.open('advapi32.dll')
      .lookupFunction<_RegGetValueNative, _RegGetValueDart>('RegGetValueW');

  static int? dword(String key, String name) => using((arena) {
    final data = arena<Uint32>();
    final size = arena<Uint32>()..value = 4;
    final status = _get(
      _currentUser,
      key.toNativeUtf16(allocator: arena),
      name.toNativeUtf16(allocator: arena),
      _dword,
      nullptr,
      data.cast(),
      size,
    );
    return status == 0 ? data.value : null;
  });

  static String? string(String key, String name) => using((arena) {
    final path = key.toNativeUtf16(allocator: arena);
    final value = name.toNativeUtf16(allocator: arena);
    final size = arena<Uint32>();
    if (_get(_currentUser, path, value, _string, nullptr, nullptr, size) != 0) {
      return null;
    }
    final data = arena<Uint8>(size.value);
    if (_get(_currentUser, path, value, _string, nullptr, data.cast(), size) !=
        0) {
      return null;
    }
    return data.cast<Utf16>().toDartString();
  });
}
