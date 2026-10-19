import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/channel.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// The four channels a flex deforms a surface by: the scale of its width
/// and height and the drift of its center.
typedef MorphFlexValues = ({
  double scaleX,
  double scaleY,
  double driftX,
  double driftY,
});

/// UIKit's flex interaction: the one machine that lifts, stretches and
/// shifts every flexible glass surface under a finger.
///
/// A finger that touches down activates the flex, after
/// [activationDelay]. While it is active the four channels (scale x,
/// scale y, drift x, drift y) chase [dynamicTargets] on the spec's
/// tracking spring; when the finger lifts they return to rest on its
/// scale spring. The spec comes from the surface's size
/// ([MorphFlexSpec.forSize]). With [glows] the interaction also carries
/// the touch glow: a wash over the surface and a little glow under the
/// finger.
///
/// The menu variant of the same machine is [menuTargets] with its pulse
/// channel, a stepped [MorphChannel]; the open menu drives those itself.
/// Each of the four channels is a [MorphChannel] on the spec's springs
/// and retarget impulse.
///
/// Times are seconds, positions pixels in the surface's own space.
///
/// A surface settles ([isSettled]) once every part's remaining swing is below
/// [MorphRest] (0.1 pt, 0.3 device px at 3x; an opacity half an 8-bit
/// step) and snaps onto its targets: invisible, NEAR.
@internal
class MorphFlexInteraction {
  /// Creates the flex of a surface of [size] at rest.
  ///
  /// Delayed reactions go on [timeline] when one is given, so they run in
  /// order with the owner's own; otherwise on a timeline of the
  /// interaction's, run by [advance].
  MorphFlexInteraction({
    required Size size,
    this.stretches = true,
    this.glows = false,
    this.activationDelay = 0,
    MorphTimeline? timeline,
  }) : _size = size,
       _spec = MorphFlexSpec.forSize(size),
       _timeline = timeline ?? MorphTimeline(now: 0),
       _ownsTimeline = timeline == null;

  /// The share of the stretch threshold a finger travelling inside the
  /// surface counts: inside, the stretch grows by a quarter of what the
  /// same travel beyond the edge adds. Read from UIKit, notes private;
  /// replayed by the glass button's drag-off captures.
  static const double inBoundsWeight = 0.25;

  /// The slope at which a movement scale enters its soft limit
  /// ([softClamp]). Read from UIKit, notes private.
  static const double softness = 0.55;

  /// The time constant of the glow fading in, in seconds.
  static const double glowTime = 0.023;

  /// The spring the glow fades out and the little glow grows on.
  static const glowSpring = MorphSpring(0.5, 1);

  /// The diameter of the little glow at the touch point.
  static const double littleGlowSize = 66;

  /// How much the little glow grows while it fades out.
  static const double littleGlowGrowth = 4;

  /// A flex at rest.
  static const MorphFlexValues rest = (
    scaleX: 1,
    scaleY: 1,
    driftX: 0,
    driftY: 0,
  );

  /// Whether a dragging finger stretches the surface and shifts it after
  /// the finger; without it the flex only lifts.
  final bool stretches;

  /// Whether the interaction carries the touch glow.
  final bool glows;

  /// Seconds between the touch and the flex becoming active.
  final double activationDelay;

  /// Whether the surface moves for Reduce Motion: it still glows but
  /// never lifts, stretches or shifts. This approximates the platform's
  /// behavior; it is not measured.
  bool reducedMotion = false;

  final MorphTimeline _timeline;
  final bool _ownsTimeline;
  Size _size;
  MorphFlexSpec _spec;
  late final MorphChannel _scaleX = _channel(1);
  late final MorphChannel _scaleY = _channel(1);
  late final MorphChannel _driftX = _channel(0);
  late final MorphChannel _driftY = _channel(0);

  MorphChannel _channel(double value) => MorphChannel(
    value,
    spring: _spec.scaleSpring,
    trackingSpring: _spec.trackingSpring,
    retargetImpulse: _spec.retargetImpulse,
  );

