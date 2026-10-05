import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Receives every pointer stamp: the event and the motion time it got.
///
/// Measurement tooling sets it to log how touches land on the motion
/// clock; it is null otherwise.
@internal
void Function(PointerEvent event, double time)? morphClockStampObserver;

/// The current time on the clock the engine stamps frames with
/// ([SchedulerBinding.currentSystemFrameTimeStamp]).
///
/// The Dart timeline clock is that clock on iOS (CLOCK_MONOTONIC_RAW,
/// measured on an iPhone 16 Pro, iOS 27.0.1, Flutter 3.47.2); pointer time
/// stamps are not (UITouch.timestamp, CLOCK_UPTIME_RAW, which stops while
/// the device sleeps). Tests replace it to drive [MorphClock] with frames
/// on a fake clock.
@internal
Duration Function() morphClockNow = _timelineNow;

Duration _timelineNow() => Duration(microseconds: Timeline.now);

/// Drives a pure measured motion from a ticker.
///
/// The clock is the ticker's elapsed time accumulated across restarts, so
/// the motion sees one continuous timeline while the ticker sleeps
/// between gestures; time spent asleep does not count. The ticker stops
/// as soon as the motion settles.
///
/// Pointer events are stamped with [stamp] one display frame after their
/// delivery, read on [morphClockNow]: UIKit sets an animation started
/// from an event handler to begin a frame after the call, and a frame's
/// time stamp is the time it is shown at (on iOS the display link's
/// target). While the ticker runs, or dozes, the stamp is the latest
/// frame's clock plus the time from that frame's time stamp to one frame
/// after the delivery. Events that arrive while it sleeps keep their
/// spacing, measured by their own time stamps and slowed by
/// [timeDilation], and the first frame after the wake continues from the
/// latest of them by the time from one frame after its delivery to that
/// frame's time stamp, so the clock never runs backwards. When the frame
/// time stamps and [morphClockNow] disagree by more than [maxFrameLead] (a
/// test's fake frame clock), an event gets the latest frame's clock while
/// the ticker runs, and the first frame after a wake continues from the
/// latest stamp itself.
///
/// A motion that shows nothing new until a later time names it in
/// [motionWakeTime]; the ticker then dozes until that time instead of
/// producing frames that draw the same picture. Unlike a settled sleep, a
/// doze counts: the frame that ends it reads the clock from the frame
/// time stamps, exactly as an uninterrupted ticker would, and the doze ends
/// half a frame early so the frame that shows the change is never missed.
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
  Timer? _doze;
  Duration? _dozeStamp;
  double _dozeClock = 0;
  Duration? _tickStamp;
  bool _stampsAgree = false;
  Duration? _wakeFrom;
  double _wakeClock = 0;

  /// The largest distance, in seconds, between a frame's time stamp and
  /// [morphClockNow] at its callback for which the two count as one clock.
  static const double maxFrameLead = 0.05;

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

  /// The motion time before which the motion draws nothing new, or null
  /// when it changes every frame.
  double? get motionWakeTime => null;

  /// The motion time of [event], waking the ticker.
  double stamp(PointerEvent event) {
    final time = _stamp(event);
    morphClockStampObserver?.call(event, time);
    return time;
  }

  double _stamp(PointerEvent event) {
    final now = morphClockNow();
    wake();
    if (_ticking) {
      final tick = _tickStamp;
      if (!_stampsAgree || tick == null) return _clock;
      final since = (now - tick).inMicroseconds / 1e6 + 1 / _frameRate;
      if (since < -maxFrameLead) return _clock;
      return _clock + since / timeDilation;
    }
    _wakeFrom = now;
    final from = _stampFrom;
    if (from == null) {
      _stampFrom = event.timeStamp;
      _stampClock = _clock;
      _wakeClock = _clock;
      return _clock;
    }
    final elapsed = (event.timeStamp - from).inMicroseconds / 1e6;
    if (elapsed > 0) {
      final t = _stampClock + elapsed / timeDilation;
      if (t > _clock) _clock = t;
    }
    _wakeClock = _clock;
    return _clock;
  }

  void _onTick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    final stamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    _stampsAgree =
        ((stamp - morphClockNow()).inMicroseconds / 1e6).abs() < maxFrameLead;
    _tickStamp = stamp;
    if (_wakeFrom case final from?) {
      _wakeFrom = null;
      final lag = (stamp - from).inMicroseconds / 1e6 - 1 / _frameRate;
      if (_stampsAgree && lag > 0 && lag < 1) {
        final woken = _wakeClock + lag / timeDilation;
        if (_base + seconds < woken) _base = woken - seconds;
      }
    }
    if (_dozeStamp case final dozed?) {
      final now = SchedulerBinding.instance.currentFrameTimeStamp;
      final micros = (_dozeClock * 1e6).round() + (now - dozed).inMicroseconds;
      _base = micros / 1e6 - seconds;
      _dozeStamp = null;
    }
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
      return;
    }
    final until = motionWakeTime;
    if (until != null && until - _clock > 2 / _frameRate) {
      _dozeStamp = SchedulerBinding.instance.currentFrameTimeStamp;
      _dozeClock = _clock;
      _ticker.stop();
      _doze = Timer(
        Duration(
          microseconds:
              ((until - _clock - 0.5 / _frameRate) * timeDilation * 1e6)
                  .floor(),
        ),
        _endDoze,
      );
    }
  }

  void _endDoze() {
    _doze = null;
    if (!_ticker.isActive) _ticker.start();
  }

  /// Makes sure the ticker runs so a pending motion gets frames.
  void wake() {
    _doze?.cancel();
    _doze = null;
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
    _doze?.cancel();
    _ticker.dispose();
    _frames.dispose();
    super.dispose();
  }
}
