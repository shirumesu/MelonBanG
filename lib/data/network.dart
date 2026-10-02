import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'json.dart';

class RequestCancelled implements Exception {
  const RequestCancelled();
  @override
  String toString() => '请求已取消';
}

class RequestCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled;
  void throwIfCancelled() {
    if (_cancelled) throw const RequestCancelled();
  }

  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }
}

Future<dynamic> decodeJsonBytes(List<int> bytes) async =>
    bytes.length < 256 * 1024
    ? jsonDecode(utf8.decode(bytes))
    : Isolate.run(() => jsonDecode(utf8.decode(bytes)));

class _HostRequests {
  int active = 0;
  final waiting = Queue<Completer<void>>();
  Future<T> run<T>(Future<T> Function() action) async {
    if (active >= 4) {
      final slot = Completer<void>();
      waiting.add(slot);
      await slot.future;
    } else {
      active++;
    }
    try {
      return await action();
    } finally {
      if (waiting.isEmpty) {
        active--;
      } else {
        waiting.removeFirst().complete();
      }
    }
  }
}

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
  final _hosts = <String, _HostRequests>{};
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
    RequestCancellation? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final abort = Completer<void>();
    final request = _request(
      uri,
      abort: abort,
      method: method,
      body: body,
      headers: headers,
    );
    _active.add(abort);
    final unsubscribe = cancel?.listen(() {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final queue = _hosts.putIfAbsent(uri.host, _HostRequests.new);
      final receiving = queue
          .run(() {
            if (abort.isCompleted) throw const RequestCancelled();
            return client.send(request).then(http.Response.fromStream);
          })
          .whenComplete(() {
            if (queue.active == 0) _hosts.remove(uri.host);
          });
      final response = await Future.any([
        receiving,
        abort.future.then<http.Response>((_) => throw const RequestCancelled()),
      ]).timeout(timeout, onTimeout: () => _timedOut(uri, abort));
      if (!acceptedStatuses.contains(response.statusCode)) {
        _checkResponse(response, uri);
      }
      cancel?.throwIfCancelled();
      return response;
    } catch (_) {
      cancel?.throwIfCancelled();
      rethrow;
    } finally {
      unsubscribe?.call();
      _active.remove(abort);
    }
  }

  Stream<Json> ndjson(
    Uri uri, {
    Map<String, String> headers = const {},
    void Function(Map<String, String>)? onHeaders,
  }) async* {
    final abort = Completer<void>();
    final request = _request(
      uri,
      abort: abort,
      headers: {'Accept': 'application/x-ndjson', ...headers},
    );
    _active.add(abort);
    try {
      final response = await client
          .send(request)
          .timeout(timeout, onTimeout: () => _timedOut(uri, abort));
      onHeaders?.call(response.headers);
      if (response.statusCode == 304) {
        await response.stream.drain<void>();
        yield {'type': 'notModified'};
        return;
      }
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
        yield object(
          line.length < 256 * 1024
              ? jsonDecode(line)
              : await Isolate.run(() => jsonDecode(line)),
        );
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
    RequestCancellation? cancel,
  }) async {
    final response = await send(
      uri,
      method: method,
      body: body,
      headers: headers,
      cancel: cancel,
    );
    return response.bodyBytes.isEmpty
        ? null
        : await decodeJsonBytes(response.bodyBytes);
  }

  Future<Json> map(
    Uri uri, {
    String method = 'GET',
    Object? body,
    Map<String, String> headers = const {},
    RequestCancellation? cancel,
  }) async => object(
    await json(
      uri,
      method: method,
      body: body,
      headers: headers,
      cancel: cancel,
    ),
  );
  void close() {
    if (_closed) return;
    _closed = true;
    for (final abort in _active) {
      if (!abort.isCompleted) abort.complete();
    }
    client.close();
  }
}
