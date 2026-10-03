import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Drives a pure measured motion from a ticker.
///
/// The clock is the ticker's elapsed time accumulated across restarts, so
/// the motion sees one continuous timeline while the ticker sleeps
/// between gestures; time spent asleep does not count. The ticker stops
/// as soon as the motion settles.
///
/// Pointer events are stamped with [stamp]: while the ticker runs, with
/// the clock of the latest frame, which is the granularity UIKit reacts
/// at as well. Events that arrive while it sleeps or before the first
/// frame after it wakes keep their spacing, measured by their own
/// timestamps and slowed by [timeDilation], and that frame continues
/// from the latest stamp, so the clock never runs backwards.
@internal
mixin MorphClock<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final Ticker _ticker = createTicker(_onTick);
  double _base = 0;
  double _clock = 0;
  bool _ticking = false;
  Duration? _stampFrom;
  double _stampClock = 0;
  double _frameRate = 120;
  final ValueNotifier<int> _frames = ValueNotifier<int>(0);

  /// Notifies on every frame of the motion; use it as a painter's repaint.
  Listenable get frames => _frames;

  /// The current time on the motion's clock, in seconds.
  double get clock => _clock;

  /// The frame rate measured motions created by this state filter at: 60
  /// when the display refreshes at 60 Hz, 120 otherwise.
  double get motionFrameRate => _frameRate;

  /// Advances the motion to [t].
  void advanceMotion(double t);

  /// Whether the motion has nothing left to animate.
  bool get motionSettled;

  /// The motion time of [event], waking the ticker.
  double stamp(PointerEvent event) {
    wake();
    if (_ticking) return _clock;
    final from = _stampFrom;
    if (from == null) {
      _stampFrom = event.timeStamp;
      _stampClock = _clock;
      return _clock;
    }
    final elapsed = (event.timeStamp - from).inMicroseconds / 1e6;
    if (elapsed > 0) {
      final t = _stampClock + elapsed / timeDilation;
      if (t > _clock) _clock = t;
    }
    return _clock;
  }

  void _onTick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    if (_base + seconds < _clock) _base = _clock - seconds;
    _clock = _base + seconds;
    _ticking = true;
    _stampFrom = null;
    advanceMotion(_clock);
    _frames.value++;
    if (motionSettled) {
      _base = _clock;
      _ticking = false;
      _ticker.stop();
    }
  }

  /// Makes sure the ticker runs so a pending motion gets frames.
  void wake() {
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rate = View.maybeOf(context)?.display.refreshRate;
    _frameRate = rate != null && rate.round() == 60 ? 60 : 120;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frames.dispose();
    super.dispose();
  }
}
