import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final _chinese = RegExp(r'[一-鿿]');

/// The text shown to the user for [error]. The app's own failures carry a
/// Chinese message, shown as is; system and library failures, whose text is
/// an English diagnostic, are named by kind instead.
String errorMessage(Object error) {
  String? own(String? message) =>
      message != null && _chinese.hasMatch(message) ? message : null;
  switch (error) {
    case String():
      return error;
    case SocketException() ||
        TlsException() ||
        HttpException() ||
        http.ClientException():
      final reason = networkFailure(error);
      return reason == null ? '网络连接失败' : '网络连接失败：$reason';
    case FileSystemException(:final osError):
      return osError == null ? '文件读写失败' : '文件读写失败：${osError.message.trim()}';
    case StateError(:final message):
      if (own(message) case final text?) return text;
    case FormatException(:final message):
      return own(message) ?? '返回的数据无法识别';
    case TimeoutException(:final message):
      return own(message) ?? '请求超时';
    case Error():
      break;
    default:
      return '$error'.replaceFirst(RegExp(r'^Exception: '), '');
  }
  debugPrint('Unexpected error: $error');
  return '出现意外错误（${error.runtimeType}）';
}

/// Why a connection failed, when its error names a known cause.
String? networkFailure(Object error) {
  final text = '$error';
  if (text.contains('Failed host lookup') || text.contains('nodename')) {
    return '无法解析域名';
  }
  if (text.contains('Connection refused')) return '连接被拒绝';
  if (text.contains('Connection reset') || text.contains('Connection closed')) {
    return '连接被重置';
  }
  if (text.contains('HandshakeException') || text.contains('CERTIFICATE')) {
    return 'TLS 握手失败';
  }
  if (text.contains('Proxy') || text.contains('proxy')) return '代理连接失败';
  return null;
}
