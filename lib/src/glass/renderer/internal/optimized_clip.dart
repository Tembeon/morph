import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/glass_live.dart';
import 'package:morph/src/glass/renderer/liquid_shape.dart';

/// Clips its child using the given [shape].
///
/// Compared to using [ClipPath] directly, this widget uses Impeller's
/// specialized clip layers for ovals, rounded rects, and superellipses.
///
/// If [shape] is null or [clipBehavior] is [Clip.none], no clipping is applied.
@internal
class OptimizedClip extends StatelessWidget {
  const OptimizedClip({
    required this.shape,
    required this.child,
    this.clipBehavior = Clip.antiAlias,
    this.outset = 0,
    super.key,
  });

  final ShapeBorder? shape;

  final Clip clipBehavior;

  /// Extra room outside the widget bounds retained by the clip.
  final double outset;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (clipBehavior == Clip.none) {
      return child;
    }
    final shape = this.shape;
    if (shape != null && outset > 0) {
      return ClipPath(
        clipBehavior: clipBehavior,
        clipper: _OutsetShapeBorderClipper(shape: shape, outset: outset),
        child: child,
      );
    }
    return switch (shape) {
      null => child,
      LiquidRoundedSuperellipse(:final borderRadius) => ClipRSuperellipse(
        clipBehavior: clipBehavior,
        borderRadius: BorderRadius.circular(borderRadius),
        child: child,
      ),
      LiquidRoundedRectangle(:final borderRadius) => ClipRRect(
        clipBehavior: clipBehavior,
        borderRadius: BorderRadius.circular(borderRadius),
        child: child,
      ),
      LiquidOval() => ClipOval(clipBehavior: clipBehavior, child: child),
      RoundedSuperellipseBorder(:final borderRadius) => ClipRSuperellipse(
        clipBehavior: clipBehavior,
        borderRadius: borderRadius,
        child: child,
      ),
      RoundedRectangleBorder(:final borderRadius) => ClipRRect(
        clipBehavior: clipBehavior,
        borderRadius: borderRadius,
        child: child,
      ),
      OvalBorder() => ClipOval(clipBehavior: clipBehavior, child: child),
      LinearBorder() => ClipRect(clipBehavior: clipBehavior, child: child),
      _ => ClipPath(
        clipBehavior: clipBehavior,
        clipper: ShapeBorderClipper(shape: shape),
        child: child,
      ),
    };
  }
}

class _OutsetShapeBorderClipper extends CustomClipper<Path> {
  const _OutsetShapeBorderClipper({required this.shape, required this.outset});

  final ShapeBorder shape;
  final double outset;

  @override
  Path getClip(Size size) =>
      shape.getOuterPath((Offset.zero & size).inflate(outset));

  @override
  bool shouldReclip(covariant _OutsetShapeBorderClipper oldClipper) =>
      oldClipper.shape != shape || oldClipper.outset != outset;
}

/// An [OptimizedClip] for a liquid shape that follows a live source: the
/// same clip widget the current shape picks, its radius read again on
/// every notification of [live].
///
/// The kind of shape (oval, rounded rectangle, rounded superellipse) is
/// read once per build; an owner whose shape changes kind rebuilds it.
@internal
class GlassLiveShapeClip extends StatelessWidget {
  /// Clips [child] to [shapeOf].
  const GlassLiveShapeClip({
    required this.live,
    required this.shapeOf,
    required this.child,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  /// The source of the shape.
  final Listenable? live;

  /// The shape now.
  final LiquidShape Function() shapeOf;

  /// How the clip is antialiased; [Clip.none] does not clip.
  final Clip clipBehavior;

  /// The clipped subtree.
  final Widget child;

  BorderRadiusGeometry _radius() => switch (shapeOf()) {
    LiquidRoundedSuperellipse(:final borderRadius) ||
    LiquidRoundedRectangle(
      :final borderRadius,
    ) => BorderRadius.circular(borderRadius),
    LiquidOval() => BorderRadius.zero,
  };

  @override
  Widget build(BuildContext context) {
    if (clipBehavior == Clip.none) return child;
    return switch (shapeOf()) {
      LiquidRoundedSuperellipse() => GlassLiveClipRSuperellipse(
        live: live,
        borderRadiusOf: _radius,
        clipBehavior: clipBehavior,
        child: child,
      ),
      LiquidRoundedRectangle() => GlassLiveClipRRect(
        live: live,
        borderRadiusOf: _radius,
        clipBehavior: clipBehavior,
        child: child,
      ),
      LiquidOval() => ClipOval(clipBehavior: clipBehavior, child: child),
    };
  }
}
