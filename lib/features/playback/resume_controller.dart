import 'package:flutter/foundation.dart';

import 'playback_library.dart';

/// Recently watched episodes, and which episodes of one subject can play
/// from local files.
class ResumeController extends ChangeNotifier {
  ResumeController(this.library);
  final PlaybackLibrary library;

  List<PlaybackResume> resumable = [];
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

  Future<void> refresh(int? subjectId) async {
    final ticket = ++_ticket;
    final recent = await library.recent();
    final resume =
        recent.where((item) => item.subject.id == subjectId).firstOrNull ??
        (subjectId == null
            ? null
            : (await library.recent(
                limit: 1,
                forSubject: subjectId,
              )).firstOrNull);
    final playable = subjectId == null
        ? null
        : await library.playableEpisodes(subjectId);
    if (ticket != _ticket) return;
    resumable = recent;
    _subjectId = subjectId;
    _playable = playable;
    _resume = resume;
    notifyListeners();
  }
}
