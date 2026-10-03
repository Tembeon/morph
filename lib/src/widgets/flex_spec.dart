import 'dart:ui';

import 'package:morph/src/spring.dart';

/// The deformation tuning of a glass surface that responds to touch.
///
/// UIKit keeps one set of these values per size class and derives the set
/// for a concrete surface from its size: [MorphFlexSpec.forSize] for
/// controls, selection lenses and buttons, [MorphFlexSpec.loupeForSize]
/// for magnifying loupes such as a slider thumb. Lengths are in logical
/// pixels and are absolute, not proportional to the surface.
class MorphFlexSpec {
  /// Creates a flex spec from explicit values.
  const MorphFlexSpec({
    required this.liftScalePoints,
    required this.scaleDistanceThreshold,
    required this.movementNormalizationFactor,
    required this.movementScalePoints,
    required this.movementMinScale,
    required this.movementMaxScale,
    required this.scaleSpring,
    required this.trackingSpring,
    this.interactionPulseNormalizationFactor = 1,
    this.interactionPulseScaleX = 0,
    this.interactionPulseScaleY = 0,
    this.interactionPulseDriftRatio = 0,
    this.littleGlowOpacity = 0,
    this.bigGlowOpacity = 0,
  });

  /// How many pixels the surface grows in each dimension while pressed.
  final double liftScalePoints;

  /// The squared-distance scale over which a drag stretches the surface.
  final double scaleDistanceThreshold;

  /// The divisor that normalizes movement before it becomes deformation.
  final double movementNormalizationFactor;

  /// The deformation, in pixels, produced by a normalized unit of movement.
  final double movementScalePoints;

  /// The smallest scale movement may squash the surface to.
  final double movementMinScale;

  /// The largest scale movement may stretch the surface to.
  final double movementMaxScale;

  /// The spring that carries the deformation once the finger lets go.
  final MorphSpring scaleSpring;

  /// The spring that carries the deformation while the finger is down.
  final MorphSpring trackingSpring;

  /// The divisor that normalizes an interaction pulse.
  final double interactionPulseNormalizationFactor;

  /// The horizontal size of an interaction pulse, in pixels.
  final double interactionPulseScaleX;

  /// The vertical size of an interaction pulse, in pixels.
  final double interactionPulseScaleY;

  /// How far an interaction pulse drifts toward the touch, as a ratio.
  final double interactionPulseDriftRatio;

  /// The opacity of the small touch glow.
  final double littleGlowOpacity;

  /// The opacity of the large touch glow.
  final double bigGlowOpacity;

  /// The class for surfaces narrower than [compactWidthLimit].
  static const ultraSmall = MorphFlexSpec(
    liftScalePoints: 16,
    scaleDistanceThreshold: 2000,
    movementNormalizationFactor: 10000,
    movementScalePoints: 10,
    movementMinScale: 0.9,
    movementMaxScale: 1.1,
    scaleSpring: MorphSpring(0.4, 0.375),
    trackingSpring: MorphSpring(0.262, 0.625),
    littleGlowOpacity: 1,
    bigGlowOpacity: 1,
  );

  /// The small end of the interpolated range, anchored at 44 pixels.
  static const small = MorphFlexSpec(
    liftScalePoints: 16,
    scaleDistanceThreshold: 6000,
    movementNormalizationFactor: 10000,
    movementScalePoints: 10,
    movementMinScale: 0.9,
    movementMaxScale: 1.1,
    scaleSpring: MorphSpring(0.4, 0.375),
    trackingSpring: MorphSpring(0.262, 0.625),
    littleGlowOpacity: 0.3,
    bigGlowOpacity: 1,
  );

  /// The large end of the interpolated range, anchored at 160 pixels.
  static const large = MorphFlexSpec(
    liftScalePoints: 4,
    scaleDistanceThreshold: 24000,
    movementNormalizationFactor: 10000,
    movementScalePoints: 5,
    movementMinScale: 0.9,
    movementMaxScale: 1.1,
    scaleSpring: MorphSpring(0.36, 0.6),
    trackingSpring: MorphSpring(0.314, 0.625),
    littleGlowOpacity: 0.2,
  );

  /// The spec of a button that opens a menu.
  static const menu = MorphFlexSpec(
    liftScalePoints: 0,
    scaleDistanceThreshold: 6000,
    movementNormalizationFactor: 10000,
    movementScalePoints: 5,
    movementMinScale: 0.9,
    movementMaxScale: 1.1,
    scaleSpring: MorphSpring(0.6, 0.5),
    trackingSpring: MorphSpring(0.15, 0.5),
    interactionPulseNormalizationFactor: 8000,
    interactionPulseScaleX: 50,
    interactionPulseScaleY: 32,
    interactionPulseDriftRatio: 0.7,
    littleGlowOpacity: 0.5,
  );

