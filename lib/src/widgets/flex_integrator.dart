import 'package:meta/meta.dart';

/// UIKit's deformation filter: three one-pole low-passes in a row over a
/// moving surface's position, its velocity and the rate of change of its
/// speed.
///
/// UIKit runs the filter once per rendered frame with a fixed weight of
/// [alpha], whatever the frame interval, so its response is a function of
/// frames rather than of time. Step it from a [MorphSubClock] to
/// reproduce that on any host and under any time dilation.
@internal
class MorphFlexIntegrator {
  /// The weight of each new sample in all three filters.
  static const double alpha = 0.3;

  /// The filtered position, or null until the filter is primed by
  /// [reset] or by its first [step].
  double? pf;

  /// The filtered velocity.
  double vf = 0;

  /// The filtered rate of change of the speed `|v|`.
  double af = 0;

  /// Primes the filter at rest on [position].
  void reset(double position) {
    pf = position;
    vf = 0;
    af = 0;
  }

  /// Feeds the visible position of the previous frame, [dt] seconds per
  /// frame, and returns the new filtered acceleration [af].
  ///
  /// An unprimed filter starts at rest on [previousVisiblePosition].
  double step(double previousVisiblePosition, double dt) {
    final p = pf ?? previousVisiblePosition;
    final np = (1 - alpha) * p + alpha * previousVisiblePosition;
    final nv = (1 - alpha) * vf + alpha * (np - p) / dt;
    final na = (1 - alpha) * af + alpha * (nv.abs() - vf.abs()) / dt;
    pf = np;
    vf = nv;
    af = na;
    return na;
  }
}

/// A fixed-rate frame clock inside a motion's own time.
///
/// UIKit's per-frame filters must see the same frames whatever the host
/// renders: a 60 Hz host, a 120 Hz one, a slowed-down ticker or a test
/// that advances in coarse steps. The sub-clock splits motion time into
/// frames of `1 / frameRate` seconds, numbered from zero, and reports
/// every frame boundary a motion crosses as it advances.
@internal
class MorphSubClock {
  /// Creates a sub-clock ticking [frameRate] times per second of motion
  /// time.
  MorphSubClock(this.frameRate) : assert(frameRate > 0);

  /// The frames per second of motion time.
  final double frameRate;

  /// The length of one frame, in seconds.
  double get frame => 1 / frameRate;

  /// The most frames one advance steps through; earlier frames of a
  /// longer gap are skipped, since a motion only sleeps once it settled.
  static const int maxFrames = 600;

  int? _last;

  /// Starts counting from time [t]; frames at or before [t] are not
  /// reported.
  void start(double t) {
    _last = _index(t);
  }

  /// Calls [onFrame] with the time of every frame boundary after the
  /// previous call and up to [t], in order.
  void run(double t, void Function(double t) onFrame) {
    final last = _last;
    if (last == null) {
      start(t);
      return;
    }
    final end = _index(t);
    if (end <= last) return;
    _last = end;
    var k = last + 1;
    if (end - k >= maxFrames) k = end - maxFrames + 1;
    for (; k <= end; k++) {
      onFrame(k / frameRate);
    }
  }

  int _index(double t) => (t * frameRate + 1e-6).floor();
}
