import 'dart:async';
import 'dart:typed_data';

import '../../core/store.dart';
import '../../domain/transfer.dart';

/// Download tasks across transfers: adds go to the chosen [CacheMethod],
/// task operations to the transfer that owns the task.
class DownloadRepository {
  DownloadRepository(this.store, this.transfers);
  final AppStore store;
  final List<Transfer> transfers;
  CacheMethod defaultMethod = CacheMethod.bt;
  final changes = StreamController<TransferSnapshot>.broadcast();
  final _subscriptions = <StreamSubscription<void>>[];
  Future<void>? _restoring, _closing;
  bool _closed = false;
  Future<void> get ready => _restoring ?? initialize();

  Future<void> loadPreferences() async {
    defaultMethod = CacheMethod.fromStored(
      (await store.get('settings', 'cache'))?['method'],
    );
  }

  Future<void> saveCacheMethod(CacheMethod method) async {
    await ready;
    await store.put('settings', 'cache', {'method': method.name});
    defaultMethod = method;
    _emit();
  }

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

  Transfer _transfer(CacheMethod method) =>
      transfers.firstWhere((transfer) => transfer.method == method);

  Transfer _owner(String id) =>
      transfers.where((transfer) => transfer.contains(id)).firstOrNull ??
      (throw StateError('下载任务不存在'));

  bool contains(String id) => transfers.any((t) => t.contains(id));

  Future<DownloadTask> addMagnet(
    String input, {
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    CacheMethod? method,
    List<String> releaseGroups = const [],
  }) async {
    await ready;
    final uri = Uri.tryParse(input.trim());
    if (uri?.scheme != 'magnet') {
      throw const FormatException('磁力链接缺少有效的 BT info hash');
    }
    return _transfer(method ?? defaultMethod).addMagnet(
      uri!,
      subjectId: subjectId,
      episodeId: episodeId,
      coverUrl: coverUrl,
      releaseGroups: releaseGroups,
    );
  }

  Future<DownloadTask> addTorrent(
    Uint8List bytes,
    String name, {
    int? subjectId,
    int? episodeId,
    String? coverUrl,
    CacheMethod? method,
    List<String> releaseGroups = const [],
  }) async {
    await ready;
    if (bytes.isEmpty) throw const FormatException('种子文件为空');
    return _transfer(method ?? defaultMethod).addTorrent(
      bytes,
      name,
      subjectId: subjectId,
      episodeId: episodeId,
      coverUrl: coverUrl,
      releaseGroups: releaseGroups,
    );
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