  List<MorphChannel> get _channels => [_scaleX, _scaleY, _driftX, _driftY];
  final MorphSpringState _glowOut = MorphSpringState(glowSpring, 0);
  final MorphSpringState _littleScale = MorphSpringState(glowSpring, 1);
  final MorphSpringState _glowX = MorphSpringState(
    MorphFlexSpec.ultraSmall.trackingSpring,
    0,
  );
  final MorphSpringState _glowY = MorphSpringState(
    MorphFlexSpec.ultraSmall.trackingSpring,
    0,
  );

  Offset? _down;
  Offset _position = Offset.zero;
  bool _active = false;
  int _generation = 0;
  double _glowStart = 0;
  double _glowFrom = 0;

  /// The size of the surface at rest.
  Size get size => _size;

  set size(Size value) {
    if (value == _size) return;
    _size = value;
    _spec = MorphFlexSpec.forSize(value);
    for (final channel in _channels) {
      channel.spring = _spec.scaleSpring;
      channel.trackingSpring = _spec.trackingSpring;
      channel.retargetImpulse = _spec.retargetImpulse;
    }
  }

  /// The deformation tuning UIKit derives for [size].
  MorphFlexSpec get spec => _spec;

  /// The scale of the surface fully lifted.
  double get liftedScale => _spec.liftScaleFor(_size);

  /// Whether a finger is down on the surface.
  bool get isPressed => _down != null;

  /// Whether the flex follows the finger: from [activationDelay] after the
  /// touch until the finger lifts.
  bool get isActive => _active;

  /// Runs the reactions that came due by time [t] on the interaction's own
  /// timeline; an owner that passed its timeline runs it itself.
  void advance(double t) {
    if (_ownsTimeline) _timeline.runDue(t);
  }

  /// A finger touched the surface at [position] at time [t].
  void pointerDown(double t, Offset position) {
    advance(t);
    _down = position;
    _position = position;
    if (glows) {
      _glowFrom = glow(t);
      _glowStart = t;
      _littleScale.snap(t, 1);
      final at = _clamped(position);
      _glowX.snap(t, at.dx);
      _glowY.snap(t, at.dy);
    }
    final generation = ++_generation;
    if (activationDelay <= 0) {
      _activate(t);
    } else {
      _timeline.at(t + activationDelay, (double s) {
        if (generation == _generation && _down != null) _activate(s);
      });
    }
  }

  /// The finger moved to [position] at time [t].
  void pointerMove(double t, Offset position) {
    advance(t);
    if (_down == null) return;
    _position = position;
    if (_active) _retarget(t, targets, tracking: true);
    if (glows) {
      final at = _clamped(position);
      final tracking = _spec.trackingSpring;
      _glowX.retarget(t, at.dx, spring: tracking);
      _glowY.retarget(t, at.dy, spring: tracking);
    }
  }

  /// The finger lifted at time [t], at [position] when given.
  void pointerUp(double t, [Offset? position]) {
    if (position != null) pointerMove(t, position);
    release(t);
  }

  /// The touch was cancelled at time [t].
  void pointerCancel(double t) => release(t);

  /// Ends the touch at time [t]: the channels return to rest on the
  /// spec's scale spring and the glow fades.
  void release(double t) {
    advance(t);
    _generation++;
    final strength = glow(t);
    final wasDown = _down != null;
    _down = null;
    _active = false;
    _retarget(t, rest, tracking: false);
    if (glows && wasDown) {
      _glowOut.snap(t, strength);
      _glowOut.retarget(t, 0);
      _littleScale.retarget(t, littleGlowGrowth);
    }
  }

  void _activate(double t) {
    _active = true;
    _retarget(t, targets, tracking: true);
  }

  void _retarget(double t, MorphFlexValues to, {required bool tracking}) {
    _scaleX.set(t, to.scaleX, tracking: tracking);
    _scaleY.set(t, to.scaleY, tracking: tracking);
    _driftX.set(t, to.driftX, tracking: tracking);
    _driftY.set(t, to.driftY, tracking: tracking);
  }

