import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/geometry/glass_shape_pack.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/internal/raster_phase.dart';
import 'package:morph/src/glass/renderer/internal/render_liquid_glass_geometry.dart';
import 'package:morph/src/glass/renderer/internal/rounded_superellipse_parameters.dart';
import 'package:morph/src/glass/renderer/internal/snap_rect_to_pixels.dart';
import 'package:morph/src/glass/renderer/pass/final_pass.dart';
import 'package:morph/src/glass/renderer/pass/final_pass_layout.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/liquid_field.dart' show liquidMinMergeWidth;

/// One geometry frame of a glass layer: its shapes evaluated in the final
/// shader, or encoded into a matte.
@internal
sealed class GlassGeometry {
  const GlassGeometry({
    required this.matteBounds,
    required this.materialCenter,
    required this.materialSize,
    required this.textureSize,
    required this.appearances,
  });

  /// Where the matte (or the analytic frame's culling rect) lies, in the
  /// layer's logical pixels.
  final Rect matteBounds;

  /// The center of the glass in the matte, in logical pixels.
  final Offset materialCenter;

  /// The size of the glass, in logical pixels.
  final Size materialSize;

  /// The matte texture's size in the layer's own device pixels.
  final Size textureSize;

  /// The appearances of the frame's shapes, in paint order.
  final List<LiquidGlassAppearance> appearances;
}

/// A frame whose shapes the final shader evaluates from the layer's
/// [GlassShapePack]: no matte, material map or field upload.
@internal
final class AnalyticGeometry extends GlassGeometry {
  /// An analytic frame.
  const AnalyticGeometry({
    required super.matteBounds,
    required super.materialCenter,
    required super.materialSize,
    required super.textureSize,
    required super.appearances,
  });
}

/// A frame encoded into a matte (and a material map for mixed
/// appearances).
///
/// The images borrow the renderer's handles: a frame kept across another
/// render clones both before that render can dispose them.
@internal
final class MatteGeometry extends GlassGeometry {
  /// A matte frame.
  const MatteGeometry({
    required super.matteBounds,
    required super.materialCenter,
    required super.materialSize,
    required super.textureSize,
    required super.appearances,
    required this.image,
    required this.material,
    required this.materialTextureSize,
  });

  /// The matte.
  final ui.Image image;

  /// The material map, or null for one appearance.
  final ui.Image? material;

  /// The material map's size in texels.
  final Size materialTextureSize;
}

/// What a [GlassGeometryEncoder] reads from the layer whose shapes it
/// encodes.
@internal
abstract interface class GlassGeometrySource {
  /// The Flutter GPU renderer of the matte passes.
  FlutterGpuGeometryRenderer? get gpuGeometryRenderer;

  /// The layer's settings.
  LiquidGlassSettings get settings;

  /// The layer's device pixel ratio.
  double get devicePixelRatio;

  /// The appearance of shapes without one of their own.
  LiquidGlassAppearance get defaultAppearance;

  /// The fused body's field, or null to shade the shapes.
  GlassField? get field;
}

/// The switches of one encode that the analytic policy owns.
typedef GlassEncodeFlags = ({
  bool analyticEnabled,
  bool resting,
  bool capsule,
  bool flatFace,
});

/// Encodes a glass layer's shapes into a geometry frame: the analytic
/// eligibility, the packed shapes, the matte and its raster grid.
///
/// The matte is in the layer's local coordinates, its texels nearest
/// sampled (it packs 12-bit normal angle and displacement codes across byte
/// boundaries). Off the pixel grid each shape is moved onto the grid of its
/// own layer ([glassRasterPhaseShift]); under a scale of its pass along
/// its axes within [glassMatteDensityRange] a matte without a material map
/// is encoded at the pass's pixels ([glassMatteDensity]). An analytic frame
/// has neither: its shapes are evaluated where they are.
@internal
final class GlassGeometryEncoder {
  /// Encodes [_source]'s shapes for [_pass].
  GlassGeometryEncoder(this._source, this._pass);

  final GlassGeometrySource _source;
  final GlassFinalPass _pass;

  /// The shapes of the latest frame, read by the geometry pass and, in an
  /// analytic frame, by the final shader.
  final GlassShapePack pack = GlassShapePack();

