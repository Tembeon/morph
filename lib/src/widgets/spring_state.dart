import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:morph/src/spring.dart';

/// A damped spring evaluated in closed form from its last retarget.
///
/// Time is an explicit argument everywhere, so a motion built from these
/// is a pure function of its inputs and replays exactly in tests.
@internal
class MorphSpringState {
  /// Creates a spring resting at [value].
  MorphSpringState(MorphSpring spring, double value)
    : _spring = spring,
      _origin = 0,
      _y0 = value,
      _target = value;

  /// The spring's tuning; switch it through [retarget] so the switch
  /// happens at a known time.
  MorphSpring get spring => _spring;
  MorphSpring _spring;
  double _origin;
  double _y0;
  double _v0 = 0;
  double _target;

  /// The value the spring is heading to.
  double get target => _target;

  /// Sends the spring toward [target] from its state at time [t],
  /// switching to [spring] from then on when one is given.
  void retarget(double t, double target, {MorphSpring? spring}) {
    final (y, v) = _state(t);
    if (spring != null) _spring = spring;
    _origin = t;
    _y0 = y;
    _v0 = v;
    _target = target;
  }

  /// Puts the spring at rest on [value] at time [t].
  void snap(double t, double value) {
    _origin = t;
    _y0 = value;
    _v0 = 0;
    _target = value;
  }

  /// The spring's value at time [t].
  double value(double t) => _state(t).$1;

  /// The spring's velocity at time [t].
  double velocity(double t) => _state(t).$2;

  /// Sets the spring's value and velocity at time [t] without moving the
  /// target.
  void setState(double t, double value, double velocity) {
    _origin = t;
    _y0 = value;
    _v0 = velocity;
  }

  /// Whether the spring is within [tolerance] of its target and nearly
  /// still at time [t].
  bool isAtRest(double t, [double tolerance = 0.01]) {
    final (y, v) = _state(t);
    return (y - _target).abs() < tolerance && v.abs() < tolerance * 10;
  }

  (double, double) _state(double t) {
    final dt = t - _origin;
    if (dt <= 0) return (_y0, _v0);
    final k = _spring.stiffness;
    final c = _spring.damping;
    final w0 = math.sqrt(k);
    final zeta = c / (2 * w0);
    final a = _y0 - _target;
    if (zeta < 1 - 1e-9) {
      final wd = w0 * math.sqrt(1 - zeta * zeta);
      final b = (_v0 + zeta * w0 * a) / wd;
      final e = math.exp(-zeta * w0 * dt);
      final cos = math.cos(wd * dt);
      final sin = math.sin(wd * dt);
      final y = _target + e * (a * cos + b * sin);
      final dy =
          e * (-zeta * w0 * (a * cos + b * sin) + wd * (-a * sin + b * cos));
      return (y, dy);
    }
    if (zeta <= 1 + 1e-9) {
      final cc = _v0 + w0 * a;
      final e = math.exp(-w0 * dt);
      return (_target + (a + cc * dt) * e, (cc - w0 * (a + cc * dt)) * e);
    }
    final s = w0 * math.sqrt(zeta * zeta - 1);
    final r1 = -zeta * w0 + s;
    final r2 = -zeta * w0 - s;
    final c2 = (_v0 - r1 * a) / (r2 - r1);
    final c1 = a - c2;
    final e1 = math.exp(r1 * dt);
    final e2 = math.exp(r2 * dt);
    return (_target + c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2);
  }
}
