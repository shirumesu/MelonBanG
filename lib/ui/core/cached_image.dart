import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/content_cache.dart';

class ContentCacheScope extends InheritedWidget {
  const ContentCacheScope({
    super.key,
    required this.cache,
    required super.child,
  });
  final ContentCache cache;

  static ContentCache of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentCacheScope>()!.cache;

  @override
  bool updateShouldNotify(ContentCacheScope oldWidget) =>
      cache != oldWidget.cache;
}

ImageProvider cachedImageProvider(
  BuildContext context,
  String url, {
  int? cacheWidth,
}) => ResizeImage.resizeIfNeeded(
  cacheWidth,
  null,
  _CachedImage(ContentCacheScope.of(context), url),
);

class _CachedImage extends ImageProvider<_CachedImage> {
  const _CachedImage(this.cache, this.url);
  final ContentCache cache;
  final String url;

  @override
  Future<_CachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: url,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes = await cache.image(url);
      if (await _blank(bytes)) throw StateError('Blank image: $url');
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    }
  }

  /// Bangumi serves some "no artwork" slots as a plain white upload; treat
  /// an image whose thumbnail is a single flat colour as missing.
  static Future<bool> _blank(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final data = await frame.image.toByteData();
    frame.image.dispose();
    final pixels = data!.buffer.asUint8List();
    for (var channel = 0; channel < 4; channel++) {
      var low = 255, high = 0;
      for (var i = channel; i < pixels.length; i += 4) {
        low = math.min(low, pixels[i]);
        high = math.max(high, pixels[i]);
      }
      if (high - low > 12) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedImage && other.cache == cache && other.url == url;

  @override
  int get hashCode => Object.hash(cache, url);
}