  /// What the channels head to now: [dynamicTargets] of the finger while
  /// the flex is active, [rest] otherwise.
  MorphFlexValues get targets {
    final down = _down;
    if (!_active || down == null || reducedMotion) return rest;
    final at = _position;
    return dynamicTargets(
      spec: _spec,
      size: _size,
      translation: at - down,
      inBounds: _clamped(at) - down,
      stretch: stretches,
    );
  }

  /// The channels at time [t].
  MorphFlexValues values(double t) => (
    scaleX: _scaleX.value(t),
    scaleY: _scaleY.value(t),
    driftX: _driftX.value(t),
    driftY: _driftY.value(t),
  );

  /// The horizontal scale at time [t].
  double scaleX(double t) => _scaleX.value(t);

  /// The vertical scale at time [t].
  double scaleY(double t) => _scaleY.value(t);

  /// The lift at time [t]: the mean of the two scales, which the stretch
  /// leaves alone.
  double scale(double t) => (_scaleX.value(t) + _scaleY.value(t)) / 2;

  /// How far the surface's center shows shifted at time [t]: the drift
  /// times the scale, as UIKit scales the drifted surface.
  ///
  /// Replays the glass button's drag-off captures to 0.03 pt rms on the
  /// simulator and 0.07 on the device (120 x 44, a 150 pt drag).
  Offset translation(double t) => Offset(
    _driftX.value(t) * _scaleX.value(t),
    _driftY.value(t) * _scaleY.value(t),
  );

  /// The glow strength at time [t], 0 to 1.
  double glow(double t) {
    if (!glows) return 0;
    if (_down != null) {
      return 1 - (1 - _glowFrom) * math.exp(-(t - _glowStart) / glowTime);
    }
    return _glowOut.value(t).clamp(0.0, 1.0);
  }

  /// The opacity of the glow over the whole surface at time [t].
  double bigGlowOpacity(double t) => glow(t) * _spec.bigGlowOpacity;

  /// The opacity of the little glow at the touch point at time [t].
  double littleGlowOpacity(double t) => glow(t) * _spec.littleGlowOpacity;

  /// The scale of the little glow at time [t].
  double littleGlowScale(double t) => _littleScale.value(t);

  /// The center of the little glow at time [t].
  Offset littleGlowCenter(double t) => Offset(_glowX.value(t), _glowY.value(t));

  /// Whether what remains of the surface's motion at time [t] is
  /// invisible ([MorphRest], NEAR): the scales' swing over the surface's
  /// longer side, the drifts' swing and the glow's change (fading in under
  /// a finger or out after it) below a visible step, and no reaction
  /// pending. A finger held still counts: a held surface sleeps until the
  /// finger moves or lifts.
  bool isSettled(double t) {
    if (_ownsTimeline && !_timeline.isEmpty) return false;
    const length = MorphRest.length;
    final scale = MorphRest.scale(math.max(_size.width, _size.height));
    final still =
        _scaleX.isWithin(t, scale) &&
        _scaleY.isWithin(t, scale) &&
        _driftX.isWithin(t, length) &&
        _driftY.isWithin(t, length);
    if (!still || !glows) return still;
    if (_down == null) return _glowOut.isWithin(t, MorphRest.opacity);
    final peak = math.max(_spec.bigGlowOpacity, _spec.littleGlowOpacity);
    return (1 - glow(t)) * peak < MorphRest.opacity &&
        _glowX.isWithin(t, length) &&
        _glowY.isWithin(t, length);
  }

  /// Puts a settled surface onto its targets at time [t]; a held glow
  /// shows at full strength.
  void settle(double t) {
    for (final channel in _channels) {
      channel.snap(t, channel.target);
    }
    if (!glows) return;
    _glowX.settle(t);
    _glowY.settle(t);
    if (_down != null) {
      _glowFrom = 1;
      _glowStart = t;
    } else {
      _glowOut.snap(t, 0);
      _littleScale.settle(t);
    }
  }

  Offset _clamped(Offset p) =>
      Offset(p.dx.clamp(0.0, _size.width), p.dy.clamp(0.0, _size.height));

