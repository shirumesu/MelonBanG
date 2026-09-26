import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/ui/player/danmaku.dart';
import 'package:melonbang/ui/player/danmaku_layout.dart';

import 'ui/player_interactions_test.dart' show MemoryPlayback;

Json comment(double time, double width, [String mode = 'scroll']) => {
  'timeSeconds': time,
  'text': '$width',
  'width': width,
  'mode': mode,
};

List<PlacedDanmaku> advance(
  DanmakuLayout layout,
  List<Json> comments,
  double time, {
  Size viewport = const Size(800, 400),
  double area = .6,
  double fontSize = 20,
}) => List.of(
  layout.update(
    comments: comments,
    time: time,
    viewport: viewport,
    fontSize: fontSize,
    area: area,
    measure: (item) => Size(number(item['width']), fontSize),
  ),
);

void main() {
  test('short comments reuse horizontal space before the leader exits', () {
    final comments = [comment(0, 80), comment(1, 80)];
    final placed = advance(DanmakuLayout(), comments, 2);
    expect(placed, hasLength(2));
    expect(placed[1].y, placed[0].y);
    final left = placed[0].boundsAt(2, 800);
    final right = placed[1].boundsAt(2, 800);
    expect(right.left - left.right, greaterThanOrEqualTo(20));
  });

  test('a long faster follower gets a different lane before catching up', () {
    final comments = [comment(0, 80), comment(1, 400)];
    final layout = DanmakuLayout();
    final placed = advance(layout, comments, 1);
    expect(placed, hasLength(2));
    expect(placed[1].y, greaterThan(placed[0].y));
    final lane = placed[1].y;
    for (var time = 1.0; time < 9; time += .1) {
      final visible = advance(layout, comments, time);
      expect(visible.last.y, lane);
      for (var i = 0; i < visible.length - 1; i++) {
        expect(
          visible[i]
              .boundsAt(time, 800)
              .overlaps(visible[i + 1].boundsAt(time, 800)),
          isFalse,
        );
      }
    }
  });

  test('a shorter follower can safely follow a long comment', () {
    final placed = advance(DanmakuLayout(), [
      comment(0, 400),
      comment(3, 80),
    ], 3);
    expect(placed, hasLength(2));
    expect(placed[0].y, placed[1].y);
  });

  test(
    'full lanes drop at admission, never pop in when space becomes free',
    () {
      final layout = DanmakuLayout();
      final comments = [comment(0, 80), comment(.1, 80), comment(8.2, 80)];
      List<PlacedDanmaku> frame(double time) =>
          advance(layout, comments, time, viewport: const Size(800, 120));
      expect(frame(.1), hasLength(1));
      expect(frame(2), hasLength(1));
      expect(frame(8), isEmpty);
      expect(frame(8.2).single.start, 8.2);
    },
  );

  test('fixed and scrolling comments share physical collision checks', () {
    for (final modes in [
      ['scroll', 'top'],
      ['top', 'scroll'],
      ['top', 'bottom'],
    ]) {
      final placed = advance(
        DanmakuLayout(),
        [comment(0, 100, modes[0]), comment(0, 100, modes[1])],
        1,
        viewport: const Size(800, 120),
        area: 1,
      );
      expect(placed, hasLength(1), reason: '$modes in one physical row');
    }
  });

  test(
    'seek, changed comments and geometry rebuild within the chosen area',
    () {
      final layout = DanmakuLayout();
      final comments = [
        for (var i = 0; i < 20; i++) comment(i.toDouble(), 100),
      ];
      advance(layout, comments, 19);
      expect(advance(layout, comments, 2).map((e) => e.start), [0, 1, 2]);
      expect(
        advance(layout, [comment(2, 120, 'top')], 2).single.item['mode'],
        'top',
      );
      final resized = advance(
        layout,
        comments,
        19,
        viewport: const Size(400, 220),
        fontSize: 30,
        area: .3,
      );
      expect(resized, isNotEmpty);
      for (final item in resized) {
        final bounds = item.boundsAt(19, 400);
        expect(bounds.top, greaterThanOrEqualTo(16));
        expect(bounds.bottom, lessThanOrEqualTo(16 + 220 * .3));
        expect(item.extent.height, 30);
      }
      layout.clear();
      expect(advance(layout, [], 19), isEmpty);
    },
  );

  testWidgets('the overlay paints measured short comments on the same row', (
    tester,
  ) async {
    final playback = MemoryPlayback()
      ..danmakuEnabled = true
      ..comments = [
        {'timeSeconds': 0, 'text': 'Hi', 'mode': 'scroll'},
        {'timeSeconds': 1, 'text': 'OK', 'mode': 'scroll'},
      ];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await playback.player.dispose();
      playback.dispose();
    });
    await playback.player.seek(const Duration(seconds: 2));
    await tester.pumpWidget(
      MaterialApp(home: DanmakuLayer(playback: playback)),
    );
    await tester.pump();
    final paint = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is DanmakuPainter,
    );
    Offset? first;
    expect(
      paint,
      paints
        ..paragraph(
          offset: predicate<Offset>((offset) {
            first = offset;
            return true;
          }),
        )
        ..paragraph(
          offset: predicate<Offset>(
            (offset) => offset.dy == first!.dy && offset.dx > first!.dx,
          ),
        ),
    );
  });
}
