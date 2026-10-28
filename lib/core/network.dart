import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'cancellation.dart';
import 'json.dart';

export 'cancellation.dart';

Future<dynamic> decodeJsonBytes(List<int> bytes) async =>
    bytes.length < 256 * 1024
    ? jsonDecode(utf8.decode(bytes))
    : Isolate.run(() => jsonDecode(utf8.decode(bytes)));

extension AbortableSend on http.Client {
  /// Sends a request that stops once [abort] completes, which it does on its
  /// own when no response arrives within [timeout]; the request then fails
  /// with [message].
  Future<http.StreamedResponse> sendAbortable(
    String method,
    Uri uri, {
    required Completer<void> abort,
    required Duration timeout,
    required String message,
    Map<String, String> headers = const {},
    String? body,
  }) {
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abort.future,
    )..headers.addAll(headers);
    if (body != null) request.body = body;
    return send(request).timeout(
      timeout,
      onTimeout: () {
        if (!abort.isCompleted) abort.complete();
        throw TimeoutException(message, timeout);
      },
    );
  }
}

class _HostRequests {
  int active = 0;
  final waiting = Queue<Completer<void>>();
  Future<T> run<T>(Future<T> Function() action) async {
    if (active >= ApiClient.maxRequestsPerHost) {
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
  ApiClient({this.timeout = const Duration(seconds: 20)});

  /// A subject page reads six parts from Bangumi at once.
  static const maxRequestsPerHost = 6;
  final Duration timeout;
  final _active = <Completer<void>>{};
  final _hosts = <String, _HostRequests>{};
  bool _closed = false;

  // A new TLS connection took 0.2–3 s on the user's network, against 0.1 s
  // for a request on an open one; Dart drops idle connections after 15 s,
  // so returning to a page after reading one would connect again. Bangumi's
  // and Melon API's servers kept idle connections over five minutes.
  final client = IOClient(
    HttpClient()..idleTimeout = const Duration(minutes: 2),
  );
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
  }) => _exchange(
    uri,
    method: method,
    body: body,
    headers: headers,
    cancel: cancel,
    read: (streamed) async {
      final response = await http.Response.fromStream(streamed);
      if (!acceptedStatuses.contains(response.statusCode)) {
        _checkResponse(response, uri);
      }
      return response;
    },
  );

  /// [uri]'s text up to where [end] first matches, leaving the rest
  /// undownloaded: what a large page on a slow site holds near its top. The
  /// whole text when [end] never matches.
  Future<String> head(
    Uri uri,
    Pattern end, {
    Map<String, String> headers = const {},
    RequestCancellation? cancel,
  }) => _exchange(
    uri,
    headers: headers,
    cancel: cancel,
    read: (streamed) async {
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        _checkResponse(await http.Response.fromStream(streamed), uri);
      }
      final text = StringBuffer();
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        text.write(chunk);
        if (end.allMatches('$text').isNotEmpty) break;
      }
      return '$text';
    },
  );

  Future<T> _exchange<T>(
    Uri uri, {
    String method = 'GET',
    Object? body,
    Map<String, String> headers = const {},
    RequestCancellation? cancel,
    required Future<T> Function(http.StreamedResponse) read,
  }) async {
    cancel?.throwIfCancelled();
    final abort = Completer<void>();
    _active.add(abort);
    final unsubscribe = cancel?.listen(() {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final queue = _hosts.putIfAbsent(uri.host, _HostRequests.new);
      final started = Completer<void>();
      final receiving = queue
          .run(() async {
            started.complete();
            for (var attempt = 0; ; attempt++) {
              if (abort.isCompleted) throw const RequestCancelled();
              final request = _request(
                uri,
                abort: abort,
                method: method,
                body: body,
                headers: headers,
              );
              try {
                return await client.send(request).then(read);
              } on HandshakeException {
                // Some networks reset a few percent of new TLS connections
                // (measured ~2% to api.bgm.tv); the request was never sent and
                // a fresh connection succeeds.
                if (attempt > 0) rethrow;
              }
            }
          })
          .whenComplete(() {
            if (queue.active == 0 && identical(_hosts[uri.host], queue)) {
              _hosts.remove(uri.host);
            }
          });
      receiving.ignore();
      final cancelled = abort.future.then<T>(
        (_) => throw const RequestCancelled(),
      );
      // Waiting behind the host's other requests is not the request taking
      // long: a search reading a dozen feeds of one site queues most of them.
      await Future.any([started.future, cancelled]);
      final result = await Future.any([receiving, cancelled])
          .timeout(timeout, onTimeout: () => _timedOut(uri, abort));
      cancel?.throwIfCancelled();
      return result;
    } catch (_) {
      cancel?.throwIfCancelled();
      rethrow;
    } finally {
      unsubscribe?.call();
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
