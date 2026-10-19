import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/sources.dart';
import '../../domain/transfer.dart';

/// Download tasks across transfers: torrents go to the chosen [CacheMethod],
/// online entries to the online transfer, task operations to the transfer
/// that owns the task.
class DownloadRepository {
  DownloadRepository(this.transfers);
  final List<Transfer> transfers;
  final changes = StreamController<TransferSnapshot>.broadcast();

  /// Why a task added for another method went to BT, by task id.
  final fallbacks = <String, String>{};
  final _subscriptions = <StreamSubscription<void>>[];
  Future<void>? _restoring, _closing;
  bool _closed = false;
  Future<void> get ready => _restoring ?? initialize();

  Future<void> initialize() => _restoring ??= _restore();

  Future<void> _restore() async {
    for (final transfer in transfers) {
      _subscriptions.add(transfer.changes.listen((_) => _emit()));
      await transfer.initialize();
    }
    _emit();
  }

  TransferSnapshot snapshot() =>
      TransferSnapshot([for (final transfer in transfers) ...transfer.tasks()]);

  TorrentTransfer _transfer(CacheMethod method) => transfers
      .whereType<TorrentTransfer>()
      .firstWhere((transfer) => transfer.method == method);

  Transfer _owner(String id) =>
      transfers.where((transfer) => transfer.contains(id)).firstOrNull ??
      (throw StateError('下载任务不存在'));

  bool contains(String id) => transfers.any((t) => t.contains(id));

  Future<DownloadTask> addMagnet(
    String input, {
    required CacheMethod method,
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    List<String> releaseGroups = const [],
  }) async {
    await ready;
    final uri = Uri.tryParse(input.trim());
    if (uri?.scheme != 'magnet') {
      throw const FormatException('磁力链接缺少有效的 BT info hash');
    }
    Future<DownloadTask> add(CacheMethod method) => _transfer(method).addMagnet(
      uri!,
      subjectId: subjectId,
      episodeId: episodeId,
      coverUrl: coverUrl,
      releaseGroups: releaseGroups,
    );
    try {
      return await add(method);
    } on TransferUnavailable catch (error) {
      // Only PikPak declines a resource; BT fetches it from the swarm.
      return _fallback(add, error);
    }
  }

  Future<DownloadTask> addTorrent(
    Uint8List bytes,
    String name, {
    required CacheMethod method,
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    List<String> releaseGroups = const [],
  }) async {
    await ready;
    if (bytes.isEmpty) throw const FormatException('种子文件为空');
    Future<DownloadTask> add(CacheMethod method) =>
        _transfer(method).addTorrent(
          bytes,
          name,
          subjectId: subjectId,
          episodeId: episodeId,
          coverUrl: coverUrl,
          releaseGroups: releaseGroups,
        );
    try {
      return await add(method);
    } on TransferUnavailable catch (error) {
      return _fallback(add, error);
    }
  }

  Future<DownloadTask> addOnline(
    StreamRef ref, {
    required String title,
    required String source,
    int? subjectId,
    int? episodeId,
    String? coverUrl,
  }) async {
    await ready;
    return transfers.whereType<OnlineTransfer>().single.addOnline(
      ref,
      title: title,
      source: source,
      subjectId: subjectId,
      episodeId: episodeId,
      coverUrl: coverUrl,
    );
  }

  /// Removes a finished task whose files were all deleted outside the app;
  /// true when it did.
  Future<bool> forgetDeleted(String id) async {
    final task = snapshot().task(id);
    if (task == null ||
        !task.complete ||
        task.files.isEmpty ||
        !await Directory(_owner(id).directory).exists()) {
      return false;
    }
    for (final file in task.files) {
      if (await File(file.path).exists()) return false;
    }
    await remove(id);
    return true;
  }

  Future<DownloadTask> _fallback(
    Future<DownloadTask> Function(CacheMethod) add,
    TransferUnavailable error,
  ) async {
    final task = await add(CacheMethod.bt);
    fallbacks[task.id] = error.message;
    return task;
  }

  Future<void> pause(String id) async {
    await ready;
    await _owner(id).pause(id);
  }

  Future<void> resume(String id) async {
    await ready;
    await _owner(id).resume(id);
  }

  Future<void> remove(String id) async {
    await ready;
    for (final transfer in transfers) {
      if (transfer.contains(id)) return transfer.remove(id);
    }
  }

  TransferMedia media(String id, {String? fileId}) =>
      _owner(id).media(id, fileId: fileId);

  Future<TransferMedia> openMedia(String id, {String? fileId}) async {
    await ready;
    return _owner(id).openMedia(id, fileId: fileId);
  }

  /// The most complete playable download of an episode.
  TransferMedia episodeMedia(int subjectId, int episodeId) {
    final tasks =
        snapshot()
            .forSubject(subjectId)
            .where((task) => task.episodeId == episodeId)
            .toList()
          ..sort((a, b) => b.progress.compareTo(a.progress));
    for (final task in tasks) {
      try {
        return media(task.id);
      } on StateError {
        continue;
      }
    }
    throw StateError('该章节尚无可播放下载，请选择资源或具体视频文件');
  }

  void releaseStreamsExcept(int? keep) {
    for (final transfer in transfers) {
      transfer.releaseStreamsExcept(keep);
    }
  }

  void _emit() {
    if (!_closed) changes.add(snapshot());
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final transfer in transfers) {
      await transfer.close();
    }
    await changes.close();
  }
}
