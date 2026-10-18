import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/clock.dart';

/// The scheduling decision after one explicit-time motion sample.
typedef ProbeFrameOutcome = ({bool settled, double? wakeTime});

const _maxEventAge = 0.25;
const _maxFrameLead = 0.05;

/// A prototype extraction of the measured clock, usable by State or route.
class ProbeMotionClock {
  /// Creates a clock with injectable platform timestamp sources.
  ProbeMotionClock({
    required TickerProvider vsync,
    required this.onFrame,
    required this.now,
    required this.pointerOffset,
    this.frameRate = 60,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  /// Samples the motion before listeners read it.
  final ProbeFrameOutcome Function(double time) onFrame;

  /// The platform frame clock at the current instant.
  final Duration Function() now;

  /// The frame-clock offset of platform pointer timestamps, if known.
  final Duration? Function() pointerOffset;
  late final Ticker _ticker;
  final _frames = ValueNotifier<int>(0);
  final _grid = MorphFrameGrid();
  double _base = 0;
  double _time = 0;
  double _tickTime = 0;
  bool _ticking = false;
  bool _disposed = false;
  bool _publishing = false;
  bool _stampsAgree = false;
  Duration? _tickStamp;
  Duration? _stampFrom;
  double _stampTime = 0;
  Duration? _wakeFrom;
  double _wakeTime = 0;
  Timer? _doze;
  Duration? _dozeStamp;
  Duration? _dozeRawStamp;
  double _dozeTime = 0;
  Duration? _resumeStamp;
  double _resumeTime = 0;

  /// The display rate used for fallback stamps and wake scheduling.
  double frameRate;

  /// The most recently sampled motion time.
  double get time => _time;

  /// The motion time of the frame being produced, also before this clock's
  /// own tick in it, or [time] outside a running frame.
  ///
  /// Input delivered from another ticker, such as a scroll notification of
  /// a fling, reads this so its stamp does not depend on the tickers' order.
  /// It differs from the next tick's time by at most the grid's snap.
  double get frameTime {
    final scheduler = SchedulerBinding.instance;
    final tick = _tickStamp;
    if (!_ticking ||
        tick == null ||
        scheduler.schedulerPhase != SchedulerPhase.transientCallbacks) {
      return _time;
    }
    final since = scheduler.currentSystemFrameTimeStamp - tick;
    return _tickTime + since.inMicroseconds / 1e6 / timeDilation;
  }

  /// The learned period of the display grid, in motion seconds.
  double? get framePeriod => _grid.period;

  /// Notifies after the motion has advanced and the scheduling decision is read.
  Listenable get frames => _frames;

  Duration _occurred(PointerEvent event, Duration now) {
    final offset = pointerOffset();
    if (offset != null) {
      final at = event.timeStamp + offset;
      final age = (now - at).inMicroseconds / 1e6;
      if (age >= 0 && age < _maxEventAge) return at;
    }
    return now + Duration(microseconds: (1e6 / frameRate).round());
  }

  /// Maps the event's own timestamp and ensures a future motion frame.
  double stamp(PointerEvent event) {
    final now = this.now();
    wake();
    if (_ticking) {
      final tick = _tickStamp;
      if (!_stampsAgree || tick == null) return _time;
      final since = (_occurred(event, now) - tick).inMicroseconds / 1e6;
      if (since < -_maxEventAge) return _time;
      return _tickTime + since / timeDilation;
    }
    _wakeFrom = _occurred(event, now);
    final from = _stampFrom;
    if (from == null) {
      _stampFrom = event.timeStamp;
      _stampTime = _time;
      _wakeTime = _time;
      return _time;
    }
    final elapsed = (event.timeStamp - from).inMicroseconds / 1e6;
    if (elapsed > 0) {
      final candidate = _stampTime + elapsed / timeDilation;
      if (candidate > _time) _time = candidate;
    }
    _wakeTime = _time;
    return _time;
  }

  void _tick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    final scheduler = SchedulerBinding.instance;
    final stamp = scheduler.currentSystemFrameTimeStamp;
    _stampsAgree = ((stamp - now()).inMicroseconds / 1e6).abs() < _maxFrameLead;
    _tickStamp = stamp;
    if (_resumeStamp case final from?) {
      _resumeStamp = null;
      final lag = (stamp - from).inMicroseconds / 1e6;
      if (lag > 0) {
        final resumed = _resumeTime + lag / timeDilation;
        if (_base + seconds < resumed) _base = resumed - seconds;
      }
    }
    if (_wakeFrom case final from?) {
      _wakeFrom = null;
      final lag = (stamp - from).inMicroseconds / 1e6;
      if (_stampsAgree && lag > 0 && lag < 1) {
        final woken = _wakeTime + lag / timeDilation;
        if (_base + seconds < woken) _base = woken - seconds;
      }
    }
    if (_dozeStamp case final dozed?) {
      final now = scheduler.currentFrameTimeStamp;
      final micros = (_dozeTime * 1e6).round() + (now - dozed).inMicroseconds;
      _base = micros / 1e6 - seconds;
      _dozeStamp = null;
      _dozeRawStamp = null;
    }
    if (_base + seconds < _time) _base = _time - seconds;
    _tickTime = _base + seconds;
    final snapped = _grid.snap(_tickTime);
    _time = snapped >= _time ? snapped : _tickTime;
    _ticking = true;
    _stampFrom = null;
    final outcome = onFrame(_time);
    if (_disposed) return;
    _publishing = true;
    try {
      _frames.value++;
    } finally {
      _publishing = false;
      if (_disposed) _frames.dispose();
    }
    if (_disposed) return;
    if (outcome.settled) {
      _base = _time;
      _ticking = false;
      _ticker.stop();
      return;
    }
    final until = outcome.wakeTime;
    if (until != null && until - _time > 2 / frameRate) {
      _dozeStamp = scheduler.currentFrameTimeStamp;
      _dozeRawStamp = stamp;
      _dozeTime = _time;
      _ticker.stop();
      _doze = Timer(
        Duration(
          microseconds: ((until - _time - 0.5 / frameRate) * timeDilation * 1e6)
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

  /// Resumes frames, cancelling any timer for a delayed change.
  void wake() {
    _doze?.cancel();
    _doze = null;
    if (!_ticker.isActive) _ticker.start();
  }

  /// Stops sampling when this clock relinquishes its model to another owner.
  void pause() {
    _doze?.cancel();
    _doze = null;
    _dozeStamp = null;
    _dozeRawStamp = null;
    _resumeStamp = null;
    _wakeFrom = null;
    _stampFrom = null;
    _base = _time;
    _ticking = false;
    _ticker.stop();
  }

  /// Resumes transferred motion from an absolute engine-clock timestamp.
  ///
  /// The first callback includes time since the transfer, even when
  /// starting a ticker outside a frame would otherwise sample elapsed zero.
  /// The returned local anchor includes elapsed doze time and is used when
  /// mapping the captured model onto this clock.
  /// Use the system frame timestamp during a frame, or [now] for input delivery.
  /// The dilation factor must stay unchanged during the transfer.
  double resumeAt(Duration absoluteStamp) {
    _resumeStamp = absoluteStamp;
    _resumeTime = _time;
    if (_dozeRawStamp case final dozed?) {
      _resumeTime =
          _dozeTime +
          (absoluteStamp - dozed).inMicroseconds / 1e6 / timeDilation;
    }
    wake();
    return _resumeTime;
  }

  /// Releases the ticker, delayed wake and frame listeners.
  void dispose() {
    _disposed = true;
    _doze?.cancel();
    _ticker.dispose();
    if (!_publishing) _frames.dispose();
  }
}
