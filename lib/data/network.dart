import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'json.dart';

class ApiException implements Exception {
  const ApiException(this.status, this.host, {this.reason});
  final int status;
  final String host;
  final String? reason;
  @override
  String toString() =>
      '$host 请求失败（HTTP $status）'
      '${reason == null || reason!.isEmpty ? '' : '：$reason'}';
}

class ApiClient {
  ApiClient({http.Client? client, this.timeout = const Duration(seconds: 20)})
    : client = client ?? http.Client();
  final Duration timeout;
  final _active = <Completer<void>>{};
  bool _closed = false;
  final http.Client client;
  http.AbortableRequest _request(
    Uri uri, {
    required Completer<void> abort,
    String method = 'GET',
    Object? body,
    Map<String, String> headers = const {},
  }) {
    if (_closed) throw StateError('网络服务已关闭');
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
    return request;
  }

  Never _timedOut(Uri uri, Completer<void> abort) {
    if (!abort.isCompleted) abort.complete();
    throw TimeoutException('${uri.host} 请求超时', timeout);
  }

  void _checkResponse(http.Response response, Uri uri) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final reason =
        response.headers['x-error-message']?.trim() ??
        (response.headers['content-type']?.contains('application/json') == true
            ? object(object(jsonDecode(response.body))['error'])['message']
                  as String?
            : null);
    throw ApiException(response.statusCode, uri.host, reason: reason);
  }

  Future<http.Response> send(
    Uri uri, {
    String method = 'GET',
    Object? body,
    Map<String, String> headers = const {},
    Set<int> acceptedStatuses = const {},
  }) async {
    final abort = Completer<void>();
    final request = _request(
      uri,
      abort: abort,
      method: method,
      body: body,
      headers: headers,
    );
    _active.add(abort);
    try {
      final receiving = client.send(request).then(http.Response.fromStream);
      final response = await receiving.timeout(
        timeout,
        onTimeout: () => _timedOut(uri, abort),
      );
      if (!acceptedStatuses.contains(response.statusCode)) {
        _checkResponse(response, uri);
      }
      return response;
    } finally {
      _active.remove(abort);
    }
  }

  Stream<Json> ndjson(Uri uri) async* {
    final abort = Completer<void>();
    final request = _request(
      uri,
      abort: abort,
      headers: const {'Accept': 'application/x-ndjson'},
    );
    _active.add(abort);
    try {
      final response = await client
          .send(request)
          .timeout(timeout, onTimeout: () => _timedOut(uri, abort));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _checkResponse(
          await http.Response.fromStream(response)
              .timeout(timeout, onTimeout: () => _timedOut(uri, abort)),
          uri,
        );
      }
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(
            timeout,
            onTimeout: (sink) {
              if (!abort.isCompleted) abort.complete();
              sink.addError(TimeoutException('${uri.host} 请求超时', timeout));
              sink.close();
            },
          );
      await for (final line in lines) {
        yield object(jsonDecode(line));
      }
    } finally {
      if (!abort.isCompleted) abort.complete();
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
