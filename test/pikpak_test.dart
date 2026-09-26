import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melonbang/data/credentials.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/pikpak.dart';

class _Credentials implements Credentials {
  String? value;
  bool locked = false;
  final reads = <bool>[];
  @override
  Future<String?> read(String key, {bool allowInteraction = true}) async {
    expect(key, 'pikpak');
    reads.add(allowInteraction);
    if (locked && !allowInteraction) {
      throw const CredentialInteractionRequired();
    }
    return value;
  }

  @override
  Future<void> write(String key, String? value) async => this.value = value;
}

Json _token({String access = 'access', String refresh = 'refresh'}) => {
  'access_token': access,
  'refresh_token': refresh,
  'expires_in': 7200,
  'sub': 'user-1',
};

_Credentials _saved({bool expired = false}) => _Credentials()
  ..value = jsonEncode({
    ..._token(),
    'account': 'example@example.com',
    'device_id': 'persistent-device',
    'expires_at': expired
        ? 1
        : DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
  });

http.Response _json(Json body, {int status = 200}) =>
    http.Response(jsonEncode(body), status);

void main() {
  test('silent restore waits for explicit credential unlock', () async {
    final credentials = _saved()..locked = true;
    var requests = 0;
    final client = PikPakClient(
      credentials,
      httpClient: MockClient((_) async {
        requests++;
        throw StateError('Restore must not use the network');
      }),
    );
    addTearDown(client.close);
    await client.initialize();
    expect(client.needsAuthorization, isTrue);
    expect(client.isSignedIn, isFalse);
    expect(credentials.reads, [false]);
    await client.unlock();
    expect(client.isSignedIn, isTrue);
    expect(client.needsAuthorization, isFalse);
    expect(client.userId, 'user-1');
    expect(requests, 0);
    expect(client.session!.keys, isNot(contains('access_token')));
  });

  test(
    'native login stores tokens without retaining password or client secret',
    () async {
      final credentials = _Credentials();
      final requests = <http.Request>[];
      final client = PikPakClient(
        credentials,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/v1/shield/captcha/init') {
            expect(
              object(jsonDecode(request.body))['action'],
              'POST:/v1/auth/signin',
            );
            return _json({'captcha_token': 'captcha', 'expires_in': 300});
          }
          expect(request.url.host, 'user.mypikpak.com');
          expect(request.url.path, '/v1/auth/signin');
          final body = object(jsonDecode(request.body));
          expect(body['username'], 'example@example.com');
          expect(body['password'], 'password-only-in-request');
          expect(body.containsKey('client_secret'), isFalse);
          expect(request.headers['X-Captcha-Token'], 'captcha');
          return _json(_token());
        }),
      );
      addTearDown(client.close);
      await client.signIn(' example@example.com ', 'password-only-in-request');
      expect(client.account, 'example@example.com');
      expect(credentials.value, isNot(contains('password-only-in-request')));
      expect(credentials.value, contains('refresh_token'));
      expect(requests, hasLength(2));
      await client.signOut();
      expect(client.isSignedIn, isFalse);
      expect(credentials.value, isNull);
    },
  );

  test('interactive captcha preserves its token for the user retry', () async {
    var captchaCalls = 0;
    final client = PikPakClient(
      _Credentials(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/shield/captcha/init') {
          captchaCalls++;
          return _json({
            'captcha_token': 'challenge-token',
            'url': 'https://user.mypikpak.com/captcha/verify',
            'expires_in': 0,
          });
        }
        expect(request.headers['X-Captcha-Token'], 'challenge-token');
        return _json(_token());
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.signIn('example@example.com', 'password'),
      throwsA(
        isA<PikPakCaptchaRequired>().having(
          (error) => error.url.host,
          'verification host',
          'user.mypikpak.com',
        ),
      ),
    );
    expect(client.isSignedIn, isFalse);
    await client.signIn('example@example.com', 'password');
    expect(client.isSignedIn, isTrue);
    expect(captchaCalls, 1);
  });

  test(
    'concurrent API calls refresh one expired token and persist rotation',
    () async {
      final credentials = _saved(expired: true);
      var refreshCalls = 0;
      final release = Completer<void>();
      final started = Completer<void>();
      final client = PikPakClient(
        credentials,
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/token') {
            refreshCalls++;
            started.complete();
            await release.future;
            expect(
              object(jsonDecode(request.body))['refresh_token'],
              'refresh',
            );
            return _json(
              _token(access: 'new-access', refresh: 'rotated-refresh'),
            );
          }
          if (request.url.path == '/v1/shield/captcha/init') {
            final meta = object(object(jsonDecode(request.body))['meta']);
            expect(meta['captcha_sign'], startsWith('1.'));
            expect(meta['user_id'], 'user-1');
            return _json({'captcha_token': 'captcha', 'expires_in': 300});
          }
          expect(request.headers['Authorization'], 'Bearer new-access');
          expect(request.headers['X-Device-Id'], 'persistent-device');
          return _json({'id': request.url.pathSegments.last});
        }),
      );
      addTearDown(client.close);
      await client.initialize();
      final first = client.task('one');
      await started.future;
      final second = client.task('two');
      release.complete();
      expect(await Future.wait([first, second]), [
        {'id': 'one'},
        {'id': 'two'},
      ]);
      expect(refreshCalls, 1);
      expect(credentials.value, contains('rotated-refresh'));
    },
  );

  test('revoked access and rejected captcha each recover once', () async {
    var calls = 0;
    var captchaCalls = 0;
    final client = PikPakClient(
      _saved(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/auth/token') {
          return _json(_token(access: 'replacement'));
        }
        if (request.url.path == '/v1/shield/captcha/init') {
          captchaCalls++;
          return _json({
            'captcha_token': 'captcha-$captchaCalls',
            'expires_in': 300,
          });
        }
        calls++;
        if (calls == 1) {
          return _json({
            'error_code': 16,
            'error': 'unauthenticated',
          }, status: 401);
        }
        if (calls == 2) {
          return _json({
            'error_code': 9,
            'error': 'captcha_invalid',
          }, status: 400);
        }
        expect(request.headers['Authorization'], 'Bearer replacement');
        expect(request.headers['X-Captcha-Token'], 'captcha-2');
        return _json({'id': 'task', 'phase': 'PHASE_TYPE_COMPLETE'});
      }),
    );
    addTearDown(client.close);
    await client.initialize();
    expect((await client.task('task'))['phase'], 'PHASE_TYPE_COMPLETE');
    expect(calls, 3);
    expect(captchaCalls, 2);
  });

  test('cloud submission, paginated folders, and signed links keep their contracts', () async {
    var linkCalls = 0;
    final client = PikPakClient(
      _saved(),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path == '/v1/shield/captcha/init') {
          return _json({'captcha_token': 'captcha', 'expires_in': 300});
        }
        if (request.method == 'POST' && path == '/drive/v1/files') {
          final body = object(jsonDecode(request.body));
          expect(body['upload_type'], 'UPLOAD_TYPE_URL');
          expect(object(body['url'])['url'], 'magnet:?xt=urn:btih:test');
          return _json({
            'task': {'id': 'task-1', 'file_id': 'root'},
          });
        }
        if (path == '/drive/v1/files/root') {
          return _json({
            'id': 'root',
            'name': 'Season',
            'kind': 'drive#folder',
          });
        }
        if (path == '/drive/v1/files') {
          if (request.url.queryParameters['parent_id'] == 'nested') {
            return _json({
              'files': [
                {'id': 'sub', 'name': 'episode.ass'},
              ],
            });
          }
          if (request.url.queryParameters['page_token'] == 'page-2') {
            return _json({
              'files': [
                {'id': 'video', 'name': 'episode.mkv', 'size': '100'},
              ],
            });
          }
          return _json({
            'files': [
              {'id': 'nested', 'name': 'Subs', 'kind': 'drive#folder'},
            ],
            'next_page_token': 'page-2',
          });
        }
        expect(path, '/drive/v1/files/video');
        linkCalls++;
        return _json({
          'id': 'video',
          'web_content_link': 'https://cdn.example/$linkCalls',
        });
      }),
    );
    addTearDown(client.close);
    await client.initialize();
    expect(
      object(
        (await client.offlineDownload('magnet:?xt=urn:btih:test'))['task'],
      )['id'],
      'task-1',
    );
    expect((await client.files('root')).map((file) => file['path']), [
      'Subs/episode.ass',
      'episode.mkv',
    ]);
    expect(
      (await client.file('video'))['web_content_link'],
      'https://cdn.example/1',
    );
    expect(
      (await client.file('video'))['web_content_link'],
      'https://cdn.example/2',
    );
  });

  test(
    'sign-out during login cannot restore credentials from its late response',
    () async {
      final credentials = _Credentials();
      final started = Completer<void>();
      final release = Completer<void>();
      final client = PikPakClient(
        credentials,
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/shield/captcha/init') {
            return _json({'captcha_token': 'captcha', 'expires_in': 300});
          }
          started.complete();
          await release.future;
          return _json(_token());
        }),
      );
      addTearDown(client.close);
      final login = client.signIn('example@example.com', 'password');
      final assertion = expectLater(login, throwsA(isA<PikPakException>()));
      await started.future;
      await client.signOut();
      release.complete();
      await assertion;
      expect(client.isSignedIn, isFalse);
      expect(credentials.value, isNull);
    },
  );
}
