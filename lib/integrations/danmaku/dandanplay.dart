import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/json.dart';
import '../../core/network.dart';
import '../../core/service_configuration.dart';
import '../../domain/danmaku.dart';
import 'matching.dart';

/// Dandanplay: Bangumi mapping, then title search, then file matching.
class DandanplayDanmaku implements DanmakuSearch {
  DandanplayDanmaku(this.api, this.configuration);
  final ApiClient api;
  final ServiceConfiguration configuration;

  @override
  String get id => 'dandanplay';
  @override
  String get label => '弹弹play';

  @override
  String get description =>
      '先按 Bangumi 条目对应，再按番名和集数搜索，最后按文件匹配；'
      '包含弹弹play 关联的其他网站弹幕。';
  @override
  String? get unconfigured =>
      configuration.hasDandanplay ? null : '此版本没有弹弹play 应用凭证';
  @override
  bool get manual => true;

  Future<Json> _request(String path, {Json? body}) async {
    if (!configuration.hasDandanplay) {
      throw StateError('此版本尚未启用弹弹play，请使用其他弹幕来源或已配置的应用版本。');
    }
    final appId = configuration.dandanplayAppId.trim();
    final appSecret = configuration.dandanplayAppSecret.trim();
    final uri = Uri.parse('https://api.dandanplay.net$path');
    final timestamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final signature = base64Encode(
      sha256
          .convert(utf8.encode('$appId$timestamp${uri.path}$appSecret'))
          .bytes,
    );
    return api.map(
      uri,
      method: body == null ? 'GET' : 'POST',
      body: body,
      headers: {
        'X-AppId': appId,
        'X-Timestamp': timestamp,
        'X-Signature': signature,
      },
    );
  }

  @override
  Future<List<DanmakuCandidate>> search(String title) async =>
      (await _search(title)).map(_candidate).toList();

  Future<List<Json>> _search(String title, {double? episode}) async {
    final value = await _request(
      '/api/v2/search/episodes?anime=${Uri.encodeQueryComponent(title)}'
      '${episode == null ? '' : '&episode=${episode.toInt()}'}',
    );
    if (value['success'] != true) throw StateError('弹弹play搜索失败');
    return objects(value['animes'])
        .expand(
          (anime) => objects(anime['episodes']).map(
            (e) => {
              ...e,
              'animeTitle': anime['animeTitle'],
              'animeId': anime['animeId'],
            },
          ),
        )
        .toList();
  }

  @override
  Future<DanmakuMatch> match(DanmakuQuery query) async {
    final file = query.file;
    final DanmakuEpisode episode;
    try {
      episode = await query.episode();
    } catch (_) {
      // A missing catalogue episode must not prevent filename matching.
      if (file == null) rethrow;
      return _found(await _matchFile(file));
    }
    var match = const DanmakuMatch.none('');
    try {
      match = await _matchBangumi(episode.subjectId, episode.number);
    } catch (_) {
      // Mapping availability is independent of episode search.
    }
    if (match.empty) match = await _matchTitles(episode.names, episode.number);
    if (match.empty && file != null) match = await _matchFile(file);
    return _found(match);
  }

  DanmakuMatch _found(DanmakuMatch match) =>
      match.empty ? const DanmakuMatch.none('未匹配到唯一章节') : match;

  Future<DanmakuMatch> _matchBangumi(int subjectId, double episode) async {
    if (!episode.isFinite || episode <= 0) return const DanmakuMatch.none('');
    final value = await _request('/api/v2/bangumi/bgmtv/$subjectId');
    if (value['success'] != true) {
      throw StateError('弹弹play条目映射失败：${value['errorMessage'] ?? '未知错误'}');
    }
    final bangumi = object(value['bangumi']);
    final candidates = objects(bangumi['episodes'])
        .where((item) => episodeNumber('${item['episodeNumber']}') == episode)
        .where((item) => positiveId(item['episodeId']) != null)
        .map((item) => {...item, 'animeTitle': bangumi['animeTitle']})
        .toList();
    return _matched(candidates.length == 1 ? candidates.single : null, [
      ...candidates,
    ]);
  }

