import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/json.dart' show coverAddress;
import '../../domain/catalog.dart';
import '../tracking/collection_labels.dart';
import 'cached_image.dart';
import 'page_widgets.dart';
import 'motion.dart';
import 'theme.dart';

/// A missing or loading portrait of a character or person: the "invisible"
/// Akkarin line drawing tinted to the theme, so empty slots stay neutral
/// instead of adding colour.
class ArtPlaceholder extends StatelessWidget {
  const ArtPlaceholder({super.key, this.label = ''});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.onSurfaceVariant.withValues(alpha: .6);
    return Semantics(
      label: label.isEmpty ? '暂无图片' : label,
      image: true,
      child: ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: FractionallySizedBox(
          widthFactor: .8,
          heightFactor: .8,
          child: Image.asset(
            'assets/images/akkarin.png',
            color: line,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}

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

class SubjectPosters extends StatelessWidget {
  const SubjectPosters({
    super.key,
    required this.items,
    required this.onOpen,
    this.horizontal = false,
    this.ranked = false,
    this.tracking = false,
  });
  final List<Subject> items;
  final ValueChanged<Subject> onOpen;
  final bool horizontal, ranked, tracking;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyState(text: '这里还没有番剧');
    Widget poster(int i) => SubjectPoster(
      onOpen: onOpen,
      item: items[i],
      rank: ranked ? i + 1 : null,
      tracking: tracking,
    );
    if (horizontal) {
      return HorizontalPosters(
        storageId: key,
        ranked: ranked,
        itemCount: items.length,
        itemBuilder: poster,
      );
    }
    return CustomScrollView(
      slivers: [
        SubjectPosterGrid(items: items, onOpen: onOpen, tracking: tracking),
      ],
    );
  }
}

/// Posters in a grid. When the order or set of items changes, posters that
/// stay glide to their new cells and new ones fade in.
class SubjectPosterGrid extends StatefulWidget {
  const SubjectPosterGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.tracking = false,
    this.personalScore = false,
  });
  final List<Subject> items;
  final ValueChanged<Subject> onOpen;
  final bool tracking;

  /// Shows the user's own score instead of the public one.
  final bool personalScore;

  @override
  State<SubjectPosterGrid> createState() => _SubjectPosterGridState();
}

class _SubjectPosterGridState extends State<SubjectPosterGrid> {
  /// Set on creation too, so the first posters cascade in row by row.
  DateTime _changedAt = DateTime.now();

  @override
  void didUpdateWidget(SubjectPosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.items, after = widget.items;
    if (before.length != after.length ||
        Iterable.generate(after.length)
            .any((i) => before[i].id != after[i].id)) {
      _changedAt = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final indexes = {for (final (i, item) in items.indexed) item.id: i};
    final duration = motionDuration(context, 220);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const spacing = Offset(16, 20);
        final columns = (constraints.crossAxisExtent / 184).floor().clamp(1, 8);
        final width =
            (constraints.crossAxisExtent - (columns - 1) * spacing.dx) /
            columns;
        final stride = Offset(width, width / .65) + spacing;
        return SliverGrid.builder(
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing.dx,
            mainAxisSpacing: spacing.dy,
            childAspectRatio: .65,
          ),
          findChildIndexCallback: (key) =>
              indexes[(key as ValueKey<int>).value],
          itemBuilder: (_, i) => _PosterMotion(
            key: ValueKey(items[i].id),
            index: i,
            columns: columns,
            stride: stride,
            duration: duration,
            // Only posters built right after a change fade in, not those
            // scrolled into view later.
            entering:
                DateTime.now().difference(_changedAt) <
                const Duration(milliseconds: 300),
            child: SubjectPoster(
              onOpen: widget.onOpen,
              item: items[i],
              tracking: widget.tracking,
              personalScore: widget.personalScore,
            ),
          ),
        );
      },
    );
  }
}

class _PosterMotion extends StatefulWidget {
  const _PosterMotion({
    super.key,
    required this.index,
    required this.columns,
    required this.stride,
    required this.duration,
    required this.entering,
    required this.child,
  });
  final int index, columns;
  final Offset stride;
  final Duration duration;
  final bool entering;
  final Widget child;

