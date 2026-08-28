import 'dart:ui';

/// Squash and stretch derived from how a body ACCELERATES, not from
/// whatever happens to be moving it.
///
/// Feed it the mover's position once per frame - a selection blob's
/// center, a dock pill mid-glide, anything that travels - and read back
/// a signed scale deviation applied oppositely on the two axes
/// ([scaleX] `= 1 + deviation`, [scaleY] `= 1 - deviation`), so area
/// stays roughly constant. Gaining speed stretches, braking squashes,
/// constant speed leaves the body undeformed: force is what deforms it,
/// not motion. Because only positions are sampled, the deformation
/// composes with ANY driver - a spring, a drag, a fling - and the
/// driver never learns about it; a glide's launch stretches and its
/// arrival squashes with no extra choreography.
///
/// The two axes combine into ONE deformation axis: rightward and upward
/// acceleration read the same (positive deviation), leftward and
/// downward the opposite. A horizontal mover passes `Offset(x, 0)` and
/// gets the collapsed one-axis behaviour.
///
/// This class is physics only: the caller owns the ticker, calls
/// [track] once per frame with its monotonic clock, and [reset] when
/// the effect goes live again after a pause - stale history must not
/// deform a fresh start. A body that stops moving unsquashes on its
/// own: the relaxation is the tail of the same measurement inside
/// [window], eased by [responseTime], not a separate animation.
///
/// Writing [scaleX]/[scaleY] into a `MorphPieceChannel` is the
/// intended consumption: the mass deforms, the skin re-traces only the
/// moving cluster, and content rides the same transform.
class MorphSquash {
  /// Creates a tracker; the defaults are calibrated for UI points at
  /// display frame rates and a selection-pill scale of motion.
  MorphSquash({
    this.window = 0.3,
    this.sensitivity = 0.00007,
    this.maxDeviation = 0.3,
    this.responseTime = 0.18,
  });

  /// Seconds of position history averaged into one acceleration -
  /// bigger reads calmer, smaller twitchier.
  final double window;

  /// Gain from acceleration (px/s^2) to scale deviation.
  final double sensitivity;

  /// Hard cap on the absolute deviation, for visual stability.
  final double maxDeviation;

  /// Seconds for the deviation to ease toward the acceleration's
  /// answer instead of snapping to it every frame; 0 restores the
  /// frame-locked response.
  final double responseTime;

  final List<(Offset, double)> _history = <(Offset, double)>[];
  double _deviation = 0;

  /// The current eased scale deviation, signed; 0 at rest.
  double get deviation => _deviation;

  /// The horizontal scale to write into a channel.
  double get scaleX => 1 + _deviation;

  /// The vertical scale to write into a channel.
  double get scaleY => 1 - _deviation;

  /// Whether the tracker has relaxed back to no deformation.
  bool get isSettled =>
      _deviation.abs() < 0.0005 &&
      (_history.length < 3 || _acceleration() == 0);

  /// Samples one frame and returns the new [deviation]. [now] is the
  /// caller's monotonic clock in seconds; [dt] the seconds since the
  /// previous frame.
  double track(Offset position, {required double now, required double dt}) {
    _history.add((position, now));
    final double cutoff = now - window;
    _history.removeWhere(((Offset, double) sample) => sample.$2 < cutoff);

    final double raw = (_acceleration() * sensitivity).clamp(
      -maxDeviation,
      maxDeviation,
    );
    final double ease = responseTime <= 0
        ? 1.0
        : (dt / responseTime).clamp(0.0, 1.0);
    _deviation += (raw - _deviation) * ease;
    return _deviation;
  }

  /// Drops the history and the deformation, so a later start does not
  /// deform from stale motion.
  void reset() {
    _history.clear();
    _deviation = 0;
  }

  double _acceleration() {
    if (_history.length < 3) {
      return 0;
    }

    final List<(Offset, double)> velocities = <(Offset, double)>[];
    for (int i = 1; i < _history.length; i++) {
      final (Offset p0, double t0) = _history[i - 1];
      final (Offset p1, double t1) = _history[i];
      final double dt = t1 - t0;
      if (dt <= 0) {
        continue;
      }
      velocities.add(((p1 - p0) / dt, (t0 + t1) / 2));
    }
    if (velocities.length < 2) {
      return 0;
    }

    double ax = 0;
    double ay = 0;
    int samples = 0;
    for (int i = 1; i < velocities.length; i++) {
      final (Offset v0, double t0) = velocities[i - 1];
      final (Offset v1, double t1) = velocities[i];
      final double dt = t1 - t0;
      if (dt <= 0) {
        continue;
      }
      ax += (v1.dx - v0.dx) / dt;
      ay += (v1.dy - v0.dy) / dt;
      samples++;
    }
    if (samples == 0) {
      return 0;
    }

    // Y grows downward on screen, so SUBTRACTING it makes upward
    // acceleration read the same as rightward: one deformation axis
    // for any direction of travel.
    return ax / samples - ay / samples;
  }
}