  Future<DanmakuMatch> _matchTitles(
    Iterable<String> names,
    double episode,
  ) async {
    if (!episode.isFinite ||
        episode <= 0 ||
        episode != episode.roundToDouble()) {
      return const DanmakuMatch.none('');
    }
    final titles = names
        .map((name) => name.trim())
        .where((name) => name.length >= 2)
        .toSet();
    final normalized = titles.map(normalizedTitle).toSet();
    final candidates = <String, Json>{};
    for (final title in titles) {
      for (final item in await _search(title, episode: episode)) {
        final id = positiveId(item['episodeId']);
        if (id != null) candidates[id] = item;
      }
    }
    final exact = candidates.values.where((item) {
      final prefix = RegExp(r'^第\s*(\d+)\s*[話话集](?:\s|$)')
          .firstMatch('${item['episodeTitle']}');
      final number =
          episodeNumber('${item['episodeNumber'] ?? item['episodeTitle']}') ??
          (prefix == null ? null : double.tryParse(prefix[1]!));
      return normalized.contains(normalizedTitle('${item['animeTitle']}')) &&
          number == episode;
    }).toList();
    return _matched(
      exact.length == 1 ? exact.single : null,
      exact.isEmpty ? candidates.values : exact,
    );
  }

  Future<DanmakuMatch> _matchFile(DanmakuFile file) async {
    var size = file.size;
    String? hash;
    if (!file.filenameOnly) {
      final path = file.path;
      final fingerprint = await Isolate.run(() => _fileFingerprint(path));
      hash = fingerprint.$1;
      size = fingerprint.$2;
    }
    final value = await _request(
      '/api/v2/match',
      body: {
        'fileName': p.basenameWithoutExtension(file.path),
        'fileHash': ?hash,
        if (size != null && size > 0) 'fileSize': size,
        'videoDuration': file.duration.isFinite && file.duration > 0
            ? file.duration.round()
            : 0,
        'matchMode': file.filenameOnly ? 'fileNameOnly' : 'hashAndFileName',
      },
    );
    if (value['success'] != true) {
      throw StateError('弹弹play匹配失败：${value['errorMessage'] ?? '未知错误'}');
    }
    final matches = objects(value['matches']);
    if (value['isMatched'] == true && matches.length == 1) {
      final id = positiveId(matches.single['episodeId']);
      if (id == null) throw StateError('弹弹play返回了无效章节');
      return DanmakuMatch.found(id);
    }
    return _matched(
      null,
      matches.where((item) => positiveId(item['episodeId']) != null),
    );
  }

  DanmakuMatch _matched(Json? unique, Iterable<Json> candidates) {
    if (unique != null) {
      return DanmakuMatch.found(positiveId(unique['episodeId'])!);
    }
    final list = candidates.map(_candidate).toList();
    return list.isEmpty
        ? const DanmakuMatch.none('')
        : DanmakuMatch.suggested(list);
  }

  DanmakuCandidate _candidate(Json item) => DanmakuCandidate(
    locator: positiveId(item['episodeId']) ?? '${item['episodeId']}',
    title: '${item['animeTitle'] ?? '候选番剧'}',
    episode: '${item['episodeTitle'] ?? item['episodeNumber'] ?? ''}',
  );

  @override
  Future<List<DanmakuComment>> load(String locator) async {
    final value = await _request(
      '/api/v2/comment/${int.parse(locator)}?withRelated=true&chConvert=1',
    );
    if (value['success'] == false) {
      throw StateError('弹弹play弹幕获取失败：${value['errorMessage'] ?? '未知错误'}');
    }
    final rows = objects(value['comments']);
    return Isolate.run(
      () => sortedComments(
        rows.map((c) {
          final fields = '${c['p']}'.split(',');
          return DanmakuComment.parse(
            source: 'dandanplay',
            time: double.tryParse(fields.first),
            mode: fields.length > 1
                ? danmakuMode(int.tryParse(fields[1]) ?? 1)
                : DanmakuMode.scroll,
            color: fields.length > 2
                ? (int.tryParse(fields[2]) ?? 0xffffff) & 0xffffff
                : null,
            text: c['m'],
          );
        }),
      ),
    );
  }
}

Future<(String, int)> _fileFingerprint(String path) async {
  final file = File(path);
  final handle = await file.open();
  try {
    return (
      md5.convert(await handle.read(16 * 1024 * 1024)).toString(),
      await file.length(),
    );
  } finally {
    await handle.close();
  }
}
