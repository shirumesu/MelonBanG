import 'package:flutter/foundation.dart';

import '../../data/tracking.dart';
import '../../domain/catalog.dart';

/// The subject detail page: the shown subject, its loading state and
/// collection edits. A newer [open] or [cancel] discards older results.
class SubjectController extends ChangeNotifier {
  SubjectController(this.tracking);
  final TrackingRepository tracking;

  Subject? subject;
  bool loading = false;
  int _ticket = 0, _saveTicket = 0;

  int? get id => subject?.id;

  /// Shows [item] at once, then its detail and personal progress as they
  /// arrive.
  Future<void> open(Subject item) async {
    final ticket = ++_ticket;
    subject = item;
    loading = true;
    notifyListeners();
    try {
      final detail = await tracking.subject(
        item.id,
        onAvailable: (value) {
          if (ticket != _ticket) return;
          subject = value;
          notifyListeners();
        },
      );
      if (ticket == _ticket) subject = detail;
    } catch (_) {
      // Failures of a replaced load are not this page's to report.
      if (ticket == _ticket) rethrow;
    } finally {
      if (ticket == _ticket) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Shows an earlier subject without loading it.
  void show(Subject? item) {
    _ticket++;
    subject = item;
    loading = false;
    notifyListeners();
  }

  /// Stops delivering the running load.
  void cancel() {
    _ticket++;
    loading = false;
  }

  Future<void> saveCollection(CollectionChange change) => _save(
    (id) => tracking.setCollection(id, change),
    (item) => item.copyWith(
      collection: (item.collection ?? const SubjectCollection()).apply(change),
      episodes: change.completeEpisodes
          ? [
              for (final episode in item.episodes)
                episode.main
                    ? episode.withStatus(EpisodeStatus.watched)
                    : episode,
            ]
          : null,
    ),
  );

  Future<void> saveEpisodes(List<int> ids, EpisodeStatus status) => _save(
    (id) => tracking.setEpisodes(id, ids, status),
    (item) => item.copyWith(
      episodes: [
        for (final episode in item.episodes)
          ids.contains(episode.id) ? episode.withStatus(status) : episode,
      ],
    ),
  );

  /// Writes locally, then reflects the committed change at once.
  Future<void> _save(
    Future<void> Function(int subjectId) write,
    Subject Function(Subject) update,
  ) async {
    final subjectId = subject!.id;
    final ticket = _ticket, user = tracking.account.userId;
    await write(subjectId);
    if (ticket == _ticket &&
        subject?.id == subjectId &&
        user == tracking.account.userId) {
      _saveTicket++;
      subject = update(subject!);
      notifyListeners();
    }
  }

  /// Reloads the shown detail after an edit; navigation or a newer edit wins.
  Future<void> reload() async {
    final current = subject;
    if (current == null) return;
    final ticket = _ticket, save = ++_saveTicket;
    final user = tracking.account.userId;
    final detail = await tracking.subject(current.id);
    if (ticket == _ticket &&
        save == _saveTicket &&
        subject?.id == current.id &&
        user == tracking.account.userId) {
      subject = detail;
      notifyListeners();
    }
  }
}
