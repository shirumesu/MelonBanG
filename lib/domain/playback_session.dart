import 'sources.dart';

/// What the player opens: a downloaded (or streaming) file, or an online
/// stream. [resumeKey] and the progress keys derived from it are stable.
class PlaybackSession {
  const PlaybackSession({
    required this.id,
    required this.title,
    required this.url,
    this.headers = const {},
    this.format,
    this.playlist,
    this.audioUrl,
    this.danmaku,
    this.path,
    this.resumeKey,
    this.streamId,
    this.subjectId,
    this.episodeId,
    this.downloadId,
    this.fileId,
    this.fileSize,
    this.remote = false,
    this.standalone = false,
    this.startSeconds,
  });

  final String id, title, url;
  final Map<String, String> headers;

  /// Online streams only; a [playlist] replaces [url] as the manifest.
  final StreamFormat? format;
  final String? playlist;

  /// An external audio track played with [url]: an online stream's, or the
  /// saved copy of one.
  final String? audioUrl;

  /// A danmaku locator supplied by the stream or its saved copy, as
  /// (provider, locator).
  final (String, String)? danmaku;

  /// Local path of a downloaded file.
  final String? path;

  /// `download:<id>:<fileId>` or `online:<subject>:<episode>`.
  final String? resumeKey;

  /// Set while an incomplete download is streamed.
  final int? streamId;
  final int? subjectId, episodeId;
  final String? downloadId, fileId;
  final int? fileSize;

  /// Not a complete local file.
  final bool remote;

  /// Online playback outside a catalogue episode: no progress or danmaku
  /// matching, no autoplay.
  final bool standalone;

  /// Overrides saved progress, e.g. when recovering mid-episode.
  final double? startSeconds;

  /// Progress storage key.
  String get progressKey => resumeKey ?? url;

  PlaybackSession startingAt(double seconds) => PlaybackSession(
    id: id,
    title: title,
    url: url,
    headers: headers,
    format: format,
    playlist: playlist,
    audioUrl: audioUrl,
    danmaku: danmaku,
    path: path,
    resumeKey: resumeKey,
    streamId: streamId,
    subjectId: subjectId,
    episodeId: episodeId,
    downloadId: downloadId,
    fileId: fileId,
    fileSize: fileSize,
    remote: remote,
    standalone: standalone,
    startSeconds: seconds,
  );
}
