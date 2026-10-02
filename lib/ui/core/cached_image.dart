import 'dart:async';
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
      return await decode(
        await ui.ImmutableBuffer.fromUint8List(await cache.image(url)),
      );
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedImage && other.cache == cache && other.url == url;

  @override
  int get hashCode => Object.hash(cache, url);
}
