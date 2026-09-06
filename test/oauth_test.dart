import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melonbang/data/account.dart';
import 'package:melonbang/data/network.dart';

import 'support/memory_credentials.dart';

class DelayedConfiguration extends MemoryCredentials {
  final requested = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String?> read(String key) async {
    if (key == 'oauth') {
      requested.complete();
      await release.future;
    }
    return super.read(key);
  }
}

void main() {
  test(
    'cancel during configuration loading prevents opening a login browser',
    () async {
      final credentials = DelayedConfiguration();
      final api = ApiClient();
      var launches = 0;
      final account = AccountRepository(
        api,
        credentials,
        launch: (_) async {
          launches++;
        },
      );
      await account.configure(clientId: 'id', clientSecret: 'secret');
      final result = expectLater(account.signIn(), throwsStateError);
      await credentials.requested.future;
      await account.cancelSignIn();
      credentials.release.complete();
      await result;
      expect(launches, 0);
      expect(account.session, isNull);
      await account.close();
      api.close();
    },
  );
  test(
    'OAuth rejects a wrong state then exchanges the valid callback',
    () async {
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final credentials = MemoryCredentials();
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/oauth/access_token') {
            expect(Uri.splitQueryString(request.body)['code'], 'valid-code');
            return http.Response(
              jsonEncode({
                'access_token': 'token',
                'refresh_token': 'refresh',
                'expires_in': 3600,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'id': 1,
              'username': 'test',
              'nickname': 'Test',
              'avatar': {},
            }),
            200,
          );
        }),
      );
      final account = AccountRepository(
        api,
        credentials,
        launch: (url) async {
          final callback = Uri.parse(url.queryParameters['redirect_uri']!);
          final client = http.Client();
          expect(
            (await client.get(
              callback.replace(
                queryParameters: {'code': 'wrong', 'state': 'wrong'},
              ),
            )).statusCode,
            400,
          );
          expect(
            (await client.get(
              callback.replace(
                queryParameters: {
                  'code': 'valid-code',
                  'state': url.queryParameters['state']!,
                },
              ),
            )).statusCode,
            200,
          );
          client.close();
        },
      );
      await account.configure(
        clientId: 'id',
        clientSecret: 'secret',
        redirectUri: 'http://127.0.0.1:$port/callback',
      );
      expect((await account.signIn())['userId'], '1');
      expect(await account.accessToken(), 'token');
      await account.close();
      api.close();
    },
  );
  test(
    'cancel closes the loopback listener and never persists a session',
    () async {
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final launched = Completer<void>();
      final api = ApiClient(
        client: MockClient(
          (_) async => throw StateError('No token exchange expected'),
        ),
      );
      final credentials = MemoryCredentials();
      final account = AccountRepository(
        api,
        credentials,
        launch: (_) async {
          launched.complete();
        },
      );
      await account.configure(
        clientId: 'id',
        clientSecret: 'secret',
        redirectUri: 'http://127.0.0.1:$port/callback',
      );
      final result = expectLater(account.signIn(), throwsStateError);
      await launched.future;
      await account.cancelSignIn();
      await result;
      expect(await credentials.read('account'), isNull);
      final available = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await available.close();
      await account.close();
      api.close();
    },
  );
}
