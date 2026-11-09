import 'dart:async';
import 'dart:typed_data';

import '../../core/deleted_files.dart';
import '../../core/error_message.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';

/// Download tasks across transfers: torrents go to the chosen [CacheMethod]
/// and nowhere else when it declines them, online entries to the online
/// transfer, task operations to the transfer that owns the task.
class DownloadRepository {
  DownloadRepository(this.transfers);
  final List<Transfer> transfers;
  final changes = StreamController<TransferSnapshot>.broadcast();
  final _subscriptions = <StreamSubscription<void>>[];
  Future<void>? _restoring, _closing;
  bool _closed = false;
  Future<void> get ready => initialize();

  Future<void> initialize() => _restoring ??= _restore();

  /// Why a transfer could not start. Its tasks stay listed, but using one
  /// reports this; the other transfers work on. Only when none starts does
  /// [ready] fail.
  final _failures = <Transfer, (Object, StackTrace)>{};

  /// What cannot be cached now and why, such as the BT engine failing to
  /// start, by method.
  Map<CacheMethod, String> get failures => {
    for (final MapEntry(key: transfer, value: (error, _)) in _failures.entries)
      transfer.method: '${_name(transfer.method)}无法启动：${errorMessage(error)}',
  };

  static String _name(CacheMethod method) => switch (method) {
    CacheMethod.bt => 'BT 引擎',
    CacheMethod.pikpak => 'PikPak 缓存',
    CacheMethod.online => '在线缓存',
  };

  Future<void> _restore() async {
    for (final transfer in transfers) {
      _subscriptions.add(transfer.changes.listen((_) => _emit()));
      try {
        await transfer.initialize();
      } catch (error, stack) {
        _failures[transfer] = (error, stack);
      }
    }
    if (transfers.isNotEmpty && _failures.length == transfers.length) {
      final (error, stack) = _failures.values.first;
      Error.throwWithStackTrace(error, stack);
    }
    _emit();
  }

  /// [transfer], unless it could not start, which is then the error.
  T _usable<T extends Transfer>(T transfer) {
    if (_failures.containsKey(transfer)) {
      throw StateError(failures[transfer.method]!);
    }
    return transfer;
  }

  /// Counts changes to the tasks, so what is worked out from a [snapshot]
  /// can be kept until the next one.
  int get revision => _revision;
  int _revision = 0;

  TransferSnapshot snapshot() =>
      TransferSnapshot([for (final transfer in transfers) ...transfer.tasks()]);

  TorrentTransfer _transfer(CacheMethod method) => _usable(
    transfers.whereType<TorrentTransfer>().firstWhere(
      (transfer) => transfer.method == method,
    ),
  );

  Transfer _owner(String id) => _usable(
    transfers.where((transfer) => transfer.contains(id)).firstOrNull ??
        (throw StateError('下载任务不存在')),
  );

  /// Runs a change to the tasks, which a [snapshot] taken right after shows.
  Future<T> _changing<T>(Future<T> Function() change) async {
    try {
      return await change();
    } finally {
      _revision++;
    }
  }

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
    return _changing(
      () => _transfer(method).addMagnet(
        Uri.parse(input.trim()),
        subjectId: subjectId,
        episodeId: episodeId,
        coverUrl: coverUrl,
        releaseGroups: releaseGroups,
      ),
    );
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
    return _changing(
      () => _transfer(method).addTorrent(
        bytes,
        name,
        subjectId: subjectId,
        episodeId: episodeId,
        coverUrl: coverUrl,
        releaseGroups: releaseGroups,
      ),
    );
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
    return _changing(
      () => _usable(transfers.whereType<OnlineTransfer>().single).addOnline(
        ref,
        title: title,
        source: source,
        subjectId: subjectId,
        episodeId: episodeId,
        coverUrl: coverUrl,
      ),
    );
  }

  /// Removes a finished task whose files were all deleted outside the app;
  /// true when it did.
  Future<bool> forgetDeleted(String id) async {
    final task = snapshot().task(id);
    if (task == null ||
        !task.complete ||
        !await deletedOutside([
          for (final file in task.files) file.path,
        ], _owner(id).directory)) {
      return false;
    }
    await remove(id);
    return true;
  }

  Future<void> pause(String id) async {
    await ready;
    await _changing(() => _owner(id).pause(id));
  }

  Future<void> resume(String id) async {
    await ready;
    await _changing(() => _owner(id).resume(id));
  }

  Future<void> remove(String id) async {
    await ready;
    for (final transfer in transfers) {
      if (transfer.contains(id)) {
        return _changing(() => _usable(transfer).remove(id));
      }
    }
  }

  /// Deletes [fileIds] of a finished BT or PikPak task.
  Future<void> removeFiles(String id, Set<String> fileIds) async {
    await ready;
    await _changing(
      () => (_owner(id) as TorrentTransfer).removeFiles(id, fileIds),
    );
  }

  TransferMedia media(String id, {String? fileId}) =>
      _owner(id).media(id, fileId: fileId);

  Future<TransferMedia> openMedia(String id, {String? fileId}) async {
    await ready;
    return _owner(id).openMedia(id, fileId: fileId);
  }

  void releaseStreamsExcept(int? keep) {
    for (final transfer in transfers) {
      if (!_failures.containsKey(transfer)) transfer.releaseStreamsExcept(keep);
    }
  }

  void _emit() {
    _revision++;
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
