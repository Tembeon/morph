import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/glass_live.dart';
import 'package:morph/src/glass/renderer/renderer.dart';

/// Conservative pixel support of Flutter's Gaussian shadow mask.
///
/// [BoxShadow.blurRadius] is converted to sigma before rasterization. Reserving
/// only the radius clips the low-energy tail, especially when the shadow is
/// painted into a bounded saveLayer before translucent glass.
@internal
double glassShadowBlurSupport(double blurRadius) =>
    Shadow.convertRadiusToSigma(blurRadius) * 3;

/// Paints [BoxShadow]s for a [LiquidShape] using canvas primitives
/// (drawRRect, drawCircle, drawRSuperellipse, etc.) instead of drawPath.
///
/// This avoids the cost of rasterizing an arbitrary [Path] with a blur
/// [MaskFilter], which is significantly slower than the dedicated GPU-
/// accelerated primitives that Impeller/Skia provide for simple shapes.
@internal
class GlassShadow extends SingleChildRenderObjectWidget {
  /// Creates a new [GlassShadow] widget with the given [shape], [shadows], and
  /// optional [child].
  const GlassShadow({
    required this.shape,
    required this.shadows,
    required this.settings,
    this.appearanceVisibility = 1,
    super.child,
    super.key,
  }) : live = null,
       shapeOf = null,
       shadowsOf = null,
       visibilityOf = null;

  /// Creates shadows whose shape, list and visibility follow [live]: every
  /// notification writes them into the render object.
  GlassShadow.live({
    required this.live,
    required LiquidShape Function() this.shapeOf,
    required List<BoxShadow> Function() this.shadowsOf,
    required double Function() this.visibilityOf,
    required this.settings,
    super.child,
    super.key,
  }) : shape = shapeOf(),
       shadows = shadowsOf(),
       appearanceVisibility = visibilityOf();

  /// The source of live shadows, or null for fixed ones.
  final Listenable? live;

  /// The shape now, for live shadows.
  final LiquidShape Function()? shapeOf;

  /// The shadows now, for live shadows.
  final List<BoxShadow> Function()? shadowsOf;

  /// The visibility now, for live shadows.
  final double Function()? visibilityOf;

  void _applyLive(_RenderGlassShadow shadow) {
    shadow.shape = shapeOf!();
    shadow.shadows = shadowsOf!();
    shadow.visibility = visibilityOf!();
  }

  /// The shape to paint shadows for.
  final LiquidShape shape;

  final LiquidGlassSettings settings;

  /// Per-shape materialization progress.
  final double appearanceVisibility;

  /// The list of shadows to paint.
  ///
  /// Only outer-equivalent shadows are supported; [BoxShadow.blurStyle] is
  /// ignored. When any shadow has a non-zero [BoxShadow.offset], the
  /// shadows are clipped to outside the glass shape so they do not bleed
  /// through the translucent glass body.
  final List<BoxShadow> shadows;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final shadow = _RenderGlassShadow(
      shape: shape,
      shadows: shadows,
      visibility: appearanceVisibility,
    );
    if (shapeOf != null) shadow.bindLive(live, () => _applyLive(shadow));
    return shadow;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    // ignore: library_private_types_in_public_api
    _RenderGlassShadow renderObject,
  ) {
    if (shapeOf != null) {
      renderObject.bindLive(live, () => _applyLive(renderObject));
      return;
    }
    renderObject
      ..shape = shape
      ..shadows = shadows
      ..visibility = appearanceVisibility;
  }
}

class _RenderGlassShadow extends RenderProxyBox with GlassLiveBinding {
  _RenderGlassShadow({
    required this._shape,
    required this._shadows,
    required double visibility,
  }) : _visibility = visibility.clamp(0, 1);

