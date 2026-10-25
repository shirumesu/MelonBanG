/// Advances on display frames; native positions only synchronize the clock.
class DanmakuClock {
  final _frames = _FrameTimeSmoother();
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
      final delta = _frames.smooth(
        (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond,
      );
      if (_running && delta > 0) {
        final step = delta * _rate;
        // mpv reports frame timestamps, which jitter by up to a frame; drift
        // is slewed within 2% so that jitter never reads as a speed change.
        final correction = _correction.clamp(-step * .02, step * .02);
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

/// Turns frame timestamp intervals into the display's even cadence, as
/// Animeko's FrameTimeSmoother does. Flutter on Windows stamps frames on a
/// timer grid that is not locked to the display, so raw intervals jitter
/// (0, 2, 1 periods…) while the screen refreshes evenly: a simple phase-locked
/// loop advances one estimated period per frame and feeds the accumulated
/// difference back slowly, so real drops are made up over a few frames.
class _FrameTimeSmoother {
  double _period = 0;
  double _error = 0;

  /// Seconds to advance for a [raw] frame interval in seconds.
  double smooth(double raw) {
    if (raw < 0) return 0;
    // Resumes, occluded windows and long stalls are real time: pass through.
    if (raw >= .25) {
      _error = 0;
      return raw;
    }
    if (_period == 0) {
      if (raw == 0) return 0;
      _period = raw.clamp(.002, .05);
      return raw;
    }
    // Clamped around the estimate so single outliers cannot skew it.
    final sample = raw.clamp(_period / 2, _period * 2).clamp(.002, .05);
    _period += (sample - _period) / 32;
    _error += raw - _period;
    final correction = (_error * .1).clamp(-_period * .2, _period * .2);
    _error -= correction;
    return _period + correction;
  }
}
