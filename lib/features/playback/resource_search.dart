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

  /// The source the subject was last played from, which ranks first.
  final RememberedSource? remembered;
}

/// Searches online sources, torrent indexes and PikPak's index together for
/// a subject or one of its chapters. Starting a new search or [cancel]
/// cancels the running one.
class ResourceSearchController extends ChangeNotifier {
  ResourceSearchController(this.selection, this.playback, this.downloadsReady);
  final PlaySelectionRepository selection;
  final Playback playback;

  /// Completes once restored downloads can accept new tasks.
  final Future<void> Function() downloadsReady;

  DownloadRepository get downloads => selection.downloads;

  ResourceSearchState state = const ResourceSearchState();
  bool busy = false;
  int _ticket = 0;
  RequestCancellation _cancel = RequestCancellation();

  SourceRegistry get sources => selection.registry;

  /// Shows [subject] with no results yet.
  void open(Subject? subject, {Episode? episode}) {
    cancel();
    state = ResourceSearchState(subject: subject, episode: episode);
    notifyListeners();
  }

  void restore(ResourceSearchState value) {
    cancel();
    state = value;
    notifyListeners();
  }

  void cancel() {
    _cancel.cancel();
    _ticket++;
    busy = false;
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
    RememberedSource? remembered;
    final progress = <String, SourceProgress>{};
    Timer? pending;
    void show() {
      pending?.cancel();
      pending = null;
      if (ticket != _ticket) return;
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
        onUpdate: (values) {
          candidates = values;
          showSoon();
        },
        onProgress: (value) {
          progress[value.sourceId] = value;
          showSoon();
        },
      );
      show();
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
  }) async {
    await downloadsReady();
    return selection.releases.enqueue(
      candidate,
      method: method,
      episodeId: episode?.id,
    );
  }

  /// Saves an online entry as [episode], by default the searched one.
  Future<DownloadTask> saveOnline(
    PlayCandidate candidate, {
    Episode? episode,
  }) async {
    await downloadsReady();
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
    super.dispose();
  }
}
