import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melonbang/data/network.dart';

void main() {
  test(
    'HTTP errors without a provider reason keep the status and host',
    () async {
      final api = ApiClient(
        client: MockClient((_) async => http.Response('', 403)),
      );
      addTearDown(api.close);
      await expectLater(
        api.send(Uri.https('example.com', '/resource')),
        throwsA(
          isA<ApiException>().having(
            (error) => error.toString(),
            'visible error',
            'example.com 请求失败（HTTP 403）',
          ),
        ),
      );
    },
  );

  test(
    'a stalled response body is aborted and later requests still work',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final disconnected = Completer<void>();
      final sockets = <Socket>[];
      server.listen((socket) {
        sockets.add(socket);
        var request = '', replied = false, stalled = false;
        socket.listen(
          (data) {
            request += ascii.decode(data);
            if (replied || !request.contains('\r\n\r\n')) return;
            replied = true;
            stalled = request.startsWith('GET /stall ');
            socket.write(
              stalled ? 'HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\nx' : 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok',
            );
            if (!stalled) unawaited(socket.close());
          },
          onDone: () {
            if (stalled && !disconnected.isCompleted) disconnected.complete();
            socket.destroy();
          },
          onError: (Object _) {
            socket.destroy();
          },
        );
      });
      final api = ApiClient(timeout: const Duration(milliseconds: 300));
      try {
        final origin = 'http://127.0.0.1:${server.port}';
        await expectLater(
          api.send(Uri.parse('$origin/stall')),
          throwsA(isA<TimeoutException>()),
        );
        await disconnected.future.timeout(const Duration(seconds: 3));
        expect((await api.send(Uri.parse('$origin/ok'))).body, 'ok');
        api.close();
        await expectLater(api.send(Uri.parse('$origin/ok')), throwsStateError);
      } finally {
        api.close();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    },
  );
}
