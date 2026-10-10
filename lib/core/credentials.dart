import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

abstract interface class Credentials {
  Future<String?> read(String key, {bool allowInteraction = true});
  Future<void> write(String key, String? value);
}

Credentials platformCredentials(String directory) {
  if (Platform.isWindows) {
    return CachedCredentials(WindowsCredentials(directory));
  }
  if (Platform.isMacOS) return CachedCredentials(MacOSCredentials(directory));
  throw UnsupportedError('Unsupported credential platform');
}

class CredentialInteractionRequired implements Exception {
  const CredentialInteractionRequired();
  @override
  String toString() => '登录凭据需要授权，请在账户设置中点击「解锁同步」后重试。';
}

/// Cache successful reads only, and serialize reads/writes for each credential.
class CachedCredentials implements Credentials {
  CachedCredentials(this.storage);
  final Credentials storage;
  final _values = <String, String?>{};
  final _pending = <String, Future<void>>{};

  Future<T> _serial<T>(String key, Future<T> Function() operation) {
    final previous = _pending[key] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending[key] = settled;
    settled.then((_) {
      if (identical(_pending[key], settled)) _pending.remove(key);
    });
    return result;
  }

  @override
  Future<String?> read(String key, {bool allowInteraction = true}) => _serial(
    key,
    () async {
      if (_values.containsKey(key)) return _values[key];
      final value = await storage.read(key, allowInteraction: allowInteraction);
      _values[key] = value;
      return value;
    },
  );

  @override
  Future<void> write(String key, String? value) => _serial(key, () async {
    await storage.write(key, value);
    _values[key] = value;
  });
}

/// Store account tokens in the login keychain, isolated by data directory.
class MacOSCredentials implements Credentials {
  MacOSCredentials(String directory)
    : _service =
          'org.melonbang.credentials.${sha256.convert(utf8.encode(p.normalize(p.absolute(directory))))}';

  static const _channel = MethodChannel('org.melonbang/credentials');
  final String _service;

  @override
  Future<String?> read(String key, {bool allowInteraction = true}) async {
    try {
      return await _channel.invokeMethod<String>('read', {
        'service': _service,
        'key': key,
        'allowInteraction': allowInteraction,
      });
    } on PlatformException catch (e) {
      if (e.code == 'keychain_-25308' ||
          (!allowInteraction && e.code == 'keychain_-25293')) {
        throw const CredentialInteractionRequired();
      }
      rethrow;
    }
  }

  @override
  Future<void> write(String key, String? value) => _channel.invokeMethod<void>(
    'write',
    {'service': _service, 'key': key, 'value': value},
  );
}

final class _DataBlob extends Struct {
  @Uint32()
  external int length;
  external Pointer<Uint8> data;
}

typedef _CryptNative = Int32 Function(
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_DataBlob>,
);
typedef _CryptDart = int Function(
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_DataBlob>,
);

/// Encrypt credentials using the current Windows user's DPAPI identity.
class WindowsCredentials implements Credentials {
  WindowsCredentials(this.directory);
  final String directory;
  final _writes = <String, Future<void>>{};
  Uint8List _crypt(Uint8List bytes, bool decrypt) {
    final dll = DynamicLibrary.open('crypt32.dll');
    final call = dll.lookupFunction<_CryptNative, _CryptDart>(
      decrypt ? 'CryptUnprotectData' : 'CryptProtectData',
    );
    final localFree = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('LocalFree');
    final input = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    input.ref.length = bytes.length;
    input.ref.data = calloc<Uint8>(bytes.length);
    input.ref.data.asTypedList(bytes.length).setAll(0, bytes);
    try {
      if (call(input, nullptr, nullptr, nullptr, nullptr, 1, output) == 0) {
        throw StateError('Windows 凭据加密操作失败');
      }
      return Uint8List.fromList(output.ref.data.asTypedList(output.ref.length));
    } finally {
      if (output.ref.data != nullptr) localFree(output.ref.data.cast());
      calloc.free(input.ref.data);
      calloc.free(input);
      calloc.free(output);
    }
  }

  File _file(String key) {
    if (!RegExp(r'^[a-z_]+$').hasMatch(key)) throw ArgumentError.value(key);
    return File(p.join(directory, '$key.bin'));
  }

  @override
  Future<String?> read(String key, {bool allowInteraction = true}) async {
    await _writes[key];
    final file = _file(key);
    return await file.exists()
        ? utf8.decode(_crypt(await file.readAsBytes(), true))
        : null;
  }

  @override
  Future<void> write(String key, String? value) {
    final previous = _writes[key] ?? Future<void>.value();
    late final Future<void> writing;
    writing = previous
        .catchError((Object _) {})
        .then((_) {
          return _write(key, value);
        })
        .whenComplete(() {
          if (identical(_writes[key], writing)) _writes.remove(key);
        });
    return _writes[key] = writing;
  }

  Future<void> _write(String key, String? value) async {
    final file = _file(key);
    if (value == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsBytes(
      _crypt(Uint8List.fromList(utf8.encode(value)), false),
      flush: true,
    );
    await pending.rename(file.path);
  }
}
