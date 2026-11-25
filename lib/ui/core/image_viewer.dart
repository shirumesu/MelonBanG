import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cached_image.dart';
import 'external_link.dart';
import 'motion.dart';
import 'theme.dart';

/// Shows the picture at [address] large and zoomable, fitted to the window
/// at its shape ([aspectRatio] until known) but no larger than itself, unless
/// [original], a larger rendition laid over it once loaded, will fill it.
/// [browsable] adds opening [address] in the browser.
Future<void> showImageViewer(
  BuildContext context, {
  required String address,
  required String label,
  String? original,
  double aspectRatio = .72,
  bool browsable = false,
}) => showMelonDialog<void>(
  context: context,
  builder: (context) => _ImageViewer(
    address: address,
    label: label,
    original: original == address ? null : original,
    aspectRatio: aspectRatio,
    browsable: browsable,
  ),
);

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({
    required this.address,
    required this.label,
    required this.original,
    required this.aspectRatio,
    required this.browsable,
  });
  final String address, label;
  final String? original;
  final double aspectRatio;
  final bool browsable;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  ImageStream? _stream;
  late final _listener = ImageStreamListener(_loaded);

  /// The picture's size in pixels, once decoded. Its failure shows through
  /// the [CachedImage] below, which listens to the same stream.
  Size? _natural;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stream = cachedImageProvider(
      context,
      widget.address,
    ).resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _loaded(ImageInfo info, bool _) {
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    info.dispose();
    if (mounted && size != _natural) setState(() => _natural = size);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  /// As large as the window allows at the picture's shape; no larger than
  /// the picture itself unless an original will fill it.
  Size _box(Size window) {
    final natural = _natural;
    final aspect = natural == null || natural.isEmpty
        ? widget.aspectRatio
        : natural.width / natural.height;
    final width = window.width - 2 * Gap.xl;
    final height = math.min(window.height - 2 * Gap.xl, 960.0);
    var box = Size(width, width / aspect);
    if (box.height > height) box = Size(height * aspect, height);
    if (natural != null && widget.original == null && natural < box) {
      return natural;
    }
    return box;
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.original;
    Widget button(String tooltip, IconData icon, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip,
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: .45),
            foregroundColor: Colors.white,
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
        );
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(Gap.xl),
      child: Semantics(
        label: widget.label,
        image: true,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              maxScale: 4,
              child: SizedBox.fromSize(
                size: _box(MediaQuery.sizeOf(context)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedImage(
                      url: widget.address,
                      fit: BoxFit.contain,
                      frameBuilder: (_, child, frame, _) =>
                          frame == null ? const SizedBox.expand() : child,
                      errorBuilder: (context, _, _) => Center(
                        child: Text(
                          '图片加载失败',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    if (original != null)
                      CachedImage(
                        url: original,
                        fit: BoxFit.contain,
                        frameBuilder: (context, child, frame, synchronous) =>
                            Stack(
                              fit: StackFit.expand,
                              children: [
                                AnimatedOpacity(
                                  opacity: frame == null ? 0 : 1,
                                  duration: synchronous
                                      ? Duration.zero
                                      : motionDuration(context, 240),
                                  curve: Curves.easeOut,
                                  child: child,
                                ),
                                if (frame == null)
                                  const Align(
                                    alignment: Alignment.bottomCenter,
                                    child: LinearProgressIndicator(
                                      minHeight: 2,
                                    ),
                                  ),
                              ],
                            ),
                        errorBuilder: (_, _, _) => const Align(
                          alignment: Alignment.bottomCenter,
                          child: _ViewerNote('原图加载失败'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: Gap.sm,
              right: Gap.sm,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Gap.xs,
                children: [
                  if (widget.browsable)
                    button(
                      '在浏览器打开',
                      Icons.open_in_new,
                      () => openExternal(context, widget.address),
                    ),
                  button('关闭', Icons.close, () => Navigator.pop(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A line over the picture, readable on any picture.
class _ViewerNote extends StatelessWidget {
  const _ViewerNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Gap.md),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: badgeBorderRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.sm,
          vertical: Gap.xs,
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: FontSize.small, color: Colors.white),
        ),
      ),
    ),
  );
}