  /// The targets of UIKit's dynamic flex for a finger on a surface of
  /// [size] with tuning [spec].
  ///
  /// [translation] is the finger's travel since the touch-down,
  /// [inBounds] the same travel with the finger clamped into the surface.
  /// With [lift] both scales start from the lift over the long side L,
  /// `s = (L + liftScalePoints) / L`; with [stretch], along x (y likewise
  /// with H, the scales swapped):
  ///
  /// ```
  /// kx = |it.x| / (4 T) + (|t.x| - |it.x|) / T   (0 when t.x is 0)
  /// sx = s + kx, sy = s - kx, dx = sign(t.x) kx W
  /// ```
  ///
  /// T the spec's stretch threshold. Read from UIKit, notes private.
  static MorphFlexValues dynamicTargets({
    required MorphFlexSpec spec,
    required Size size,
    required Offset translation,
    required Offset inBounds,
    bool lift = true,
    bool stretch = true,
  }) {
    if (size.width <= 0 || size.height <= 0) return rest;
    final s = lift ? spec.liftScaleFor(size) : 1.0;
    var sx = s;
    var sy = s;
    var dx = 0.0;
    var dy = 0.0;
    final threshold = spec.scaleDistanceThreshold;
    if (stretch && threshold > 0) {
      final kx = stretchOf(translation.dx, inBounds.dx, threshold);
      final ky = stretchOf(translation.dy, inBounds.dy, threshold);
      sx += kx - ky;
      sy += ky - kx;
      dx = _sign(translation.dx) * kx * size.width;
      dy = _sign(translation.dy) * ky * size.height;
    }
    return (scaleX: sx, scaleY: sy, driftX: dx, driftY: dy);
  }

  /// The stretch along one axis of a finger that travelled [travel] since
  /// the touch-down, [inBounds] of it inside the surface:
  /// `|it| / (4 T) + (|t| - |it|) / T`, zero without travel.
  static double stretchOf(double travel, double inBounds, double threshold) {
    if (travel == 0) return 0;
    final inside = inBounds.abs();
    return (inBoundsWeight * inside + travel.abs() - inside) / threshold;
  }

  /// The scales movement may take a surface [extent] long to along that
  /// axis: the spec's movement points either way, within its movement
  /// scale bounds. Read from UIKit, notes private.
  static ({double low, double high}) movementBounds(
    MorphFlexSpec spec,
    double extent,
  ) {
    final points = spec.movementScalePoints;
    return (
      low: math.max(spec.movementMinScale, (extent - points) / extent),
      high: math.min(spec.movementMaxScale, (extent + points) / extent),
    );
  }

  /// [value] eased into [low] .. [high]: unchanged inside, and beyond an
  /// end it approaches a third of the range further out, entering at the
  /// slope [softness]. Read from UIKit, notes private; the easing curve is
  /// a hyperbolic tangent (inferred: the library call's name is not
  /// recoverable, its ends and slope are).
  static double softClamp(double value, double low, double high) {
    final margin = (high - low) / 3;
    if (margin <= 0) return value.clamp(low, high);
    if (value > high) {
      return high + margin * _tanh(softness * (value - high) / margin);
    }
    if (value < low) {
      return low + margin * _tanh(softness * (value - low) / margin);
    }
    return value;
  }

