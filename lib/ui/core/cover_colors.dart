import 'package:flutter/material.dart';

import '../../core/content_cache.dart';
import '../../core/json.dart';

/// Theme colours taken from subject covers, read from the shared image
/// cache and kept for the rest of the run.
class CoverColors {
  CoverColors(this.cache);
  final ContentCache cache;
  final _seeds = <String, Future<Color?>>{};

  /// The cover's most representative colour, or null when the cover cannot
  /// be read.
  Future<Color?> seed(String? coverUrl) {
    final address = coverAddress(coverUrl);
    if (address == null) return Future.value();
    return _seeds.putIfAbsent(address, () async {
      try {
        final bytes = await cache.image(address);
        final scheme = await ColorScheme.fromImageProvider(
          provider: ResizeImage(MemoryImage(bytes), width: 96),
        );
        return scheme.primary;
      } catch (_) {
        // A failed read can succeed on the next visit.
        _seeds.remove(address);
        return null;
      }
    });
  }
}
