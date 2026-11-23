import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'cancellation.dart';
import 'error_message.dart';
import 'json.dart';
import 'proxy.dart';

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

/// An HTTP client that keeps each site reachable whichever way works for
/// it. A request goes the way the proxy setting says, unless its site was
/// learned to connect only direct; when a GET or HEAD cannot connect that
/// way, it is sent once the other way, and if that one connects, the site
/// is remembered for that way ([NetworkRoutes]). Writes are never sent
/// twice, and a proxy app that is not running teaches nothing: the request
/// goes direct and the proxy is looked for again.
///
/// Without a proxy in use every request goes direct, as before.
class RoutedClient extends http.BaseClient {
  RoutedClient({Duration idleTimeout = const Duration(seconds: 15)})
    : _proxy = NetworkProxy.installed {
    HttpClient open(String Function(Uri) route) => HttpClient()
      ..idleTimeout = idleTimeout
      ..connectionTimeout = connectTimeout
      ..findProxy = route;
    _direct = IOClient(open((_) => 'DIRECT'));
    // Asked only once a request is sent through the proxy; the setting can
    // drop it in between, and then the request goes direct.
    _proxied = IOClient(
      open((uri) => _proxy?.configuredFor(uri)?.directive ?? 'DIRECT'),
    );
  }

  /// How long a connection may take to open: a blocked site that never
  /// answers fails over to the other way after this.
  static const connectTimeout = Duration(seconds: 5);

