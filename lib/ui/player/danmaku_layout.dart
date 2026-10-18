import 'dart:math' as math;
import 'dart:ui';

import '../../domain/danmaku.dart';

int firstVisibleComment(List<DanmakuComment> comments, double after) {
  var low = 0;
  var high = comments.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (comments[middle].time < after) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

class PlacedDanmaku {
  PlacedDanmaku(this.item, this.extent, this.y, this.lifetime);

  final DanmakuComment item;
  final Size extent;
  final double y;
  final double lifetime;
  double get start => item.time;
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
  double? _time;
  int _next = 0;

  void clear() {
    _active.clear();
    _configuration = null;
    _time = null;
    _next = 0;
  }

  List<PlacedDanmaku> update({
    required List<DanmakuComment> comments,
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
      comments,
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
    if (_configuration != configuration ||
        _time == null ||
        time < _time! ||
        time - _time! > lifetime) {
      _active.clear();
      _next = firstVisibleComment(comments, time - lifetime);
      _configuration = configuration;
    }
    _time = time;
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
    while (_next < comments.length) {
      final item = comments[_next];
      final start = item.time;
      if (start > time) break;
      _next++;
      _active.removeWhere((entry) => entry.end <= start);
      if (cap > 0 && _active.length >= cap) continue;
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
      if (placed != null) _active.add(placed);
    }
    _active.removeWhere((entry) => entry.end <= time);
    return _active;
  }

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
