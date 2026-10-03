import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:morph/src/gesture.dart';
import 'package:morph/src/widgets/small_lens.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// The motion of an iOS 27 switch: knob, track color and knob lens.
///
/// A touch lifts the knob lens. A tap toggles on release: the knob
/// travels on a critically damped spring while the lens may still be
/// lifted, and the track color fades on its own spring, slower toward on
/// than toward off. A drag moves the knob with the finger, with a rubber
/// band past each end; a drag that starts moving within [deadZoneWindow]
/// of the touch first crosses a [deadZone]. The drag commits to the other
/// state when the knob's target reaches the far end and uncommits only
/// when it returns to the starting end; the track color follows each
/// commit after [colorDelay]. The release keeps the committed state if
/// the drag ever committed and toggles like a tap otherwise.
///
/// Times are seconds and positions pixels along the track.
class MorphSwitchMotion {
  /// Creates a switch resting at [value] whose knob lens filters its
  /// motion at [frameRate] frames per second of motion time.
  MorphSwitchMotion({required bool value, this.frameRate = 120})
    : _value = value,
      _knob = MorphSpringState(knobSpring, value ? travel : 0),
      _color = MorphSpringState(onColorSpring, value ? 1 : 0),
      lens = MorphSmallLens(
        restSize: knobSize,
        liftedSize: liftedKnobSize,
        frameRate: frameRate,
      );

  /// The frames per second of motion time the knob lens filters at: 120
  /// for a ProMotion display, 60 for a 60 Hz one.
  final double frameRate;

  /// How far the knob travels between off and on.
  static const double travel = 22;

  /// The size of the resting knob.
  static const Size knobSize = Size(37, 24);

  /// The size of the lifted knob.
  static const Size liftedKnobSize = Size(58, 38.33);

  /// The spring that carries the knob.
  static const knobSpring = MorphSpring(0.3, 0.99);

  /// The spring of the track color turning on.
  static const onColorSpring = MorphSpring(0.68, 1);

  /// The spring of the track color turning off.
  static const offColorSpring = MorphSpring(0.4, 1);

  /// The drag distance before the knob starts to follow, for a drag that
  /// starts moving within [deadZoneWindow] of the touch.
  static const double deadZone = 5;

  /// Seconds after the touch within which a starting drag crosses
  /// [deadZone] first; a finger held still that long drags the knob
  /// directly.
  static const double deadZoneWindow = 0.1;

  /// Seconds between a drag's commit or uncommit and the start of the
  /// track color's change.
  static const double colorDelay = 0.09;

  /// The rubber band past each end as (limit, stiffness).
  static const (double, double) rubberBand = (12, 0.54);

  bool _value;
  final MorphSpringState _knob;
  final MorphSpringState _color;

  /// The knob's lens.
  final MorphSmallLens lens;

  final MorphTimeline _timeline = MorphTimeline(now: 0);
  bool _started = false;
  double? _downX;
  double _downT = 0;
  double _downKnob = 0;
  double? _slop;
  bool _committed = false;
  bool _everCommitted = false;

  /// Called with the new value whenever the user toggles the switch.
  ValueChanged<bool>? onChanged;

  /// Whether the switch is on.
  bool get value => _value;

  double get _now => _timeline.now;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// The knob position from the off end, rubber band included.
  double get knob => _knob.value(_now);

  /// How far the track color has turned toward on, 0 to 1.
  double get color => _color.value(_now).clamp(0.0, 1.0);

  /// Whether every part of the switch is at rest.
  bool get isSettled =>
      _downX == null &&
      _timeline.isEmpty &&
      _knob.isAtRest(_now, 0.01) &&
      _color.isAtRest(_now, 0.002) &&
      lens.isSettled(_now);

  /// A finger touched the switch at [x].
  void pointerDown(double t, double x) {
    advance(t);
    _downX = x;
    _downT = t;
    _downKnob = _knob.target;
    _slop = null;
    _committed = false;
    _everCommitted = false;
    lens.lift(t);
  }

  /// The finger moved to [x].
  void pointerMove(double t, double x) {
    advance(t);
    final downX = _downX;
    if (downX == null) return;
    final slop = _slop ??= t - _downT < deadZoneWindow ? deadZone : 0;
    final dx = x - downX;
    if (dx.abs() <= slop) return;
    final target = _band(_downKnob + dx - slop * dx.sign);
    _knob.retarget(t, target);
    final far = _value ? 0.0 : travel;
    final start = _value ? travel : 0.0;
    final atFar = _value ? target <= far : target >= far;
    final atStart = _value ? target >= start : target <= start;
    if (!_committed && atFar) {
      _committed = true;
      _everCommitted = true;
      _colorLater(t, on: !_value);
    } else if (_committed && atStart) {
      _committed = false;
      _colorLater(t, on: _value);
    }
  }

  /// The finger left the switch at [x].
  void pointerUp(double t, double x) {
    advance(t);
    if (_downX == null) return;
    _downX = null;
    final next = _everCommitted ? _committed != _value : !_value;
    _timeline.clear();
    _settle(t, next: next);
    lens.unlift(t);
  }

  /// The touch was cancelled; the switch keeps its value.
  void pointerCancel(double t) {
    advance(t);
    if (_downX == null) return;
    _downX = null;
    _timeline.clear();
    _knob.retarget(t, _value ? travel : 0);
    _colorTo(t, on: _value);
    lens.unlift(t);
  }

  /// Sets the value without a touch.
  void setValue(double t, {required bool value}) {
    advance(t);
    if (value == _value) return;
    _timeline.clear();
    _value = value;
    _knob.retarget(t, value ? travel : 0);
    _colorTo(t, on: value);
  }

  void _settle(double t, {required bool next}) {
    final changed = next != _value;
    _value = next;
    _knob.retarget(t, next ? travel : 0);
    _colorTo(t, on: next);
    if (changed) onChanged?.call(next);
  }

  void _colorLater(double t, {required bool on}) {
    _timeline.clear();
    _timeline.at(t + colorDelay, (double s) => _colorTo(s, on: on));
  }

  void _colorTo(double t, {required bool on}) {
    final target = on ? 1.0 : 0.0;
    if (_color.target == target) return;
    _color.retarget(t, target, spring: on ? onColorSpring : offColorSpring);
  }

  /// Advances the motion to time [t].
  void advance(double t) {
    if (!_started) {
      _started = true;
      _timeline.runDue(t);
      lens.advance(t, _knob.value);
      return;
    }
    if (t < _now) return;
    _timeline.runDue(t);
    lens.advance(t, _knob.value);
  }

  static double _band(double position) {
    final (limit, stiffness) = rubberBand;
    double shown(double over) =>
        morphRubberband(over, dimension: limit, coefficient: stiffness);
    if (position < 0) return -shown(-position);
    if (position > travel) return travel + shown(position - travel);
    return math.max(0, position);
  }
}
