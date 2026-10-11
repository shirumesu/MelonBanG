import 'package:flutter/foundation.dart';

import '../tracking/tracking_repository.dart';
import 'playback_library.dart';

/// Recently watched episodes, and which episodes of one subject can play
/// from local files. Bangumi progress overrides saved positions: one it has
/// passed is not offered.
class ResumeController extends ChangeNotifier {
  ResumeController(this.library, this.tracking);
  final PlaybackLibrary library;
  final TrackingRepository tracking;

  List<PlaybackResume> resumable = [];

  /// Subjects by when they last played, most recent first.
  List<int> played = [];
  int? _subjectId;
  PlaybackResume? _resume;
  Set<int>? _playable;
  int _ticket = 0;

  /// The resume point of [subjectId], once loaded for it.
  PlaybackResume? resumeOf(int? subjectId) =>
      subjectId != null && subjectId == _subjectId ? _resume : null;

  /// Locally playable episodes of [subjectId], once loaded for it.
  Set<int>? playableOf(int? subjectId) =>
      subjectId != null && subjectId == _subjectId ? _playable : null;

  /// Pulls Bangumi progress of the recently played subjects; the tracking
  /// change it reports refreshes the resume points.
  Future<void> pull() async => tracking.refreshProgress({
    for (final item in await library.recent()) item.subject.id,
  });

  Future<void> refresh(int? subjectId) async {
    final ticket = ++_ticket;
    final accept = tracking.leavesUnwatched;
    final recent = await library.recent(accept: accept);
    final resume =
        recent.where((item) => item.subject.id == subjectId).firstOrNull ??
        (subjectId == null
            ? null
            : (await library.recent(
                limit: 1,
                forSubject: subjectId,
                accept: accept,
              )).firstOrNull);
    final playable = subjectId == null
        ? null
        : await library.playableEpisodes(subjectId);
    final played = await library.playedSubjects();
    if (ticket != _ticket) return;
    resumable = recent;
    this.played = played;
    _subjectId = subjectId;
    _playable = playable;
    _resume = resume;
    notifyListeners();
  }
}
