import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'json.dart';
import 'network.dart';
import 'credentials.dart';

class AccountRepository {
  AccountRepository(
    this.api,
    this.credentials, {
    Future<void> Function(Uri)? launch,
  }) : launch =
           launch ??
           ((uri) async {
             if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
               throw StateError('无法打开登录网页');
             }
           });
  final ApiClient api;
  final Credentials credentials;
  final Future<void> Function(Uri) launch;
  Json? _bundle;
  Json? get session => _bundle == null ? null : object(_bundle!['user']);
  String get userId => '${session?['userId'] ?? 'local'}';
  HttpServer? _callback;
  Completer<String>? _authorization;
  Future<String>? _refresh;
  bool _closed = false;
  Future<void> initialize() async {
    final saved = await credentials.read('account');
    if (saved != null) _bundle = object(jsonDecode(saved));
  }

  Future<Json> configuration() async =>
      object(jsonDecode(await credentials.read('oauth') ?? '{}'));
  Future<void> configure({
    required String clientId,
    required String clientSecret,
    String redirectUri = 'http://127.0.0.1:14567/callback',
  }) async {
    final uri = Uri.parse(redirectUri);
    if (uri.scheme != 'http' || uri.host != '127.0.0.1' || !uri.hasPort) {
      throw const FormatException('回调地址需为 http://127.0.0.1:端口/路径');
    }
    await credentials.write(
      'oauth',
      jsonEncode({
        'clientId': clientId.trim(),
        'clientSecret': clientSecret.trim(),
        'redirectUri': uri.toString(),
      }),
    );
  }

  Future<Json> signIn() async {
    await cancelSignIn();
    final config = await configuration();
    if ('${config['clientId'] ?? ''}'.isEmpty ||
        '${config['clientSecret'] ?? ''}'.isEmpty) {
      throw StateError('请先在设置中填写 Bangumi OAuth 应用信息。');
    }
    final redirect = Uri.parse('${config['redirectUri']}');
    final state = newId();
    final authorization = Completer<String>();
    _authorization = authorization;
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      redirect.port,
    );
    _callback = server;
    server.listen((request) async {
      if (request.uri.path != redirect.path ||
          request.uri.queryParameters['state'] != state) {
        request.response.statusCode = 400;
      } else if (request.uri.queryParameters['code'] case final String code) {
        if (!authorization.isCompleted) authorization.complete(code);
        request.response.headers.contentType = ContentType.html;
        request.response.write('<meta charset="utf-8">登录完成，可以返回 Melonbang。');
      } else {
        if (!authorization.isCompleted) {
          authorization.completeError(StateError('登录未授权'));
        }
      }
      await request.response.close();
    });
    try {
      // Attach the timeout before opening the browser so cancellation is observed.
      final codeFuture = authorization.future.timeout(
        const Duration(minutes: 5),
      );
      unawaited(
        launch(
          Uri.https('bgm.tv', '/oauth/authorize', {
            'client_id': '${config['clientId']}',
            'response_type': 'code',
            'redirect_uri': redirect.toString(),
            'state': state,
          }),
        ).catchError((Object e) {
          if (!authorization.isCompleted) authorization.completeError(e);
        }),
      );
      final code = await codeFuture;
      final token = await _token(config, {
        'grant_type': 'authorization_code',
        'code': code,
        'state': state,
      });
      if (_closed || _authorization != authorization) throw StateError('登录已取消');
      final me = await api.map(
        Uri.https('api.bgm.tv', '/v0/me'),
        headers: {'Authorization': 'Bearer ${token['access_token']}'},
      );
      if (_closed || _authorization != authorization) throw StateError('登录已取消');
      _bundle = {
        ...token,
        'user': {
          'userId': '${me['id']}',
          'username': me['username'],
          'nickname': me['nickname'],
          'avatarUrl': object(me['avatar'])['medium'],
        },
      };
      await credentials.write('account', jsonEncode(_bundle));
      return session!;
    } finally {
      await server.close(force: true);
      if (_authorization == authorization) {
        _authorization = null;
        _callback = null;
      }
    }
  }

  Future<Json> _token(Json config, Map<String, String> grant) async {
    final token = await api.map(
      Uri.https('bgm.tv', '/oauth/access_token'),
      method: 'POST',
      body: <String, String>{
        ...grant,
        'client_id': '${config['clientId']}',
        'client_secret': '${config['clientSecret']}',
        'redirect_uri': '${config['redirectUri']}',
      },
    );
    if (token['access_token'] is! String) throw StateError('登录令牌无效');
    return {
      ...token,
      'expiresAt':
          DateTime.now().millisecondsSinceEpoch +
          number(token['expires_in']).toInt() * 1000,
    };
  }

  Future<String> accessToken() async {
    if (_bundle == null) throw StateError('请先登录 Bangumi');
    if (number(_bundle!['expiresAt']) >
        DateTime.now().millisecondsSinceEpoch + 60000) {
      return '${_bundle!['access_token']}';
    }
    return _refresh ??= _renew().whenComplete(() => _refresh = null);
  }

  Future<String> _renew() async {
    final old = _bundle!;
    final token = await _token(await configuration(), {
      'grant_type': 'refresh_token',
      'refresh_token': '${old['refresh_token']}',
    });
    if (_closed || !identical(_bundle, old)) throw StateError('账号已经切换');
    _bundle = {...token, 'user': old['user']};
    await credentials.write('account', jsonEncode(_bundle));
    return '${token['access_token']}';
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
  }) async => api.json(
    Uri.parse('https://api.bgm.tv$path'),
    method: method,
    body: body,
    headers: {'Authorization': 'Bearer ${await accessToken()}'},
  );
  Future<void> cancelSignIn() async {
    final pending = _authorization;
    _authorization = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('登录已取消'));
    }
    await _callback?.close(force: true);
    _callback = null;
  }

  Future<void> signOut() async {
    await cancelSignIn();
    _bundle = null;
    await credentials.write('account', null);
  }

  Future<void> close() async {
    _closed = true;
    await cancelSignIn();
  }
}
