import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/json.dart';
import '../tracking/collection_labels.dart';
import 'page_widgets.dart';
import 'motion.dart';
import 'theme.dart';

const _artColors = [
  [Color(0xff7bd0c1), Color(0xff3b82c4)],
  [Color(0xfff7a8b8), Color(0xff9b6ad8)],
  [Color(0xffffd56b), Color(0xffff7a5b)],
  [Color(0xff9be7c4), Color(0xff3aa17e)],
  [Color(0xffa9c7ff), Color(0xff6a6ae0)],
  [Color(0xffffb3c7), Color(0xffff6b9d)],
  [Color(0xffc0a8ff), Color(0xff7d5fe0)],
  [Color(0xff8fe3d6), Color(0xff3aa1a8)],
];

class SubjectPosters extends StatelessWidget {
  const SubjectPosters({
    super.key,
    required this.items,
    required this.onOpen,
    this.horizontal = false,
    this.ranked = false,
    this.tracking = false,
  });
  final List<Json> items;
  final ValueChanged<Json> onOpen;
  final bool horizontal, ranked, tracking;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyState(text: '这里还没有番剧');
    Widget poster(int i) => _SubjectPoster(
      onOpen: onOpen,
      item: items[i],
      rank: ranked ? i + 1 : null,
      tracking: tracking,
    );
    if (horizontal) {
      return _HorizontalPosters(
        storageId: key,
        ranked: ranked,
        itemCount: items.length,
        itemBuilder: poster,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        key: const PageStorageKey('poster-grid'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (constraints.maxWidth / 184).floor().clamp(1, 8),
          crossAxisSpacing: 16,
          mainAxisSpacing: 20,
          childAspectRatio: .65,
        ),
        itemBuilder: (_, i) => poster(i),
      ),
    );
  }
}

class _HorizontalPosters extends StatefulWidget {
  const _HorizontalPosters({
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
  State<_HorizontalPosters> createState() => _HorizontalPostersState();
}

class _HorizontalPostersState extends State<_HorizontalPosters> {
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

class _SubjectPoster extends StatefulWidget {
  const _SubjectPoster({
    required this.item,
    required this.onOpen,
    this.rank,
    required this.tracking,
  });
  final Json item;
  final ValueChanged<Json> onOpen;
  final int? rank;
  final bool tracking;

  @override
  State<_SubjectPoster> createState() => _SubjectPosterState();
}

class _SubjectPosterState extends State<_SubjectPoster> {
  bool hovered = false;
  bool focused = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final rank = widget.rank;
    final tracking = widget.tracking;
    final status =
        '${item['status'] ?? object(item['collection'])['status'] ?? ''}';
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
                      url: item['coverUrl'],
                      title: titleOf(item),
                      id: number(item['subjectId']).toInt(),
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
                        titleOf(item),
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
                    if (tracking && collectionLabels.containsKey(status))
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
                    if (tracking && item['episodeTotal'] != null)
                      Positioned(
                        top: 10,
                        right: 9,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 24),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: badgeBorderRadius,
                          ),
                          child: Text(
                            '全 ${item['episodeTotal']} 话',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
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
                  if (object(item['season'])['label'] != null)
                    MelonBadge(
                      '${object(item['season'])['label']}',
                      color: coral,
                    ),
                  MelonBadge('${item['platform'] ?? 'TV'}', color: sky),
                  if (item['episodeTotal'] != null)
                    MelonBadge('全${item['episodeTotal']}话', color: sky),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Text(
                '★ ${scoreLabel(item['score'])}',
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
                  item['watchedEpisodes'] == null
                      ? '未记录进度'
                      : '已看 ${item['watchedEpisodes']} 话',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else if (rank == null)
                Text(
                  item['episodeTotal'] == null
                      ? '${item['platform'] ?? '动画'}'
                      : '全 ${item['episodeTotal']} 话',
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
Color collectionColor(String status) => switch (status) {
  'wish' => sky,
  'on_hold' => gold,
  'completed' => grape,
  'dropped' => coral,
  _ => mint,
};

class SubjectCoverScope extends InheritedWidget {
  const SubjectCoverScope({
    super.key,
    required this.catalog,
    required super.child,
  });
  final CatalogRepository catalog;

  static CatalogRepository? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SubjectCoverScope>()?.catalog;

  @override
  bool updateShouldNotify(SubjectCoverScope oldWidget) =>
      catalog != oldWidget.catalog;
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
  CatalogRepository? _catalog;
  StreamSubscription<int>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final catalog = SubjectCoverScope.of(context);
    if (_catalog == catalog) return;
    _subscription?.cancel();
    _catalog = catalog;
    _subscription = catalog?.coverChanges.stream.listen((id) {
      if (mounted && id == widget.id && coverAddress(widget.url) == null) {
        setState(() {});
      }
    });
    _resolve();
  }

  @override
  void didUpdateWidget(SubjectCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.url != widget.url) _resolve();
  }

  void _resolve() {
    if (coverAddress(widget.url) == null) {
      unawaited(_catalog?.resolveCover(widget.id));
    }
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
    final address = coverAddress(widget.url) ?? _catalog?.coverFor(id);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _artColors[id.abs() % _artColors.length],
        ),
      ),
      child: Center(
        child: title.isEmpty
            ? const Icon(Icons.movie_outlined, color: Colors.white54, size: 36)
            : Text(
                title.characters.first,
                style: const TextStyle(
                  fontSize: 56,
                  color: Colors.white30,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    );
    return AnimatedSwitcher(
      duration: motionDuration(context),
      child: address == null
          ? SizedBox.expand(key: ValueKey('placeholder:$id'), child: fallback)
          : Image.network(
              address,
              key: ValueKey('$id:$address'),
              fit: widget.fit,
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