  LiquidShape get shape => _shape;
  LiquidShape _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  List<BoxShadow> get shadows => _shadows;
  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (_shadows == value) return;
    _shadows = value;
    markNeedsPaint();
  }

  double get visibility => _visibility;
  double _visibility = 1;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = value.clamp(0, 1);
    markNeedsPaint();
  }

  @override
  Rect get paintBounds {
    var bounds = super.paintBounds;
    if (visibility <= 0 || shadows.isEmpty) return bounds;

    final shapeBounds = Offset.zero & size;
    for (final shadow in shadows) {
      // Report the same conservative Gaussian support used by paint()'s
      // saveLayer. Without this, Flutter culls the blurred pixels outside the
      // render box and different blur radii collapse to the same hard ring.
      final extent = math
          .max(
            shadow.spreadRadius +
                glassShadowBlurSupport(shadow.blurRadius * visibility),
            0,
          )
          .toDouble();
      bounds = bounds.expandToInclude(
        shapeBounds.shift(shadow.offset).inflate(extent),
      );
    }
    return bounds;
  }

  // What paint draws, in local coordinates, for the size, shape, shadows
  // and visibility it was made for: built once and translated to the
  // paint offset, so a shadow that only moves rebuilds no path.
  _ShadowPlan? _plan;

  _ShadowPlan _planFor(Size size) {
    final plan = _plan;
    if (plan != null &&
        plan.size == size &&
        plan.shape == shape &&
        listEquals(plan.shadows, shadows) &&
        plan.visibility == visibility) {
      return plan;
    }
    final rect = Offset.zero & size;
    final needsCutout = shadows.any((s) => s.offset != Offset.zero);
    Path? outside;
    if (needsCutout) {
      var bounds = rect;
      for (final shadow in shadows) {
        bounds = bounds.expandToInclude(
          rect
              .shift(shadow.offset)
              .inflate(
                shadow.spreadRadius +
                    glassShadowBlurSupport(shadow.blurRadius * visibility),
              ),
        );
      }
      outside = Path();
      outside.fillType = PathFillType.evenOdd;
      outside.addRect(bounds.inflate(1));
      _addShape(outside, rect.deflate(.5));
    }
    return _plan = _ShadowPlan(
      size: size,
      shape: shape,
      shadows: shadows,
      visibility: visibility,
      outside: outside,
      draws: [
        for (final shadow in shadows)
          (
            rect.shift(shadow.offset).inflate(shadow.spreadRadius),
            shadow
                .copyWith(
                  blurRadius: shadow.blurRadius * visibility,
                  blurStyle: needsCutout ? BlurStyle.normal : BlurStyle.outer,
                  color: shadow.color.withValues(
                    alpha: shadow.color.a * visibility,
                  ),
                )
                .toPaint(),
          ),
      ],
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (shadows.isNotEmpty) {
      final plan = _planFor(size);
      final canvas = context.canvas;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      final outside = plan.outside;
      if (outside != null) canvas.clipPath(outside);
      for (final (rect, paint) in plan.draws) {
        _drawShape(canvas, rect, paint);
      }
      canvas.restore();
    }

    super.paint(context, offset);
  }

  void _addShape(Path path, Rect rect) {
    switch (shape) {
      case LiquidRoundedSuperellipse(:final borderRadius):
        path.addRSuperellipse(
          RSuperellipse.fromRectAndRadius(rect, Radius.circular(borderRadius)),
        );
      case LiquidOval():
        path.addOval(rect);
      case LiquidRoundedRectangle(:final borderRadius):
        path.addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
        );
    }
  }

  void _drawShape(Canvas canvas, Rect rect, Paint paint) {
    switch (shape) {
      case LiquidRoundedSuperellipse(:final borderRadius):
        canvas.drawRSuperellipse(
          RSuperellipse.fromRectAndRadius(rect, Radius.circular(borderRadius)),
          paint,
        );
      case LiquidOval():
        canvas.drawOval(rect, paint);
      case LiquidRoundedRectangle(:final borderRadius):
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
          paint,
        );
    }
  }
}

class _ShadowPlan {
  _ShadowPlan({
    required this.size,
    required this.shape,
    required this.shadows,
    required this.visibility,
    required this.outside,
    required this.draws,
  });

  final Size size;
  final LiquidShape shape;
  final List<BoxShadow> shadows;
  final double visibility;

  // The region outside the glass the shadows are clipped to, or null when
  // no shadow is offset.
  final Path? outside;

  final List<(Rect, Paint)> draws;
}
