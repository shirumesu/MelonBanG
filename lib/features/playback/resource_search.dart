import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network.dart';
import '../../domain/catalog.dart';
import '../../domain/play_candidate.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';
import '../downloads/download_repository.dart';
import '../acquisition/resource_metadata.dart';
import '../acquisition/source_registry.dart';
import 'play_selection.dart';
import 'playback.dart';

/// One resource search as shown: its context, request terms and results.
class ResourceSearchState {
  const ResourceSearchState({
    this.subject,
    this.episode,
    this.searched,
    this.terms,
    this.candidates = const [],
    this.sources = const [],
    this.remembered,
  });
  final Subject? subject;

  /// The chapter playback and downloads associate with; null searches the
  /// whole subject.
  final Episode? episode;

  /// The episode the terms name ([keywordEpisode]); null searches the whole
  /// subject.
  final Episode? searched;

  /// Terms of the latest search; null before the first one.
  final ResourceTerms? terms;
  final List<PlayCandidate> candidates;
  final List<SourceProgress> sources;

  /// Progress of the sites searched, without PikPak, which only looks up the
  /// torrents they list.
  List<SourceProgress> get sites =>
      sources.where((e) => e.sourceId != 'pikpak').toList();

  /// PikPak's lookups of the torrents found, while it takes part.
  SourceProgress? get cloud =>
      sources.where((e) => e.sourceId == 'pikpak').firstOrNull;

  /// The source the subject was last played from, which ranks first.
  final RememberedSource? remembered;

  ResourceSearchState withCandidates(List<PlayCandidate> value) =>
      ResourceSearchState(
        subject: subject,
        episode: episode,
        searched: searched,
        terms: terms,
        candidates: value,
        sources: sources,
        remembered: remembered,
      );
}

/// Searches online sources, torrent indexes and PikPak's index together for
/// a subject or one of its chapters. Starting a new search or [cancel]
/// cancels the running one.
class ResourceSearchController extends ChangeNotifier {
  ResourceSearchController(this.selection, this.playback) {
    playback.settings.addListener(_rerank);
  }
  final PlaySelectionRepository selection;
  final Playback playback;

  /// Ranks what the current search found; run again when preferences such
  /// as the preferred groups change.
  List<PlayCandidate> Function()? _rank;

  DownloadRepository get downloads => selection.downloads;

  ResourceSearchState state = const ResourceSearchState();
  bool busy = false;
  int _ticket = 0;
  RequestCancellation _cancel = RequestCancellation();

  SourceRegistry get sources => selection.registry;

  /// Shows [subject] with no results yet.
  void open(Subject? subject, {Episode? episode}) {
    cancel();
    _rank = null;
    state = ResourceSearchState(subject: subject, episode: episode);
    notifyListeners();
  }

  void restore(ResourceSearchState value) {
    cancel();
    _rank = null;
    state = value;
    notifyListeners();
  }

  void cancel() {
    _cancel.cancel();
    _ticket++;
    busy = false;
  }

  void _rerank() {
    if (_rank case final rank?) {
      state = state.withCandidates(rank());
      notifyListeners();
    }
  }

  Future<void> search(ResourceTerms terms) async {
    final subject = state.subject;
    if (subject == null || terms.searchNames.isEmpty) return;
    _cancel.cancel();
    final cancellation = _cancel = RequestCancellation();
    final ticket = ++_ticket;
    final episode = state.episode;
    final searched = keywordEpisode(subject, terms.episodeKeyword, episode);
    var candidates = const <PlayCandidate>[];
    // Ranked only when shown: PikPak reports its lookups one at a time.
    _rank = null;
    var stale = false;
    RememberedSource? remembered;
    final progress = <String, SourceProgress>{};
    Timer? pending;
    void show() {
      pending?.cancel();
      pending = null;
      if (ticket != _ticket) return;
      if (stale) {
        candidates = _rank!();
        stale = false;
      }
      state = ResourceSearchState(
        subject: subject,
        episode: episode,
        searched: searched,
        terms: terms,
        candidates: candidates,
        sources: progress.values.toList(),
        remembered: remembered,
      );
      notifyListeners();
    }

    // Results and progress arrive in bursts (a page of torrents, a PikPak
    // lookup per torrent); rebuilding the page for each would stall it.
    void showSoon() =>
        pending ??= Timer(const Duration(milliseconds: 120), show);

    busy = true;
    show();
    final settings = playback.settings;
    try {
      remembered = await selection.remembered(subject.id);
      candidates = await selection.candidates(
        subject,
        searched,
        terms: terms,
        includeDownloads: false,
        cancel: cancellation,
        onlineFirst:
            (subject.airing()
                ? settings.airingPriority
                : settings.completedPriority) ==
            'online',
        language: settings.subtitleLanguage,
        useContinuity: playback.session?.subjectId == subject.id,
        onUpdate: (rank) {
          _rank = rank;
          stale = true;
          showSoon();
        },
        onProgress: (value) {
          progress[value.sourceId] = value;
          showSoon();
        },
      );
      stale = false;
      show();
      unawaited(
        settings.recordGroups([
          for (final candidate in candidates)
            if (candidate.kind == PlayKind.bt)
              ...describeCandidate(candidate).sourceGroups,
        ]),
      );
    } on RequestCancelled {
      // A newer search or leaving the page replaced this one.
    } finally {
      if (pending != null) show();
      if (ticket == _ticket) {
        busy = false;
        notifyListeners();
      }
    }
  }

  /// Entries of an upload or site subject that must be chosen before playing.
  Future<List<SourceEpisode>> entries(PlayCandidate candidate) {
    final target = candidate.target as OnlineTarget;
    return sources.episodes(candidate.provider, target.chooseFrom!);
  }

  /// Adds a torrent as [episode], by default the searched one.
  Future<DownloadTask> enqueue(
    ReleaseCandidate candidate, {
    required CacheMethod method,
    Episode? episode,
  }) {
    return selection.releases.enqueue(
      candidate,
      method: method,
      episodeId: episode?.id,
    );
  }

  /// Saves an online entry as [episode], by default the searched one.
  Future<DownloadTask> saveOnline(PlayCandidate candidate, {Episode? episode}) {
    final subject = state.subject;
    return downloads.addOnline(
      (candidate.target as OnlineTarget).ref!,
      title: candidate.title,
      source: candidate.sourceLabel,
      subjectId: subject?.id,
      episodeId: (episode ?? state.searched)?.id,
      coverUrl: subject?.coverUrl,
    );
  }

  @override
  void dispose() {
    cancel();
    playback.settings.removeListener(_rerank);
    super.dispose();
  }
}
