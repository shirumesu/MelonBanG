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
  Future<void> _credentialWrites = Future.value();
  int _signInGeneration = 0;
  bool _closed = false;
  bool _restoreNeedsAuthorization = false;
  Future<void> initialize() async {
    try {
      final saved = await credentials.read('account', allowInteraction: false);
      if (saved != null) _bundle = object(jsonDecode(saved));
    } on CredentialInteractionRequired {
      _restoreNeedsAuthorization = true;
    }
  }

  Future<Json> configuration({bool allowInteraction = true}) async => object(
    jsonDecode(
      await credentials.read('oauth', allowInteraction: allowInteraction) ??
          '{}',
    ),
  );
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
    final generation = ++_signInGeneration;
    await _cancelPendingSignIn();
    if (_restoreNeedsAuthorization) {
      final saved = await credentials.read('account');
      if (_closed || generation != _signInGeneration) throw StateError('登录已取消');
      _restoreNeedsAuthorization = false;
      if (saved != null) {
        _bundle = object(jsonDecode(saved));
        return session!;
      }
    }
    final config = await configuration();
    if (_closed || generation != _signInGeneration) {
      throw StateError('登录已取消');
    }
    if ('${config['clientId'] ?? ''}'.isEmpty ||
        '${config['clientSecret'] ?? ''}'.isEmpty) {
      throw StateError('请先在设置中填写 Bangumi OAuth 应用信息。');
    }
    final redirect = Uri.parse('${config['redirectUri']}');
    final state = newId();
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      redirect.port,
    );
    if (_closed || generation != _signInGeneration) {
      await server.close(force: true);
      throw StateError('登录已取消');
    }
    final authorization = Completer<String>();
    _authorization = authorization;
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
      final bundle = <String, dynamic>{
        ...token,
        'user': {
          'userId': '${me['id']}',
          'username': me['username'],
          'nickname': me['nickname'],
          'avatarUrl': object(me['avatar'])['medium'],
        },
      };
      await _saveBundle(
        bundle,
        () =>
            !_closed &&
            generation == _signInGeneration &&
            _authorization == authorization,
      );
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
    if (_closed || _bundle == null) throw StateError('请先登录 Bangumi');
    if (number(_bundle!['expiresAt']) >
        DateTime.now().millisecondsSinceEpoch + 60000) {
      return '${_bundle!['access_token']}';
    }
    if (_refresh case final pending?) return pending;
    late final Future<String> refreshing;
    refreshing = _renew().whenComplete(() {
      if (identical(_refresh, refreshing)) _refresh = null;
    });
    return _refresh = refreshing;
  }

  Future<void> _saveBundle(Json bundle, bool Function() valid) {
    final writing = _credentialWrites.then((_) async {
      if (!valid()) throw StateError('账号已经切换');
      await credentials.write('account', jsonEncode(bundle));
      if (!valid()) throw StateError('账号已经切换');
      _bundle = bundle;
    });
    _credentialWrites = writing.catchError((Object _) {});
    return writing;
  }

  Future<String> _renew() async {
    final old = _bundle!;
    final config = await configuration(allowInteraction: false);
    if (_closed || !identical(_bundle, old)) throw StateError('账号已经切换');
    final token = await _token(config, {
      'grant_type': 'refresh_token',
      'refresh_token': '${old['refresh_token']}',
    });
    final bundle = <String, dynamic>{...old, ...token, 'user': old['user']};
    await _saveBundle(bundle, () => !_closed && identical(_bundle, old));
    return '${token['access_token']}';
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
  }) async {
    final user = userId;
    final generation = _signInGeneration;
    var token = await accessToken();
    for (var attempt = 0; ; attempt++) {
      if (_closed || user != userId || generation != _signInGeneration) {
        throw StateError('账号已经切换');
      }
      try {
        final result = await api.json(
          Uri.parse('https://api.bgm.tv$path'),
          method: method,
          body: body,
          headers: {'Authorization': 'Bearer $token'},
        );
        if (_closed || user != userId || generation != _signInGeneration) {
          throw StateError('账号已经切换');
        }
        return result;
      } on ApiException catch (e) {
        if (e.status != 401 ||
            attempt != 0 ||
            _closed ||
            user != userId ||
            generation != _signInGeneration) {
          rethrow;
        }
        // A concurrent request may already have replaced the rejected token.
        if (_bundle?['access_token'] == token) _bundle!['expiresAt'] = 0;
        token = await accessToken();
      }
    }
  }

  Future<void> cancelSignIn() async {
    _signInGeneration++;
    await _cancelPendingSignIn();
  }

  Future<void> _cancelPendingSignIn() async {
    final pending = _authorization;
    final callback = _callback;
    _authorization = null;
    _callback = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('登录已取消'));
    }
    await callback?.close(force: true);
  }

  Future<void> signOut() async {
    await cancelSignIn();
    _bundle = null;
    _refresh = null;
    _restoreNeedsAuthorization = false;
    final deleting = _credentialWrites.then(
      (_) => credentials.write('account', null),
    );
    _credentialWrites = deleting.catchError((Object _) {});
    await deleting;
  }

  Future<void> close() async {
    _closed = true;
    await cancelSignIn();
    await _credentialWrites;
  }
}
