import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/ui/player/danmaku.dart';
import 'package:melonbang/ui/player/danmaku_clock.dart';

import 'ui/player_interactions_test.dart' show MemoryPlayback;

void main() {
  test('sparse and jittery samples preserve motion at 60 and 120 Hz', () {
    for (final hz in [60, 120]) {
      final clock = DanmakuClock();
      var position = Duration.zero;
      var previous = 0.0;
      for (var frame = 0; frame <= hz * 10; frame++) {
        // A native update every 200 ms, with alternating 20 ms latency.
        if (frame % (hz ~/ 5) == 0) {
          position = Duration(
            microseconds:
                (frame / hz * 1000000).round() -
                ((frame ~/ (hz ~/ 5)).isEven ? 0 : 20000),
          );
        }
        final now = clock.sample(
          elapsed: Duration(microseconds: (frame / hz * 1000000).round()),
          position: position,
          running: true,
          rate: 1,
        );
        if (frame > 0) {
          expect(now - previous, inInclusiveRange(.89 / hz, 1.11 / hz));
        }
        expect((now - frame / hz).abs(), lessThan(.05));
        previous = now;
      }
    }
  });

  test(
    'pause, buffering, rate, seeks and session changes rebase correctly',
    () {
      final clock = DanmakuClock();
      double sample(
        int milliseconds,
        int native, {
        bool running = true,
        double rate = 1,
        bool reset = false,
      }) => clock.sample(
        elapsed: Duration(milliseconds: milliseconds),
        position: Duration(milliseconds: native),
        running: running,
        rate: rate,
        reset: reset,
      );
      expect(sample(0, 1000), 1);
      expect(sample(100, 1000), closeTo(1.1, .00001));
      expect(sample(100, 1000, running: false), closeTo(1.1, .00001));
      expect(sample(2100, 1000, running: false), closeTo(1.1, .00001));
      expect(sample(2100, 1000, rate: 2), closeTo(1.1, .00001));
      expect(sample(2200, 1000, rate: 2), closeTo(1.3, .00001));
      expect(sample(2200, 1000, rate: .5), closeTo(1.3, .00001));
      expect(sample(2300, 1000, rate: .5), closeTo(1.35, .00001));
      expect(sample(2300, 30000), 30);
      expect(sample(2400, 5000), 5);
      expect(sample(2400, 5000, running: false), 5);
      expect(sample(2500, 5100, running: false), 5.1);
      expect(sample(2600, 0, reset: true), 0);
    },
  );

  test('text layouts survive frames and expired styles are disposed', () {
    final cache = DanmakuTextCache();
    cache.beginFrame();
    final first = cache.obtain('Same comment', Colors.white, 23);
    final originalWidth = first.width;
    cache.endFrame();
    cache.beginFrame();
    expect(cache.obtain('Same comment', Colors.white, 23), same(first));
    cache.endFrame();
    cache.beginFrame();
    final resized = cache.obtain('Same comment', Colors.white, 30);
    cache.endFrame();
    expect(resized.width, greaterThan(originalWidth));
    expect(first.debugDisposed, isTrue);
    cache.clear();
    expect(resized.debugDisposed, isTrue);
  });

  testWidgets('scroll moves on every display frame between native samples', (
    tester,
  ) async {
    final playback = MemoryPlayback()
      ..danmakuEnabled = true
      ..comments = [
        {'timeSeconds': 0, 'text': 'Smooth scrolling', 'mode': 'scroll'},
      ];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await playback.player.dispose();
      playback.dispose();
    });
    await playback.player.seek(const Duration(seconds: 2));
    await playback.player.play();
    await tester.pumpWidget(
      MaterialApp(home: DanmakuLayer(playback: playback)),
    );
    await tester.pump();
    final paint = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is DanmakuPainter,
    );
    double paintedX() {
      double? x;
      expect(
        paint,
        paints..paragraph(
          offset: predicate<Offset>((offset) {
            x = offset.dx;
            return true;
          }),
        ),
      );
      return x!;
    }

    var previous = paintedX();
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(microseconds: 16667));
      final x = paintedX();
      expect(x, lessThan(previous), reason: 'Display frame $frame');
      expect(previous - x, lessThan(3));
      previous = x;
    }
    await playback.player.pause();
    await tester.pump();
    final paused = paintedX();
    await tester.pump(const Duration(seconds: 1));
    expect(paintedX(), paused);

    final native = playback.player.platform!;
    native.state = native.state.copyWith(buffering: true, playing: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(paintedX(), paused);
    native.state = native.state.copyWith(buffering: false, rate: 2);
    await tester.pump();
    await tester.pump(const Duration(microseconds: 8333));
    final fast = paintedX();
    expect(paused - fast, inInclusiveRange(2, 3));
    native.state = native.state.copyWith(completed: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(paintedX(), fast);

    playback.session = {'id': 'new-session'};
    native.state = native.state.copyWith(
      position: const Duration(seconds: 1),
      completed: false,
      playing: false,
    );
    await tester.pump(const Duration(microseconds: 8333));
    expect(paintedX(), greaterThan(fast));
  });
}