  /// The largest geometry, in device pixels of its bounds, an analytic
  /// frame shades: per-pixel shape evaluation costs in proportion to the
  /// area, and a screen-high surface (a sheet, about 2 million device
  /// pixels on a Moto g86) cost more GPU time analytically than its matte
  /// (sheet raster p99 +9 ms there), while bars and buttons (under 0.3
  /// million) gain. Larger geometry renders its matte.
  static const double analyticMaxPixels = 600000;

  /// Overrides [analyticMaxPixels] when not null, for oracles that shade
  /// large scenes analytically on purpose.
  @visibleForTesting
  static double? debugAnalyticMaxPixels;

  static final Matrix4 _identity = Matrix4.identity();

  /// Shorter side in logical pixels of the smallest shape of the latest
  /// frame. Adaptive color models use it to choose the material density;
  /// it is resolved once per geometry frame, never per fragment.
  double materialShortSide = 10000;

  /// Geometry frames rendered as a matte, counted so a texture release
  /// waits for a run of analytic frames without one.
  int matteBuilds = 0;

  /// Why the latest frame was not analytic, or null when it was.
  String? analyticIneligibility;

  // The pass phase the matte was encoded at when it shifts shapes onto
  // their own raster grids or moves its grid off a tie; null when it does
  // neither.
  Offset? _encodedPassPhase;

  // The matte texels per device pixel of the layer the matte was encoded
  // at, and whether it follows the pass's scale ([glassMatteDensity]): a
  // frame with a material map keeps the layer's own device pixels.
  ({double x, double y}) _encodedMatteDensity = glassUnitMatteDensity;
  bool _matteDensityFollows = false;

  /// The pass phase the latest matte was encoded at, or null when its
  /// encoding does not depend on it.
  Offset? get encodedPassPhase => _encodedPassPhase;

  /// The matte texels per device pixel of the layer, along x and y, the
  /// latest matte was encoded at ([glassMatteDensity]).
  ({double x, double y}) get matteDensity => _encodedMatteDensity;

  /// How far antialiasing reaches past a shape's contour, in logical
  /// pixels.
  static double contourOutset(
    LiquidGlassSettings settings,
    double devicePixelRatio,
  ) {
    if (settings.contourWidth <= 0) return 0;
    return max(
      0.5 / devicePixelRatio,
      settings.contourWidth + 1.0 / devicePixelRatio,
    );
  }

  /// The affine basis a shape maps into its layer by, or null for a
  /// degenerate one: the encoder's drawable-shape decision.
  static ({Offset axisX, Offset axisY, double determinant})? shapeBasis(
    Matrix4 geometryToLayer,
    Matrix4? shapeToGeometry,
  ) {
    final toGeometry = shapeToGeometry ?? _identity;
    Offset toMatte(Offset point) => MatrixUtils.transformPoint(
      geometryToLayer,
      MatrixUtils.transformPoint(toGeometry, point),
    );
    final origin = toMatte(Offset.zero);
    final axisX = toMatte(const Offset(1, 0)) - origin;
    final axisY = toMatte(const Offset(0, 1)) - origin;
    final determinant = axisX.dx * axisY.dy - axisY.dx * axisX.dy;
    if (determinant.abs() < 1e-8) return null;
    return (axisX: axisX, axisY: axisY, determinant: determinant);
  }

  /// Half-extents along the matte axes of a shape with local half-size
  /// [halfSize] mapped by the affine basis ([axisX], [axisY]). The geometry
  /// shader culls with these boxes instead of mapping every pixel into each
  /// shape's local space. Ellipses and rounded rectangles are exact;
  /// continuous corners extend further into the corner than a circular arc of
  /// the same radius, so they use their box.
  static Size _matteHalfExtents(
    RawShapeType type,
    Size halfSize,
    double cornerRadius,
    Offset axisX,
    Offset axisY,
  ) {
    double extent(double x, double y) {
      switch (type) {
        case RawShapeType.ellipse:
          return sqrt(pow(x * halfSize.width, 2) + pow(y * halfSize.height, 2));
        case RawShapeType.roundedRectangle:
          final radius = min(cornerRadius, halfSize.shortestSide);
          return x.abs() * (halfSize.width - radius) +
              y.abs() * (halfSize.height - radius) +
              radius * sqrt(x * x + y * y);
        case RawShapeType.squircle || RawShapeType.squirclePair:
          return x.abs() * halfSize.width + y.abs() * halfSize.height;
      }
    }

    return Size(extent(axisX.dx, axisY.dx), extent(axisX.dy, axisY.dy));
  }

