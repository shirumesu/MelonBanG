import 'dart:async';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'network.dart';
import 'store.dart';

/// The address has no usable image: the host rejected it, the bytes cannot be
/// decoded, or the artwork slot is blank. Retrying soon will not help.
class MissingImage implements Exception {
  const MissingImage(this.url);
  final String url;
  @override
  String toString() => '图片不可用：$url';
}

class ContentCache {
  ContentCache(this.api, this.store);
  final ApiClient api;
  final AppStore store;
  static const retention = Duration(days: 120);
  static const maxImageBytes = 100 * 1024 * 1024;
  static const _missingFor = Duration(minutes: 30);
  final _requests = <String, Future<Uint8List>>{};
  final _downloads = <String, _ImageQueue>{};
  final _missing = <String, DateTime>{};
  final _touched = <String>{};
  final _available = StreamController<String>.broadcast();
  Timer? _timer, _touchTimer;
  Future<void>? _cleaning;
  bool _closed = false;
  int _generation = 0;
  int get generation => _generation;

  /// Addresses whose bytes have just been read, so views that failed earlier
  /// can show them without waiting for their own retry.
  Stream<String> get available => _available.stream;

  Future<void> initialize() async {
    await prune();
    _timer = Timer.periodic(const Duration(days: 1), (_) => unawaited(prune()));
  }

  Future<Uint8List> image(String url) {
    prioritize(url);
    return _requests.putIfAbsent(url, () async {
      try {
        return await _loadImage(url);
      } finally {
        _requests.remove(url);
      }
    });
  }

  /// Moves a queued download ahead of older requests, e.g. when it is shown again.
  void prioritize(String url) =>
      _downloads[Uri.tryParse(url)?.host]?.prioritize(url);

  /// Drops stored bytes that turned out to be unusable.
  Future<void> discard(String url) async {
    _missing[url] = DateTime.now().add(_missingFor);
    await store.database.delete(
      'cached_images',
      where: 'url=?',
      whereArgs: [url],
    );
  }