  Offset get slot =>
      Offset((index % columns) * stride.dx, (index ~/ columns) * stride.dy);

  @override
  State<_PosterMotion> createState() => _PosterMotionState();
}

class _PosterMotionState extends State<_PosterMotion>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);
  Curve _curve = Curves.easeOutCubic;

  /// Offset from the cell when the animation starts.
  Offset _from = Offset.zero;
  bool _fade = false;

  Offset get _offset => _from * (1 - _curve.transform(_controller.value));

  @override
  void initState() {
    super.initState();
    if (widget.entering) _enter();
  }

  @override
  void didUpdateWidget(_PosterMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    // Continue from where the poster is drawn, even mid-move.
    final from = _offset + oldWidget.slot - widget.slot;
    // A long jump reads as noise; the poster fades in at its cell instead.
    if (from.distance > widget.stride.dy * 3) return _enter();
    _from = from;
    _fade = false;
    _run(widget.duration, Curves.easeOutCubic);
  }

  void _enter() {
    _from = const Offset(0, 10);
    _fade = true;
    if (widget.duration == Duration.zero) return _run(Duration.zero, _curve);
    // Rows further down start a little later.
    final delay = math.min(widget.index ~/ widget.columns, 4) * 25;
    final total = 180 + delay;
    _run(
      Duration(milliseconds: total),
      Interval(delay / total, 1, curve: Curves.easeOut),
    );
  }

  void _run(Duration duration, Curve curve) {
    _curve = curve;
    if (duration == Duration.zero) {
      _controller.value = 1;
      return;
    }
    _controller.duration = duration;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _fade ? _curve.transform(_controller.value) : 1,
      child: Transform.translate(offset: _offset, child: child),
    ),
  );
}

class HorizontalPosters extends StatefulWidget {
  const HorizontalPosters({
    super.key,
    required this.ranked,
    required this.itemCount,
    required this.itemBuilder,
    this.storageId,
  });
  final bool ranked;
  final int itemCount;
  final Widget Function(int) itemBuilder;
  final Object? storageId;

  @override
  State<HorizontalPosters> createState() => _HorizontalPostersState();
}

class _HorizontalPostersState extends State<HorizontalPosters> {
  final _scroll = ScrollController();
  bool _back = false, _forward = false;
  int _hoveredEdge = 0, _focusedEdge = 0;

