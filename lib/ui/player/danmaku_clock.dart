/// Advances on display frames; native positions only synchronize the clock.
class DanmakuClock {
  Duration? _elapsed;
  double _position = 0;
  double _nativePosition = 0;
  double _correction = 0;
  double _rate = 1;
  bool _running = false;

  double sample({
    required Duration elapsed,
    required Duration position,
    required bool running,
    required double rate,
    bool reset = false,
  }) {
    final native = position.inMicroseconds / Duration.microsecondsPerSecond;
    final previous = _elapsed;
    if (previous == null || reset) {
      _position = native;
      _correction = 0;
    } else {
      final delta =
          (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond;
      if (_running && delta > 0) {
        final step = delta * _rate;
        // Slew small timestamp jitter instead of jumping backwards each update.
        final correction = _correction.clamp(-step * .1, step * .1);
        _position += step + correction;
        _correction -= correction;
      }
      if (native != _nativePosition) {
        final error = native - _position;
        if (error.abs() > .5 ||
            native < _nativePosition - .1 ||
            (!_running && !running)) {
          // Seeks and paused scrubbing must rebase, not animate through the gap.
          _position = native;
          _correction = 0;
        } else {
          _correction = error;
        }
      }
      if (_running != running || _rate != rate) _correction = 0;
    }
    _elapsed = elapsed;
    _nativePosition = native;
    _running = running;
    _rate = rate;
    return _position;
  }
}
