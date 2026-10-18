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
  /// duration with width the same way: 682 px of size-25 text in 3.8 s.
  static const scrollSpeed = 682 / 3.8;
  static const fixedLifetime = 8.0;
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
    required Size Function(DanmakuComment) measure,
  }) {
    final configuration = (comments, viewport, fontSize, area, density);
    final scrollLifetime = viewport.width / scrollSpeed;
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
    final bottom = math.max(top, viewport.height - 75);
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
        if (_active.any(
          (previous) => _collides(previous, candidate, viewport.width),
        )) {
          continue;
        }
        _active.add(candidate);
        break;
      }
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
