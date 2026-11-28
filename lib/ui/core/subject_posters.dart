import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import 'collection_labels.dart';
import 'motion.dart';
import 'page_widgets.dart';
import 'poster_zoom.dart';
import 'subject_cover.dart';
import 'theme.dart';

/// Posters in a grid. When the order or set of items changes, posters that
/// stay glide to their new cells and new ones fade in.
/// Opens the menu of a poster's subject at a point of the window.
typedef PosterMenu = void Function(Subject item, Offset position);

class SubjectPosterGrid extends StatefulWidget {
  const SubjectPosterGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.tracking = false,
    this.statusBadge = true,
    this.personalScore = false,
    this.marked = const {},
    this.markedAt,
    this.zoom,
    this.onMenu,
  });
  final List<Subject> items;
  final ValueChanged<Subject> onOpen;

  /// Opens a poster's menu where it was secondary clicked.
  final PosterMenu? onMenu;
  final bool tracking, statusBadge;

  /// Shows the user's own score instead of the public one.
  final bool personalScore;

  /// Subjects a refresh just changed, ringed for a moment; [markedAt] tells
  /// one refresh's marks from the next.
  final Set<int> marked;
  final DateTime? markedAt;

  /// Lets the grid be zoomed, which it tells where it lays out.
  final PosterZoom? zoom;

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
        const spacing = posterSpacing;
        final extent = constraints.crossAxisExtent;
        widget.zoom?.layout = (
          position: Scrollable.maybeOf(context)?.position,
          top: constraints.precedingScrollExtent,
          extent: extent,
          count: items.length,
        );
        final columns = posterColumns(extent, widget.zoom?.level ?? 0);
        final width = (extent - (columns - 1) * spacing.dx) / columns;
        final stride = Offset(width, width / posterAspect) + spacing;
        return SliverGrid.builder(
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing.dx,
            mainAxisSpacing: spacing.dy,
            childAspectRatio: posterAspect,
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
              onMenu: widget.onMenu,
              item: items[i],
              tracking: widget.tracking,
              statusBadge: widget.statusBadge,
              personalScore: widget.personalScore,
              mark: widget.marked.contains(items[i].id)
                  ? widget.markedAt
                  : null,
            ),
          ),
        );
      },
    );
  }
}

/// Grey posters in [SubjectPosterGrid]'s layout while the first ones load;
/// [tracking] adds the progress at the end of each line, as the
/// collection's grid has; [level] is the grid's zoom. Shown at once: the
/// caller's [DelayedBusy] decides when.
class PosterGridSkeleton extends StatelessWidget {
  const PosterGridSkeleton({
    super.key,
    this.tracking = false,
    this.rows = 2,
    this.level = 0,
  });
  final bool tracking;
  final int rows, level;

  @override
  Widget build(BuildContext context) => SkeletonGroup(
    label: '正在加载番剧',
    child: LayoutBuilder(builder: _grid),
  );

  Widget _grid(BuildContext context, BoxConstraints constraints) {
    const spacing = posterSpacing;
    final columns = posterColumns(constraints.maxWidth, level);
    final width = (constraints.maxWidth - (columns - 1) * spacing.dx) / columns;
    return Wrap(
      spacing: spacing.dx,
      runSpacing: spacing.dy,
      children: [
        for (var i = 0; i < columns * rows; i++)
          SizedBox(
            width: width,
            height: width / posterAspect,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: SkeletonBlock(radius: posterBorderRadius),
                ),
                const SizedBox(height: Gap.sm),
                // PosterMeta: the score, then the progress at the end.
                SizedBox(
                  height: 16,
                  child: Row(
                    children: [
                      const SkeletonBlock(width: 36, height: 12),
                      const Spacer(),
                      if (tracking)
                        SkeletonBlock(width: 40 + i * 13 % 3 * 6, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
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

class SubjectPoster extends StatefulWidget {
  const SubjectPoster({
    super.key,
    required this.item,
    required this.onOpen,
    required this.tracking,
    this.statusBadge = true,
    this.personalScore = false,
    this.mark,
    this.onMenu,
  });
  final Subject item;
  final ValueChanged<Subject> onOpen;
  final PosterMenu? onMenu;
  final bool tracking, statusBadge, personalScore;

  /// Set when a refresh just changed the subject: a ring lights the cover
  /// for a moment, once per value.
  final Object? mark;

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
    final tracking = widget.tracking;
    final status = item.status;
    return InkWell(
      onTap: () => widget.onOpen(item),
      onSecondaryTapUp: switch (widget.onMenu) {
        final onMenu? => (details) => onMenu(item, details.globalPosition),
        null => null,
      },
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
                    left: Gap.md,
                    right: Gap.md,
                    bottom: Gap.md,
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: FontSize.body,
                        height: 1.3,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (tracking && widget.statusBadge && status != null)
                    Positioned(
                      top: Gap.sm,
                      left: Gap.sm,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: badgeBorderRadius,
                        child: MelonBadge(
                          collectionLabels[status]!,
                          color: collectionColor(status),
                        ),
                      ),
                    ),
                  if (widget.mark case final mark?)
                    UpdateRing(mark: mark, id: item.id),
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
          const SizedBox(height: Gap.sm),
          PosterMeta(
            item: item,
            tracking: tracking,
            personalScore: widget.personalScore,
          ),
        ],
      ),
    );
  }
}

/// A ring in the accent lighting a cover a refresh just changed: it comes
/// up quickly, holds, then fades, about 2.6s in all, once for each [mark].
/// On a page out of view it waits until the page shows.
class UpdateRing extends StatefulWidget {
  const UpdateRing({super.key, required this.mark, required this.id});
  final Object mark;

  /// The subject lit, which a mark lights once.
  final int id;

  @override
  State<UpdateRing> createState() => _UpdateRingState();
}

class _UpdateRingState extends State<UpdateRing>
    with SingleTickerProviderStateMixin {
  /// Marks already shown, so a rebuild or a poster scrolled back into view
  /// does not light again.
  static final _shown = <(Object, int)>{};

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final _opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 12,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 38),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 50,
    ),
  ]).animate(_controller);

