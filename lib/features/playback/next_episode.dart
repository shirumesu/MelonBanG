import '../../domain/catalog.dart';
import 'playback_library.dart';

/// Whether [resume] continues [episode] from a saved position.
bool resumesAt(PlaybackResume? resume, Episode episode) =>
    resume?.episodeId == episode.id && (resume?.position ?? 0) > 0;

/// The episode a subject's play button opens: the first unwatched main
/// episode, or special aired after the run, past the furthest watched one,
/// since a gap before it is more often watched elsewhere than skipped; else
/// the first unwatched, else the last main episode. Specials within the run
/// are left to autoplay. The episode to [resume] wins when it is that one or
/// was played for a while.
Episode? nextEpisode(
  List<Episode> episodes, {
  required EpisodeStatus Function(Episode) statusOf,
  required PlaybackResume? resume,
}) {
  final last = episodes.lastIndexWhere((e) => e.main);
  final furthest = episodes.lastIndexWhere(
    (e) => statusOf(e) == EpisodeStatus.watched,
  );
  final unwatched = episodes.indexed.where(
    (e) =>
        (e.$2.main || e.$1 > last) && statusOf(e.$2) != EpisodeStatus.watched,
  );
  final next =
      (unwatched.where((e) => e.$1 > furthest).firstOrNull ??
              unwatched.firstOrNull)
          ?.$2 ??
      (last < 0 ? episodes.firstOrNull : episodes[last]);
  final resumed = episodes.where((e) => resumesAt(resume, e)).firstOrNull;
  return resumed != null && (resumed == next || resume!.engaged)
      ? resumed
      : next;
}
