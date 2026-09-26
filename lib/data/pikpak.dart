import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'credentials.dart';
import 'json.dart';

class PikPakException implements Exception {
  const PikPakException(this.message, {this.code = 0, this.status = 0});
  final String message;
  final int code;
  final int status;
  @override
  String toString() => message;
}

class PikPakCaptchaRequired extends PikPakException {
  const PikPakCaptchaRequired(this.url) : super('PikPak 需要网页验证，请完成验证后重试。');
  final Uri url;
}

/// Native PikPak protocol; account credentials and tokens stay in secure storage.
class PikPakClient {
  PikPakClient(this.credentials, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final Credentials credentials;
  final http.Client _http;
  static const _auth = 'user.mypikpak.com';
  static const _drive = 'api-drive.mypikpak.com';
  // Public web-client protocol identifiers, also used by rclone's PikPak backend:
  // https://github.com/rclone/rclone/tree/master/backend/pikpak
  static const _clientId = 'YUMx5nI8ZU8Ap8pm';
  static const _clientVersion = '2.0.0';
  static const _captchaSalts = [
    'C9qPpZLN8ucRTaTiUMWYS9cQvWOE',
    '+r6CQVxjzJV6LCV',
    'F',
    'pFJRC',
    '9WXYIDGrwTCz2OiVlgZa90qpECPD6olt',
    '/750aCr4lm/Sly/c',
    'RB+DT/gZCrbV',
    '',
    'CyLsf7hdkIRxRm215hl',
    '7xHvLi2tOYP0Y92b',
    'ZGTXXxu8E/MIWaEDB+Sm/',
    '1UI3',
    'E7fP5Pfijd+7K+t6Tg/NhuLq0eEUVChpJSkrKxpO',
    'ihtqpG6FMt65+Xk+tWUH2',
    'NhXXU9rg4XXdzo7u5o',
  ];

  Json? _tokens;
  String _deviceId = _newDeviceId();
  String _captchaToken = '';
  DateTime _captchaExpiry = DateTime.fromMillisecondsSinceEpoch(0);
  String? _captchaAccount;
  Uri? _challenge;
  Future<void>? _refreshing;
  Future<String>? _captchaRefreshing;
  Future<void> _writes = Future.value();
  final _requests = <Completer<void>>{};
  int _generation = 0;
  bool _closed = false;
  bool _needsAuthorization = false;

  bool get isSignedIn => _tokens != null;
  bool get needsAuthorization => _needsAuthorization;
  Uri? get verificationUrl => _challenge;
  String? get account => _tokens?['account'] as String?;
  String? get username => account;
  String? get displayName => account;
  String? get userId => _tokens?['sub'] as String?;
  Json? get session => isSignedIn
      ? {'userId': userId, 'username': account, 'displayName': account}
      : null;

  static String _newDeviceId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> initialize() async {
    try {
      await _restore(allowInteraction: false);
    } on CredentialInteractionRequired {
      _needsAuthorization = true;
    }
  }

  Future<void> unlock() => _restore(allowInteraction: true);

  Future<void> _restore({required bool allowInteraction}) async {
    final generation = _generation;
    final value = await credentials.read(
      'pikpak',
      allowInteraction: allowInteraction,
    );
    _checkGeneration(generation);
    if (value != null) {
      final saved = object(jsonDecode(value));
      if ('${saved['refresh_token'] ?? ''}'.isNotEmpty &&
          '${saved['sub'] ?? ''}'.isNotEmpty) {
        _tokens = saved;
        _deviceId = '${saved['device_id'] ?? _deviceId}';
      }
    }
    _needsAuthorization = false;
  }

  Future<void> signIn(String username, String password) async {
    username = username.trim();
    if (username.isEmpty || password.isEmpty) {
      throw const PikPakException('请输入 PikPak 账号和密码。');
    }
    final generation = ++_generation;
    if (_captchaAccount != username) {
      _clearCaptcha();
      _captchaAccount = username;
    }
    const action = 'POST:/v1/auth/signin';
    var captcha = await _captcha(action, username: username);
    _checkGeneration(generation);
    Json response;
    try {
      response = await _send(
        'POST',
        Uri.https(_auth, '/v1/auth/signin'),
        body: {
          'username': username,
          'password': password,
          'client_id': _clientId,
        },
        captcha: captcha,
      );
    } on PikPakException catch (error) {
      if (!_isCaptchaError(error)) rethrow;
      captcha = await _captcha(action, username: username, force: true);
      _checkGeneration(generation);
      response = await _send(
        'POST',
        Uri.https(_auth, '/v1/auth/signin'),
        body: {
          'username': username,
          'password': password,
          'client_id': _clientId,
        },
        captcha: captcha,
      );
    }
    await _saveTokens(response, username, generation);
    _needsAuthorization = false;
    _clearCaptcha();
  }

  Future<void> signOut() async {
    ++_generation;
    _tokens = null;
    _needsAuthorization = false;
    _clearCaptcha();
    await _write(null);
  }

  Future<void> _write(Json? value) {
    final next = _writes
        .catchError((Object _) {})
        .then(
          (_) => credentials.write(
            'pikpak',
            value == null ? null : jsonEncode(value),
          ),
        );
    _writes = next;
    return next;
  }

  Future<void> _saveTokens(Json response, String name, int generation) async {
    _checkGeneration(generation);
    if ('${response['access_token'] ?? ''}'.isEmpty ||
        '${response['refresh_token'] ?? ''}'.isEmpty ||
        '${response['sub'] ?? ''}'.isEmpty) {
      throw const PikPakException('PikPak 登录响应缺少凭据，请重试。');
    }
    final tokens = <String, dynamic>{
      'account': name,
      'device_id': _deviceId,
      'sub': response['sub'],
      'access_token': response['access_token'],
      'refresh_token': response['refresh_token'],
      'expires_at':
          DateTime.now().millisecondsSinceEpoch +
          (_integer(response['expires_in'], fallback: 7200) - 60) * 1000,
    };
    await _write(tokens);
    _checkGeneration(generation);
    _tokens = tokens;
  }

  Future<void> _refresh({bool force = false}) async {
    if (_tokens == null) throw const PikPakException('请先在设置中登录 PikPak。');
    if (!force &&
        _integer(_tokens!['expires_at']) >
            DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    final current = _refreshing;
    if (current != null) return current;
    final generation = _generation;
    final name = account!;
    final refreshToken = _tokens!['refresh_token'];
    final operation = () async {
      final response = await _send(
        'POST',
        Uri.https(_auth, '/v1/auth/token'),
        body: {
          'client_id': _clientId,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      );
      await _saveTokens(response, name, generation);
    }();
    _refreshing = operation;
    try {
      await operation;
    } finally {
      if (identical(_refreshing, operation)) _refreshing = null;
    }
  }

  void _clearCaptcha() {
    _captchaToken = '';
    _captchaExpiry = DateTime.fromMillisecondsSinceEpoch(0);
    _challenge = null;
  }

  Future<String> _captcha(
    String action, {
    String? username,
    bool force = false,
  }) async {
    // The verification page completes this token on the server. Reuse it once
    // when the user retries; an API rejection requests a new challenge.
    if (!force && _challenge != null && _captchaToken.isNotEmpty) {
      _challenge = null;
      return _captchaToken;
    }
    if (!force &&
        _captchaToken.isNotEmpty &&
        DateTime.now().isBefore(_captchaExpiry)) {
      return _captchaToken;
    }
    final current = _captchaRefreshing;
    if (current != null) return current;
    final operation = _initCaptcha(action, username);
    _captchaRefreshing = operation;
    try {
      return await operation;
    } finally {
      if (identical(_captchaRefreshing, operation)) _captchaRefreshing = null;
    }
  }

  Future<String> _initCaptcha(String action, String? username) async {
    final generation = _generation;
    final timestamp = '${DateTime.now().millisecondsSinceEpoch}';
    var sign = '$_clientId${_clientVersion}mypikpak.com$_deviceId$timestamp';
    for (final salt in _captchaSalts) {
      sign = md5.convert(utf8.encode('$sign$salt')).toString();
    }
    final response = await _send(
      'POST',
      Uri.https(_auth, '/v1/shield/captcha/init'),
      body: {
        'client_id': _clientId,
        'device_id': _deviceId,
        'action': action,
        'captcha_token': _captchaToken,
        'meta': username != null
            ? {'username': username}
            : {
                'captcha_sign': '1.$sign',
                'timestamp': timestamp,
                'client_version': _clientVersion,
                'package_name': 'mypikpak.com',
                'user_id': userId ?? '',
              },
      },
    );
    _checkGeneration(generation);
    _captchaToken = '${response['captcha_token'] ?? ''}';
    _captchaExpiry = DateTime.now().add(
      Duration(seconds: _integer(response['expires_in'])),
    );
    final url = Uri.tryParse('${response['url'] ?? ''}');
    if (url != null && url.scheme == 'https' && url.host.isNotEmpty) {
      _challenge = url;
      throw PikPakCaptchaRequired(url);
    }
    if (_captchaToken.isEmpty) {
      throw const PikPakException('无法取得 PikPak 验证凭据，请重试。');
    }
    return _captchaToken;
  }

  Future<Json> _request(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
  }) async {
    final generation = _generation;
    await _refresh();
    var captchaRetried = false;
    var tokenRetried = false;
    while (true) {
      _checkGeneration(generation);
      final token = '${_tokens?['access_token'] ?? ''}';
      final captcha = await _captcha('$method:$path');
      _checkGeneration(generation);
      try {
        final result = await _send(
          method,
          Uri.https(_drive, path, query),
          body: body,
          token: token,
          captcha: captcha,
        );
        _checkGeneration(generation);
        return result;
      } on PikPakException catch (error) {
        if (!tokenRetried && (error.status == 401 || error.code == 16)) {
          tokenRetried = true;
          if (_tokens?['access_token'] == token) await _refresh(force: true);
        } else if (!captchaRetried && _isCaptchaError(error)) {
          captchaRetried = true;
          if (_captchaToken == captcha) {
            await _captcha('$method:$path', force: true);
          }
        } else {
          rethrow;
        }
      }
    }
  }

  Future<Json> offlineDownload(String magnet) => _request(
    'POST',
    '/drive/v1/files',
    body: {
      'kind': 'drive#file',
      'upload_type': 'UPLOAD_TYPE_URL',
      'folder_type': 'DOWNLOAD',
      'url': {'url': magnet},
    },
  );

  Future<Json> task(String id) =>
      _request('GET', '/drive/v1/tasks/${Uri.encodeComponent(id)}');

  Future<Json> file(String id) => _request(
    'GET',
    '/drive/v1/files/${Uri.encodeComponent(id)}',
    query: {'usage': 'FETCH'},
  );

  Future<List<Json>> files(String rootId) async {
    final root = await file(rootId);
    if (root['kind'] != 'drive#folder') {
      return [
        {...root, 'path': root['name']},
      ];
    }
    final result = <Json>[];
    Future<void> visit(String id, String prefix) async {
      var page = '';
      do {
        final response = await _request(
          'GET',
          '/drive/v1/files',
          query: {
            'parent_id': id,
            'limit': '100',
            'page_token': page,
            'filters': jsonEncode({
              'trashed': {'eq': false},
            }),
          },
        );
        for (final entry in objects(response['files'])) {
          final path = '$prefix${entry['name']}';
          if (entry['kind'] == 'drive#folder') {
            await visit('${entry['id']}', '$path/');
          } else {
            result.add({...entry, 'path': path});
          }
        }
        page = '${response['next_page_token'] ?? ''}';
      } while (page.isNotEmpty);
    }

    await visit(rootId, '');
    return result;
  }

  static bool _isCaptchaError(PikPakException error) =>
      error.code == 9 || error.code == 4002;

  static int _integer(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  Future<Json> _send(
    String method,
    Uri uri, {
    Json? body,
    String? token,
    String? captcha,
  }) async {
    if (_closed) throw const PikPakException('PikPak 服务已关闭。');
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'Mozilla/5.0 Melonbang/1.0',
            'Referer': 'https://mypikpak.com/',
            'X-Client-Id': _clientId,
            'X-Client-Version': _clientVersion,
            'X-Device-Id': _deviceId,
            if (token != null) 'Authorization': 'Bearer $token',
            'X-Captcha-Token': ?captcha,
          });
    if (body != null) request.body = jsonEncode(body);
    _requests.add(abort);
    http.Response response;
    try {
      response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException('PikPak 请求超时。');
            },
          );
    } finally {
      _requests.remove(abort);
    }
    Json result;
    try {
      result = object(jsonDecode(utf8.decode(response.bodyBytes)));
    } on FormatException {
      throw PikPakException('PikPak 返回了无效响应（HTTP ${response.statusCode}）。');
    }
    final code = _integer(result['error_code']);
    if (response.statusCode >= 400 || code != 0 || result['error'] != null) {
      var message =
          '${result['error_description'] ?? result['error'] ?? '请求失败'}';
      if (result['error'] == 'invalid_account_or_password') {
        message = '账号或密码不正确';
      } else if (code == 4126 || result['error'] == 'invalid_grant') {
        message = '登录已过期，请重新登录';
      }
      throw PikPakException(
        'PikPak：$message',
        code: code,
        status: response.statusCode,
      );
    }
    return result;
  }

  void _checkGeneration(int generation) {
    if (_closed || generation != _generation) {
      throw const PikPakException('PikPak 账号已更改，请重试。');
    }
  }

  void close() {
    _closed = true;
    ++_generation;
    for (final abort in _requests) {
      if (!abort.isCompleted) abort.complete();
    }
    _http.close();
  }
}
