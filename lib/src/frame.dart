import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// An immutable snapshot of all render values for one flight frame.
///
/// The system-wide invariant: every property is a PURE SYMMETRIC
/// function of the spring value. No direction- or time-dependent curves:
/// only then is an interruption (a retarget at any point) continuous for
/// all properties at once, by construction.
@immutable
class MorphFrame {
  /// Bundles the render values of one frame.
  const MorphFrame({
    required this.rect,
    required this.shape,
    required this.cornerRadius,
    required this.sourceOpacity,
    required this.targetOpacity,
    required this.targetScale,
    required this.scrimOpacity,
    required this.elevation,
    required this.surfaceColor,
  });

  /// The container rect in overlay coordinates.
  final Rect rect;

  /// The container outline for this frame.
  final ShapeBorder shape;

  /// The derived corner radius when both shapes can be expressed by one;
  /// null when falling back to ShapeBorder.lerp.
  final double? cornerRadius;

  /// Opacity of the source ghost (fades out early in the flight).
  final double sourceOpacity;

  /// Opacity of the target content (fades in after the source).
  final double targetOpacity;

  /// Scale of the target content while it fades in.
  final double targetScale;

  /// Scrim opacity for this frame.
  final double scrimOpacity;

  /// Container shadow for this frame.
  final double elevation;

  /// Container fill for this frame.
  final Color surfaceColor;
}

/// The content crossfade is a fast, early sub-range of the overall
/// progress (Material's fade-through split: outgoing 0-30%, incoming
/// 30-100%) but strictly symmetric: Material's direction-dependent
/// thresholds would break continuity on a mid-flight reversal.
// Both fades HOLD at their home end, but the source hold is SHORT
// (0.05): a spring dwells near zero, so the hold covers exactly the
// settle tail where the container still matches the button - the true
// content shows, no washed-out replica. Past it the source dissolves
// BEFORE the container's aspect diverges from the button's: with a
// wide pill flying into a tall dialog the rect is +85% taller by
// p=0.10 already, and fully opaque button content inside that box
// reads as a second surface. The target holds from 0.90 (its box has
// the target's own aspect long before that). The unreadable midstate
// around the swap stays unshown, as before.
const Interval _sourceFade = Interval(0.05, 0.30, curve: Curves.easeOut);
const Interval _targetFade = Interval(0.35, 0.90, curve: Curves.easeOut);
// The color cross sits in the MIDDLE band, which both directions
// traverse fast: a spring dwells at its ends, so a cross placed near
// either end plays in slow motion exactly where the eye rests. Below
// 0.30 the surface is fully the SOURCE color - on close the container
// is button-colored before the whole visible landing phase begins
// (and the source content, gone by 0.30, never sits on a foreign
// surface); by 0.55 it is fully the target's, under the arriving
// target content.
const Interval _surfaceBlend = Interval(0.30, 0.55);
const Interval _scrimFade = Interval(0, 0.7);

/// The geometric core of one flight frame: the rect plus the raw
/// endpoint radii when the shapes reduce to a single corner. ONE
/// implementation serves both renderings of a flight - the shuttle
/// frame and the liquid mirror blob - so the two can never drift apart.
///
/// Geometry rides the raw spring value: position and size share one
/// clock - a "position leads" split is not supported by platform
/// references. Beyond the travel range (gesture overdrag past `[0, 1]`)
/// the morph ONLY shifts along its trajectory and does not stretch:
/// the center extrapolates while size and shape freeze at the edge -
/// like an iOS sheet that hits its limit and rides with the finger
/// instead of inflating.
({Rect rect, double? sourceRadius, double? targetRadius}) morphFlightGeometry({
  required double value,
  required Rect sourceRect,
  required Rect targetRect,
  required ShapeBorder sourceShape,
  required ShapeBorder targetShape,
}) {
  final double p = clampDouble(value, 0, 1);
  final Offset center = Offset.lerp(
    sourceRect.center,
    targetRect.center,
    value,
  )!;
  final Size size = Size.lerp(sourceRect.size, targetRect.size, p)!;
  return (
    rect: .fromCenter(
      center: center,
      width: math.max(0, size.width),
      height: math.max(0, size.height),
    ),
    sourceRadius: uniformMorphRadius(sourceShape, sourceRect.size),
    targetRadius: uniformMorphRadius(targetShape, targetRect.size),
  );
}

/// The concentric-corners radius of a frame: the endpoint radii lerped
/// by progress and capped by half the shortest side of the CURRENT
/// rect - a capsule-to-rectangle morph resolves through the container's
/// own growth and structurally cannot lag behind it.
double morphConcentricRadius(
  double sourceRadius,
  double targetRadius,
  double progress,
  Rect rect,
) {
  return clampDouble(
    lerpDouble(sourceRadius, targetRadius, progress)!,
    0,
    rect.shortestSide / 2,
  );
}

