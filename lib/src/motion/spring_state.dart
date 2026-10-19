import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/physics.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/motion/spring.dart';

/// The visible rest of a motion: how close every part must stay to its
/// target before the motion stops ticking and snaps onto it.
///
/// A spring that rests at 0.01 pt keeps a ticker alive for up to a second
/// after its last visible step. These thresholds end it when what remains
/// cannot be seen. Fidelity: NEAR, invisible. A motion settles once every
/// part's remaining swing ([MorphSpringState.reach]) is below [length]
/// (0.3 device px at 3x, 0.26 px on a 2.625x Pixel 6a), a scale's swing
/// times its surface's extent below [length], and an opacity's below
/// [opacity] (half an 8-bit step); the snap moves no edge by more than
/// that.
@internal
abstract final class MorphRest {
  /// The remaining swing of a position or length, in logical pixels.
  static const double length = 0.1;

  /// The remaining swing of an opacity or color mix, 0 to 1.
  static const double opacity = 0.002;

  /// The remaining swing of a scale of a surface [extent] pixels long.
  static double scale(double extent) => length / math.max(extent, 1);

  /// The extent, in pixels, a motion assumes before its host has measured
  /// what it moves: about a phone screen's longer side.
  static const double screen = 1000;

  /// The farthest an edge moves between frames [from] and [to]: the
  /// center's travel plus half the change of width or height. A progress
  /// from one to the other rests visibly at [scale] of it.
  static double travel(Rect from, Rect to) =>
      (to.center - from.center).distance +
      math.max((to.width - from.width).abs(), (to.height - from.height).abs()) /
          2;
}

/// A damped spring: the SDK's [SpringSimulation] from its last retarget.
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
  bool _moved = false;
  SpringSimulation? _simulation;
  double _memoT = double.nan;
  double _memoY = 0;
  double _memoV = 0;

  /// The value the spring is heading to.
  double get target => _target;

  /// Sends the spring toward [target] from its state at time [t],
  /// switching to [spring] from then on when one is given.
  ///
  /// A change never reaches back before the previous one: a [t] earlier
  /// than the last retarget, [snap] or [setState] takes effect at that
  /// change's time instead: a pointer event handled before its frame's
  /// callback can be stamped before changes that frame already made.
  void retarget(double t, double target, {MorphSpring? spring}) {
    final at = _since(t);
    final (y, v) = _state(at);
    if (spring != null) _spring = spring;
    _changed();
    _origin = at;
    _y0 = y;
    _v0 = v;
    _target = target;
  }

  /// Puts the spring at rest on [value] at time [t].
  void snap(double t, double value) {
    _changed();
    _origin = _since(t);
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
    _changed();
    _origin = _since(t);
    _y0 = value;
    _v0 = velocity;
  }

  /// A bound on how far the spring still swings from its target at any
  /// time from [t] on, until the next change.
  ///
  /// An underdamped spring's offset stays inside its decaying envelope;
  /// a critically or overdamped one inside the sum of its modes' sizes.
  double reach(double t) {
    final (y, v) = _state(t);
    final a = y - _target;
    final k = _spring.stiffness;
    final c = _spring.damping;
    final w0 = math.sqrt(k);
    final zeta = c / (2 * w0);
    if (zeta < 1 - 1e-9) {
      final wd = w0 * math.sqrt(1 - zeta * zeta);
      final b = (v + zeta * w0 * a) / wd;
      return math.sqrt(a * a + b * b);
    }
    if (zeta <= 1 + 1e-9) return a.abs() + (v + w0 * a).abs() / (w0 * math.e);
    final s = w0 * math.sqrt(zeta * zeta - 1);
    final r1 = -zeta * w0 + s;
    final r2 = -zeta * w0 - s;
    final c2 = (v - r1 * a) / (r2 - r1);
    return (a - c2).abs() + c2.abs();
  }

  /// Whether the spring's remaining swing ([reach]) stays below
  /// [tolerance] from time [t] on.
  bool isWithin(double t, double tolerance) => reach(t) < tolerance;

  /// Puts the spring at rest on its target at time [t].
  void settle(double t) => snap(t, _target);

  double _since(double t) {
    if (_moved && t < _origin) return _origin;
    _moved = true;
    return t;
  }

  void _changed() {
    _memoT = double.nan;
    _simulation = null;
  }

  (double, double) _state(double t) {
    if (t == _memoT) return (_memoY, _memoV);
    final (y, v) = _evaluate(t);
    _memoT = t;
    _memoY = y;
    _memoV = v;
    return (y, v);
  }

  (double, double) _evaluate(double t) {
    final dt = t - _origin;
    if (dt <= 0) return (_y0, _v0);
    final simulation = _simulation ??= SpringSimulation(
      _spring.description,
      _y0,
      _target,
      _v0,
    );
    return (simulation.x(dt), simulation.dx(dt));
  }
}
