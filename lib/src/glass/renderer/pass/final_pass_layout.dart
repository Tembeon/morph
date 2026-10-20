import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/liquid_glass_glow.dart';

/// The float indices of the final shader's uniforms, in the order
/// shaders/liquid_glass_final_render_core.glsl and
/// shaders/analytic_geometry.glsl declare them.
///
/// Every final variant declares the core block, so a uniform sits at the
/// same index in each; only the analytic variants declare the block from
/// [analytic], and only some of them its tails ([fusedBoxes], [tints],
/// [fusedTints]). test/final_pass_layout_test.dart reads the GLSL and fails
/// when a declaration moves without this table.
@internal
abstract final class FinalPassLayout {
  /// uSize: the size in device pixels of the texture the pass reads.
  static const int size = 0;

  /// uGeometryOffset: the matte's origin in device pixels.
  static const int geometryOffset = 2;

  /// uGeometrySize: the matte's size in device pixels.
  static const int geometrySize = 4;

  /// uTint, the first float of the block the settings and the appearance
  /// fill, through uAppearanceConfig.
  static const int tint = 6;

  /// The material center in matte device pixels, the middle two floats of
  /// uProfileConfig.
  static const int materialCenter = 34;

  /// uFilterToMatteBasis: the 2x2 basis from fragment to matte pixels.
  static const int filterToMatteBasis = 47;

  /// uFilterToMatteOffset: the fragment-to-matte offset.
  static const int filterToMatteOffset = 51;

  /// uBlurFade: 1 while a blur, in a pass or in the shader, frosts the
  /// glass.
  static const int blurFade = 53;

  /// uSoften: the shader frost's sigma plus 2, 1 for the softening kernel,
  /// 0 for neither.
  static const int soften = 54;

  /// uBackdropBounds: the device rect the backdrop is captured for.
  static const int backdropBounds = 55;

  /// uGeometryUVScale: the matte's share of its texture.
  static const int geometryUVScale = 59;

  /// uMaterialTextureSize: the material map's size in texels.
  static const int materialTextureSize = 61;

  /// uBackdropShrinkAxis: half the line the backdrop shrinks about.
  static const int backdropShrinkAxis = 63;

  /// uSolidBackdrop, element 0 of uSolidBackdropGlow: the declared or
  /// overlaid backdrop color, zero to read the backdrop.
  static const int solidBackdrop = 65;

  /// uGlowSpot, uGlowBox and uGlowShape, elements 1 to 3 of
  /// uSolidBackdropGlow.
  static const int glow = solidBackdrop + 4;

  /// uAnalyticHeader: the optics vec4, then the ranges vec4.
  static const int analytic = glow + LiquidGlassGlow.floatCount;

  /// The most shapes an analytic variant evaluates; ANALYTIC_MAX_SHAPES in
  /// shaders/analytic_geometry.glsl.
  static const int analyticMaxShapes = 8;

  /// uShapeData: 3 vec4 per shape.
  static const int shapeData = analytic + 8;

  /// uRseData: 3 vec4 per shape, then the bottom halves of pairs, 3 vec4
  /// per shape from [rseLower].
  static const int rseData = shapeData + analyticMaxShapes * 12;

  /// The bottom halves of uRseData.
  static const int rseLower = rseData + analyticMaxShapes * 12;

  /// uShapeBounds: one vec4 of bounds per shape.
  static const int shapeBounds = rseLower + analyticMaxShapes * 12;

  /// The cull factors, the tail of uShapeBounds: one float per shape.
  static const int shapeCull = shapeBounds + analyticMaxShapes * 4;

  /// uAnalyticFlatFace.
  static const int flatFace = shapeCull + analyticMaxShapes;

  /// uFusedBoxes: 2 vec4 per merged box; only the fused variants declare
  /// it.
  static const int fusedBoxes = flatFace + 1;

  /// uShapeTints of the separate-shape tint variants.
  static const int tints = flatFace + 1;

  /// uShapeTints of the fused tint variants, after uFusedBoxes.
  static const int fusedTints = fusedBoxes + GlassBoxField.maxBoxes * 8;

  /// uFusedBoxes of the tint-only matte variants (shaders/fused_tint.glsl),
  /// after the core block, where the analytic variants declare theirs.
  static const int matteFusedBoxes = analytic;

  /// uFusedTints of the tint-only matte variants: each fused box's tint.
  static const int matteFusedTints =
      matteFusedBoxes + GlassBoxField.maxBoxes * 8;

  /// uFusedTintBoxes of the tint-only matte variants: the fused boxes, 0
  /// for separate shapes, which read the material map.
  static const int matteFusedTintBoxes =
      matteFusedTints + GlassBoxField.maxBoxes * 4;
}
