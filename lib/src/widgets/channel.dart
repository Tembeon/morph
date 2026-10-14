import 'package:meta/meta.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';

/// One animatable value of a UIKit surface: what UIKit keeps for every
/// channel a flex or a lens drives (a scale, a drift, the menu's pulse).
///
/// Setting a target retargets the channel's spring from its presentation,
/// value and velocity carried: on [trackingSpring] while a finger tracks,
/// on [spring] otherwise. A target equal to the current one is skipped
/// entirely, the spring switch included. A target that changes adds a
/// velocity impulse toward it, `stiffness * retargetImpulse * (new -
/// old)`, on the spring in use. Read from UIKit, notes private; the
/// impulse replays the open menu's channels to the recorded velocity on
/// every retarget (iPhone 16 Pro, iOS 27.0.1).
///
/// A stepped channel ([MorphChannel.stepped]) runs its spring on a clock
/// of its own that the owner advances with [step]: a step whose target
/// changed advances the spring by a fixed retarget step, a step with the
/// same target by the time that passed, and the channel holds what it
/// published between steps. That is how UIKit's low refresh rate scope
/// runs the open menu's pulse channel (`MorphMenuTuning.flexPulseRate`).
///
/// Times are seconds; a pure function of the targets it is given and the
/// times it is read at.
@internal
class MorphChannel {
  /// Creates a channel resting at [value].
  MorphChannel(
    double value, {
    required this.spring,
    MorphSpring? trackingSpring,
    this.retargetImpulse = 0,
  }) : trackingSpring = trackingSpring ?? spring,
       retargetStep = null,
       _state = MorphSpringState(spring, value),
       _target = value;

  /// Creates a channel at rest on [value] whose spring runs on its own
  /// clock, advanced by [step]: [retargetStep] seconds for a step whose
  /// target changed, the time that passed otherwise.
  MorphChannel.stepped(
    double value, {
    required this.spring,
    required double this.retargetStep,
  }) : trackingSpring = spring,
       retargetImpulse = 0,
       _state = MorphSpringState(spring, value),
       _target = value,
       _published = value;

  /// The spring the channel settles on; a change applies from the next
  /// target.
  MorphSpring spring;

  /// The spring the channel follows a tracking finger on.
  MorphSpring trackingSpring;

  /// The duration, in seconds, of the push a changed target gives the
  /// channel: its velocity grows by the spring's stiffness times this
  /// times the change of target.
  double retargetImpulse;

  /// The spring time a changed target advances a stepped channel by, or
  /// null for a channel that runs on the caller's time.
  final double? retargetStep;

  final MorphSpringState _state;
  double _target;
  double _clock = 0;
  double _stepped = 0;
  double _published = 0;
  double _publishedVelocity = 0;

  /// The value the channel heads to.
  double get target => _target;

  /// Sets the target at time [t] on the tracking spring when [tracking],
  /// else on the settling spring; returns false when the target is the
  /// current one and nothing changed.
  bool set(double t, double target, {bool tracking = false}) {
    assert(retargetStep == null, 'a stepped channel moves through step');
    if (target == _target) return false;
    final use = tracking ? trackingSpring : spring;
    _state.retarget(t, target, spring: use);
    if (retargetImpulse != 0) {
      final push = use.stiffness * retargetImpulse * (target - _target);
      _state.setState(t, _state.value(t), _state.velocity(t) + push);
    }
    _target = target;
    return true;
  }

  /// Puts the channel at rest on [value] at time [t].
  void snap(double t, double value) {
    _target = value;
    if (retargetStep != null) {
      _state.snap(_clock, value);
      _stepped = t;
      _published = value;
      _publishedVelocity = 0;
      return;
    }
    _state.snap(t, value);
  }

  /// Gives the channel [value] and [velocity] at time [t], keeping its
  /// target.
  void setState(double t, double value, double velocity) =>
      _state.setState(t, value, velocity);

  /// The presentation value at time [t]; a stepped channel's last
  /// published value.
  double value(double t) => retargetStep == null ? _state.value(t) : _published;

  /// The presentation velocity at time [t]; a stepped channel's last
  /// published velocity, per second of its own clock.
  double velocity(double t) =>
      retargetStep == null ? _state.velocity(t) : _publishedVelocity;

  /// Steps a stepped channel at wall time [t] toward [target] and
  /// publishes its value and velocity.
  void step(double t, double target) {
    final h = target != _target ? retargetStep! : t - _stepped;
    _state.retarget(_clock, target);
    _clock += h;
    _target = target;
    _stepped = t;
    _published = _state.value(_clock);
    _publishedVelocity = _state.velocity(_clock);
  }

  /// Zeroes what a stepped channel published as its velocity, as UIKit
  /// does when the finger lifts; the spring itself is untouched.
  void clearPublishedVelocity() => _publishedVelocity = 0;

  /// Whether, held at [target], the most a stepped channel can still
  /// publish moves its reader by less than [rest]; [reach] is how far the
  /// reader moves per unit per second of published velocity.
  bool holdsWithin(double target, double reach, double rest) {
    final omega = _state.spring.omega;
    return target == _target &&
        (_publishedVelocity.abs() + omega * (_published - target).abs()) *
                reach <
            rest;
  }

  /// Whether the channel's remaining swing stays below [tolerance] from
  /// time [t] on ([MorphSpringState.reach]).
  bool isWithin(double t, double tolerance) =>
      _state.isWithin(retargetStep == null ? t : _clock, tolerance);

  /// Whether the channel is within [tolerance] of its target and nearly
  /// still at time [t].
  bool isAtRest(double t, [double tolerance = 0.01]) =>
      _state.isAtRest(t, tolerance);
}
