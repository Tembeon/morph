import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/src/motion.dart';

/// A single retargetable scalar spring from which all derived morph
/// values are computed. An interruption (open during close and vice
/// versa) is a new SpringSimulation starting from the old one's current
/// value and velocity: the velocity carry-over automatically makes the
/// interruption consistent for every derived property.
class MorphController extends ChangeNotifier {
  /// Creates a standalone spring; [onHandoff] fires once per close, on
  /// the first zero crossing.
  MorphController({
    required TickerProvider vsync,
    MorphMotion motion = .liquid,
    this.onHandoff,
  }) : _userMotion = motion {
    _ticker = vsync.createTicker(_tick);
  }

  static const double _handoffEpsilon = 0.001;

  late final Ticker _ticker;
  Simulation? _sim;

  MorphMotion _userMotion;
  bool _disableAnimations = false;

  double _value = 0;
  double _velocity = 0;
  double _target = 0;
  bool _handedOff = true;

  /// The latch: fires exactly once per close, on the first zero
  /// crossing, when the morph coincides with its source widget.
  VoidCallback? onHandoff;

  /// The spring value: 0 closed, 1 open, beyond either during an
  /// overshoot.
  double get value => _value;

  /// The spring velocity in value units per second.
  double get velocity => _velocity;

  /// The value for bounded appearance curves, clamped to `0..1`.
  double get progress => clampDouble(_value, 0, 1);

  /// The current retarget destination: 1 open, 0 closed.
  double get target => _target;

  /// Whether a simulation is ticking.
  bool get isAnimating => _ticker.isActive;

  /// Whether a close simulation is in flight.
  bool get isClosing => _target == 0 && isAnimating;

  /// Whether the handoff latch has fired for the current close.
  bool get hasHandedOff => _handedOff;

  /// Whether reduced motion is active.
  bool get disableAnimations => _disableAnimations;

  /// Switches reduced motion; a live simulation retargets onto the
  /// effective profile with its velocity carried over.
  set disableAnimations(bool disabled) {
    if (_disableAnimations == disabled) {
      return;
    }
    _disableAnimations = disabled;
    if (isAnimating) {
      _retarget(_target, velocity: _velocity);
    }
  }

  /// The configured motion profile.
  MorphMotion get motion => _userMotion;

  /// The profile actually driving simulations: [MorphMotion.instant]
  /// under reduced motion, [motion] otherwise.
  MorphMotion get effectiveMotion =>
      _disableAnimations ? .instant : _userMotion;

  /// Swaps the profile; a live simulation retargets onto it with the
  /// current velocity carried over.
  set motion(MorphMotion next) {
    if (_userMotion == next) {
      return;
    }
    _userMotion = next;
    if (isAnimating) {
      _retarget(_target, velocity: _velocity);
    }
  }

  /// Retargets toward open, carrying the current velocity unless
  /// [velocity] is given.
  void open({double? velocity}) {
    final double v = velocity ?? _velocity;
    _handedOff = false;
    _retarget(1, velocity: v);
  }

  /// Retargets toward closed; a close from rest starts still unless
  /// [velocity] is given.
  void close({double? velocity}) {
    final double v = velocity ?? (isAnimating ? _velocity : 0);
    _retarget(0, velocity: v);
  }

  /// Stops the simulation where it is.
  ///
  /// Silent by design: it neither notifies listeners nor fires
  /// [onHandoff]. A teardown runs while the tree may be locked (a
  /// disposing owner), where a notification would rebuild dying
  /// listeners; the caller restores whatever the latch would have (the
  /// flight's abort reveals its source itself).
  void stop() {
    _ticker.stop();
    _sim = null;
  }

  void _retarget(double target, {required double velocity}) {
    _target = target;
    _velocity = velocity;
    // Each direction has its own spring; interruption continuity does
    // not suffer: the new simulation starts from the current value and
    // velocity.
    final spring = target >= 1
        ? effectiveMotion.openSpring
        : effectiveMotion.closeSpring;
    _sim = SpringSimulation(spring.description, _value, target, velocity);
    _ticker.stop();
    if (_sim!.isDone(0)) {
      _settle();
    } else {
      _ticker.start();
    }
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    final Simulation sim = _sim!;
    final double t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _value = sim.x(t);
    _velocity = sim.dx(t);
    _maybeHandoff();
    if (sim.isDone(t)) {
      _ticker.stop();
      _settle();
    }
    notifyListeners();
  }

  void _maybeHandoff() {
    if (_target == 0 && !_handedOff && _value <= _handoffEpsilon) {
      _handedOff = true;
      onHandoff?.call();
    }
  }

  void _settle() {
    _value = _target;
    _velocity = 0;
    if (_target == 0 && !_handedOff) {
      _handedOff = true;
      onHandoff?.call();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
