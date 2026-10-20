enum DanmakuMode { scroll, top, bottom }

class DanmakuComment {
  const DanmakuComment(
    this.time,
    this.text, {
    required this.source,
    this.mode = DanmakuMode.scroll,
    this.color = 0xffffff,
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

/// An episode offered for confirmation when matching is ambiguous.
class DanmakuCandidate {
  const DanmakuCandidate({
    required this.locator,
    required this.title,
    required this.episode,
  });
  final String locator, title, episode;
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
  const DanmakuQuery({required this.episode, this.file});

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
}

/// A matcher whose episodes can also be searched by title.
abstract interface class DanmakuSearch implements DanmakuMatcher {
  Future<List<DanmakuCandidate>> search(String title);
}
