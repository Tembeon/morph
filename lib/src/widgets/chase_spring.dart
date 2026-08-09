import 'dart:math' as math;
import 'dart:ui';

/// A critically damped spring chasing a MOVING target, integrated step
/// by step by its owner's clock (a Ticker's elapsed deltas).
///
/// Why this exists instead of a controller: retargeting a simulation
/// per pointer event starves it - a high-frequency mouse restarts the
/// simulation before it ever ticks and the value freezes while the
/// pointer moves. The chase inverts the flow: events only move
/// [target], and the owner integrates exactly once per frame.
///
/// Critically damped by construction (damping = 2 * sqrt(stiffness)):
/// tight under a finger, no oscillation of its own - character belongs
/// to whatever plays after the chase hands off its [velocity].
class ChaseSpring {
  /// Creates a chase with the given [stiffness].
  ChaseSpring({this.stiffness = 900});

  /// Spring stiffness; higher chases tighter. The damping is derived
  /// as 2 * sqrt(stiffness), keeping the chase critically damped.
  final double stiffness;

  /// Where the spring is now. Seed it through [grab].
  Offset value = .zero;

  /// The spring's current velocity in px/s - hand it to whatever takes
  /// over on release, so a flick lands with its momentum.
  Offset velocity = .zero;

  Offset _target = .zero;
  bool _resting = false;

  /// The moving target; writing a NEW position wakes a resting chase.
  Offset get target => _target;
  set target(Offset next) {
    if (next != _target) {
      _target = next;
      _resting = false;
    }
  }

  /// Seeds the chase at [at] (target included), carrying [velocity]
  /// in - grabbing a surface mid-return stays continuous.
  void grab(Offset at, {Offset velocity = Offset.zero}) {
    value = at;
    this.velocity = velocity;
    _target = at;
    _resting = false;
  }

  /// Advances by [dt] seconds. Returns whether [value] changed - false
  /// once the chase has come to rest (after snapping exactly onto the
  /// target once), so the owner can skip downstream work instead of
  /// re-rendering epsilon motion every frame under a motionless
  /// finger.
  ///
  /// The frame is integrated in slices: semi-implicit Euler at this
  /// stiffness is stable only for steps under ~sqrt(stiffness)/0.83
  /// seconds, and a 30 fps frame is already past that - one whole-frame
  /// step would make the chase diverge with growing oscillation
  /// instead of converging.
  bool tick(double dt) {
    if (_resting || dt <= 0) {
      return false;
    }
    final double maxStep = 0.25 / math.sqrt(stiffness);
    final double damping = 2 * math.sqrt(stiffness);
    double remaining = dt;
    while (remaining > 0) {
      final Offset delta = _target - value;
      if (delta.distanceSquared < 0.01 && velocity.distanceSquared < 0.25) {
        value = _target;
        velocity = .zero;
        _resting = true;
        return true;
      }
      final double h = remaining < maxStep ? remaining : maxStep;
      velocity += (delta * stiffness - velocity * damping) * h;
      value += velocity * h;
      remaining -= h;
    }
    return true;
  }
}
