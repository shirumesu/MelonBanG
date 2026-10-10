import 'package:flutter/foundation.dart';

import '../../data/network.dart';
import '../../data/resource_metadata.dart';
import '../../domain/catalog.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';
import 'release_search.dart';

/// A resource search as shown on the resources page.
class ResourcesState {
  const ResourcesState({
    this.subject,
    this.episodeId,
    this.releases = const ReleaseSearchResult(),
    this.names,
    this.episodeKeyword = '',
  });
  final Subject? subject;
  final int? episodeId;
  final ReleaseSearchResult releases;

  /// Names and episode keyword of the latest search.
  final List<String>? names;
  final String episodeKeyword;
}

/// Torrent search for one subject (and optionally one episode). Starting a
/// new search or [cancel] cancels the running one.
class ResourcesController extends ChangeNotifier {
  ResourcesController(this.releases, this.downloadsReady);
  final ReleaseSearch releases;

  /// Completes once restored downloads can accept new tasks.
  final Future<void> Function() downloadsReady;

  ResourcesState state = const ResourcesState();
  bool busy = false;
  int _ticket = 0;
  RequestCancellation _cancel = RequestCancellation();

  /// Shows [subject] with no results yet.
  void open(Subject? subject, {int? episodeId}) {
    cancel();
    state = ResourcesState(subject: subject, episodeId: episodeId);
    notifyListeners();
  }

  void restore(ResourcesState value) {
    cancel();
    state = value;
    notifyListeners();
  }

  void cancel() {
    _cancel.cancel();
    _ticket++;
    busy = false;
  }

  /// Searches [keyword] plus [names] (catalogue aliases by default).
  Future<void> search(
    String keyword, {
    List<String>? names,
    String episodeKeyword = '',
  }) async {
    final subject = state.subject;
    if (subject == null) return;
    final searchNames = names ?? resourceNames(subject);
    if (keyword.trim().isEmpty && searchNames.isEmpty) return;
    _cancel.cancel();
    final cancellation = _cancel = RequestCancellation();
    final ticket = ++_ticket;
    final episodeId = state.episodeId;
    void show(ReleaseSearchResult releases) {
      if (ticket != _ticket) return;
      state = ResourcesState(
        subject: subject,
        episodeId: episodeId,
        releases: releases,
        names: searchNames,
        episodeKeyword: episodeKeyword,
      );
      notifyListeners();
    }

    busy = true;
    show(const ReleaseSearchResult());
    try {
      show(
        await releases.search(
          subject.id,
          keyword.trim(),
          cancel: cancellation,
          episodeId: episodeId,
          alternativeNames: searchNames,
          episodeKeyword: episodeKeyword,
          coverUrl: subject.coverUrl,
          isCurrent: () => ticket == _ticket,
          onUpdate: show,
        ),
      );
    } on RequestCancelled {
      // A newer search or leaving the page replaced this one.
    } finally {
      if (ticket == _ticket) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> enqueue(
    ReleaseCandidate candidate, {
    CacheMethod? method,
  }) async {
    await downloadsReady();
    await releases.enqueue(candidate, method: method);
  }
}