  Future<Uint8List> _loadImage(String url) async {
    final generation = _generation;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await store.database.query(
      'cached_images',
      columns: ['bytes'],
      where: 'url=? AND saved>?',
      whereArgs: [url, now - retention.inMilliseconds],
    );
    if (rows.isNotEmpty) {
      _touch(url);
      return _publish(url, rows.single['bytes'] as Uint8List);
    }
    if (_missing[url]?.isAfter(DateTime.now()) ?? false) {
      throw MissingImage(url);
    }
    final Uint8List bytes;
    try {
      bytes = await _download(url);
    } on ApiException catch (error) {
      if (error.status == 408 || error.status == 429 || error.status >= 500) {
        rethrow;
      }
      _missing[url] = DateTime.now().add(_missingFor);
      throw MissingImage(url);
    }
    // A clear action also discards downloads that were already in flight.
    if (bytes.length <= maxImageBytes) {
      await store.database.transaction((tx) async {
        if (generation != _generation) return;
        final saved = DateTime.now().millisecondsSinceEpoch;
        await tx.insert('cached_images', {
          'url': url,
          'bytes': bytes,
          'saved': saved,
          'accessed': saved,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await _trimImages(tx);
      });
    }
    return _publish(url, bytes);
  }

  Uint8List _publish(String url, Uint8List bytes) {
    if (!_closed) _available.add(url);
    return bytes;
  }

  // Image downloads are scheduled here rather than in the API client queue,
  // whose deadline includes waiting time: a busy page must not time out the
  // artwork queued behind it.
  Future<Uint8List> _download(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) throw MissingImage(url);
    final queue = _downloads.putIfAbsent(uri.host, _ImageQueue.new);
    await queue.acquire(url);
    try {
      if (_closed) throw StateError('图片缓存已关闭');
      final response = await api.send(
        uri,
        headers: const {'Accept': 'image/*'},
      );
      return response.bodyBytes;
    } finally {
      queue.release();
    }
  }

  void _touch(String url) {
    _touched.add(url);
    _touchTimer ??= Timer(
      const Duration(seconds: 5),
      () => unawaited(_flushTouched()),
    );
  }

  Future<void> _flushTouched() async {
    _touchTimer?.cancel();
    _touchTimer = null;
    if (_touched.isEmpty) return;
    final accessed = DateTime.now().millisecondsSinceEpoch;
    final batch = store.database.batch();
    for (final url in _touched) {
      batch.update(
        'cached_images',
        {'accessed': accessed},
        where: 'url=?',
        whereArgs: [url],
      );
    }
    _touched.clear();
    await batch.commit(noResult: true);
  }

  Future<void> prune() => _clean(expiredOnly: true);

  Future<int> size() async =>
      (await store.database.rawQuery(
            'SELECT COALESCE((SELECT SUM(length(bytes)) FROM cached_images),0) '
            '+ COALESCE((SELECT SUM(length(CAST(body AS BLOB))) FROM documents WHERE scope=?),0) AS bytes',
            ['catalog'],
          )).single['bytes']
          as int;

  Future<int> _trimImages(DatabaseExecutor tx) => tx.rawDelete(
    'DELETE FROM cached_images WHERE url IN ('
    'SELECT url FROM ('
    'SELECT url, SUM(length(bytes)) OVER (ORDER BY accessed DESC, url) AS retained '
    'FROM cached_images) WHERE retained>?)',
    [maxImageBytes],
  );

  Future<void> clear() {
    _generation++;
    _missing.clear();
    return _clean(expiredOnly: false);
  }

  Future<void> _clean({required bool expiredOnly}) {
    final operation = (_cleaning ?? Future<void>.value()).then(
      (_) => _remove(expiredOnly: expiredOnly),
    );
    _cleaning = operation;
    return operation.whenComplete(() {
      if (identical(_cleaning, operation)) _cleaning = null;
    });
  }

  Future<void> _remove({required bool expiredOnly}) async {
    final cutoff = DateTime.now().subtract(retention).millisecondsSinceEpoch;
    final removed = await store.database.transaction((tx) async {
      final images = await tx.delete(
        'cached_images',
        where: expiredOnly ? 'saved<=?' : null,
        whereArgs: expiredOnly ? [cutoff] : null,
      );
      final catalog = await tx.delete(
        'documents',
        where: expiredOnly ? 'scope=? AND updated<=?' : 'scope=?',
        whereArgs: ['catalog', if (expiredOnly) cutoff],
      );
      return images + catalog + (expiredOnly ? await _trimImages(tx) : 0);
    });
    if (removed > 0) await store.database.execute('VACUUM');
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _generation++;
    for (final queue in _downloads.values) {
      queue.close();
    }
    await _cleaning;
    await Future.wait(
      _requests.values.toList().map(
        (request) => request.then<void>((_) {}, onError: (Object _) {}),
      ),
    );
    await _flushTouched();
    await _available.close();
  }
}

/// Per-host download slots, granted newest request first so artwork on the
/// current screen is not stuck behind requests from views already left.
class _ImageQueue {
  int active = 0;
  final waiting = <String, Completer<void>>{};

  Future<void> acquire(String url) {
    if (active < ApiClient.maxRequestsPerHost) {
      active++;
      return Future.value();
    }
    return waiting.putIfAbsent(url, Completer<void>.new).future;
  }

  void prioritize(String url) {
    final slot = waiting.remove(url);
    if (slot != null) waiting[url] = slot;
  }

  void release() {
    if (waiting.isEmpty) {
      active--;
    } else {
      waiting.remove(waiting.keys.last)!.complete();
    }
  }

  void close() {
    for (final slot in waiting.values) {
      slot.completeError(StateError('图片缓存已关闭'));
    }
    waiting.clear();
  }
}
