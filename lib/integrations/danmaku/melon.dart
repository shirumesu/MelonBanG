import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;

import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/danmaku.dart';
import '../melon_api/source_rules.dart' show melonApiOrigin;
import 'matching.dart';

/// MelonBanG's own danmaku on Melon API. Every episode bound to Bangumi has
/// a library under its episode ID, so nothing needs matching; signed-in
/// viewers send to it with their Bangumi token, one comment every three
/// seconds and 200 a day.
class MelonDanmaku implements DanmakuMatcher, DanmakuSender {
  MelonDanmaku(this.api, {required this.token, required this.signedIn});
  final ApiClient api;

  /// The Bangumi access token; throws while signed out.
  final Future<String> Function() token;
  final bool Function() signedIn;

  @override
  String get id => 'melon';
  @override
  String get label => 'MelonBanG';

  @override
  String get description =>
      'MelonBanG 用户发送的弹幕，按 Bangumi 章节存放，关联了章节的视频都能读到。'
      '登录 Bangumi 后可以在播放器里发送：每 3 秒一条，每天最多 200 条。';
  @override
  String? get unconfigured => null;

  Uri _uri(String path) => Uri.parse('$melonApiOrigin/v1/danmaku/$path');

  @override
  Future<DanmakuMatch> match(DanmakuQuery query) async =>
      switch (query.episodeId) {
        final id? => DanmakuMatch.found('$id'),
        null => const DanmakuMatch.none('没有关联 Bangumi 章节'),
      };

  @override
  Future<List<DanmakuComment>> load(String locator) async {
    final value = await api.map(_uri(locator));
    // A top-level callback: a closure here could capture the client.
    return compute(_comments, objects(value['data']));
  }

  @override
  String? get unavailable => signedIn() ? null : '登录 Bangumi 后发送弹幕';

  @override
  Future<DanmakuQuota> send(String locator, DanmakuComment comment) async =>
      _quota(
        await _authorized(
          _uri(locator),
          method: 'POST',
          body: {
            'time': (comment.time * 1000).round() / 1000,
            'text': comment.text,
            'mode': switch (comment.mode) {
              DanmakuMode.scroll => 1,
              DanmakuMode.bottom => 4,
              DanmakuMode.top => 5,
            },
            'color': comment.color,
          },
        ),
      );

  @override
  Future<DanmakuQuota> quota() async =>
      _quota(await _authorized(_uri('quota')));

  /// A request with the Bangumi token; Melon API's refusals become
  /// [DanmakuSendRejected] with its message.
  Future<Json> _authorized(Uri uri, {String method = 'GET', Json? body}) async {
    final response = await api.send(
      uri,
      method: method,
      body: body,
      headers: {'Authorization': 'Bearer ${await token()}'},
      acceptedStatuses: const {400, 401, 429, 502, 503},
    );
    final value = object(jsonDecode(utf8.decode(response.bodyBytes)));
    if (response.statusCode < 300) return value;
    final error = object(value['error']);
    final details = error['details'];
    throw DanmakuSendRejected(
      '${error['message'] ?? '弹幕发送失败（HTTP ${response.statusCode}）'}',
      details is Map ? _quota(object(details)) : null,
    );
  }

  static DanmakuQuota _quota(Json value) => DanmakuQuota(
    limit: number(value['limit'] ?? 200).toInt(),
    remaining: number(value['remaining'] ?? 0).toInt(),
    wait: Duration(seconds: number(value['waitSeconds'] ?? 0).toInt()),
  );
}

List<DanmakuComment> _comments(List<Json> rows) => sortedComments(
  rows.map(
    (row) => DanmakuComment.parse(
      source: 'melon',
      time: row['time'],
      mode: danmakuMode(number(row['mode'] ?? 1).toInt()),
      color: number(row['color'] ?? 0xffffff).toInt() & 0xffffff,
      text: row['text'],
    ),
  ),
);
