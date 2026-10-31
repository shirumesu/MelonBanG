import '../core/cancellation.dart';
import '../core/json.dart';

/// Highest rule engine version this client can run. Rules with a higher
/// `minEngine` are listed but never executed.
const sourceEngineVersion = 2;

/// What a source instance yields: instant streams or torrent releases.
enum SourceKind { online, torrent }

/// One maintained source, declared by a rule. The engine is code; everything
/// site-specific lives in [config] and is interpreted only by that engine.
final class SourceInstance {
  SourceInstance({
    required this.id,
    required this.name,
    required this.engine,
    required this.kind,
    required this.baseUrls,
    required this.config,
    this.website,
    this.description,
    this.manualOnly = false,
    this.disabled = false,
    this.minEngine = 1,
  });

  factory SourceInstance.fromJson(Json rule) {
    if (rule['id'] is! String ||
        rule['name'] is! String ||
        rule['baseUrls'] is! List ||
        rule['engine'] is! String) {
      throw const FormatException('来源规则不完整');
    }
    return SourceInstance(
      id: rule['id'] as String,
      name: rule['name'] as String,
      engine: rule['engine'] as String,
      kind: rule['kind'] == 'torrent' ? SourceKind.torrent : SourceKind.online,
      baseUrls: [for (final url in rule['baseUrls'] as List) '$url'],
      website: rule['website'] as String?,
      description: rule['description'] as String?,
      manualOnly: rule['manualOnly'] == true,
      disabled: rule['disabled'] == true,
      minEngine: number(rule['minEngine'] ?? 1).toInt(),
      config: rule,
    );
  }

  final String id, name, engine;
  final SourceKind kind;
  final List<String> baseUrls;
  final String? website, description;
  final bool manualOnly, disabled;
  final int minEngine;
  final Json config;
  bool get supported => minEngine <= sourceEngineVersion;
}

/// A versioned rule set, as served by Melon API or bundled with the app.
final class SourceSnapshot {
  SourceSnapshot({
    required this.version,
    required this.updatedAt,
    required this.instances,
    required this.json,
  });

  factory SourceSnapshot.fromJson(Json value) {
    if (value['version'] is! String || value['rules'] is! List) {
      throw const FormatException('规则格式无效');
    }
    return SourceSnapshot(
      version: value['version'] as String,
      updatedAt: DateTime.tryParse('${value['updatedAt']}'),
      instances: objects(value['rules']).map(SourceInstance.fromJson).toList(),
      json: value,
    );
  }

  final String version;
  final DateTime? updatedAt;
  final List<SourceInstance> instances;

  /// The original payload, kept for the local rule cache.
  final Json json;
}

class SourceVerificationRequired implements Exception {
  const SourceVerificationRequired(this.url);
  final String url;
  @override
  String toString() => '站点需要人机验证，请在浏览器打开 $url';
}

/// A title on an online site. [data] is private to the producing engine.
final class SourceSubject {
  const SourceSubject({
    required this.id,
    required this.title,
    this.year,
    this.episodeTotal,
    this.line,
    this.description,
    this.choosePart = false,
    this.durationSeconds,
    this.publishedAt,
    this.tags = const [],
    this.danmakuCount,
    this.direct = false,
    this.data = const {},
  });
  final String id, title;
  final int? year, episodeTotal;
  final String? line, description;

  /// The entry is a single upload whose parts must be chosen explicitly.
  final bool choosePart;

  /// Total length, publication time and uploader tags of an upload.
  final int? durationSeconds;
  final DateTime? publishedAt;
  final List<String> tags;

  /// Comments posted on an upload, across its parts.
  final int? danmakuCount;

  /// Looked up by an identifier the user entered rather than found by title,
  /// so it is never filtered out as a mismatch.
  final bool direct;
  final Json data;
}

/// Engine-private locator of one playable entry.
final class StreamRef {
  const StreamRef(this.sourceId, this.data);
  final String sourceId;
  final Json data;
}

final class SourceEpisode {
  const SourceEpisode({
    required this.label,
    required this.line,
    required this.ref,
    this.description,
  });
  final String label, line;
  final String? description;
  final StreamRef ref;
}

enum StreamFormat {
  hls('hls'),
  file('mp4');

  const StreamFormat(this.key);
  final String key;
}

final class ResolvedStream {
  const ResolvedStream({
    required this.url,
    required this.format,
    required this.sourceId,
    this.headers = const {},
    this.playlist,
    this.audioUrl,
    this.line,
    this.quality,
    this.danmakuProvider,
    this.danmakuLocator,
  });
  final String url, sourceId;
  final StreamFormat format;
  final Map<String, String> headers;

  /// Filtered HLS manifest to play instead of [url].
  final String? playlist;

  /// Separate audio track played alongside the video at [url].
  final String? audioUrl;
  final String? line, quality, danmakuProvider, danmakuLocator;

  ResolvedStream withPlaylist(String value) => ResolvedStream(
    url: url,
    format: format,
    sourceId: sourceId,
    headers: headers,
    playlist: value,
    audioUrl: audioUrl,
    line: line,
    quality: quality,
    danmakuProvider: danmakuProvider,
    danmakuLocator: danmakuLocator,
  );
}

