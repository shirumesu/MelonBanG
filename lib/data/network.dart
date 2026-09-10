import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'json.dart';

class ApiException implements Exception {
  const ApiException(this.status, this.host);
  final int status;
  final String host;
  @override
  String toString() => '$host 请求失败（HTTP $status）';
}

class ApiClient {
  ApiClient({http.Client? client, this.timeout = const Duration(seconds: 20)})
    : client = client ?? http.Client();
  final Duration timeout;
  final _active = <Completer<void>>{};
  bool _closed = false;
  final http.Client client;
  Future<http.Response> send(
    Uri uri, {
    String method = 'GET',
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    if (_closed) throw StateError('网络服务已关闭');
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abort.future,
    );
    request.headers.addAll({
      'Accept': 'application/json',
      'User-Agent': 'Melonbang/1.0 (Flutter; ${Platform.operatingSystem})',
      ...headers,
    });
    if (body is Map<String, String>) {
      request.bodyFields = body;
    } else if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    _active.add(abort);
    try {
      final receiving = client.send(request).then(http.Response.fromStream);
      final response = await receiving.timeout(
        timeout,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException('${uri.host} 请求超时', timeout);
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(response.statusCode, uri.host);
      }
      return response;
    } finally {
      _active.remove(abort);
    }
  }

  Future<dynamic> json(
    Uri uri, {
    String method = 'GET',
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final response = await send(
      uri,
      method: method,
      body: body,
      headers: headers,
    );
    return response.bodyBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Json> map(
    Uri uri, {
    String method = 'GET',
    Object? body,
    Map<String, String> headers = const {},
  }) async =>
      object(await json(uri, method: method, body: body, headers: headers));
  void close() {
    if (_closed) return;
    _closed = true;
    for (final abort in _active) {
      if (!abort.isCompleted) abort.complete();
    }
    client.close();
  }
}