  /// [base] with the movement of a surface of [size] added: [acceleration]
  /// is the filtered rate of change of its speed along each axis and
  /// [velocity] its filtered velocity, as the flex integrator reports
  /// them.
  ///
  /// Along x (y likewise, the axes swapped), with m = a.x / N (N the
  /// spec's movement normalization) and the bounds of [movementBounds]:
  ///
  /// ```
  /// Lx = soft(1 + m (hiX - 1)), sx += Lx - 1, sy += soft(1 + m (loY - 1)) - 1
  /// dx += (1 - Lx) W / 2 sign(v.x)
  /// ```
  ///
  /// so a surface speeding up grows along its motion, narrows across it
  /// and its trailing edge lags. Read from UIKit, notes private; the
  /// lens deformation measured on UISegmentedControl and UITabBar follows
  /// the same law with [MorphFlexSpec.loupeForSize].
  static MorphFlexValues withMovement(
    MorphFlexValues base, {
    required MorphFlexSpec spec,
    required Size size,
    required Offset acceleration,
    required Offset velocity,
  }) {
    final n = spec.movementNormalizationFactor;
    final x = movementBounds(spec, size.width);
    final y = movementBounds(spec, size.height);
    var (:scaleX, :scaleY, :driftX, :driftY) = base;
    final mx = acceleration.dx / n;
    if (mx != 0 && !mx.isNaN) {
      final along = softClamp(1 + mx * (x.high - 1), x.low, x.high);
      scaleX += along - 1;
      driftX += (1 - along) * 0.5 * size.width * _sign(velocity.dx);
      scaleY += softClamp(1 + mx * (y.low - 1), y.low, y.high) - 1;
    }
    final my = acceleration.dy / n;
    if (my != 0 && !my.isNaN) {
      final along = softClamp(1 + my * (y.high - 1), y.low, y.high);
      scaleY += along - 1;
      driftY += (1 - along) * 0.5 * size.height * _sign(velocity.dy);
      scaleX += softClamp(1 + my * (x.low - 1), x.low, x.high) - 1;
    }
    return (scaleX: scaleX, scaleY: scaleY, driftX: driftX, driftY: driftY);
  }

  /// The targets of UIKit's menu flex: the stretch an open menu of [size]
  /// takes under a finger and its pulse.
  ///
  /// [translation] is the finger's travel from its touch-down, [inBounds]
  /// its travel clamped into the menu, [velocity] the pulse channel's
  /// velocity (a stepped [MorphChannel]) and [side] +1 for a menu below its
  /// button, -1 above it. Along x (y likewise with H):
  ///
  /// ```
  /// kx = (|t.x| - |it.x| + P |it.x| / W) / T   (0 when t.x is 0)
  /// sx = 1 + kx - ky, sy = 1 - kx + ky
  /// dx = sign(t.x) kx W, dy = sign(t.y) ky H
  /// p = velocity side / pulse normalization
  /// sx *= 1 - pulseX p / W, sy *= 1 + pulseY p / H,
  /// dy += side driftRatio pulseY p
  /// sx, sy clamped to the movement bounds
  /// ```
  ///
  /// T the spec's stretch threshold and P [inBoundsPoints]. Read from
  /// UIKit, notes private.
  static MorphFlexValues menuTargets({
    required MorphFlexSpec spec,
    required double inBoundsPoints,
    required Offset translation,
    required Offset inBounds,
    required Size size,
    required double velocity,
    required double side,
  }) {
    double k(double t, double it, double extent) => t == 0
        ? 0
        : (t.abs() - it.abs() + inBoundsPoints * it.abs() / extent) /
              spec.scaleDistanceThreshold;
    final w = size.width;
    final h = size.height;
    final kx = k(translation.dx, inBounds.dx, w);
    final ky = k(translation.dy, inBounds.dy, h);
    final p = velocity * side / spec.interactionPulseNormalizationFactor;
    final sx = (1 + kx - ky) * (1 - p * spec.interactionPulseScaleX / w);
    final sy = (1 - kx + ky) * (1 + p * spec.interactionPulseScaleY / h);
    return (
      scaleX: sx.clamp(spec.movementMinScale, spec.movementMaxScale),
      scaleY: sy.clamp(spec.movementMinScale, spec.movementMaxScale),
      driftX: translation.dx.sign * kx * w,
      driftY:
          translation.dy.sign * ky * h +
          side *
              spec.interactionPulseDriftRatio *
              spec.interactionPulseScaleY *
              p,
    );
  }

  static double _sign(double x) => x.isNegative ? -1 : 1;

  static double _tanh(double x) {
    final e = math.exp(-2 * x.abs());
    final y = (1 - e) / (1 + e);
    return x.isNegative ? -y : y;
  }
}
