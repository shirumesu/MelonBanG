import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

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
        final codec = await ui.instantiateImageCodec(
          await cache.image(address),
          targetWidth: 96,
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        final pixels = (await frame.image.toByteData())!.buffer.asUint32List();
        frame.image.dispose();
        // What ColorScheme.fromImageProvider does, but quantizing off the
        // UI isolate, where it takes long enough to drop frames.
        final source = await Isolate.run(() => _sourceColor(pixels));
        return ColorScheme.fromSeed(seedColor: Color(source)).primary;
      } catch (_) {
        // A failed read can succeed on the next visit.
        _seeds.remove(address);
        return null;
      }
    });
  }
}

/// The best theme source colour among [pixels], read as RGBA bytes.
Future<int> _sourceColor(Uint32List pixels) async {
  final quantized = await QuantizerCelebi().quantize(pixels, 128);
  return Score.score({
    // Little-endian RGBA bytes read as ABGR words; Score takes ARGB.
    for (final MapEntry(key: abgr, :value) in quantized.colorToCount.entries)
      (abgr & 0xff00ff00) | (abgr & 0xff) << 16 | (abgr >> 16) & 0xff: value,
  }, desired: 1).first;
}
