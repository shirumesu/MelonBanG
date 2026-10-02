import 'dart:async';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'network.dart';
import 'store.dart';

class ContentCache {
  ContentCache(this.api, this.store);
  final ApiClient api;
  final AppStore store;
  static const retention = Duration(days: 120);
  final _requests = <String, Future<Uint8List>>{};
  Timer? _timer;
  Future<void>? _cleaning;
  int _generation = 0;

  Future<void> initialize() async {
    await prune();
    _timer = Timer.periodic(const Duration(days: 1), (_) => unawaited(prune()));
  }

  Future<Uint8List> image(String url) => _requests.putIfAbsent(url, () async {
    try {
      return await _loadImage(url);
    } finally {
      _requests.remove(url);
    }
  });

  Future<Uint8List> _loadImage(String url) async {
    final generation = _generation;
    final rows = await store.database.query(
      'cached_images',
      columns: ['bytes'],
      where: 'url=? AND saved>?',
      whereArgs: [
        url,
        DateTime.now().subtract(retention).millisecondsSinceEpoch,
      ],
    );
    if (rows.isNotEmpty) return rows.single['bytes'] as Uint8List;
    final response = await api.send(
      Uri.parse(url),
      headers: const {'Accept': 'image/*'},
    );
    final bytes = response.bodyBytes;
    // A clear action also discards downloads that were already in flight.
    if (generation == _generation) {
      await store.database.insert('cached_images', {
        'url': url,
        'bytes': bytes,
        'saved': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return bytes;
  }

  Future<void> prune() => _clean(expiredOnly: true);

  Future<void> clear() {
    _generation++;
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
      return images + catalog;
    });
    if (removed > 0) await store.database.execute('VACUUM');
  }

  Future<void> close() async {
    _timer?.cancel();
    _generation++;
    await _cleaning;
    await Future.wait(
      _requests.values.toList().map(
        (request) => request.then<void>((_) {}, onError: (Object _) {}),
      ),
    );
  }
}
