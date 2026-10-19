// The test paints shadows through the renderer's own caster.
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';
import 'package:morph/src/glass/renderer/renderer.dart';

/// A box that paints [shadows] for [shape] around [child] through
/// [GlassShadowCaster], the way a liquid glass shape paints its own.
class GlassShadowBox extends SingleChildRenderObjectWidget {
  /// Paints [shadows] for [shape] at [appearanceVisibility].
  const GlassShadowBox({
    required this.shape,
    required this.shadows,
    this.appearanceVisibility = 1,
    super.child,
    super.key,
  });

  /// The shape to paint shadows for.
  final LiquidShape shape;

  /// The shadows.
  final List<BoxShadow> shadows;

  /// The materialization progress the shadows fade with.
  final double appearanceVisibility;

  @override
  RenderGlassShadowBox createRenderObject(BuildContext context) =>
      RenderGlassShadowBox(
        shape: shape,
        shadows: shadows,
        visibility: appearanceVisibility,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassShadowBox renderObject,
  ) {
    renderObject.shape = shape;
    renderObject.shadows = shadows;
    renderObject.visibility = appearanceVisibility;
  }
}

/// The render object of a [GlassShadowBox].
class RenderGlassShadowBox extends RenderProxyBox with GlassShadowCaster {
  /// Paints [shadows] for [shape] at [visibility].
  RenderGlassShadowBox({
    required this._shape,
    required this._shadows,
    required double visibility,
  }) : _visibility = visibility.clamp(0, 1);

  @override
  LiquidShape get shape => _shape;
  LiquidShape _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  @override
  List<BoxShadow> get shadows => _shadows;
  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (_shadows == value) return;
    _shadows = value;
    markNeedsPaint();
  }

  /// The materialization progress.
  double get visibility => _visibility;
  double _visibility;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = value.clamp(0, 1);
    markNeedsPaint();
  }

  @override
  double get shadowVisibility => _visibility;

  @override
  void paint(PaintingContext context, Offset offset) {
    paintShadows(context, offset);
    super.paint(context, offset);
  }
}
