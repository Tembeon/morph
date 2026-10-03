import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:morph/src/motion.dart';

/// The scrim of a flight as its own degree of freedom: a spring of its
/// own, retargeted toward 1 when the flight opens and toward 0 when it
/// closes, each after its own delay.
///
/// Without one a flight dims as a function of its value
/// (`morphScrimOpacity`: full at 70 percent of the travel). With one the
/// scrim opacity is `maxScrimOpacity` times this channel's value - a
/// dimming that runs on its own clock beside the geometry, the way UIKit
/// animates a context menu's dimming view on springs of its own. The
/// channel is a second orthogonal degree of freedom, like the drag
/// displacement: every retarget starts from its current value and
/// velocity, so a reversal is continuous, and it never touches the
/// flight value or the content's opacity.
///
/// The channel answers the flight's target changing (open, close, a
/// re-open mid-close), not a scrub of the value. It outlives the
/// handoff latch: past it the shuttle keeps only the scrim until the
/// dimming rests, and the flight lands once both are at rest. Under
/// reduced motion it rides [MorphMotion.instant] with no delays.
@immutable
class MorphScrimMotion {
  /// Creates a scrim motion from its springs and delays.
  const MorphScrimMotion({
    required this.motion,
    this.openDelay = Duration.zero,
    this.closeDelay = Duration.zero,
  });

  /// The springs the scrim opens and closes on.
  final MorphMotion motion;

  /// How long after the flight turns toward open the scrim follows.
  final Duration openDelay;

  /// How long after the flight turns toward closed the scrim follows.
  final Duration closeDelay;

  @override
  bool operator ==(Object other) =>
      other is MorphScrimMotion &&
      other.motion == motion &&
      other.openDelay == openDelay &&
      other.closeDelay == closeDelay;

  @override
  int get hashCode => Object.hash(motion, openDelay, closeDelay);

  @override
  String toString() =>
      'MorphScrimMotion($motion, openDelay: $openDelay, '
      'closeDelay: $closeDelay)';
}

/// The live state of a [MorphScrimMotion]: a value in `[0, 1]` (it may
/// overshoot while a spring rings) on its own ticker.
///
/// Time is the ticker's elapsed time, accumulated across restarts. A
/// retarget requested between frames applies, after its delay, from the
/// (value, velocity) the current simulation has at that moment; a newer
/// request replaces a pending one that has not applied yet.
@internal
class MorphScrimChannel extends ChangeNotifier {
  /// Creates a channel at rest at 0.
  MorphScrimChannel({
    required this.scrim,
    required this._vsync,
    required this.reducedMotion,
  });

  /// The springs and delays.
  final MorphScrimMotion scrim;

  /// Whether reduced motion is on (read at every retarget).
  final ValueGetter<bool> reducedMotion;

  final TickerProvider _vsync;
  Ticker? _ticker;

  double _value = 0;
  double _target = 0;
  Simulation? _sim;
  double _simStart = 0;
  double _now = 0;
  double _base = 0;
  double? _pendingTarget;
  double _pendingDue = 0;

  /// The scrim's value this frame: 0 clear, 1 at the flight's
  /// `maxScrimOpacity`.
  double get value => _value;

  /// The value's rate of change, per second.
  double get velocity => _sim?.dx(_now - _simStart) ?? 0;

  /// The value the channel heads to, pending retarget included.
  double get target => _pendingTarget ?? _target;

  /// Whether nothing moves and nothing is pending.
  bool get isAtRest => _sim == null && _pendingTarget == null;

  /// Heads toward [target] after the delay of its direction.
  void retarget(double target) {
    if (target == this.target) {
      return;
    }
    final bool reduced = reducedMotion();
    final Duration delay = reduced
        ? Duration.zero
        : (target >= 1 ? scrim.openDelay : scrim.closeDelay);
    _pendingTarget = target;
    _pendingDue = _now + delay.inMicroseconds / Duration.microsecondsPerSecond;
    final Ticker ticker = _ticker ??= _vsync.createTicker(_tick);
    if (delay == Duration.zero) {
      _apply(_now);
    }
    if (!ticker.isActive) {
      _base = _now;
      ticker.start();
    }
    notifyListeners();
  }

  void _apply(double at) {
    final double target = _pendingTarget!;
    _pendingTarget = null;
    final Simulation? running = _sim;
    final double start = running?.x(at - _simStart) ?? _value;
    final double velocity = running?.dx(at - _simStart) ?? 0;
    final MorphMotion motion = reducedMotion() ? .instant : scrim.motion;
    final Simulation next =
        (target >= 1 ? motion.openMotion : motion.closeMotion).createSimulation(
          start: start,
          end: target,
          velocity: velocity,
        );
    _target = target;
    _value = start;
    if (next.isDone(0)) {
      _sim = null;
      _value = target;
      return;
    }
    _sim = next;
    _simStart = at;
  }

  void _tick(Duration elapsed) {
    _now = _base + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (_pendingTarget != null && _now >= _pendingDue) {
      _apply(_pendingDue);
    }
    final Simulation? sim = _sim;
    if (sim != null) {
      final double t = _now - _simStart;
      if (sim.isDone(t)) {
        _sim = null;
        _value = _target;
      } else {
        _value = sim.x(t);
      }
    }
    if (isAtRest) {
      _ticker?.stop();
    }
    notifyListeners();
  }

  /// The opacity of a scrim whose ceiling is [maxOpacity] this frame.
  double opacity(double maxOpacity) => maxOpacity * clampDouble(_value, 0, 1);

  /// Drops every motion and parks the channel at 0.
  void reset() {
    _ticker?.stop();
    _sim = null;
    _pendingTarget = null;
    _value = 0;
    _target = 0;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}
