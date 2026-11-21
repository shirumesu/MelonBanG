import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/credentials.dart';
import '../../core/json.dart';
import '../../core/network.dart';

/// A login QR code: what it encodes and the key its state is asked by.
typedef BilibiliQr = ({String url, String key});

/// Where a login QR code stands.
enum BilibiliQrState { waiting, scanned, expired, signedIn }

/// The Bilibili account the app reads as, signed in by scanning a QR code
/// with the Bilibili app, so no password passes through the app. Its
/// cookies go with every Bilibili API request: a guest gets a fraction of
/// an episode's comments, an account most of them, and 大会员 the members'
/// episodes and higher quality too. A sign-in Bilibili no longer accepts
/// lapses back to a guest, until the next scan.
class BilibiliAccount extends ChangeNotifier {
  BilibiliAccount(this.api, this.credentials);
  final ApiClient api;
  final Credentials credentials;

  static const _key = 'bilibili';
  static const headers = {
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://www.bilibili.com/',
  };

  /// SESSDATA, bili_jct and DedeUserID, as Bilibili sets them.
  Map<String, String>? _cookies;

  /// The account's name, and its membership: whether 大会员 is active and
  /// what Bilibili calls it (年度大会员).
  String? name, membership;
  bool vip = false;

  /// Why the account signed out by itself.
  String? lapsed;

  bool get signedIn => _cookies != null;

  /// The account's cookies for a request's `Cookie` header.
  String? get cookie => switch (_cookies) {
    final cookies? => [
      for (final MapEntry(:key, :value) in cookies.entries) '$key=$value',
    ].join('; '),
    null => null,
  };

  /// Reads the saved sign-in, then checks it with Bilibili in the
  /// background.
  Future<void> initialize() async {
    try {
      final saved = await credentials.read(_key, allowInteraction: false);
      if (saved != null) {
        final value = object(jsonDecode(saved));
        final cookies = object(value['cookies']);
        if (cookies['SESSDATA'] is String) {
          _cookies = {
            for (final MapEntry(:key, :value) in cookies.entries)
              if (value is String) key: value,
          };
          name = value['name'] as String?;
          membership = value['membership'] as String?;
          vip = value['vip'] == true;
        }
      }
    } catch (_) {
      // An unreadable sign-in counts as none.
    }
    if (signedIn) unawaited(refresh());
  }

  /// Reads the account's name and membership again; a sign-in Bilibili no
  /// longer accepts lapses. Offline, the account stays as it was. Any other
  /// answer, such as risk control's -352 or a rate limit's, says nothing of
  /// the sign-in, so it stays too and the call fails.
  Future<void> refresh() async {
    final cookie = this.cookie;
    if (cookie == null) return;
    final Json value;
    try {
      value = await api.map(
        Uri.https('api.bilibili.com', '/x/web-interface/nav'),
        headers: {...headers, 'Cookie': cookie},
      );
    } catch (_) {
      return;
    }
    if (cookie != this.cookie) return;
    final code = value['code'];
    final data = object(value['data']);
    // -101 is Bilibili's 账号未登录.
    if (code == -101 || (code == 0 && data['isLogin'] == false)) {
      await lapse();
      return;
    }
    if (code != 0 || data['isLogin'] != true) {
      throw StateError('B 站没有返回登录状态（$code），稍后再试');
    }
    name = data['uname'] as String?;
    vip = data['vipStatus'] == 1;
    membership = vip
        ? switch (object(data['vip_label'])['text']) {
            final String text when text.isNotEmpty => text,
            _ => '大会员',
          }
        : null;
    await _save();
    notifyListeners();
  }

  /// Signs out a sign-in Bilibili turned down, saying so.
  Future<void> lapse() async {
    if (!signedIn) return;
    _clear();
    lapsed = 'B 站登录已过期，重新扫码登录';
    await credentials.write(_key, null);
    notifyListeners();
  }

  /// A new login QR code, valid for three minutes.
  Future<BilibiliQr> startLogin() async {
    final value = await api.map(
      Uri.https(
        'passport.bilibili.com',
        '/x/passport-login/web/qrcode/generate',
      ),
      headers: headers,
    );
    final data = object(value['data']);
    if (value['code'] != 0 || data['url'] is! String) {
      throw StateError('B 站没有给出登录二维码，稍后再试');
    }
    return (url: data['url'] as String, key: '${data['qrcode_key']}');
  }

  /// Where [qr] stands; signs in once the phone confirms it. The caller
  /// reads the name and membership with [refresh] next, so failing to read
  /// them leaves the sign-in standing.
  Future<BilibiliQrState> poll(BilibiliQr qr) async {
    final response = await api.send(
      Uri.https('passport.bilibili.com', '/x/passport-login/web/qrcode/poll', {
        'qrcode_key': qr.key,
      }),
      headers: headers,
    );
    final data = object(
      object(await decodeJsonBytes(response.bodyBytes))['data'],
    );
    switch (data['code']) {
      case 86101:
        return BilibiliQrState.waiting;
      case 86090:
        return BilibiliQrState.scanned;
      case 86038:
        return BilibiliQrState.expired;
      case 0:
        // The cookies come back set on the response and in the address the
        // page would go on to, both still encoded as Bilibili sets them.
        final query = Uri.tryParse('${data['url']}')?.query ?? '';
        final cookies = {
          for (final match in _setCookie.allMatches(
            response.headers['set-cookie'] ?? '',
          ))
            match[1]!: match[2]!,
          for (final pair in query.split('&'))
            if (pair.split('=') case [final key, final value]
                when _cookieNames.contains(key))
              key: value,
        };
        if (cookies['SESSDATA'] == null) {
          throw StateError('B 站登录没有返回凭据，重新扫码试试');
        }
        _cookies = cookies;
        lapsed = null;
        await _save();
        notifyListeners();
        return BilibiliQrState.signedIn;
      default:
        throw StateError('${data['message'] ?? 'B 站登录失败'}');
    }
  }

  /// Ends the sign-in on Bilibili too, so the cookies stop working.
  Future<void> signOut() async {
    final cookie = this.cookie;
    final csrf = _cookies?['bili_jct'];
    _clear();
    lapsed = null;
    await credentials.write(_key, null);
    notifyListeners();
    if (cookie == null || csrf == null) return;
    try {
      await api.send(
        Uri.https('passport.bilibili.com', '/login/exit/v2'),
        method: 'POST',
        body: {'biliCSRF': csrf},
        headers: {...headers, 'Cookie': cookie},
      );
    } catch (_) {
      // Signed out here all the same; Bilibili ends it in time.
    }
  }

  void _clear() {
    _cookies = null;
    name = null;
    membership = null;
    vip = false;
  }

  Future<void> _save() => credentials.write(
    _key,
    jsonEncode({
      'cookies': _cookies,
      'name': name,
      'membership': membership,
      'vip': vip,
    }),
  );

  static final _setCookie = RegExp(
    r'(?:^|[,;]\s*)(SESSDATA|bili_jct|DedeUserID|DedeUserID__ckMd5)=([^;,\s]+)',
  );

  static const _cookieNames = {
    'SESSDATA',
    'bili_jct',
    'DedeUserID',
    'DedeUserID__ckMd5',
  };
}