  // [rect] grown to the pixel grid of the pass [layerToPass] maps this
  // layer into by a scale along its axes: a matte of [density] texels per
  // device pixel over it centers every texel on a pixel of the pass, so a
  // nearest sample reads the texel encoded at that pixel's center.
  Rect _onPassPixels(
    Rect rect,
    Matrix4 layerToPass,
    ({double x, double y}) density,
  ) {
    final devicePixelRatio = _source.devicePixelRatio;
    final m = layerToPass.storage;
    final passX = m[12] * devicePixelRatio;
    final passY = m[13] * devicePixelRatio;
    final scaleX = devicePixelRatio * density.x;
    final scaleY = devicePixelRatio * density.y;
    double down(double v, double scale, double pass) =>
        ((v * scale + pass).floorToDouble() - pass) / scale;
    double up(double v, double scale, double pass) =>
        ((v * scale + pass).ceilToDouble() - pass) / scale;
    return Rect.fromLTRB(
      down(rect.left, scaleX, passX),
      down(rect.top, scaleY, passY),
      up(rect.right, scaleX, passX),
      up(rect.bottom, scaleY, passY),
    );
  }

  Offset _passPhase(Matrix4 layerToPass) {
    final devicePixelRatio = _source.devicePixelRatio;
    final origin = MatrixUtils.transformPoint(layerToPass, Offset.zero);
    return Offset(
      glassRasterPhase(origin.dx * devicePixelRatio),
      glassRasterPhase(origin.dy * devicePixelRatio),
    );
  }

  /// Whether the latest matte, encoded for another pass phase, would be
  /// encoded differently under [layerToPass]: its shifts moved, a matte
  /// encoded on the layer's own grid now falls within the tie band, or the
  /// pass's scale moved off the matte's density. Never for an analytic
  /// frame, which has no raster grid.
  bool rasterGridStale(Matrix4 layerToPass, {required bool analytic}) {
    if (analytic) return false;
    if (_matteDensityFollows &&
        glassMatteDensity(layerToPass) != _encodedMatteDensity) {
      return true;
    }
    if (_encodedPassPhase case final phase?) {
      return _passPhase(layerToPass) != phase;
    }
    if (_source.field != null) return false;
    return glassRasterGrid(layerToPass, _source.devicePixelRatio)?.biased ??
        false;
  }

  /// Why shapes cannot be evaluated in the final shader, or null when they
  /// can: analytic geometry is [enabled], the layer has no fused field
  /// ([hasField]) or one of at most [GlassBoxField.maxBoxes] merged boxes
  /// ([fusedBoxes], 0 for a sampled field), there are at most
  /// [FinalPassLayout.analyticMaxShapes] shapes, no geometry of two or more
  /// shapes blends them, the appearances are one or differ only by tint
  /// (against [fallback] when there are none), and the analytic shaders are
  /// ready ([shadersReady]).
  ///
  /// [geometries] holds each geometry's blend and its shapes' appearances.
  @visibleForTesting
  static String? analyticIneligibilityOf({
    required bool enabled,
    required bool hasField,
    required bool Function() shadersReady,
    required Iterable<(double, Iterable<LiquidGlassAppearance>)> geometries,
    required LiquidGlassAppearance fallback,
    int fusedBoxes = 0,
  }) {
    if (!enabled) return 'disabled';
    if (hasField) {
      if (fusedBoxes == 0) return 'fused field';
      if (fusedBoxes > GlassBoxField.maxBoxes) {
        return 'more than ${GlassBoxField.maxBoxes} fused boxes';
      }
    }
    final appearances = <LiquidGlassAppearance>[];
    for (final (blend, shapes) in geometries) {
      final start = appearances.length;
      for (final appearance in shapes) {
        if (appearances.length == FinalPassLayout.analyticMaxShapes) {
          return 'more than ${FinalPassLayout.analyticMaxShapes} shapes';
        }
        appearances.add(appearance);
      }
      if (blend != 0 && appearances.length - start > 1) return 'blend group';
    }
    final (mixed, tintOnly, _) = classifyGlassAppearances(
      appearances,
      fallback,
    );
    if (mixed && !tintOnly) return 'mixed appearances';
    if (!shadersReady()) return 'shaders not loaded';
    return null;
  }