  ValueListenable<TickerModeData>? _shownPage;
  bool _pending = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.getValuesNotifier(context);
    if (shown != _shownPage) {
      _shownPage?.removeListener(_play);
      _shownPage = shown..addListener(_play);
    }
    _play();
  }

  @override
  void didUpdateWidget(UpdateRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mark == widget.mark) return;
    _pending = true;
    _play();
  }

  /// Lights the ring once the page shows: a muted ticker keeps time, so
  /// one started out of view would be over before it was seen.
  void _play() {
    if (!_pending || !(_shownPage?.value.enabled ?? false)) return;
    _pending = false;
    if (_shown.add((widget.mark, widget.id))) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _shownPage?.removeListener(_play);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(context).accent;
    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: posterBorderRadius,
            border: Border.all(color: accent, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .45),
                blurRadius: 10,
                blurStyle: BlurStyle.inner,
              ),
            ],
          ),
        ),
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
      child: CoverFrame(child: child),
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
    this.personalScore = false,
  });
  final Subject item;
  final bool tracking;

  /// Shows the user's own score, marked apart so it is not taken for the
  /// public one.
  final bool personalScore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final personal = item.collection?.score ?? 0;
    final meta = TextStyle(
      fontSize: FontSize.caption,
      color: scheme.onSurfaceVariant,
    );
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
                    child: Text(
                      '我的 ★ ${personal > 0 ? personal : '—'}',
                      style: TextStyle(
                        fontSize: FontSize.small,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                )
              : Text(
                  '★ ${scoreLabel(item.score)}',
                  key: const ValueKey('public'),
                  style: TextStyle(
                    fontSize: FontSize.small,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
        ),
        if (tracking)
          // Progress pulled from Bangumi cross-fades in rather than jumping;
          // a zoomed-out grid's narrow poster cuts it short.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: Gap.sm),
              child: Align(
                alignment: Alignment.centerRight,
                child: MotionSwap(
                  value: item.watchedEpisodes,
                  scale: 1,
                  alignment: Alignment.centerRight,
                  child: Text(
                    switch ((item.watchedEpisodes, item.episodeTotal)) {
                      (null, null) => '',
                      (null, final total?) => '全 $total 话',
                      (final watched?, null) => '已看 $watched 话',
                      (final watched?, final total?) => '已看 $watched/$total',
                    },
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: meta,
                  ),
                ),
              ),
            ),
          )
        else ...[
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Gap.sm,
            children: [
              if (item.season?.year case final year?)
                Text('$year', style: meta),
              if (item.episodeTotal case final total?)
                Text('全 $total 话', style: meta),
            ],
          ),
        ],
      ],
    );
  }
}

String scoreLabel(Object? value) =>
    value is num && value > 0 ? value.toStringAsFixed(1) : '—';

/// [value] with a comma every three digits, as Bangumi writes counts.
String thousands(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);
Color collectionColor(CollectionStatus status) => switch (status) {
  CollectionStatus.wish => sky,
  CollectionStatus.onHold => gold,
  CollectionStatus.completed => grape,
  CollectionStatus.dropped => coral,
  CollectionStatus.watching => mint,
};
