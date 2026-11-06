import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

final _chinese = RegExp(r'[一-鿿]');

/// A failure of the app's own whose [userMessage] is written for the user;
/// its `toString` may keep diagnostics, which are never shown.
abstract interface class UserFacingError implements Exception {
  String get userMessage;
}

/// The text shown to the user for [error]: one plain sentence saying what
/// went wrong, without addresses, status codes or library diagnostics. The
/// app's own failures carry a Chinese message; system and library failures
/// are named by kind.
String errorMessage(Object error) => _clean(switch (error) {
  String() => error,
  UserFacingError() => error.userMessage,
  TimeoutException(:final message) => _own(message) ?? '连接超时，请检查网络后重试',
  HttpException(:final message) when _own(message) != null => message,
  SocketException() ||
  TlsException() ||
  HttpException() ||
  http.ClientException() => switch (networkFailure(error)) {
    final reason? => '网络连接失败：$reason',
    null => '网络连接失败，请检查网络后重试',
  },
  FileSystemException(:final osError) => fileFailure(osError?.errorCode),
  FormatException(:final message) => _own(message) ?? '收到的数据无法识别',
  StateError(:final message) => _own(message) ?? _unexpected,
  ArgumentError(:final message) => _own('$message') ?? _unexpected,
  PlatformException() || MissingPluginException() => '系统功能暂时无法使用',
  Error() => _unexpected,
  _ => _own('$error'.replaceFirst(RegExp(r'^Exception: '), '')) ?? _unexpected,
});

const _unexpected = '出了点问题，请重试';

String? _own(String? message) =>
    message != null && _chinese.hasMatch(message) ? message : null;

/// [message] without the addresses and status codes diagnostics carry.
String _clean(String message) {
  final text = message
      .replaceAll(RegExp(r'\s*[（(]\s*HTTP\s*\d{3}\s*[)）]'), '')
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAll(RegExp(r'[：:，,\s]+$'), '')
      .trim();
  return text.isEmpty ? _unexpected : text;
}

/// A file operation's failure by its system error code, on macOS, Linux and
/// Windows.
String fileFailure(int? code) => switch (code) {
  28 || 39 || 112 => '磁盘空间不足',
  1 || 5 || 13 => '没有权限读写这个位置',
  2 || 3 => '文件不存在或已被移动',
  _ => '文件读写失败',
};

/// Why a connection failed, when its error names a known cause.
String? networkFailure(Object error) {
  final text = '$error';
  if (text.contains('Failed host lookup') || text.contains('nodename')) {
    return '无法解析域名';
  }
  if (text.contains('Connection refused')) return '连接被拒绝';
  if (text.contains('Connection reset') || text.contains('Connection closed')) {
    return '连接被中断';
  }
  if (text.contains('HandshakeException') || text.contains('CERTIFICATE')) {
    return '安全连接失败';
  }
  if (text.contains('Proxy') || text.contains('proxy')) return '代理连接失败';
  return null;
}

/// What an mpv or FFmpeg error line means for the user.
String playerFailure(String line) {
  final text = line.toLowerCase();
  if (RegExp(r'\b(403|404|410)\b|forbidden|not found').hasMatch(text)) {
    return '播放地址已失效';
  }
  if (text.contains('failed to open') ||
      text.contains('connection') ||
      text.contains('timed out') ||
      text.contains('network')) {
    return '无法打开视频，可能是网络或来源出了问题';
  }
  if (text.contains('codec') ||
      text.contains('decoder') ||
      text.contains('demux') ||
      text.contains('invalid data')) {
    return '视频格式无法解码';
  }
  return _own(line) ?? '视频播放出错';
}

/// What a libtorrent task error means for the user.
String torrentFailure(String message) {
  final text = message.toLowerCase();
  if (text.contains('no space') || text.contains('disk full')) {
    return '磁盘空间不足，腾出空间后可以继续';
  }
  if (text.contains('permission') || text.contains('access is denied')) {
    return '没有权限写入缓存位置';
  }
  if (text.contains('no such file') ||
      text.contains('cannot find') ||
      text.contains('not found')) {
    return '缓存文件不见了，可以重新下载';
  }
  if (text.contains('torrent') && text.contains('invalid')) {
    return '种子文件无效';
  }
  return _own(message) ?? '下载出错，可以重试';
}