  String? _ineligibility(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds,
    GlassEncodeFlags flags,
  ) {
    if (!flags.analyticEnabled) return 'disabled';
    if (flags.resting) return 'resting';
    final devicePixelRatio = _source.devicePixelRatio;
    final pixels =
        bounds.width * bounds.height * devicePixelRatio * devicePixelRatio;
    if (pixels > (debugAnalyticMaxPixels ?? analyticMaxPixels)) {
      return 'larger than analyticMaxPixels';
    }
    final field = _source.field;
    return analyticIneligibilityOf(
      enabled: true,
      hasField: field != null,
      fusedBoxes: switch (field) {
        GlassBoxField(:final boxes) => boxes.length,
        _ => 0,
      },
      shadersReady: () =>
          _pass.analyticShadersReady(fused: field is GlassBoxField),
      geometries: [
        for (final (_, geometry, _) in geometries)
          (
            geometry.blend,
            [for (final shape in geometry.shapes) shape.appearance],
          ),
      ],
      fallback: _source.defaultAppearance,
    );
  }

  List<double> _appearanceLookupData(List<LiquidGlassAppearance> appearances) {
    // This is used only for mixed frames; unused lookup rows must not depend
    // on the owner's active (possibly different) uniform frame.
    final fallback = _source.defaultAppearance;
    LiquidGlassAppearance at(int index) =>
        index < appearances.length ? appearances[index] : fallback;
    return <double>[
      for (
        var i = 0;
        i < FlutterGpuGeometryRenderer.maxShapes;
        i++
      ) ...<double>[at(i).tint.r, at(i).tint.g, at(i).tint.b, at(i).tint.a],
      for (
        var i = 0;
        i < FlutterGpuGeometryRenderer.maxShapes;
        i++
      ) ...<double>[
        at(i).saturation / 4,
        at(i).transmissionGamma / 4,
        at(i).vibrancy / 4,
        (at(i).visibility + at(i).colorModel.shaderValue * 2) / 7,
      ],
    ];
  }