  void _hover(int direction) {
    if (_hoveredEdge != direction) setState(() => _hoveredEdge = direction);
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateButtons);
  }

  void _updateButtons() {
    if (!mounted ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions) {
      return;
    }
    final back = _scroll.position.extentBefore > .5;
    final forward = _scroll.position.extentAfter > .5;
    if (back != _back || forward != _forward) {
      setState(() {
        _back = back;
        _forward = forward;
      });
    }
  }

  void _page(int direction) {
    final position = _scroll.position;
    final stride = (widget.ranked ? 180.0 : 188.0) + 16;
    final count = (position.viewportDimension / stride).floor().clamp(
      1,
      widget.itemCount,
    );
    final target = (position.pixels + direction * count * stride).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final duration = motionDuration(context, 220);
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: duration, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.ranked ? 330 : 292,
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _updateButtons();
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) => MouseRegion(
          onExit: (_) => _hover(0),
          onHover: (event) {
            final point = event.localPosition;
            final nearButton =
                (point.dy - (widget.ranked ? 122 : 134)).abs() <= 56;
            _hover(
              !nearButton
                  ? 0
                  : point.dx <= 76
                  ? -1
                  : point.dx >= constraints.maxWidth - 76
                  ? 1
                  : 0,
            );
          },
          child: Stack(
            children: [
              ListView.separated(
                key: PageStorageKey(
                  widget.storageId ??
                      (widget.ranked ? 'ranked-posters' : 'subject-posters'),
                ),
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(2, 3, 2, 10),
                scrollDirection: Axis.horizontal,
                itemCount: widget.itemCount,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (_, i) => SizedBox(
                  width: widget.ranked ? 180 : 188,
                  child: widget.itemBuilder(i),
                ),
              ),
              for (final direction in [-1, 1])
                if (direction < 0 ? _back : _forward)
                  Positioned(
                    left: direction < 0 ? 6 : null,
                    right: direction > 0 ? 6 : null,
                    top: widget.ranked ? 102 : 114,
                    child: Focus(
                      canRequestFocus: false,
                      onFocusChange: (focused) => setState(() {
                        _focusedEdge = focused
                            ? direction
                            : _focusedEdge == direction
                            ? 0
                            : _focusedEdge;
                      }),
                      child: IgnorePointer(
                        ignoring:
                            _hoveredEdge != direction &&
                            _focusedEdge != direction,
                        child: AnimatedOpacity(
                          opacity:
                              _hoveredEdge == direction ||
                                  _focusedEdge == direction
                              ? .85
                              : 0,
                          duration: motionDuration(context, 150),
                          child: Material(
                            color: Theme.of(context).colorScheme.surface,
                            shape: const CircleBorder(),
                            elevation: 2,
                            shadowColor: Theme.of(context).shadowColor,
                            child: IconButton(
                              tooltip: direction < 0 ? '向左翻页' : '向右翻页',
                              onPressed: () => _page(direction),
                              icon: Icon(
                                direction < 0
                                    ? Icons.chevron_left
                                    : Icons.chevron_right,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SubjectPoster extends StatefulWidget {
  const SubjectPoster({
    super.key,
    required this.item,
    required this.onOpen,
    this.rank,
    required this.tracking,
    this.badge,
    this.personalScore = false,
  });
  final Subject item;
  final ValueChanged<Subject> onOpen;
  final int? rank;
  final bool tracking, personalScore;

  /// Replaces the collection status badge with a highlighted label.
  final String? badge;

  @override
  State<SubjectPoster> createState() => _SubjectPosterState();
}

class _SubjectPosterState extends State<SubjectPoster> {
  bool hovered = false;
  bool focused = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final rank = widget.rank;
    final tracking = widget.tracking;
    final status = item.status;
    return InkWell(
      onTap: () => widget.onOpen(item),
      onHover: (value) => setState(() => hovered = value),
      onFocusChange: (value) => setState(() => focused = value),
      onHighlightChanged: (value) => setState(() => pressed = value),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      borderRadius: posterBorderRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PosterLift(
              raised: hovered || focused,
              pressed: pressed,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SubjectCover(
                    url: item.coverUrl,
                    title: item.title,
                    id: item.id,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [.4, 1],
                        colors: [Colors.transparent, Color(0xcc000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 11,
                    right: 10,
                    bottom: 12,
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (rank != null)
                    Positioned(
                      top: 9,
                      left: 9,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: badgeBorderRadius,
                          gradient: rank <= 3
                              ? const LinearGradient(
                                  colors: [Color(0xffffcf6b), coral],
                                )
                              : null,
                          color: rank > 3 ? Colors.black38 : null,
                        ),
                        child: Text(
                          '#$rank',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (widget.badge case final badge?)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: const BoxDecoration(
                          color: coral,
                          borderRadius: badgeBorderRadius,
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )
                  else if (tracking && status != null)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: badgeBorderRadius,
                        child: MelonBadge(
                          collectionLabels[status]!,
                          color: collectionColor(status),
                        ),
                      ),
                    ),
                  IgnorePointer(
                    child: AnimatedContainer(
                      duration: motionDuration(context, pressed ? 80 : 120),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        borderRadius: posterBorderRadius,
                        color: pressed
                            ? Colors.black.withValues(alpha: .12)
                            : hovered
                            ? Colors.white.withValues(alpha: .06)
                            : Colors.transparent,
                        border: focused
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
          ),
          const SizedBox(height: 10),
          if (rank != null) ...[
            SizedBox(
              height: 54,
              child: Wrap(
                spacing: 5,
                runSpacing: 4,
                children: [
                  if (item.season?.label case final label?)
                    MelonBadge(label, color: coral),
                  MelonBadge(item.platform ?? 'TV', color: sky),
                  if (item.episodeTotal != null)
                    MelonBadge('全${item.episodeTotal}话', color: sky),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          PosterMeta(
            item: item,
            tracking: tracking,
            ranked: rank != null,
            personalScore: widget.personalScore,
          ),
        ],
      ),
    );
  }
}

/// A poster's cover that rises a little toward the pointer, its shadow
/// deepening, and gives slightly under a press.
class PosterLift extends StatelessWidget {
  const PosterLift({
    super.key,
    required this.raised,
    required this.child,
    this.pressed = false,
  });
  final bool raised, pressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: pressed
        ? .98
        : raised
        ? 1.02
        : 1,
    duration: motionDuration(context, pressed ? 100 : 260),
    curve: Curves.easeOutCubic,
    child: AnimatedContainer(
      duration: motionDuration(context, 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: posterBorderRadius,
        boxShadow: posterShadows(context, raised: raised && !pressed),
      ),
      child: ClipRRect(borderRadius: posterBorderRadius, child: child),
    ),
  );
}

/// The line under a poster: the score, then the watch progress when
/// [tracking], or the year and episode count.
class PosterMeta extends StatelessWidget {
  const PosterMeta({
    super.key,
    required this.item,
    this.tracking = false,
    this.ranked = false,
    this.personalScore = false,
  });
  final Subject item;
  final bool tracking, ranked;

  /// Shows the user's own score, marked apart so it is not taken for the
  /// public one.
  final bool personalScore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final personal = item.collection?.score ?? 0;
    return Row(
      children: [
        AnimatedSwitcher(
          duration: motionDuration(context, 150),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: personalScore
              ? DecoratedBox(
                  key: const ValueKey('personal'),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: badgeBorderRadius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text.rich(
                      TextSpan(
                        text: '我的 ',
                        children: [
                          TextSpan(
                            text: '★ ${personal > 0 ? personal : '—'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                )
              : Text(
                  '★ ${scoreLabel(item.score)}',
                  key: const ValueKey('public'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ranked ? scheme.tertiary : scheme.onSurfaceVariant,
                  ),
                ),
        ),
        const Spacer(),
        if (tracking)
          Text(
            switch ((item.watchedEpisodes, item.episodeTotal)) {
              (null, null) => '',
              (null, final total?) => '全 $total 话',
              (final watched?, null) => '已看 $watched 话',
              (final watched?, final total?) => '已看 $watched/$total',
            },
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          )
        else if (!ranked)
          Text(
            [
              if (item.season?.year case final year?) '$year',
              if (item.episodeTotal != null) '${item.episodeTotal} 话',
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

String scoreLabel(Object? value) =>
    value is num && value > 0 ? value.toStringAsFixed(1) : '—';
Color collectionColor(CollectionStatus status) => switch (status) {
  CollectionStatus.wish => sky,
  CollectionStatus.onHold => gold,
  CollectionStatus.completed => grape,
  CollectionStatus.dropped => coral,
  CollectionStatus.watching => mint,
};

int imageDecodeWidth(BuildContext context, double width) =>
    ((width * MediaQuery.devicePixelRatioOf(context) / 64).ceil() * 64).clamp(
      64,
      2048,
    );

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
  });
  final Object? url;
  final String title;
  final int id;
  final BoxFit fit;

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
      if (!mounted || id != widget.id || _address != null) return;
      _retry = Timer(
        Duration(seconds: math.min(60, 1 << math.min(++_attempt, 6))),
        _resolve,
      );
    }

    // The placeholder remains visible while missing metadata or a failed
    // catalogue request is retried, just like CachedImage's byte requests.
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
              builder: (context, constraints) => CachedImage(
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
              ),
            ),
    );
  }
}

class PosterPlaceholders extends StatelessWidget {
  const PosterPlaceholders({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载番剧',
    child: ExcludeSemantics(
      child: MotionPulse(
        child: SizedBox(
          height: 330,
          child: ListView.separated(
            key: const PageStorageKey('poster-placeholders'),
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, _) => SizedBox(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 240,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: posterBorderRadius,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 130,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: badgeBorderRadius,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
