import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings.dart';

/// Space between posters in a grid, across and down.
const posterSpacing = Offset(16, 20);

/// A poster cell's width over its height, the cover and the line under it.
const posterAspect = .65;

/// Columns a poster grid [extent] wide shows unzoomed: posters about 184
/// pixels wide, at most eight to a row.
int standardPosterColumns(double extent) => (extent / 184).floor().clamp(1, 8);

/// Columns at zoom [level]: each level one column more, or fewer when
/// negative, with posters kept between 112 and 400 pixels wide.
int posterColumns(double extent, int level) {
  final standard = standardPosterColumns(extent);
  final fewest = math.min(
    standard,
    math.max(
      1,
      ((extent + posterSpacing.dx) / (400 + posterSpacing.dx)).ceil(),
    ),
  );
  final most = math.max(
    standard,
    ((extent + posterSpacing.dx) / (112 + posterSpacing.dx)).floor(),
  );
  return (standard + level).clamp(fewest, most);
}

/// The distance from one row's top to the next in a grid of [columns].
double posterRowStride(double extent, int columns) =>
    (extent - (columns - 1) * posterSpacing.dx) / columns / posterAspect +
    posterSpacing.dy;

/// Where a zoomable grid last laid out: its scroll view, where it starts in
/// it, how wide it is and how many posters it holds.
typedef PosterGridLayout = ({
  ScrollPosition? position,
  double top,
  double extent,
  int count,
});

/// How many posters a row of a grid holds, as a zoom level over the
/// standard count, which follows the window's width. Saved per device: the
/// same level means a different size on another screen.
class PosterZoom extends ChangeNotifier {
  PosterZoom(this.settings, this.setting) : _level = settings.get(setting);
  final Settings settings;
  final IntSetting setting;

  int _level;
  int get level => _level;

  /// Set by the grid each time it lays out.
  PosterGridLayout? layout;

  /// The columns the grid shows now; null before it lays out.
  int? get columns => switch (layout) {
    final layout? => posterColumns(layout.extent, _level),
    null => null,
  };

  /// Shows [columns] to a row, keeping the poster at [focus] (a point in
  /// the scroll view) where it is.
  void show(int columns, Offset focus, {required double viewportWidth}) {
    final layout = this.layout;
    if (layout == null) return;
    final from = posterColumns(layout.extent, _level);
    final standard = standardPosterColumns(layout.extent);
    final level = columns - standard;
    final to = posterColumns(layout.extent, level);
    if (to == from) return;
    _level = to - standard;
    unawaited(settings.set(setting, _level));
    _keep(layout, from, to, focus, viewportWidth);
    notifyListeners();
  }

  /// Back to the standard count.
  void reset(Offset focus, {required double viewportWidth}) {
    final layout = this.layout;
    if (layout == null) return;
    show(
      standardPosterColumns(layout.extent),
      focus,
      viewportWidth: viewportWidth,
    );
  }

  /// Scrolls so the poster at [focus] stays under it once rows reflow from
  /// [from] columns to [to]; above the grid nothing moves.
  static void _keep(
    PosterGridLayout layout,
    int from,
    int to,
    Offset focus,
    double viewportWidth,
  ) {
    final position = layout.position;
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions ||
        layout.count == 0) {
      return;
    }
    final before = posterRowStride(layout.extent, from);
    final after = posterRowStride(layout.extent, to);
    final y = position.pixels + focus.dy - layout.top;
    if (y <= 0) return;
    final row = (y / before).floor();
    final within = y / before - row;
    // The grid sits centred in the scroll view.
    final x = focus.dx - (viewportWidth - layout.extent) / 2;
    final column = (x / (layout.extent / from)).floor().clamp(0, from - 1);
    final index = math.min(row * from + column, layout.count - 1);
    double height(int columns, double stride) =>
        (layout.count / columns).ceil() * stride - posterSpacing.dy;
    // What follows the grid keeps its height, so the new end is known
    // before the reflow lays it out.
    final trailing =
        position.maxScrollExtent +
        position.viewportDimension -
        layout.top -
        height(from, before);
    final end =
        layout.top + height(to, after) + trailing - position.viewportDimension;
    final target = layout.top + (index ~/ to + within) * after - focus.dy;
    position.jumpTo(
      target.clamp(
        position.minScrollExtent,
        math.max(position.minScrollExtent, end),
      ),
    );
  }
}

/// Zooms the poster grid in [child], a scroll view filling this region:
/// the wheel with ctrl (⌘ on macOS), a trackpad pinch, and ctrl or ⌘ with
/// +, - and 0 while the page shows.
class PosterZoomRegion extends StatefulWidget {
  const PosterZoomRegion({super.key, required this.zoom, required this.child});
  final PosterZoom zoom;
  final Widget child;

  @override
  State<PosterZoomRegion> createState() => _PosterZoomRegionState();
}

class _PosterZoomRegionState extends State<PosterZoomRegion> {
  late ValueListenable<TickerModeData> _shown;

  /// Null outside any route, where nothing can cover the page.
  ModalRoute<Object?>? _route;

  /// Wheel travel not yet turned into a step: a notch is 100 on Windows,
  /// a smooth wheel sends many small ones.
  double _wheel = 0;

  /// The columns and point a pinch started with.
  (int, Offset)? _pinch;

  static bool get _modifier => Platform.isMacOS
      ? HardwareKeyboard.instance.isMetaPressed
      : HardwareKeyboard.instance.isControlPressed;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown = TickerMode.getValuesNotifier(context);
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  /// Laid out before any key or pointer reaches it.
  double get _width => context.size!.width;

  void _step(int columns, Offset focus) {
    final current = widget.zoom.columns;
    if (current == null) return;
    widget.zoom.show(current + columns, focus, viewportWidth: _width);
  }

  bool _key(KeyEvent event) {
    if (event is KeyUpEvent ||
        !_modifier ||
        !mounted ||
        !_shown.value.enabled ||
        !(_route?.isCurrent ?? true)) {
      return false;
    }
    // The top of the view stays put.
    final focus = Offset(_width / 2, 0);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.equal ||
          LogicalKeyboardKey.add ||
          LogicalKeyboardKey.numpadAdd:
        _step(-1, focus);
      case LogicalKeyboardKey.minus || LogicalKeyboardKey.numpadSubtract:
        _step(1, focus);
      case LogicalKeyboardKey.digit0 || LogicalKeyboardKey.numpad0:
        widget.zoom.reset(focus, viewportWidth: _width);
      default:
        return false;
    }
    return true;
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_modifier) return;
    // Registered before the scroll view under it, which then leaves the
    // event alone.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final delta = event.scrollDelta.dy;
      if (delta == 0) return;
      if (_wheel * delta < 0) _wheel = 0;
      _wheel += delta;
      if (_wheel.abs() < 40) return;
      _wheel = 0;
      // Down shows more posters, as zooming out does elsewhere.
      _step(delta > 0 ? 1 : -1, event.localPosition);
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      // On top and see-through: it hears the wheel before the scroll view
      // does, and every pointer still reaches what lies under it.
      Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: _signal,
          onPointerPanZoomStart: (event) {
            if (widget.zoom.columns case final columns?) {
              _pinch = (columns, event.localPosition);
            }
          },
          onPointerPanZoomUpdate: (event) {
            // Spreading the fingers enlarges posters: fewer to a row.
            if (_pinch case (final columns, final focus)) {
              widget.zoom.show(
                (columns / event.scale).round(),
                focus,
                viewportWidth: _width,
              );
            }
          },
          onPointerPanZoomEnd: (_) => _pinch = null,
        ),
      ),
    ],
  );
}