/// Computes every render value of a flight frame from one spring
/// [value] - the whole visual contract in a single pure function.
MorphFrame computeMorphFrame({
  required double value,
  required Rect sourceRect,
  required Rect targetRect,
  required ShapeBorder sourceShape,
  required ShapeBorder targetShape,
  required Color sourceColor,
  required Color targetColor,
  required double maxScrimOpacity,
  double sourceElevation = 0,
  double targetElevation = 24,
}) {
  final double p = clampDouble(value, 0, 1);

  final ({Rect rect, double? sourceRadius, double? targetRadius}) geometry =
      morphFlightGeometry(
        value: value,
        sourceRect: sourceRect,
        targetRect: targetRect,
        sourceShape: sourceShape,
        targetShape: targetShape,
      );
  final Rect rect = geometry.rect;

  final double targetReveal = _targetFade.transform(p);

  double? cornerRadius;
  ShapeBorder shape;
  if (geometry.sourceRadius == null || geometry.targetRadius == null) {
    shape = ShapeBorder.lerp(sourceShape, targetShape, p) ?? targetShape;
  } else {
    cornerRadius = morphConcentricRadius(
      geometry.sourceRadius!,
      geometry.targetRadius!,
      p,
      rect,
    );
    shape = _shapeFromRadius(sourceShape, targetShape, cornerRadius);
  }

  return MorphFrame(
    rect: rect,
    shape: shape,
    cornerRadius: cornerRadius,
    sourceOpacity: 1 - _sourceFade.transform(p),
    targetOpacity: targetReveal,
    targetScale: lerpDouble(0.95, 1, targetReveal)!,
    scrimOpacity: maxScrimOpacity * _scrimFade.transform(p),
    // The shadow belongs to the morphing container (the Material
    // container-transform guideline): the shuttle starts with exactly
    // the button's shadow and grows it continuously into the container
    // one - no shadow pop when the tag hides or at handoff. The lerp
    // rides p^1.5, not p: linear shadow reads as a hover near the
    // source end (a button-sized container carrying a quarter of the
    // dialog's elevation floats a layer above its resting self, and a
    // slow profile makes that a scene), while too-flat a curve starves
    // the middle of the "card" cue - a big surface with a button's
    // shadow reads as the button deformed, not a dialog materializing.
    // p^1.5 keeps the settle tail at the button's own shadow and gives
    // the mid-flight surface its card depth; symmetric, still a pure
    // function of the value.
    elevation: lerpDouble(sourceElevation, targetElevation, p * math.sqrt(p))!,
    surfaceColor: Color.lerp(
      sourceColor,
      targetColor,
      _surfaceBlend.transform(p),
    )!,
  );
}

/// The landing bump: one set of formulas for every consumer (the
/// MorphTag content transform and the liquid-skin rect deformation).
/// Full-wave: it lives on the FULL spring value - a dip below zero gives
/// squash along the impact axis, a slight stretch across it, and a
/// recoil kick; the return into positive plays the reverse. A degenerate
/// axis falls back to vertical.
({double scaleX, double scaleY, Offset kick}) morphLandingBump({
  required double value,
  required Offset impactAxis,
  required double bumpScale,
  required double bumpRecoil,
}) {
  final Offset axis = impactAxis.distance < 1 ? const Offset(0, 1) : impactAxis;
  final bool vertical = axis.dy.abs() >= axis.dx.abs();
  final double along = 1 + value * bumpScale;
  final double across = 1 - value * bumpScale * 0.45;
  final Offset unit = axis / axis.distance;
  return (
    scaleX: vertical ? across : along,
    scaleY: vertical ? along : across,
    kick: unit * (-value * bumpRecoil),
  );
}

/// The same bump applied to geometry: the rect squashes and kicks around
/// its own center. For consumers whose mass IS the visual (the liquid
/// skin) a transform is not an option.
Rect morphBumpedRect(
  Rect rect, {
  required double value,
  required Offset impactAxis,
  required double bumpScale,
  required double bumpRecoil,
}) {
  final ({double scaleX, double scaleY, Offset kick}) bump = morphLandingBump(
    value: value,
    impactAxis: impactAxis,
    bumpScale: bumpScale,
    bumpRecoil: bumpRecoil,
  );
  return .fromCenter(
    center: rect.center + bump.kick,
    width: rect.width * bump.scaleX,
    height: rect.height * bump.scaleY,
  );
}

/// The corner radius is not interpolated as a shape; it is derived from
/// live geometry (the "concentric corners" model): the target radius is
/// lerped but always capped by half the shortest side. Stadium and
/// Circle are just a radius sitting on that cap, so a "capsule ->
/// rectangle" morph is resolved by the container's own growth and
/// structurally cannot lag behind it.
ShapeBorder _shapeFromRadius(
  ShapeBorder sourceShape,
  ShapeBorder targetShape,
  double radius,
) {
  if (targetShape is RoundedSuperellipseBorder ||
      sourceShape is RoundedSuperellipseBorder) {
    return RoundedSuperellipseBorder(borderRadius: .circular(radius));
  }
  return RoundedRectangleBorder(borderRadius: .circular(radius));
}

/// The single radius of a shape when it can be expressed by one (Circle,
/// Stadium, rrect/superellipse with equal corners); null for exotic
/// shapes.
double? uniformMorphRadius(ShapeBorder shape, Size size) {
  if (shape is CircleBorder || shape is StadiumBorder) {
    return size.shortestSide / 2;
  }
  if (shape is RoundedRectangleBorder) {
    return _uniformCorner(shape.borderRadius, size);
  }
  if (shape is RoundedSuperellipseBorder) {
    return _uniformCorner(shape.borderRadius, size);
  }
  return null;
}

double? _uniformCorner(BorderRadiusGeometry geometry, Size size) {
  final BorderRadius resolved = geometry.resolve(.ltr);
  final Radius corner = resolved.topLeft;
  final bool uniform =
      corner.x == corner.y &&
      resolved.topRight == corner &&
      resolved.bottomLeft == corner &&
      resolved.bottomRight == corner;
  return uniform ? math.min(corner.x, size.shortestSide / 2) : null;
}