/// A torrent offered by an index site.
final class TorrentRelease {
  const TorrentRelease({
    required this.title,
    required this.locator,
    this.publishedAt,
    this.sizeBytes,
    this.sizeLabel,
    this.detailUrl,
    this.releaseGroups = const [],
  });
  final String title, locator;
  final String? publishedAt, sizeLabel, detailUrl;
  final int? sizeBytes;

  /// Authoritative groups from site metadata, never parsed from the title.
  final List<String> releaseGroups;

  /// Adds site metadata found for the same torrent.
  TorrentRelease enrich(TorrentRelease metadata) => TorrentRelease(
    title: title,
    locator: locator,
    publishedAt: publishedAt,
    sizeBytes: sizeBytes,
    sizeLabel: metadata.sizeLabel ?? sizeLabel,
    detailUrl: metadata.detailUrl ?? detailUrl,
    releaseGroups: metadata.releaseGroups.isEmpty
        ? releaseGroups
        : metadata.releaseGroups,
  );
}

/// The maintained rule snapshot: one bundled with the app, and conditional
/// reads of the current one.
abstract interface class SourceRules {
  SourceSnapshot get bundled;

  /// Returns `null` when the snapshot matching [etag] is still current.
  Future<({SourceSnapshot snapshot, String? etag})?> fetch({String? etag});
}

/// Creates the engine that runs [instance]; keyed by the rule `engine` name.
typedef SourceEngineFactory = SourceEngine Function(SourceInstance instance);

abstract interface class SourceEngine {
  SourceInstance get instance;
  String get currentBase;
}

abstract interface class OnlineSourceEngine implements SourceEngine {
  Future<List<SourceSubject>> searchSubjects(
    String name, {
    RequestCancellation? cancel,
  });
  Future<List<SourceEpisode>> episodes(
    SourceSubject subject, {
    RequestCancellation? cancel,
  });

  /// Always reads fresh addresses; site links may expire.
  Future<ResolvedStream> resolve(StreamRef ref, {RequestCancellation? cancel});
}

abstract interface class TorrentSourceEngine implements SourceEngine {
  Future<List<TorrentRelease>> search(
    String keyword, {
    RequestCancellation? cancel,
  });

  /// Optional site pages carrying release groups and sizes, published as
  /// they arrive; empty when the instance declares none. [pages] shares page
  /// reads between the keywords of one search.
  Stream<List<TorrentRelease>> metadata(
    String keyword, {
    Map<Uri, Future<String>>? pages,
    RequestCancellation? cancel,
  });
}

/// A torrent search result bound to the subject and chapter it was found for.
final class ReleaseCandidate {
  const ReleaseCandidate({
    required this.candidateId,
    required this.sourceId,
    required this.sourceName,
    required this.release,
    required this.subjectId,
    this.episodeId,
    this.coverUrl,
    this.otherSources = const [],
  });
  final String candidateId, sourceId, sourceName;
  final TorrentRelease release;
  final int subjectId;
  final int? episodeId;
  final String? coverUrl;

  /// Other index sites listing the same torrent; DMHY and Mikan share many.
  final List<String> otherSources;

  ReleaseCandidate withRelease(TorrentRelease value) => ReleaseCandidate(
    candidateId: candidateId,
    sourceId: sourceId,
    sourceName: sourceName,
    release: value,
    subjectId: subjectId,
    episodeId: episodeId,
    coverUrl: coverUrl,
    otherSources: otherSources,
  );

  /// This result, also listed by [source].
  ReleaseCandidate listedBy(String source) =>
      source == sourceId || otherSources.contains(source)
      ? this
      : ReleaseCandidate(
          candidateId: candidateId,
          sourceId: sourceId,
          sourceName: sourceName,
          release: release,
          subjectId: subjectId,
          episodeId: episodeId,
          coverUrl: coverUrl,
          otherSources: [...otherSources, source],
        );
}

enum SearchStatus { loading, ready, partial, error }

/// Per-source progress of a multi-keyword release search.
final class SourceProgress {
  const SourceProgress({
    required this.sourceId,
    required this.sourceName,
    required this.total,
    this.status = SearchStatus.loading,
    this.resultCount = 0,
    this.completed = 0,
    this.failed = 0,
    this.message,
    this.metadataMessage,
  });
  final String sourceId, sourceName;
  final SearchStatus status;
  final int resultCount, completed, failed, total;
  final String? message, metadataMessage;

  SourceProgress copyWith({
    SearchStatus? status,
    int? resultCount,
    int? completed,
    int? failed,
    String? message,
    String? metadataMessage,
  }) => SourceProgress(
    sourceId: sourceId,
    sourceName: sourceName,
    total: total,
    status: status ?? this.status,
    resultCount: resultCount ?? this.resultCount,
    completed: completed ?? this.completed,
    failed: failed ?? this.failed,
    message: message ?? this.message,
    metadataMessage: metadataMessage ?? this.metadataMessage,
  );
}

final class ReleaseSearchResult {
  const ReleaseSearchResult({
    this.candidates = const [],
    this.sources = const [],
  });
  final List<ReleaseCandidate> candidates;
  final List<SourceProgress> sources;
}

/// In-memory health of a source in this run; never reported or persisted.
enum SourceHealth { enabled, error, verification, update, disabled }
