import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/json.dart' show coverAddress;
import '../../domain/catalog.dart';
import '../tracking/collection_labels.dart';
import 'cached_image.dart';
import 'page_widgets.dart';
import 'motion.dart';
import 'theme.dart';

/// Missing or loading artwork: the "invisible" Akkarin line drawing tinted
/// to the theme, so empty slots stay neutral instead of adding colour.
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
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: Image.asset(
              'assets/images/akkarin.png',
              color: line,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
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

class SubjectPosterGrid extends StatelessWidget {
  const SubjectPosterGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.tracking = false,
  });
  final List<Subject> items;
  final ValueChanged<Subject> onOpen;
  final bool tracking;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) => SliverGrid.builder(
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: (constraints.crossAxisExtent / 184).floor().clamp(1, 8),
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
        childAspectRatio: .65,
      ),
      itemBuilder: (_, i) => SubjectPoster(
        key: ValueKey(items[i].id),
        onOpen: onOpen,
        item: items[i],
        tracking: tracking,
      ),
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
  });
  final Subject item;
  final ValueChanged<Subject> onOpen;
  final int? rank;
  final bool tracking;

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
            child: Container(
              decoration: BoxDecoration(
                borderRadius: posterBorderRadius,
                boxShadow: posterShadows(context),
              ),
              child: ClipRRect(
                borderRadius: posterBorderRadius,
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
          Row(
            children: [
              Text(
                '★ ${scoreLabel(tracking ? item.collection?.score : item.score)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: rank != null
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else if (rank == null)
                Text(
                  [
                    if (item.season?.year case final year?) '$year',
                    if (item.episodeTotal != null) '${item.episodeTotal} 话',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
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
    if (oldWidget.id != widget.id || oldWidget.url != widget.url) _resolve();
  }

  // The item's own address comes first; the catalogue's latest cover for the
  // subject fills in when it is absent or turned out to be unusable.
  String? get _address => [
    coverAddress(widget.url),
    _catalog?.coverFor(widget.id),
  ].nonNulls.where((address) => !_unusable.contains(address)).firstOrNull;

  void _resolve() {
    if (_address == null) unawaited(_catalog?.resolveCover(widget.id));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final title = widget.title;
    final address = _address;
    final fallback = ArtPlaceholder(label: title);
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
  );
}
