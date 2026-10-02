import 'dart:math' as math;
import 'dart:ui';

import '../../app_services.dart';

int firstVisibleComment(List<Json> comments, double after) {
  var low = 0;
  var high = comments.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (number(comments[middle]['timeSeconds']) < after) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

class PlacedDanmaku {
  PlacedDanmaku(this.item, this.extent, this.y);

  final Json item;
  final Size extent;
  final double y;
  double get start => number(item['timeSeconds']);
  double get end => start + DanmakuLayout.lifetime;
  bool get scrolling => (item['mode'] ?? 'scroll') == 'scroll';

  Rect boundsAt(double time, double viewportWidth) => Rect.fromLTWH(
    scrolling
        ? viewportWidth -
              (viewportWidth + extent.width) *
                  (time - start) /
                  DanmakuLayout.lifetime
        : (viewportWidth - extent.width) / 2,
    y,
    extent.width,
    extent.height,
  );
}

/// Admits comments once, using their measured bounds over their shared lifetime.
class DanmakuLayout {
  static const lifetime = 8.0;
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
    required List<Json> comments,
    required double time,
    required Size viewport,
    required double fontSize,
    required double area,
    int density = 1,
    required Size Function(Json) measure,
  }) {
    final configuration = (comments, viewport, fontSize, area, density);
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
      final start = number(item['timeSeconds']);
      if (start > time) break;
      _next++;
      _active.removeWhere((entry) => entry.end <= start);
      if ('${item['text'] ?? ''}'.isEmpty ||
          (cap > 0 && _active.length >= cap)) {
        continue;
      }
      final extent = measure(item);
      final step = math.max(fontSize, extent.height) + verticalGap;
      final laneCount = math.max(1, ((band / step) * laneRatio).ceil());
      for (var lane = 0; lane < laneCount; lane++) {
        final offset = lane * step;
        if (offset + extent.height > band) break;
        final y = item['mode'] == 'bottom'
            ? bottom - extent.height - offset
            : top + offset;
        final candidate = PlacedDanmaku(item, extent, y);
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
