import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/json.dart' show coverAddress, coverOriginal;
import '../../domain/catalog.dart';
import 'cached_image.dart';
import 'image_viewer.dart';
import 'motion.dart';
import 'theme.dart';

/// A subject cover that is missing, still loading or failed to load: one
/// picture-off glyph on the neutral surface.
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({super.key, this.label = ''});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label.isEmpty ? '暂无封面' : label,
      image: true,
      child: ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: Icon(
              Icons.hide_image_outlined,
              size: (constraints.biggest.shortestSide * .3).clamp(14, 44),
              color: scheme.onSurfaceVariant.withValues(alpha: .45),
            ),
          ),
        ),
      ),
    );
  }
}

/// A cover's rounded clip with a hairline just inside its edge, so a pale
/// cover keeps its outline on a pale page. [shadow] casts [posterShadows].
class CoverFrame extends StatelessWidget {
  const CoverFrame({
    super.key,
    required this.child,
    this.radius = posterBorderRadius,
    this.shadow = false,
  });
  final Widget child;
  final BorderRadius radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final framed = ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: coverEdgeColor(context)),
        ),
        child: child,
      ),
    );
    if (!shadow) return framed;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: posterShadows(context),
      ),
      child: framed,
    );
  }
}

class SubjectCoverScope extends InheritedWidget {
  const SubjectCoverScope({
    super.key,
    required this.covers,
    required super.child,
  });
  final SubjectCovers covers;

  static SubjectCovers? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SubjectCoverScope>()?.covers;

  @override
  bool updateShouldNotify(SubjectCoverScope oldWidget) =>
      covers != oldWidget.covers;
}

class SubjectCover extends StatefulWidget {
  const SubjectCover({
    super.key,
    required this.url,
    this.title = '',
    this.id = 0,
    this.fit = BoxFit.cover,
    this.viewable = false,
  });
  final Object? url;
  final String title;
  final int id;
  final BoxFit fit;

  /// Whether a click or Enter on the cover opens it large.
  final bool viewable;

  @override
  State<SubjectCover> createState() => _SubjectCoverState();
}

class _SubjectCoverState extends State<SubjectCover> {
  SubjectCovers? _catalog;
  StreamSubscription<int>? _subscription;
  Timer? _retry;
  int _attempt = 0;
  final _unusable = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final catalog = SubjectCoverScope.of(context);
    if (_catalog == catalog) return;
    _subscription?.cancel();
    _catalog = catalog;
    _subscription = catalog?.coverUpdates.listen((id) {
      if (mounted && id == widget.id) setState(() {});
    });
    _resolve();
  }

  @override
  void didUpdateWidget(SubjectCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.url != widget.url) {
      _attempt = 0;
      _resolve();
    }
  }

  // The item's own address comes first; the catalogue's latest cover for the
  // subject fills in when it is absent or turned out to be unusable.
  String? get _address => [
    coverAddress(widget.url),
    _catalog?.coverFor(widget.id),
  ].nonNulls.where((address) => !_unusable.contains(address)).firstOrNull;

  void _resolve() {
    _retry?.cancel();
    final catalog = _catalog;
    final id = widget.id;
    if (catalog == null || id <= 0 || _address != null) return;
    void retry() {
      if (!mounted || id != widget.id || _address != null || _attempt > 0) {
        return;
      }
      _attempt++;
      _retry = Timer(const Duration(seconds: 2), _resolve);
    }

    // Missing metadata or a failed catalogue request is asked once more, as
    // CachedImage retries its bytes once; then the placeholder stays until
    // the cover is built anew.
    unawaited(
      catalog
          .resolveCover(id)
          .then((_) => retry(), onError: (Object _) => retry()),
    );
  }

  @override
  void dispose() {
    _retry?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final title = widget.title;
    final address = _address;
    final fallback = CoverPlaceholder(label: title);
    return AnimatedSwitcher(
      duration: motionDuration(context),
      child: address == null
          ? SizedBox.expand(key: ValueKey('placeholder:$id'), child: fallback)
          : LayoutBuilder(
              key: ValueKey('$id:$address'),
              builder: (context, constraints) {
                final image = CachedImage(
                  url: address,
                  cacheWidth: imageDecodeWidth(
                    context,
                    constraints.maxWidth.isFinite ? constraints.maxWidth : 512,
                  ),
                  fit: widget.fit,
                  onMissing: (address) {
                    setState(() => _unusable.add(address));
                    _resolve();
                  },
                  frameBuilder: (context, child, frame, synchronous) => Stack(
                    fit: StackFit.expand,
                    children: [
                      fallback,
                      AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: synchronous
                            ? Duration.zero
                            : motionDuration(context),
                        child: child,
                      ),
                    ],
                  ),
                  errorBuilder: (_, _, _) => fallback,
                );
                return widget.viewable
                    ? _ViewableCover(
                        address: address,
                        title: title,
                        child: image,
                      )
                    : image;
              },
            ),
    );
  }
}

/// A cover that opens large on a click or Enter: it lightens a little under
/// the pointer and takes a ring when reached from the keyboard.
class _ViewableCover extends StatefulWidget {
  const _ViewableCover({
    required this.address,
    required this.title,
    required this.child,
  });
  final String address, title;
  final Widget child;

  @override
  State<_ViewableCover> createState() => _ViewableCoverState();
}

class _ViewableCoverState extends State<_ViewableCover> {
  bool hovered = false, focused = false;

  @override
  Widget build(BuildContext context) {
    final ring =
        focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Tooltip(
      message: '查看大图',
      child: InkWell(
        onTap: () => showImageViewer(
          context,
          address: widget.address,
          original: coverOriginal(widget.address),
          label: widget.title.isEmpty ? '封面' : '${widget.title} 封面',
        ),
        onHover: (value) => setState(() => hovered = value),
        onFocusChange: (value) => setState(() => focused = value),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        borderRadius: posterBorderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            IgnorePointer(
              child: AnimatedContainer(
                duration: motionDuration(context, 120),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: posterBorderRadius,
                  color: hovered
                      ? Colors.white.withValues(alpha: .06)
                      : Colors.transparent,
                  border: ring
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
