import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/content_cache.dart';

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

/// An [Image] backed by [ContentCache] that recovers from transient failures:
/// it retries with backoff and as soon as any other view reads the same
/// address. [MissingImage] failures are reported through [onMissing] instead.
class CachedImage extends StatefulWidget {
  const CachedImage({
    super.key,
    required this.url,
    required this.errorBuilder,
    this.cacheWidth,
    this.fit,
    this.alignment = Alignment.center,
    this.frameBuilder,
    this.onMissing,
  });
  final String url;
  final int? cacheWidth;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageFrameBuilder? frameBuilder;
  final ImageErrorWidgetBuilder errorBuilder;
  final ValueChanged<String>? onMissing;

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  ContentCache? _cache;
  StreamSubscription<String>? _available;
  Timer? _retry;
  int _attempt = 0;
  bool _failed = false, _missing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cache = ContentCacheScope.of(context);
    if (cache == _cache) return;
    _available?.cancel();
    _cache = cache;
    _available = cache.available.listen((url) {
      if (url == widget.url) _reload();
    });
    cache.prioritize(widget.url);
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _retry?.cancel();
    _attempt = 0;
    _failed = _missing = false;
    _cache?.prioritize(widget.url);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _available?.cancel();
    super.dispose();
  }

  void _failure(Object error) {
    if (_failed) return;
    _failed = true;
    if (error is MissingImage) {
      _missing = true;
      final url = widget.url;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && url == widget.url) widget.onMissing?.call(url);
      });
    } else {
      _retry = Timer(
        Duration(seconds: math.min(60, 1 << math.min(_attempt + 1, 6))),
        _reload,
      );
    }
  }

  void _reload() {
    _retry?.cancel();
    if (!mounted || !_failed || _missing) return;
    setState(() {
      _attempt++;
      _failed = false;
    });
  }

  @override
  Widget build(BuildContext context) => Image(
    key: ValueKey((widget.url, _attempt)),
    image: cachedImageProvider(
      context,
      widget.url,
      cacheWidth: widget.cacheWidth,
    ),
    fit: widget.fit,
    alignment: widget.alignment,
    frameBuilder: widget.frameBuilder,
    errorBuilder: (context, error, stack) {
      _failure(error);
      return widget.errorBuilder(context, error, stack);
    },
  );
}

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
      final bool blank;
      try {
        blank = await _blank(bytes);
      } catch (_) {
        await cache.discard(url);
        rethrow;
      }
      if (blank) throw MissingImage(url);
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
