import 'dart:convert';

import '../../core/network.dart';

/// Follows master playlists to a media playlist and rewrites every URI as
/// absolute. With [filter], drops discontinuity blocks served from a foreign
/// directory (inserted advertisements).
Future<(String, Uri)> fetchPlaylist(
  ApiClient api,
  Uri uri,
  Map<String, String> headers, {
  bool filter = false,
  RequestCancellation? cancel,
}) async {
  for (var depth = 0; depth < 4; depth++) {
    final response = await api.send(uri, headers: headers, cancel: cancel);
    final text = utf8.decode(response.bodyBytes);
    if (!text.trimLeft().startsWith('#EXTM3U')) {
      throw StateError('站点没有返回有效 m3u8');
    }
    final lines = text.split(RegExp(r'\r?\n'));
    if (lines.any((line) => line.startsWith('#EXT-X-STREAM-INF'))) {
      final next = lines
          .where((line) => line.trim().isNotEmpty && !line.startsWith('#'))
          .firstOrNull;
      if (next == null) throw StateError('主清单没有播放线路');
      uri = uri.resolve(next.trim());
      continue;
    }
    final rendered = filter
        ? filterPlaylist(text, uri)
        : absolutePlaylist(text, uri);
    return (rendered, uri);
  }
  throw StateError('m3u8 清单嵌套层数过多');
}

String absolutePlaylist(String text, Uri base) => text
    .split(RegExp(r'\r?\n'))
    .map((line) {
      if (line.isNotEmpty && !line.startsWith('#')) {
        return base.resolve(line.trim()).toString();
      }
      return line.replaceAllMapped(
        RegExp('URI="([^"]+)"'),
        (match) => 'URI="${base.resolve(match[1]!)}"',
      );
    })
    .join('\n');

String filterPlaylist(String text, Uri base) {
  final blocks = text.split('#EXT-X-DISCONTINUITY');
  final directory = base.resolve('.').path;
  final kept = <String>[];
  for (final block in blocks) {
    final segments = block
        .split(RegExp(r'\r?\n'))
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .map((line) => base.resolve(line.trim()))
        .toList();
    // Content segments may use a separate CDN host from the playlist.
    if (segments.isEmpty ||
        segments.every((segment) => segment.path.startsWith(directory))) {
      kept.add(block.replaceAll('#EXT-X-ENDLIST', '').trim());
    }
  }
  final result = kept.join('\n#EXT-X-DISCONTINUITY\n');
  if (!result.contains('#EXTM3U')) throw StateError('过滤后没有正片清单');
  return absolutePlaylist(
    '$result\n${text.contains('#EXT-X-ENDLIST') ? '#EXT-X-ENDLIST\n' : ''}',
    base,
  );
}
