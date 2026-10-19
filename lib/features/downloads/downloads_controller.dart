import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/transfer.dart';
import 'download_repository.dart';

/// The download list and its task operations.
class DownloadsController {
  DownloadsController(
    this.downloads, {
    required this.ready,
    required this.stopSeeding,
  }) {
    _accept(downloads.snapshot());
    _subscription = downloads.changes.stream.listen(_accept);
  }
  final DownloadRepository downloads;

  /// Completes once restored tasks are loaded.
  final Future<void> Function() ready;

  /// Stops seeding a finished BT task.
  final Future<void> Function(String id) stopSeeding;
  late final StreamSubscription<TransferSnapshot> _subscription;

  final snapshot = ValueNotifier(const TransferSnapshot());

  /// Tasks still fetching data.
  final active = ValueNotifier(0);

  /// Bumped when a task appears, disappears, changes status or completes, so
  /// playable episodes may have changed.
  final availability = ValueNotifier(0);

  void _accept(TransferSnapshot value) {
    String signature(TransferSnapshot snapshot) => snapshot.tasks
        .map((task) => '${task.id}:${task.status.name}:${task.complete}')
        .join('|');
    final changed = signature(snapshot.value) != signature(value);
    snapshot.value = value;
    active.value = value.tasks
        .where(
          (task) =>
              const {
                DownloadStatus.metadata,
                DownloadStatus.downloading,
                DownloadStatus.queued,
                DownloadStatus.checking,
              }.contains(task.status) &&
              !task.complete,
        )
        .length;
    if (changed) availability.value++;
  }

  Future<void> addMagnet(String uri) async {
    await ready();
    await downloads.addMagnet(uri, method: CacheMethod.bt);
  }

  Future<void> addTorrent(Uint8List bytes, String name) async {
    await ready();
    await downloads.addTorrent(bytes, name, method: CacheMethod.bt);
  }

  Future<void> remove(String id) => downloads.remove(id);

  /// Resumes a paused, failed or finished task; pauses any other.
  Future<void> toggle(DownloadTask task) =>
      const {
        DownloadStatus.paused,
        DownloadStatus.failed,
        DownloadStatus.completed,
      }.contains(task.status)
      ? downloads.resume(task.id)
      : downloads.pause(task.id);

  Future<void> close() => _subscription.cancel();
}
