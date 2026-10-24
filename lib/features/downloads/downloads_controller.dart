import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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

  Future<void> remove(String id) => downloads.remove(id);

  /// Deletes [fileIds] of a finished task; a BT task then no longer seeds.
  Future<void> removeFiles(String id, Set<String> fileIds) =>
      downloads.removeFiles(id, fileIds);

  /// Does what [DownloadTask.toggle] names.
  Future<void> toggle(DownloadTask task) => switch (task.toggle) {
    TaskToggle.pause => downloads.pause(task.id),
    TaskToggle.resume || TaskToggle.resumeSeeding => downloads.resume(task.id),
    TaskToggle.stopSeeding => stopSeeding(task.id),
    null => Future.value(),
  };

  /// Shows the task's video, or its first file, selected in the system file
  /// manager; its folder while nothing is written yet. A finished task whose
  /// files were all deleted is removed instead.
  Future<void> reveal(DownloadTask task) async {
    if (await downloads.forgetDeleted(task.id)) {
      throw StateError('文件已被删除，已从缓存中移除');
    }
    final file = task.videos.firstOrNull ?? task.files.firstOrNull;
    if (file == null) throw StateError('还没有文件');
    for (final path in [file.path, '${file.path}.part']) {
      if (await File(path).exists()) {
        return _show(p.normalize(path), select: true);
      }
    }
    final folder = p.dirname(file.path);
    if (await Directory(folder).exists()) return _show(p.normalize(folder));
    throw StateError('文件尚未开始下载');
  }

  static Future<void> _show(String path, {bool select = false}) async {
    if (Platform.isMacOS) {
      await Process.run('open', [if (select) '-R', path]);
    } else {
      // Explorer exits with 1 even when it opened the window.
      await Process.start('explorer.exe', [
        if (select) '/select,',
        path,
      ], mode: ProcessStartMode.detached);
    }
  }

  Future<void> close() => _subscription.cancel();
}
