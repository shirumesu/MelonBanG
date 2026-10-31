import 'sources.dart';

enum DanmakuMode { scroll, top, bottom }

class DanmakuComment {
  const DanmakuComment(
    this.time,
    this.text, {
    required this.source,
    this.mode = DanmakuMode.scroll,
    this.color = 0xffffff,
    this.own = false,
  });

  /// A valid comment, or null when time/text/mode are unusable.
  static DanmakuComment? parse({
    required String source,
    required Object? time,
    required Object? text,
    required DanmakuMode? mode,
    int? color,
  }) {
    final trimmed = text is String ? text.trim() : '';
    if (time is! num || !time.isFinite || time < 0 || trimmed.isEmpty) {
      return null;
    }
    if (mode == null) return null;
    return DanmakuComment(
      time.toDouble(),
      trimmed,
      source: source,
      mode: mode,
      color: color ?? 0xffffff,
    );
  }

  final double time;
  final String text;

  /// Provider id; merging keeps sources apart.
  final String source;
  final DanmakuMode mode;

  /// 0xRRGGBB.
  final int color;

  /// Sent from this app in the current session; drawn framed and never
  /// merged or filtered away.
  final bool own;
}

/// `#rrggbb`, or null.
int? hexColor(Object? value) =>
    value is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)
    ? int.parse(value.substring(1), radix: 16)
    : null;

/// Collapses equal comments of a source (colour ignored) and sorts by time.
List<DanmakuComment> sortedComments(Iterable<DanmakuComment?> input) {
  final unique = <(String, double, DanmakuMode, String), DanmakuComment>{};
  for (final comment in input) {
    if (comment == null) continue;
    unique[(comment.source, comment.time, comment.mode, comment.text)] =
        comment;
  }
  return unique.values.toList()..sort((a, b) => a.time.compareTo(b.time));
}

/// An episode offered for confirmation when matching is ambiguous, or a row
/// of a manual search: an episode to load, or a group (series, version
/// list, collection, multi-part video) to open.
class DanmakuCandidate {
  const DanmakuCandidate({
    required this.title,
    this.subtitle,
    this.locator,
    this.open,
    this.site,
  });
  final String title;
  final String? subtitle;

  /// The resource search's entry a search row stands for, checked against
  /// the playing subject the way resource search checks it.
  final SourceSubject? site;

  /// The episode to load; null for a group.
  final String? locator;

  /// A group's rows.
  final Future<List<DanmakuCandidate>> Function()? open;
}

class DanmakuMatch {
  const DanmakuMatch.found(String this.locator)
    : candidates = const [],
      message = null;
  const DanmakuMatch.suggested(this.candidates)
    : locator = null,
      message = '找到候选剧集，请选择确认';
  const DanmakuMatch.none(String this.message)
    : locator = null,
      candidates = const [];
  final String? locator;
  final List<DanmakuCandidate> candidates;

  /// Why nothing was loaded automatically.
  final String? message;
  bool get empty => locator == null && candidates.isEmpty;
}

/// Matching cannot proceed; reported as unmatched rather than an error.
class DanmakuUnmatched implements Exception {
  const DanmakuUnmatched(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The catalogue episode being played.
class DanmakuEpisode {
  const DanmakuEpisode({
    required this.subjectId,
    required this.title,
    required this.names,
    required this.number,
  });
  final int subjectId;
  final String title;

  /// Catalogue title and aliases.
  final List<String> names;
  final double number;
}

class DanmakuFile {
  const DanmakuFile({
    required this.path,
    required this.duration,
    this.size,
    this.filenameOnly = false,
  });
  final String path;
  final double duration;
  final int? size;

  /// Incomplete or remote media must not be read for a fingerprint.
  final bool filenameOnly;
}

class DanmakuQuery {
  const DanmakuQuery({required this.episode, this.episodeId, this.file});

  /// The Bangumi episode being played, when the session is bound to one.
  final int? episodeId;

  /// Resolved lazily and shared by providers; throws [DanmakuUnmatched] when
  /// the episode is unknown.
  final Future<DanmakuEpisode> Function() episode;
  final DanmakuFile? file;
}

/// A source of comments addressed by a provider-specific locator: an episode
/// id, a playback URL, or a local file path.
abstract interface class DanmakuProvider {
  String get id;
  String get label;
  Future<List<DanmakuComment>> load(String locator);
}

/// A provider that can find a locator for the playing episode on its own.
abstract interface class DanmakuMatcher implements DanmakuProvider {
  Future<DanmakuMatch> match(DanmakuQuery query);

  /// What the source holds and how it is matched, for the data sources page.
  String get description;

  /// Why this build cannot use the source at all; null when it can.
  String? get unconfigured;
}

/// A provider that takes comments for an episode it has loaded.
abstract interface class DanmakuSender implements DanmakuProvider {
  /// Why sending is impossible now, such as being signed out; null when
  /// it can send.
  String? get unavailable;

  /// Sends [comment] and returns what may still be sent.
  Future<DanmakuQuota> send(String locator, DanmakuComment comment);

  /// What the viewer may still send.
  Future<DanmakuQuota> quota();
}

/// How much one viewer may still send.
class DanmakuQuota {
  const DanmakuQuota({
    required this.limit,
    required this.remaining,
    this.wait = Duration.zero,
  });
  final int limit, remaining;

  /// Until the next comment may go.
  final Duration wait;
}

/// A send turned away for its pace or the daily limit.
class DanmakuSendRejected implements Exception {
  const DanmakuSendRejected(this.message, this.quota);
  final String message;
  final DanmakuQuota? quota;
  @override
  String toString() => message;
}

/// A matcher whose episode the viewer can also pick by hand, searching by
/// title or pasted link; the playing episode alone decides other matchers.
abstract interface class DanmakuSearch implements DanmakuMatcher {
  Future<List<DanmakuCandidate>> search(String title);
}

/// A provider that carries an episode picked by hand over to the subject's
/// other episodes, within the same multi-part video, collection or season.
abstract interface class DanmakuFollower implements DanmakuProvider {
  /// The episode numbered [to] beside [locator], which was picked for
  /// episode [from]; null unless exactly one plausible episode is found.
  Future<DanmakuCandidate?> follow(String locator, double from, double to);
}