  /// Encodes [geometries] within [bounds] of [layer], whose pass maps it by
  /// [layerToPass].
  GlassGeometry encode(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds, {
    required RenderObject layer,
    required Matrix4 layerToPass,
    required GlassEncodeFlags flags,
  }) {
    final renderer = _source.gpuGeometryRenderer;
    if (renderer == null) {
      throw StateError(
        'Flutter GPU is required for LiquidGlass. Enable it in the platform '
        'manifest or with --enable-flutter-gpu.',
      );
    }
    final settings = _source.settings;
    final devicePixelRatio = _source.devicePixelRatio;
    final defaultAppearance = _source.defaultAppearance;
    final field = _source.field;

    try {
      // Centered SDF antialiasing needs half a physical pixel outside the
      // mathematical shape. Keep that margin in the persistent geometry
      // texture so the positive side of the fade is not clipped at the matte
      // edge.
      final ineligibility = _ineligibility(geometries, bounds, flags);
      analyticIneligibility = ineligibility;
      final analytic = ineligibility == null;
      // A matte under a scale is encoded at the pass's pixels, so its
      // nearest samples read one texel per pixel; every position and
      // distance it holds stays in the layer's own device pixels, the
      // units the final pass reads. A material map keeps the layer's own
      // device pixels.
      final follows =
          !analytic && !_mixesAppearances(geometries, defaultAppearance);
      final density = follows
          ? glassMatteDensity(layerToPass)
          : glassUnitMatteDensity;
      final dense = density != glassUnitMatteDensity;
      _encodedMatteDensity = density;
      _matteDensityFollows = follows;
      // Analytic shapes are evaluated where they are: no matte grid to
      // move or to shift them onto.
      final grid = analytic
          ? null
          : glassRasterGrid(
              layerToPass,
              devicePixelRatio,
              movable: field == null,
            );
      final shifts = [
        for (final (owner, _, _) in geometries)
          grid == null
              ? Offset.zero
              : glassRasterPhaseShift(layer, owner, grid, devicePixelRatio),
      ];
      final biased = grid?.biased ?? false;
      final anchored = shifts.any((Offset shift) => shift != Offset.zero);
      // A matte under a scale centers its texels on the pass's pixels,
      // which moves with the pass phase.
      _encodedPassPhase = anchored || biased || dense
          ? _passPhase(layerToPass)
          : null;
      final aaPadding = max(
        0.5 / devicePixelRatio,
        contourOutset(settings, devicePixelRatio),
      );
      final shiftPadding = anchored ? 0.5 / devicePixelRatio : 0.0;
      // The matte is in this layer's local coordinates. Ancestor transforms
      // are applied once by the compositor; baking them in would apply scale
      // and rotation twice.
      final snapped = bounds
          .inflate(aaPadding + shiftPadding)
          .snapToPixels(devicePixelRatio);
      final boundsInMatteSpace = dense
          ? _onPassPixels(snapped, layerToPass, density)
          : biased
          ? snapped.shift(grid!.bias / devicePixelRatio)
          : snapped;
      final materialCenter = bounds.center;

      final textureWidth =
          (boundsInMatteSpace.width * devicePixelRatio * density.x).ceil();
      final textureHeight =
          (boundsInMatteSpace.height * devicePixelRatio * density.y).ceil();

      if (textureWidth <= 0 || textureHeight <= 0) {
        throw StateError('Cannot render empty liquid-glass geometry.');
      }

      // Gather shapes in cache order. A negative blend marker starts a new
      // group; this preserves smooth unions within a group without blending
      // unrelated standalone glass widgets together.
      // The analytic frame reads these lists; it ends with them.
      final pack = this.pack;
      pack.clear();
      final appearances = <LiquidGlassAppearance>[];
      var numShapes = 0;
      var shortSide = double.infinity;

      for (final (index, (_, geometry, geometryToLayer))
          in geometries.indexed) {
        final shift = shifts[index];
        var firstInGroup = true;
        for (final shape in geometry.shapes) {
          if (numShapes >= FlutterGpuGeometryRenderer.maxShapes) break;

          final shapeToGeometry = shape.shapeToGeometry ?? _identity;
          final basis = shapeBasis(geometryToLayer, shapeToGeometry);
          if (basis == null) continue;
          final (:axisX, :axisY, :determinant) = basis;

          // Inverse 2D affine basis maps matte-space physical pixels back to
          // the shape's own physical-pixel coordinate system.
          final inverse00 = axisY.dy / determinant;
          final inverse01 = -axisY.dx / determinant;
          final inverse10 = -axisX.dy / determinant;
          final inverse11 = axisX.dx / determinant;

          // The minimum singular value conservatively converts local SDF
          // distances back to screen pixels under non-uniform scaling.
          final trace =
              axisX.dx * axisX.dx +
              axisX.dy * axisX.dy +
              axisY.dx * axisY.dx +
              axisY.dy * axisY.dy;
          final discriminant = max(
            0,
            trace * trace - 4 * determinant * determinant,
          );
          final distanceScale = sqrt(
            max(0.0, (trace - sqrt(discriminant)) * 0.5),
          );
          // The analytic shader's lower bound of the shape's distance from
          // its box distance: the scaled distance can fall below the true
          // one by the singular values' ratio, and the corner solvers'
          // Chebyshev branches by up to sqrt 2.
          final largest = sqrt(max(0.0, (trace + sqrt(discriminant)) * 0.5));
          pack.cullData.add(
            largest > 0 ? distanceScale / largest * sqrt1_2 : 0,
          );

          final centerInGeometry = MatrixUtils.transformPoint(
            shapeToGeometry,
            Offset(
              shape.renderObject.size.width / 2,
              shape.renderObject.size.height / 2,
            ),
          );
          final centerInLayer = MatrixUtils.transformPoint(
            geometryToLayer,
            centerInGeometry,
          );
          final centerInMatte = centerInLayer + shift;

          // The inverse affine basis above already maps matte coordinates back
          // into the shape's local coordinate system. Using the transformed
          // AABB here would apply scale a second time (and turn rotations into
          // oversized primitives), which is especially visible for stretched
          // shapes in a blend group.
          final size = shape.renderObject.size;
          // An analytic frame may shade a full-radius superellipse as the
          // stadium of its box (an approximation, see
          // ShaderKeys.analyticCapsule).
          final capsule =
              analytic &&
              flags.capsule &&
              shape.rawShapeType == RawShapeType.squircle &&
              shape.rawCornerRadius >= size.shortestSide / 2;
          final pair = shape.rawShapeType == RawShapeType.squirclePair;
          final rseParameters = pair
              ? roundedSuperellipsePairParameters(
                  size,
                  shape.rawCornerRadius,
                  shape.rawBottomRadius,
                  scale: devicePixelRatio,
                )
              : roundedSuperellipseParameters(
                  size,
                  shape.rawCornerRadius,
                  scale: devicePixelRatio,
                );
          // The geometry shader tests each cap's angular span as
          // 1 - cos(span).
          for (final at in pair ? const [0, 12] : const [0]) {
            rseParameters[at + 2] = 1.0 - cos(rseParameters[at + 2]);
            rseParameters[at + 3] = 1.0 - cos(rseParameters[at + 3]);
          }
          pack.rseData.addAll(rseParameters.sublist(0, 12));
          if (pair) pack.pairCount++;
          pack.rseLowerData.addAll(
            pair ? rseParameters.sublist(12) : GlassShapePack.noLowerHalf,
          );
          final center = centerInMatte * devicePixelRatio;
          final halfExtents = _matteHalfExtents(
            shape.rawShapeType,
            size * devicePixelRatio / 2,
            shape.rawCornerRadius * devicePixelRatio,
            axisX,
            axisY,
          );
          pack.boundsData.add(center.dx - halfExtents.width);
          pack.boundsData.add(center.dy - halfExtents.height);
          pack.boundsData.add(center.dx + halfExtents.width);
          pack.boundsData.add(center.dy + halfExtents.height);
          final blendMarker = firstInGroup
              ? -(geometry.blend * devicePixelRatio + 1)
              : geometry.blend * devicePixelRatio;

          final shapeData = pack.shapeData;
          // vec4 0: primitive parameters.
          shapeData.add(
            shape.appearance.visibility <= 0
                ? 0
                : capsule
                ? RawShapeType.roundedRectangle.shaderIndex
                : shape.rawShapeType.shaderIndex,
          );
          shapeData.add(size.width * devicePixelRatio);
          shapeData.add(size.height * devicePixelRatio);
          shapeData.add(
            (capsule ? size.shortestSide / 2 : shape.rawCornerRadius) *
                devicePixelRatio,
          );
          // vec4 1: inverse affine basis.
          shapeData.add(inverse00);
          shapeData.add(inverse01);
          shapeData.add(inverse10);
          shapeData.add(inverse11);
          // vec4 2: transformed center, distance scale, group marker.
          shapeData.add(centerInMatte.dx * devicePixelRatio);
          shapeData.add(centerInMatte.dy * devicePixelRatio);
          shapeData.add(distanceScale);
          shapeData.add(blendMarker);
          appearances.add(shape.appearance);
          shortSide = min(shortSide, size.shortestSide);
          numShapes++;
          firstInGroup = false;
        }
      }

      if (numShapes == 0) {
        throw StateError('No invertible liquid-glass shapes to render.');
      }
      if (shortSide != materialShortSide) {
        materialShortSide = shortSide;
        _pass.updateSettings();
      }
      final (usesShapeAppearances, usesTintOnlyAppearance, _) =
          classifyGlassAppearances(appearances, defaultAppearance);

      if (analytic) {
        pack.refractionHeight = max(
          0.0,
          settings.effectiveRefractionHeight * devicePixelRatio,
        );
        pack.refractionAmount = max(
          1e-3,
          settings.effectiveRefractionAmount * devicePixelRatio,
        );
        pack.fitsShape = settings.refractionFitsShape;
        pack.contourExtent = max(0.5, aaPadding * devicePixelRatio);
        pack.flatFace = flags.flatFace;
        pack.mergeMinWidth = liquidMinMergeWidth * devicePixelRatio;
        pack.shapeCount = numShapes;
        pack.boxCount = 0;
        pack.spacing = 0;
        if (field case GlassBoxField(:final boxes, :final spacing)) {
          final scale = devicePixelRatio;
          final out = pack.boxes;
          for (final (i, box) in boxes.indexed) {
            final hx = box.width / 2;
            final hy = box.height / 2;
            final at = i * 8;
            out[at] = box.center.dx * scale;
            out[at + 1] = box.center.dy * scale;
            out[at + 2] = hx * scale;
            out[at + 3] = hy * scale;
            out[at + 4] = min(box.tlRadiusX, min(hx, hy)) * scale;
          }
          pack.boxCount = boxes.length;
          pack.spacing = spacing * scale;
        }
        pack.tints.clear();
        if (usesTintOnlyAppearance) {
          for (final appearance in appearances) {
            final tint = appearance.tint;
            pack.tints.addAll([tint.r, tint.g, tint.b, tint.a]);
          }
        }
        _pass.markInputsChanged();
        return AnalyticGeometry(
          materialCenter: materialCenter,
          materialSize: bounds.size,
          textureSize: Size(textureWidth.toDouble(), textureHeight.toDouble()),
          appearances: appearances,
          matteBounds: Rect.fromLTWH(
            boundsInMatteSpace.left,
            boundsInMatteSpace.top,
            textureWidth / devicePixelRatio,
            textureHeight / devicePixelRatio,
          ),
        );
      }

      matteBuilds++;
      final result = renderer.render(
        width: textureWidth,
        height: textureHeight,
        shapeData: pack.shapeData,
        rseData: pack.rseData,
        rseLowerData: pack.pairCount > 0 ? pack.rseLowerData : const [],
        boundsData: pack.boundsData,
        numShapes: numShapes,
        refractionHeight: settings.effectiveRefractionHeight * devicePixelRatio,
        refractionAmount: settings.effectiveRefractionAmount * devicePixelRatio,
        edgeDistanceRange:
            settings.effectiveEdgeDistanceRange * devicePixelRatio,
        refractionFitsShape: settings.refractionFitsShape,
        contourExtent: aaPadding * devicePixelRatio,
        writeMaterials: usesShapeAppearances,
        writeTintOnly: usesTintOnlyAppearance,
        appearanceData: usesShapeAppearances
            ? _appearanceLookupData(appearances)
            : const <double>[],
        offsetX: boundsInMatteSpace.left * devicePixelRatio,
        offsetY: boundsInMatteSpace.top * devicePixelRatio,
        field: field,
        fieldScale: devicePixelRatio,
        mergeMinWidth: liquidMinMergeWidth,
        matteDensity: density,
      );
      final material = renderer.materialImage;
      return MatteGeometry(
        image: result.image,
        material: material,
        materialCenter: materialCenter,
        materialSize: bounds.size,
        // In the layer's own device pixels, as the final pass maps them.
        textureSize: Size(
          result.textureWidth / density.x,
          result.textureHeight / density.y,
        ),
        materialTextureSize: switch (material) {
          final image? => Size(image.width.toDouble(), image.height.toDouble()),
          null => const Size(1, 1),
        },
        appearances: appearances,
        matteBounds: Rect.fromLTWH(
          boundsInMatteSpace.left,
          boundsInMatteSpace.top,
          result.width / (devicePixelRatio * density.x),
          result.height / (devicePixelRatio * density.y),
        ),
      );
    } catch (e) {
      throw StateError('Flutter GPU geometry render failed: $e');
    }
  }
}

// Whether the shapes of [geometries] differ in appearance, so that a matte
// frame of them writes a material map.
bool _mixesAppearances(
  List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  LiquidGlassAppearance fallback,
) {
  final (mixed, _, _) = classifyGlassAppearances([
    for (final (_, geometry, _) in geometries)
      for (final shape in geometry.shapes) shape.appearance,
  ], fallback);
  return mixed;
}
