import 'dart:math' as math;
import 'dart:ui';

import 'package:morph/src/motion/rubberband.dart';
import 'package:morph/src/motion/motion.dart';
import 'package:morph/src/widgets/small_lens.dart';
import 'package:morph/src/motion/spring.dart';
import 'package:morph/src/motion/spring_state.dart';
import 'package:morph/src/motion/timeline.dart';

/// The motion of an iOS 27 switch: knob, track color and knob lens.
///
/// A touch lifts the knob lens. A tap toggles on release: the knob
/// travels on a critically damped spring while the lens may still be
/// lifted, and the track color fades on its own spring, slower toward on
/// than toward off. A drag moves the knob with the finger, with a rubber
/// band past each end; a drag that starts moving within [deadZoneWindow]
/// of the touch first crosses a [deadZone]. The drag flips the state the
/// switch shows each time the finger has travelled more than
/// [flipDistance] toward the other state since the touch or the last
/// flip; the track color follows each flip after [colorDelay]. The
/// release keeps the shown state if the drag ever flipped it and toggles
/// like a tap otherwise.
///
/// For Reduce Motion ([reducedMotion]) the knob never lifts or grows and
/// a drag holds it between the ends without the rubber band; its travel
/// and the track color move as usual. Read from UIKit, notes private:
/// UISwitch lifts its knob only while pressed without Reduce Motion,
/// keeps the 37 x 24 knob size for a press under it, and clamps a dragged
/// knob instead of rubber-banding it.
///
/// Times are seconds and positions pixels along the track.
///
/// The switch settles once every part's remaining swing is below
/// [MorphRest] (0.1 pt, 0.3 device px at 3x; an opacity half an 8-bit
/// step) and snaps onto its targets: invisible, NEAR.
class MorphSwitchMotion
    with MorphMotionEvents<MorphSwitchEvent>
    implements MorphMotion<MorphSwitchEvent> {
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

  /// The 63 x 28 track measured from the UISwitch view tree.
  static const Size trackSize = Size(63, 28);

  /// The 2 pixel resting knob inset measured from the UISwitch view tree.
  static const double inset = 2;

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

  /// Seconds between a drag's flip and the start of the track color's
  /// change.
  static const double colorDelay = 0.09;

  /// How far, in pixels, a dragging finger travels toward the other state
  /// since the touch or the last flip before the shown state flips.
  ///
  /// Read from UIKit, notes private: UISwitch measures its pan's
  /// translation from the touch, flips when it passes 25 pt toward the
  /// state not shown and measures again from there. The device drags
  /// there and back (`switch-tb-*`: 20 / 8 / 30 / 40 pt out, back to -5 /
  /// 0 / 12 / -10 / 5) end as this predicts.
  static const double flipDistance = 25;

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
  double _anchor = 0;
  double _downT = 0;
  double _downKnob = 0;
  double? _slop;
  bool _committed = false;
  bool _everCommitted = false;

  /// Whether the switch moves for Reduce Motion: no lift and no rubber
  /// band (see the class documentation).
  bool get reducedMotion => lens.reducedMotion;

  set reducedMotion(bool value) => lens.reducedMotion = value;

  /// Whether the switch is on.
  bool get value => _value;

  double get _now => _timeline.now;

  @override
  double get time => _now;

  // The lifted knob rests under a still finger and wakes with its moves.
  @override
  double? get wakeTime => null;

  /// The knob position from the off end, rubber band included.
  double get knob => _knob.value(_now);

  /// How far the track color has turned toward on, 0 to 1.
  double get color => _color.value(_now).clamp(0.0, 1.0);

  /// Whether what remains of the switch's motion is invisible: nothing
  /// pending and every spring's remaining swing below [MorphRest] (NEAR,
  /// invisible; [settle] snaps the rest). A finger held still counts: the
  /// lifted knob rests until the finger moves or lifts.
  @override
  bool get isSettled =>
      _timeline.isEmpty &&
      _knob.isWithin(_now, MorphRest.length) &&
      _color.isWithin(_now, MorphRest.opacity) &&
      lens.isSettled(_now) &&
      lens.hasSampled(_now, _knob.value(_now));

  /// Puts a settled switch exactly onto its targets.
  @override
  void settle() {
    _knob.settle(_now);
    _color.settle(_now);
    lens.settle(_now, _knob.target);
  }

  /// A finger touched the switch at [x].
  void pointerDown(double t, double x) {
    advance(t);
    _downX = x;
    _anchor = x;
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
    final shown = _committed != _value;
    if ((shown ? _anchor - x : x - _anchor) > flipDistance) {
      _anchor = x;
      _committed = !_committed;
      _everCommitted = true;
      _colorLater(t, on: !shown);
      emit(MorphSwitchShown(on: !shown));
    }
    final slop = _slop ??= t - _downT < deadZoneWindow ? deadZone : 0;
    final dx = x - downX;
    if (dx.abs() <= slop) return;
    final position = _downKnob + dx - slop * dx.sign;
    _knob.retarget(
      t,
      reducedMotion ? position.clamp(0.0, travel) : _band(position),
    );
  }

  /// The finger left the switch at [x].
  void pointerUp(double t, double x) {
    advance(t);
    if (_downX == null) return;
    _downX = null;
    final shown = _committed != _value;
    final next = _everCommitted ? shown : !_value;
    _timeline.clear();
    _settle(t, next: next);
    lens.unlift(t);
    if (next != shown) emit(MorphSwitchShown(on: next));
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
    lens.resetFlex(t, knob);
    _knob.retarget(t, value ? travel : 0);
    _colorTo(t, on: value);
  }

  void _settle(double t, {required bool next}) {
    final changed = next != _value;
    _value = next;
    _knob.retarget(t, next ? travel : 0);
    _colorTo(t, on: next);
    if (changed) emit(MorphSwitchChanged(on: next));
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

  @override
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

/// What a [MorphSwitchMotion] tells its host.
sealed class MorphSwitchEvent {
  const MorphSwitchEvent();
}

/// The user toggled the switch to [on].
final class MorphSwitchChanged extends MorphSwitchEvent {
  /// Creates the event.
  const MorphSwitchChanged({required this.on});

  /// The new value.
  final bool on;
}

/// A touch changed the state the switch shows to [on]: a drag committing
/// or uncommitting, or a release that toggles. This is the moment UIKit
/// plays the switch's haptic (read from UIKit, notes private).
final class MorphSwitchShown extends MorphSwitchEvent {
  /// Creates the event.
  const MorphSwitchShown({required this.on});

  /// The state the switch shows.
  final bool on;
}