  /// The large end of the loupe range, anchored at 70 pixels.
  static const loupe = MorphFlexSpec(
    liftScalePoints: 0,
    scaleDistanceThreshold: 0,
    movementNormalizationFactor: 2500,
    movementScalePoints: 100,
    movementMinScale: 0.75,
    movementMaxScale: 1.15,
    scaleSpring: MorphSpring(0.5, 1),
    trackingSpring: MorphSpring(0.5, 0.9),
  );

  /// The small end of the loupe range, anchored at 37 pixels.
  static const smallLoupe = MorphFlexSpec(
    liftScalePoints: 0,
    scaleDistanceThreshold: 6000,
    movementNormalizationFactor: 2000,
    movementScalePoints: 10,
    movementMinScale: 0.9,
    movementMaxScale: 1.1,
    scaleSpring: MorphSpring(0.444, 0.56),
    trackingSpring: MorphSpring(0.444, 0.56),
  );

  /// Surfaces narrower than this use [ultraSmall] whatever their height.
  static const double compactWidthLimit = 120;

  /// The dimension [small] is anchored at.
  static const double smallDimension = 44;

  /// The dimension [large] is anchored at.
  static const double largeDimension = 160;

  /// The dimension [smallLoupe] is anchored at.
  static const double smallLoupeDimension = 37;

  /// The dimension [loupe] is anchored at.
  static const double loupeDimension = 70;

  /// The spec UIKit derives for a touch-responsive surface of [size].
  ///
  /// Below [compactWidthLimit] the surface uses [ultraSmall]. From there
  /// on the spec blends [small] into [large] along two independent
  /// axes: the springs follow the width and the sizes (lift, stretch
  /// threshold, glow) follow the height, both over the 44 to 160 range.
  /// The movement scale stays at the small value.
  static MorphFlexSpec forSize(Size size) {
    if (size.width < compactWidthLimit) return ultraSmall;
    final tw = _unit(size.width, smallDimension, largeDimension);
    final th = _unit(size.height, smallDimension, largeDimension);
    return MorphFlexSpec(
      liftScalePoints: _lerp(small.liftScalePoints, large.liftScalePoints, th),
      scaleDistanceThreshold: _lerp(
        small.scaleDistanceThreshold,
        large.scaleDistanceThreshold,
        th,
      ),
      movementNormalizationFactor: _lerp(
        small.movementNormalizationFactor,
        large.movementNormalizationFactor,
        th,
      ),
      movementScalePoints: small.movementScalePoints,
      movementMinScale: small.movementMinScale,
      movementMaxScale: small.movementMaxScale,
      scaleSpring: MorphSpring.lerp(small.scaleSpring, large.scaleSpring, tw),
      trackingSpring: MorphSpring.lerp(
        small.trackingSpring,
        large.trackingSpring,
        tw,
      ),
      littleGlowOpacity: _lerp(
        small.littleGlowOpacity,
        large.littleGlowOpacity,
        th,
      ),
      bigGlowOpacity: _lerp(small.bigGlowOpacity, large.bigGlowOpacity, th),
    );
  }

  /// The spec UIKit derives for a magnifying loupe of [size].
  ///
  /// Every value blends [smallLoupe] into [loupe] by the height over the
  /// 37 to 70 range.
  static MorphFlexSpec loupeForSize(Size size) {
    final t = _unit(size.height, smallLoupeDimension, loupeDimension);
    const a = smallLoupe;
    const b = loupe;
    return MorphFlexSpec(
      liftScalePoints: 0,
      scaleDistanceThreshold: 0,
      movementNormalizationFactor: _lerp(
        a.movementNormalizationFactor,
        b.movementNormalizationFactor,
        t,
      ),
      movementScalePoints: _lerp(
        a.movementScalePoints,
        b.movementScalePoints,
        t,
      ),
      movementMinScale: _lerp(a.movementMinScale, b.movementMinScale, t),
      movementMaxScale: _lerp(a.movementMaxScale, b.movementMaxScale, t),
      scaleSpring: MorphSpring.lerp(a.scaleSpring, b.scaleSpring, t),
      trackingSpring: MorphSpring.lerp(a.trackingSpring, b.trackingSpring, t),
    );
  }

  static double _unit(double value, double from, double to) =>
      ((value - from) / (to - from)).clamp(0.0, 1.0);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
