/// A chapter's span in seconds.
typedef ChapterSpan = ({double start, double end});

/// The OP and ED chapters of a file, either of which may be missing.
class OpeningEnding {
  const OpeningEnding({this.opening, this.ending});
  final ChapterSpan? opening, ending;

  // Fansub and BD chapters name the songs OP/ED (or misspell them, as
  // `OPENIG`); Crunchyroll's, kept in many WEB-DL releases, name them
  // Intro and Credits, Netflix's Credits.
  static final _openingName = RegExp(
    r'^\s*(op\b|op\d|open|intro\b|オープニング|片头|片頭|序曲)',
    caseSensitive: false,
  );
  static final _endingName = RegExp(
    r'^\s*(ed\b|ed\d|ending|end\s*credits|credits?\b|outro\b|エンディング|片尾)',
    caseSensitive: false,
  );

  /// Chapters named as OP/ED, the opening in the first half and the ending
  /// in the second; either one not named is a chapter of the usual song
  /// length (80–95 s, or 55–65 s for 10–20 minute episodes) in the first or
  /// last part of the episode, as Animeko does.
  static OpeningEnding? find(
    List<({String title, double start})> chapters,
    double duration,
  ) {
    if (chapters.length < 2 || duration <= 0) return null;
    final sorted = [...chapters]..sort((a, b) => a.start.compareTo(b.start));
    final spans = [
      for (final (index, chapter) in sorted.indexed)
        (
          title: chapter.title,
          span: (
            start: chapter.start,
            end: index + 1 < sorted.length ? sorted[index + 1].start : duration,
          ),
        ),
    ];
    final half = duration / 2;
    final (low, high) = duration > 20 * 60
        ? (80.0, 95.0)
        : duration > 10 * 60
        ? (55.0, 65.0)
        : (0.0, 0.0);
    final songs = [
      for (final chapter in spans)
        if (high > 0 &&
            chapter.span.end - chapter.span.start >= low &&
            chapter.span.end - chapter.span.start <= high)
          chapter.span,
    ];
    final opening =
        spans
            .where(
              (chapter) =>
                  chapter.span.start < half &&
                  _openingName.hasMatch(chapter.title),
            )
            .firstOrNull
            ?.span ??
        songs.where((span) => span.start < duration * .4).firstOrNull;
    final ending =
        spans
            .where(
              (chapter) =>
                  chapter.span.start >= half &&
                  _endingName.hasMatch(chapter.title),
            )
            .lastOrNull
            ?.span ??
        songs.where((span) => span.start > duration * .6).lastOrNull;
    if (opening == null && ending == null) return null;
    return OpeningEnding(opening: opening, ending: ending);
  }
}
