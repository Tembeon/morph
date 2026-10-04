import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:motor/motor.dart';

import 'package:morph/src/motion.dart';

/// Semantic phases of a flight. Boundaries are computed from the clamped
/// spring value; consumers react to the phase instead of comparing
/// rawValue against magic numbers.
enum MorphPhase {
  /// Closed and at rest.
  idle,

  /// Early flight: the container is leaving its source (progress < 0.4).
  detaching,

  /// Mid flight (progress 0.4 - 0.8).
  travelling,

  /// Late flight: approaching the target (progress >= 0.8).
  arriving,

  /// Open and at rest.
  settled,
}

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
    assert(
      motion.debugContractViolation == null,
      motion.debugContractViolation ?? '',
    );
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
  bool _scrubbing = false;

  /// The latch: fires exactly once per close, on the first zero
  /// crossing. At that moment the shuttle geometry coincides with the
  /// source widget - a safe point to swap without flicker.
  VoidCallback? onHandoff;

  /// The raw spring value, including overshoot outside `0..1`.
  ///
  /// Above 1 the container's center, size and concentric corner radius
  /// extrapolate past the target. Below 0 size and radius hold at the
  /// source; the close's undershoot follows the handoff latch, once the
  /// live source widget is back.
  double get value => _value;

  /// The spring velocity in value units per second.
  double get velocity => _velocity;

  /// The value for bounded appearance curves and phases, clamped to `0..1`.
  ///
  /// Geometry uses [value] so its open overshoot remains visible.
  double get progress => clampDouble(_value, 0, 1);

  /// The current retarget destination: 1 open, 0 closed.
  double get target => _target;

  /// Whether a simulation is ticking.
  bool get isAnimating => _ticker.isActive;

  /// Whether a scrub owns the value (see [beginScrub]).
  bool get isScrubbing => _scrubbing;

  /// true from open() until the spring fully returns to 0: while true,
  /// the overlay must stay in the tree.
  bool get isShowing => _target >= 1 || _value > _handoffEpsilon;

  /// Whether a close simulation is in flight.
  bool get isClosing => _target == 0 && isAnimating;

  /// Whether the handoff latch has fired for the current close.
  bool get hasHandedOff => _handedOff;

  /// Whether reduced motion is active.
  bool get disableAnimations => _disableAnimations;

  /// The controller viewed as a standard [Animation]: derived animations
  /// (Tween.animate, CurvedAnimation) can be built from it - the engine
  /// speaks the framework's protocols.
  late final Animation<double> animation = _MorphAnimationView(this);

  /// The configured motion profile.
  MorphMotion get motion => _userMotion;

  /// The profile actually driving simulations: [MorphMotion.instant]
  /// under reduced motion, [motion] otherwise.
  MorphMotion get effectiveMotion =>
      _disableAnimations ? .instant : _userMotion;

  /// Swaps the profile; a live simulation retargets onto it with the
  /// current velocity carried over.
  set motion(MorphMotion next) {
    assert(
      next.debugContractViolation == null,
      next.debugContractViolation ?? '',
    );
    if (_userMotion == next) {
      return;
    }
    _userMotion = next;
    // Live retarget: swapping the profile mid-flight moves the
    // simulation onto the new Motion with the current velocity carried
    // over - same as the disableAnimations setter.
    if (isAnimating) {
      _retarget(_target, velocity: _velocity);
    }
  }

  /// The semantic phase derived from [progress]; consumers react to
  /// this instead of comparing raw values against magic numbers.
  MorphPhase get phase {
    if (!isAnimating && !_scrubbing) {
      return _target >= 1 ? .settled : .idle;
    }
    return switch (progress) {
      < 0.4 => .detaching,
      < 0.8 => .travelling,
      _ => .arriving,
    };
  }

  /// Retargets toward 1 on the open motion, carrying velocity over.
  void open({double? velocity}) {
    final double v = velocity ?? _velocity;
    _scrubbing = false;
    _handedOff = false;
    _retarget(1, velocity: v);
  }

  /// Retargets toward 0 on the close motion, carrying velocity over;
  /// from rest the close starts still.
  void close({double? velocity}) {
    final bool live = isAnimating || _scrubbing;
    final double v = velocity ?? (live ? _velocity : 0);
    _scrubbing = false;
    _retarget(0, velocity: v);
  }

  /// Gesture driving: the finger directly owns the spring value. The
  /// simulation is dropped and frames come from dragUpdate; releasing is
  /// an ordinary open()/close() with the gesture velocity - i.e. the
  /// same retarget with velocity carry-over.
  void beginScrub() {
    _ticker.stop();
    _sim = null;
    _scrubbing = true;
    notifyListeners();
  }

  /// Sets the scrubbed value; ignored outside a scrub.
  void updateScrub(double value, {double velocity = 0}) {
    if (!_scrubbing) {
      return;
    }
    _value = value;
    _velocity = velocity;
    notifyListeners();
  }

  /// Stops the ticker without dispose - for emergency teardown while
  /// external listeners may still be subscribed.
  ///
  /// Silent by design: it neither notifies listeners nor fires
  /// [onHandoff]. A teardown runs while the tree may be locked (a
  /// disposing owner), where a notification would rebuild dying
  /// listeners; the caller restores whatever the latch would have (the
  /// flight's abort reveals its source itself).
  void stop() {
    _ticker.stop();
    _sim = null;
    _scrubbing = false;
  }

  /// Toggles reduced motion; a live simulation retargets onto
  /// [MorphMotion.instant] (or back) with velocity carried over.
  set disableAnimations(bool disabled) {
    if (_disableAnimations == disabled) {
      return;
    }
    _disableAnimations = disabled;
    if (isAnimating) {
      _retarget(_target, velocity: _velocity);
    }
  }

  void _retarget(double target, {required double velocity}) {
    _target = target;
    _velocity = velocity;
    // Each direction has its own spring; interruption continuity does
    // not suffer: the new simulation starts from the current value and
    // velocity.
    final Motion motion = target >= 1
        ? effectiveMotion.openMotion
        : effectiveMotion.closeMotion;
    _sim = motion.createSimulation(
      start: _value,
      end: target,
      velocity: velocity,
    );
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

class _MorphAnimationView extends Animation<double> {
  _MorphAnimationView(this._controller);

  final MorphController _controller;
  final Map<AnimationStatusListener, List<VoidCallback>> _statusProxies =
      <AnimationStatusListener, List<VoidCallback>>{};

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) {
    AnimationStatus last = status;
    void proxy() {
      final AnimationStatus next = status;
      if (next != last) {
        last = next;
        listener(next);
      }
    }

    _statusProxies.putIfAbsent(listener, () => <VoidCallback>[]).add(proxy);
    _controller.addListener(proxy);
  }

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    final List<VoidCallback>? proxies = _statusProxies[listener];
    if (proxies == null || proxies.isEmpty) {
      return;
    }
    _controller.removeListener(proxies.removeLast());
    if (proxies.isEmpty) {
      _statusProxies.remove(listener);
    }
  }

  @override
  AnimationStatus get status {
    if (_controller.isScrubbing || _controller.isAnimating) {
      return _controller.target >= 1 ? .forward : .reverse;
    }
    return _controller.target >= 1 ? .completed : .dismissed;
  }

  @override
  double get value => _controller.progress;
}