  final NetworkProxy? _proxy;
  late final IOClient _direct, _proxied;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final proxy = _proxy;
    final server = proxy?.configuredFor(request.url);
    if (proxy == null || server == null) return _direct.send(request);
    final host = request.url.host;
    final direct = proxy.routes.sendsDirect(host);
    final again = _copy(request);
    try {
      return await (direct ? _direct : _proxied).send(request);
    } catch (error, stack) {
      if (again == null || !_unreachable(error)) rethrow;
      final proxyDown = !direct && _proxyDown(error);
      if (proxyDown) unawaited(proxy.refresh());
      final http.StreamedResponse response;
      try {
        response = await (direct ? _proxied : _direct).send(again);
      } catch (_) {
        // Neither way connects: the way the site was expected to work
        // says why.
        Error.throwWithStackTrace(error, stack);
      }
      if (!proxyDown) proxy.routes.learn(host, direct: !direct);
      return response;
    }
  }

  /// Whether [error] left the request unanswered: no connection, a refused
  /// tunnel or a reset before the response began. A cancelled request is
  /// not.
  static bool _unreachable(Object error) => switch (error) {
    http.RequestAbortedException() => false,
    http.ClientException() || SocketException() || TlsException() => true,
    HttpException() => true,
    _ => false,
  };

  /// Whether [error], from a request through the proxy, is the proxy itself
  /// not answering, as when its app closed while the system still points
  /// at it: through a proxy the socket opens to the proxy alone, so a
  /// refused or timed-out connection is its. A reset or a refused tunnel
  /// is the proxy failing to reach the site.
  static bool _proxyDown(Object error) =>
      error is SocketException &&
      (_noConnection.contains(error.osError?.errorCode) ||
          error.message.startsWith('HTTP connection timed out'));

  /// Errors of a connection that never opened, by system.
  static const _noConnection = {
    // Windows: refused (1225 for this machine's ports), timed out, network
    // and host unreachable.
    1225, 10061, 10060, 10051, 10065,
    // Linux: refused, timed out, network and host unreachable.
    111, 110, 101, 113,
    // macOS: refused, timed out, network and host unreachable.
    61, 60, 51, 65,
  };

  /// [request] as a second one to send, for a read whose body is known.
  static http.BaseRequest? _copy(http.BaseRequest request) {
    if ((request.method != 'GET' && request.method != 'HEAD') ||
        request is! http.Request) {
      return null;
    }
    final copy = switch (request) {
      http.Abortable(:final abortTrigger) => http.AbortableRequest(
        request.method,
        request.url,
        abortTrigger: abortTrigger,
      ),
      _ => http.Request(request.method, request.url),
    };
    copy
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    if (request.bodyBytes.isNotEmpty) copy.bodyBytes = request.bodyBytes;
    return copy;
  }

  @override
  void close() {
    _direct.close();
    _proxied.close();
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

class ApiException implements UserFacingError {
  const ApiException(this.status, this.host, {this.reason, this.code});
  final int status;
  final String host;
  final String? reason;

  /// The machine-readable error, such as OAuth's `invalid_grant`.
  final String? code;
  @override
  String toString() =>
      '$host 请求失败（HTTP $status）'
      '${reason == null || reason!.isEmpty ? '' : '：$reason'}';

  /// The service's own Chinese reason, else what the status means.
  @override
  String get userMessage {
    if (reason case final text? when RegExp(r'[一-鿿]').hasMatch(text)) {
      return text;
    }
    final name = serviceName(host);
    // Latin names stand apart from the Chinese after them.
    final service = RegExp(r'[A-Za-z]$').hasMatch(name) ? '$name ' : name;
    return switch (status) {
      401 => '$service登录已失效，请重新登录',
      403 => '$service拒绝了这次访问',
      404 => '内容不存在或已被删除',
      429 => '请求太频繁，请稍后再试',
      >= 500 => '$service暂时无法访问，请稍后再试',
      _ => '$service没有接受这次请求',
    };
  }
}

/// What the user calls the service at [host].
String serviceName(String host) => switch (host) {
  _ when host.endsWith('bgm.tv') || host.contains('bangumi') => 'Bangumi',
  _ when host.contains('github') => 'GitHub',
  _ when host.contains('pikpak') => 'PikPak',
  _ when host.contains('bilibili') => 'B 站',
  _ when host.contains('melon') || host.contains('konataizumi') => 'Melon 服务',
  _ => '网站',
};

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
  // so opening a page after reading another would connect again. Bangumi's
  // and Melon API's servers (Cloudflare) close idle connections after 398 s.
  final http.Client client = RoutedClient(
    idleTimeout: const Duration(minutes: 5),
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
    throw TimeoutException('连接超时，请检查网络后重试', timeout);
  }

  void _checkResponse(http.Response response, Uri uri) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String? reason = response.headers['x-error-message']?.trim();
    String? code;
    if (response.headers['content-type']?.contains('application/json') ==
        true) {
      // A gateway's error page can be labelled JSON; the status still says
      // what went wrong.
      final Json body;
      try {
        body = object(jsonDecode(response.body));
      } on FormatException {
        throw ApiException(response.statusCode, uri.host, reason: reason);
      }
      final error = body['error'];
      // OAuth endpoints answer {error: code, error_description: text}.
      if (error is String) {
        code = error;
        reason ??= body['error_description'] is String
            ? '${body['error_description']}（$error）'
            : error;
      } else {
        if (object(error)['code'] case final String value) code = value;
        if (object(error)['message'] case final String value) reason ??= value;
      }
    }
    throw ApiException(
      response.statusCode,
      uri.host,
      reason: reason,
      code: code,
    );
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

  /// [uri]'s body, read only up to [maxBytes]: a larger one stops
  /// downloading and fails with [tooLarge].
  Future<Uint8List> bytes(
    Uri uri, {
    required int maxBytes,
    required String tooLarge,
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
      if ((streamed.contentLength ?? 0) > maxBytes) {
        await streamed.stream.listen(null).cancel();
        throw StateError(tooLarge);
      }
      final body = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        body.add(chunk);
        if (body.length > maxBytes) throw StateError(tooLarge);
      }
      return body.takeBytes();
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
      await for (final chunk in streamed.stream.transform(
        const Utf8Decoder(allowMalformed: true),
      )) {
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
              } catch (error) {
                // A read dropped midway or a gateway briefly down usually
                // answers a second try; writes are never repeated.
                final transient = switch (error) {
                  SocketException() || http.ClientException() => true,
                  ApiException(:final status) => const {
                    502,
                    503,
                    504,
                  }.contains(status),
                  _ => false,
                };
                if (attempt > 0 ||
                    !transient ||
                    abort.isCompleted ||
                    (method != 'GET' && method != 'HEAD')) {
                  rethrow;
                }
                await Future<void>.delayed(const Duration(milliseconds: 600));
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
