import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/src/widgets/morph_squash.dart';

/// The physics HOST of a selection pill travelling a horizontal track -
/// the liquid-glass nav pill's springs with the native grab, physics
/// only: the owner owns the track's geometry (slots, weights,
/// sub-targets), the rendering (ink, glass, mass) and the semantics;
/// the host owns the springs, the grab state machine and the ticker.
///
/// Everything is in PIXELS along the track axis. The owner feeds raw
/// pointer x through [down] / [move] / [up] / [cancel] (a raw Listener
/// is the intended source - no recognizers, no timers: the DOWN itself
/// is the answer) and maps positions to targets through two callbacks;
/// each frame it reads the outputs back and draws the pill wherever
/// [centerX] and [resolveSize] say.
///
/// The model, every verdict paid for by hand against the references:
///
/// - TAP: the pill lifts the instant the finger lands and stays up for
///   the WHOLE journey - it glides on the travel spring and comes down
///   only on landing (past 92% of the way). Arriving is the landing;
///   the choice itself commits immediately ([onTarget] fires on the
///   tap, so selection and screens flip with the finger, not with the
///   pill).
/// - HOLD: the pill grows IN PLACE - even between slots - and the
///   finger then carries it by its own DISPLACEMENT, not by centering
///   under the finger. Release snaps to [snap] of wherever the pill
///   stands; a motionless hold released over a slot selects it like a
///   slow tap ([hit]).
/// - LIFT: each axis rides its own spring (damping ratio 0.6 across,
///   0.7 down) - the width overshoots a little further and settles a
///   little later than the height, which is what keeps the growth from
///   reading as a plain scale-up.
/// - DEFORMATION: from the pill's own ACCELERATION ([MorphSquash]),
///   with its magnitude kept and its sign taken from the direction of
///   travel (an eased crossing on reversals) - one deformation sense
///   per journey instead of turning inside out at the halfway mark.
/// - CHROME SYMPATHY: the track's chrome answers the hand without a
///   leash of its own - at most 4px of shift on an ease-out of the
///   accumulated drag fraction ([chromeShift]) and 16px of width
///   breathed while the pill is up ([chromeBreath]); write them into
///   the bar's piece channel and the whole mass answers.
///
/// Interruption safety by construction: a DOWN freezes a travel
/// mid-flight (the hand takes over), every release resumes the journey
/// from wherever the pill stands, and the lift cannot come down while
/// the finger holds it.
class MorphPillHost extends ChangeNotifier {
  /// Creates a host; [vsync] drives its one ticker.
  MorphPillHost({
    required TickerProvider vsync,
    required this.hit,
    required this.snap,
    this.onTarget,
    this.carrySlop = 4,
    this.carryCommit = 16,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  // ── The reference constants, verbatim ────────────────────────────
  static const double _travelStiffness = 280;
  static const double _travelDamping = 31.4;
  static const double _liftStiffness = 250;
  static const double _liftDampingX = 19.0;
  static const double _liftDampingY = 22.1;
  static const double _handoverStart = 0.92;
  static const double _followTau = 0.05;
  static const double _signTau = 0.25;
  static const double _chromeShiftMax = 4;
  static const double _chromeBreathWidth = 16;
  static const double _chromeReturnStiffness = 300;
  static const double _pressStiffness = 1000;

  /// Maps a finger x to the target CENTER a tap (or a motionless hold)
  /// selects - the owner's hit test, sub-targets included.
  final double Function(double fingerX) hit;

  /// Maps a released pill center to the nearest rest CENTER - the
  /// owner's snap grid.
  final double Function(double pillCenterX) snap;

  /// Fired whenever a POINTER gesture commits a target: every tap
  /// (re-taps included - re-tap grammar is the owner's call) and every
  /// carry release. Owner-driven [settleTo] does not fire it.
  final void Function(double centerX, {required bool byCarry})? onTarget;

  /// Pixels of pointer travel before a touch becomes a carry.
  final double carrySlop;

  /// Pixels of pointer travel past which a release snaps the CARRIED
  /// position instead of reading as a slow tap on [hit].
  final double carryCommit;

  // ── Travel state ─────────────────────────────────────────────────
  double _pos = 0;
  double _vel = 0;
  double _target = 0;
  double _from = 0;
  bool _travelActive = false;

  // ── Grab state ───────────────────────────────────────────────────
  bool _held = false;
  bool _carrying = false;
  bool _realMove = false;
  double _follow = 0;
  double _carryTarget = 0;
  double _grabPos = 0;
  double _pressX = 0;
  double _downX = 0;
  double? _lastX;

  // ── Lift and deformation ─────────────────────────────────────────
  bool _lifted = false;
  double _liftX = 0;
  double _liftXVel = 0;
  double _liftY = 0;
  double _liftYVel = 0;
  double _travelSign = 0;
  double _travelSignEased = 0;
  double _deviation = 0;
  final MorphSquash _squash = MorphSquash();

  // ── Chrome sympathy ──────────────────────────────────────────────
  double _accum = 0;
  double _accumVel = 0;
  double _press = 0;
  double _pressVel = 0;

  Ticker? _ticker;

  /// Ticker.elapsed restarts from zero on every start(): dt comes from
  /// the difference against the previous tick of THIS run, and the
  /// squash's monotonic clock is accumulated by the host itself.
  Duration? _tickerLast;
  double _now = 0;

  // ── Outputs ──────────────────────────────────────────────────────

  /// The pill's center this frame: the smoothed carry while the finger
  /// holds it, the travel spring otherwise.
  double get centerX => _carrying ? _follow : _pos;

  /// Whether the pill is raised (from touch until landing).
  bool get lifted => _lifted;

  /// Whether a finger is down on the track.
  bool get held => _held;

  /// Whether the finger is carrying the pill.
  bool get carrying => _carrying;

  /// Horizontal lift progress (overshoots past 1 - that is the life).
  double get liftX => _liftX;

  /// Vertical lift progress.
  double get liftY => _liftY;

  /// The signed acceleration deformation; see [MorphSquash].
  double get deviation => _deviation;

  /// The press breath, 0..1 (critically damped, up while the pill is).
  double get pressProgress => _press;

  /// The pill's size this frame: rest -> lifted per axis on the lift
  /// springs, then the deviation on top (area held).
  Size resolveSize({required Size rest, required Size lifted}) {
    final double w = rest.width + (lifted.width - rest.width) * _liftX;
    final double h = rest.height + (lifted.height - rest.height) * _liftY;
    return Size(w * (1 + _deviation), h * (1 - _deviation));
  }

  /// The chrome's sympathetic shift for a track of [trackWidth] px: at
  /// most 4px, on an ease-out of the accumulated drag fraction.
  double chromeShift(double trackWidth) {
    final double fraction = (_accum / math.max(trackWidth, 1)).clamp(-1.0, 1.0);
    return _chromeShiftMax *
        fraction.sign *
        Curves.easeOut.transform(fraction.abs());
  }

  /// The chrome's breath for a track of [trackWidth] px: 16px of width
  /// gained at full press, as a uniform scale.
  double chromeBreath(double trackWidth) {
    return 1 + _press * _chromeBreathWidth / math.max(trackWidth, 1);
  }

  // ── Owner-driven placement ───────────────────────────────────────

  /// Parks the pill at [center] instantly - initial layout, or
  /// re-anchoring a resting pill after a resize.
  void jumpTo(double center) {
    _pos = center;
    _vel = 0;
    _target = center;
    _from = center;
    notifyListeners();
  }

  /// Launches (or resumes) a travel to [center] from wherever the pill
  /// stands - the one door every selection walks through, so an
  /// interrupted journey can never strand the pill between slots. The
  /// pill lifts for the journey and lands on arrival.
  void settleTo(double center) {
    _travelActive = true;
    _lifted = true;
    _from = _pos;
    _target = center;
    _travelSign = _signOf(_target - _from);
    _wake();
  }

  // ── The pointer protocol (px along the track) ────────────────────

  /// The finger landed: the pill starts lifting IN PLACE immediately.
  /// What the gesture MEANS is decided later - a quick release is a
  /// tap, [carrySlop] px of travel is a carry.
  void down(double x) {
    if (_held) {
      return;
    }
    _held = true;
    _carrying = false;
    _realMove = false;
    _travelActive = false;
    _lifted = true;
    // The hand takes the deformation back off the travel.
    _travelSign = 0;
    _downX = x;
    _pressX = x;
    _follow = _pos;
    _grabPos = _pos;
    _carryTarget = _pos;
    _vel = 0;
    _lastX = x;
    _wake();
  }

  /// The finger moved; past [carrySlop] the touch becomes a carry, and
  /// the pill's target is where it was grabbed plus how far the finger
  /// has travelled since - the native carry, not a jump under the
  /// finger. Deltas are honest past the track's edges: only the owner
  /// clamps, through [snap] and [hit].
  void move(double x) {
    if (!_held) {
      return;
    }
    if (!_carrying && (x - _downX).abs() > carrySlop) {
      _carrying = true;
      _lastX = x;
    }
    if (!_carrying) {
      return;
    }
    if ((x - _pressX).abs() > carryCommit) {
      _realMove = true;
    }
    _carryTarget = _grabPos + (x - _pressX);
    _accum += x - (_lastX ?? x);
    _lastX = x;
  }

  /// The finger left. A carry snaps to [snap] of the pill's position
  /// (a sub-[carryCommit] wiggle reads as a slow tap on [hit]); a
  /// touch that never carried is a tap on [hit]. Either way the
  /// journey resumes through one door and [onTarget] reports the
  /// commit.
  void up(double x) {
    if (!_held) {
      return;
    }
    _held = false;
    if (_carrying) {
      final double target = _realMove ? snap(_follow) : hit(_pressX);
      _carrying = false;
      _lastX = null;
      _pos = _follow;
      _vel = 0;
      settleTo(target);
      onTarget?.call(target, byCarry: _realMove);
      return;
    }
    final double target = hit(x);
    settleTo(target);
    onTarget?.call(target, byCarry: false);
  }

  /// The touch was cancelled: the pill resumes its own journey to the
  /// last committed target, no selection change.
  void cancel() {
    if (!_held) {
      return;
    }
    _held = false;
    if (_carrying) {
      _carrying = false;
      _lastX = null;
      _pos = _follow;
      _vel = 0;
    }
    settleTo(snap(_pos));
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _wake() {
    final Ticker ticker = _ticker!;
    if (!ticker.isActive) {
      _tickerLast = null;
      ticker.start();
    }
  }

  double _signOf(double span) => span.abs() < 1e-6 ? 0 : span.sign;

  void _tick(Duration elapsed) {
    final Duration last = _tickerLast ?? elapsed;
    _tickerLast = elapsed;
    final double dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0) {
      return;
    }
    _now += dt;

    // 1) The travel spring, retargeting with kept velocity.
    bool travelSettled = true;
    if (_travelActive) {
      final (double p, double v) = _springStep(
        x: _pos,
        vel: _vel,
        target: _target,
        dt: dt,
        stiffness: _travelStiffness,
        damping: _travelDamping,
      );
      _pos = p;
      _vel = v;
      travelSettled = (_pos - _target).abs() < 0.25 && _vel.abs() < 4;
      if (travelSettled) {
        _pos = _target;
        _vel = 0;
      }
    }

    // 2) While carrying, smoothly chase the hand's target so the pill
    // eases rather than snaps.
    if (_carrying) {
      _follow += (_carryTarget - _follow) * (1 - math.exp(-dt / _followTau));
    }

    // 3) The lift: up from the touch, down only once landed - and
    // never while the finger still holds the pill.
    final double progress = () {
      final double span = (_target - _from).abs();
      if (span < 1e-6) {
        return 1.0;
      }
      return (1 - (_target - _pos).abs() / span).clamp(0.0, 1.0);
    }();
    if (!_held && !_carrying && (travelSettled || progress >= _handoverStart)) {
      _lifted = false;
    }
    final double liftTarget = _lifted ? 1 : 0;
    final (double lx, double lxv) = _stepLift(
      _liftX,
      _liftXVel,
      liftTarget,
      dt,
      _liftDampingX,
    );
    _liftX = lx;
    _liftXVel = lxv;
    final (double ly, double lyv) = _stepLift(
      _liftY,
      _liftYVel,
      liftTarget,
      dt,
      _liftDampingY,
    );
    _liftY = ly;
    _liftYVel = lyv;
    final bool liftSettled = !_lifted && _liftX == 0 && _liftY == 0;

    if (_travelActive && travelSettled && liftSettled && !_carrying) {
      _travelActive = false;
    }

    // 4) The squash, sampled where the pill is drawn THIS frame; its
    // magnitude is kept and its sign taken from the travel direction,
    // eased across on a reversal.
    double deviation = _squash.track(Offset(centerX, 0), now: _now, dt: dt);
    if (_travelSignEased == 0) {
      _travelSignEased = _travelSign;
    } else if (_travelSignEased != _travelSign) {
      _travelSignEased +=
          (_travelSign - _travelSignEased) * (1 - math.exp(-dt / _signTau));
      if ((_travelSign - _travelSignEased).abs() < 0.01) {
        _travelSignEased = _travelSign;
      }
    }
    final double key = _travelSignEased;
    if (key != 0) {
      deviation = deviation * (1 - key.abs()) - key * deviation.abs();
    }
    _deviation = deviation;

    // 5) Chrome sympathy: the breath follows the lift, the shift's
    // accumulation springs home once the hand lets go.
    final (double pp, double ppv) = _stepLift(
      _press,
      _pressVel,
      liftTarget,
      dt,
      2 * math.sqrt(_pressStiffness),
      stiffness: _pressStiffness,
    );
    _press = pp;
    _pressVel = ppv;
    if (!_carrying) {
      final (double a, double av) = _springStep(
        x: _accum,
        vel: _accumVel,
        target: 0,
        dt: dt,
        stiffness: _chromeReturnStiffness,
        damping: 2 * math.sqrt(_chromeReturnStiffness),
      );
      _accum = a;
      _accumVel = av;
      if (_accum.abs() < 0.05 && _accumVel.abs() < 0.5) {
        _accum = 0;
        _accumVel = 0;
      }
    }

    // 6) Everything must be finished - the deformation drains after
    // the spring does, and the sympathy after both.
    final bool motionSettled = _deviation.abs() < 0.0005;
    final bool chromeSettled = _accum == 0 && _press == 0;
    if (!_travelActive &&
        !_carrying &&
        !_held &&
        liftSettled &&
        motionSettled &&
        chromeSettled) {
      _squash.reset();
      _travelSign = 0;
      _travelSignEased = 0;
      _ticker?.stop();
    }

    notifyListeners();
  }

  /// One frame of a lift spring, snapped to its target once it has
  /// nothing left to say.
  (double, double) _stepLift(
    double x,
    double vel,
    double target,
    double dt,
    double damping, {
    double stiffness = _liftStiffness,
  }) {
    final (double p, double v) = _springStep(
      x: x,
      vel: vel,
      target: target,
      dt: dt,
      stiffness: stiffness,
      damping: damping,
    );
    if ((p - target).abs() < 0.001 && v.abs() < 0.01) {
      return (target, 0);
    }
    return (p, v);
  }

  /// One integration step of an underdamped spring, sub-stepped at
  /// 240 Hz for stability - the reference integrator, verbatim.
  static (double, double) _springStep({
    required double x,
    required double vel,
    required double target,
    required double dt,
    required double stiffness,
    required double damping,
  }) {
    double t = dt;
    double px = x;
    double pv = vel;
    while (t > 0) {
      final double step = t > 1 / 240.0 ? 1 / 240.0 : t;
      final double accel = -stiffness * (px - target) - damping * pv;
      pv += accel * step;
      px += pv * step;
      t -= step;
    }
    return (px, pv);
  }
}
