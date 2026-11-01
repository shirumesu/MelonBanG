import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/catalog.dart';
import '../tracking/tracking_repository.dart';
import 'playback_library.dart';

/// Recently watched episodes, which episodes of one subject can play from
/// local files, and the episode lists of the subjects being watched. Bangumi
/// progress overrides saved positions: one it has passed is not offered.
class ResumeController extends ChangeNotifier {
  ResumeController(this.library, this.tracking);
  final PlaybackLibrary library;
  final TrackingRepository tracking;

  List<PlaybackResume> resumable = [];

  /// When each subject last played, most recent first.
  Map<int, DateTime> played = {};

  /// The subjects being watched that have a saved detail, with their
  /// episodes and recorded progress.
  Map<int, Subject> watching = {};

  /// Locally playable episodes of each subject in [watching].
  Map<int, Set<int>> watchingPlayable = {};
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
    final watching = <int, Subject>{
      for (final id in await _watchingIds())
        if (await library.catalog.cached(id) case final detail?)
          id: await tracking.withProgress(detail),
    };
    final watchingPlayable = {
      for (final id in watching.keys) id: await library.playableEpisodes(id),
    };
    if (ticket != _ticket) return;
    resumable = recent;
    this.played = played;
    this.watching = watching;
    this.watchingPlayable = watchingPlayable;
    _subjectId = subjectId;
    _playable = playable;
    _resume = resume;
    notifyListeners();
    unawaited(_loadAiring(ticket));
  }

  Future<List<int>> _watchingIds() async => [
    for (final item in await tracking.collection())
      if (item.status == CollectionStatus.watching) item.id,
  ];

  /// Requests, one at a time, the details of watched subjects with none
  /// saved or with an episode still to air. One that fails keeps what was
  /// saved; a newer refresh takes over.
  Future<void> _loadAiring(int ticket) async {
    final now = DateTime.now();
    for (final id in await _watchingIds()) {
      final saved = watching[id];
      if (saved != null &&
          saved.episodes.isNotEmpty &&
          saved.episodes.every(
            (e) => !e.main || (e.aired?.isBefore(now) ?? false),
          )) {
        continue;
      }
      final Subject detail;
      try {
        detail = await tracking.withProgress(
          await library.catalog.subject(id, forPlayback: true),
        );
      } catch (_) {
        continue;
      }
      final playable = await library.playableEpisodes(id);
      if (ticket != _ticket) return;
      watching = {...watching, id: detail};
      watchingPlayable = {...watchingPlayable, id: playable};
      notifyListeners();
    }
  }
}
