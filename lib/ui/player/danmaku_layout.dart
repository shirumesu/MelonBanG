import 'dart:math' as math;
import 'dart:ui';

import '../../domain/danmaku.dart';

/// The first comment at or after [after], or with [inclusive] false, the
/// first one past it.
int firstVisibleComment(
  List<DanmakuComment> comments,
  double after, {
  bool inclusive = true,
}) {
  var low = 0;
  var high = comments.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    final time = comments[middle].time;
    if (inclusive ? time < after : time <= after) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

class PlacedDanmaku {
  PlacedDanmaku(this.item, this.extent, this.y, this.lifetime, this.start);

  final DanmakuComment item;
  final Size extent;
  final double y;
  final double lifetime;

  /// When it entered: its own time, or when it was sent.
  final double start;
  double get end => start + lifetime;
  bool get scrolling => item.mode == DanmakuMode.scroll;

  Rect boundsAt(double time, double viewportWidth) => Rect.fromLTWH(
    scrolling
        ? viewportWidth -
              (viewportWidth + extent.width) * (time - start) / lifetime
        : (viewportWidth - extent.width) / 2,
    y,
    extent.width,
    extent.height,
  );
}

/// Admits comments once, using their measured bounds over their shared lifetime.
class DanmakuLayout {
  /// Scrolling comments move at one speed in logical pixels at every viewport
  /// width, so fullscreen reads like the window. Bilibili's engine scales
  /// duration with width the same way: 682 px of size-25 text in 3.8 s, and
  /// shows fixed comments for the same 3.8 s.
  static const scrollSpeed = 682 / 3.8;
  static const fixedLifetime = 3.8;
  static const horizontalGap = 20.0;
  static const verticalGap = 10.0;
  final _active = <PlacedDanmaku>[];
  Object? _configuration;
  int? _revision;
  List<DanmakuComment>? _comments;
  double? _time;
  double _width = 0;
  int _next = 0;

  /// Sent comments placed when they were sent, which the list holds too.
  final _injected = Set<DanmakuComment>.identity();

  void clear() {
    _active.clear();
    _injected.clear();
    _configuration = null;
    _revision = null;
    _comments = null;
    _time = null;
    _next = 0;
  }

  /// While no comment is shown, the time the next one after [time] enters
  /// (infinity when none is left); null while one is shown, before the first
  /// layout, or when [time] went back past it and needs laying out anew.
  double? quietAfter(double time) {
    final comments = _comments;
    if (comments == null || _active.isNotEmpty || time < _time!) return null;
    return _next < comments.length ? comments[_next].time : double.infinity;
  }

  /// Lays out [comments] at [time]. A new list under the same [revision]
  /// only gained [sent] comments: those enter now from the edge, and the
  /// comments already shown keep their places. A new [revision] keeps the
  /// places of comments it still shows too, so hiding top comments leaves
  /// the scrolling ones where they are.
  List<PlacedDanmaku> update({
    required List<DanmakuComment> comments,
    required int revision,
    List<DanmakuComment> sent = const [],
    required double time,
    required Size viewport,
    required double fontSize,
    required double area,
    int density = 1,
    required double speed,
    required bool overlap,
    required bool shield,
    required Size Function(DanmakuComment) measure,
  }) {
    final configuration = (
      viewport,
      fontSize,
      area,
      density,
      speed,
      overlap,
      shield,
    );
    final scrollLifetime = viewport.width / (scrollSpeed * speed);
    final lifetime = math.max(fixedLifetime, scrollLifetime);
    // Comments of the new list that keep their earlier places.
    final staying = Set<DanmakuComment>.identity();
    if (_configuration != configuration ||
        _time == null ||
        time < _time! ||
        time - _time! > lifetime) {
      _active.clear();
      _injected.clear();
      _next = firstVisibleComment(comments, time - lifetime);
      _configuration = configuration;
    } else if (_revision != revision) {
      // Matched by content: merging rebuilds the `×N` comments each time.
      final kept = {for (final entry in _active) _key(entry.item): entry};
      _active.clear();
      _next = firstVisibleComment(comments, time - lifetime);
      // A sent comment can be stamped a little past the clock.
      for (var i = _next; i < comments.length && kept.isNotEmpty; i++) {
        final item = comments[i];
        if (item.time > time + lifetime) break;
        final entry = kept.remove(_key(item));
        if (entry == null) continue;
        _active.add(entry);
        staying.add(item);
      }
    } else if (!identical(comments, _comments)) {
      _next = firstVisibleComment(comments, _time!, inclusive: false);
    }
    _revision = revision;
    _comments = comments;
    _time = time;
    _width = viewport.width;
    const top = 16.0;
    // Shielding keeps the bottom 15% (subtitles) clear, as Bilibili's 防挡 does.
    final bottom = math.max(
      top,
      math.min(
        viewport.height - 75,
        shield ? viewport.height * .85 : viewport.height,
      ),
    );
    final band = math.min(viewport.height * area, bottom - top);
    final laneRatio = const [.35, .6, .85, 1.0][density.clamp(0, 3)];
    final cap = const [30, 60, 100, 0][density.clamp(0, 3)];
    void place(DanmakuComment item, double start) {
      _active.removeWhere((entry) => entry.end <= start);
      if (cap > 0 && _active.length >= cap && !item.own) return;
      final extent = measure(item);
      final step = math.max(fontSize, extent.height) + verticalGap;
      final laneCount = math.max(1, ((band / step) * laneRatio).ceil());
      // With overlap allowed, a crowded comment takes the least busy lane.
      PlacedDanmaku? placed;
      var fewest = 0;
      for (var lane = 0; lane < laneCount; lane++) {
        final offset = lane * step;
        if (offset + extent.height > band) break;
        final y = item.mode == DanmakuMode.bottom
            ? bottom - extent.height - offset
            : top + offset;
        final candidate = PlacedDanmaku(
          item,
          extent,
          y,
          item.mode == DanmakuMode.scroll ? scrollLifetime : fixedLifetime,
          start,
        );
        final collisions = overlap
            ? _active
                  .where(
                    (previous) =>
                        _collides(previous, candidate, viewport.width),
                  )
                  .length
            : _active.any(
                (previous) => _collides(previous, candidate, viewport.width),
              )
            ? 1
            : 0;
        if (collisions == 0) {
          placed = candidate;
          break;
        }
        if (overlap && (placed == null || collisions < fewest)) {
          placed = candidate;
          fewest = collisions;
        }
      }
      // A sent comment always shows, over the first lane if all are taken.
      if (placed == null && item.own && laneCount > 0) {
        placed = PlacedDanmaku(
          item,
          extent,
          item.mode == DanmakuMode.bottom ? bottom - extent.height : top,
          item.mode == DanmakuMode.scroll ? scrollLifetime : fixedLifetime,
          start,
        );
      }
      if (placed != null) _active.add(placed);
    }

    for (final item in sent) {
      if (_injected.add(item)) place(item, time);
    }
    while (_next < comments.length) {
      final item = comments[_next];
      if (item.time > time) break;
      _next++;
      if (!_injected.contains(item) && !staying.contains(item)) {
        place(item, item.time);
      }
    }
    _active.removeWhere((entry) => entry.end <= time);
    return _active;
  }

  /// The topmost comment shown at [position] at [time] that [test] accepts.
  DanmakuComment? hit(
    Offset position,
    double time,
    bool Function(DanmakuComment) test,
  ) {
    for (final entry in _active.reversed) {
      if (entry.boundsAt(time, _width).inflate(4).contains(position) &&
          test(entry.item)) {
        return entry.item;
      }
    }
    return null;
  }

  static (double, String, String, DanmakuMode, int, bool) _key(
    DanmakuComment item,
  ) => (item.time, item.text, item.source, item.mode, item.color, item.own);

  bool _collides(PlacedDanmaku a, PlacedDanmaku b, double width) {
    if (a.y + a.extent.height + verticalGap <= b.y ||
        b.y + b.extent.height + verticalGap <= a.y) {
      return false;
    }
    final start = b.start;
    final end = math.min(a.end, b.end);
    final aStart = a.boundsAt(start, width);
    final bStart = b.boundsAt(start, width);
    final aEnd = a.boundsAt(end, width);
    final bEnd = b.boundsAt(end, width);
    // Relative motion is linear: separation at both endpoints proves safety
    // throughout the interval, including scroll/fixed and faster followers.
    final aStaysLeft =
        aStart.right + horizontalGap <= bStart.left &&
        aEnd.right + horizontalGap <= bEnd.left;
    final bStaysLeft =
        bStart.right + horizontalGap <= aStart.left &&
        bEnd.right + horizontalGap <= aEnd.left;
    return !aStaysLeft && !bStaysLeft;
  }
}
