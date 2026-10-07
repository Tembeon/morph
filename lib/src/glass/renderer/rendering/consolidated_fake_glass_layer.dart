import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_capture_debug.dart';
import 'package:morph/src/glass/renderer/internal/fake_glass_color.dart';
import 'package:morph/src/glass/renderer/internal/glass_live.dart';
import 'package:morph/src/glass/renderer/internal/paint_fake_glass_surface.dart';
import 'package:morph/src/glass/renderer/internal/render_liquid_glass_geometry.dart';
import 'package:morph/src/glass/renderer/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_render_object.dart';

enum _FakeGlassPaintStage { shadows, backdrop, surfaces, contents }

@internal
class ConsolidatedFakeGlassLayer extends SingleChildRenderObjectWidget {
  const ConsolidatedFakeGlassLayer({
    required this.link,
    required this.settingsOf,
    required this.defaultAppearance,
    required this.backdropKey,
    required this.surfaceShader,
    required super.child,
    this.live,
    this.outlineOf,
    super.key,
  });

  /// The source of live settings and outline, or null for fixed ones.
  final Listenable? live;

  /// The outline of the one body the layer's shapes fused into, in the
  /// layer's coordinates, which the backdrop and surfaces are clipped to.
  final Path? Function()? outlineOf;

  final GeometryRenderLink link;

  /// The settings now.
  final LiquidGlassSettings Function() settingsOf;
  final LiquidGlassAppearance defaultAppearance;
  final BackdropKey? backdropKey;
  final FragmentShader? surfaceShader;

  void _apply(RenderConsolidatedFakeGlassLayer layer) {
    layer.settings = settingsOf();
    layer.outline = outlineOf?.call();
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    final layer = RenderConsolidatedFakeGlassLayer(
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
      link: link,
      settings: settingsOf(),
      defaultAppearance: defaultAppearance,
      backdropKey: backdropKey,
      surfaceShader: surfaceShader,
      outline: outlineOf?.call(),
    );
    layer.bindLive(live, () => _apply(layer));
    return layer;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConsolidatedFakeGlassLayer renderObject,
  ) {
    renderObject.devicePixelRatio =
        MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    renderObject.link = link;
    renderObject.defaultAppearance = defaultAppearance;
    renderObject.backdropKey = backdropKey;
    renderObject.surfaceShader = surfaceShader;
    renderObject.bindLive(live, () => _apply(renderObject));
  }
}

/// The fake glass layer: paints a clipped backdrop blur plus the surface
/// shader for the shared shape geometry. All shared machinery - shape
/// registration, transform and compositor-translation polling, retained
/// ancestor clips, shadows, bounds and the frame state - lives in
/// [LiquidGlassRenderObject]; this class implements only the effect.
@visibleForTesting
@internal
class RenderConsolidatedFakeGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin, GlassLiveBinding
    implements LiquidGlassLayerRenderObject {
  RenderConsolidatedFakeGlassLayer({
    required super.devicePixelRatio,
    required super.link,
    required super.settings,
    required super.defaultAppearance,
    required super.backdropKey,
    required this._surfaceShader,
    this._outline,
  });

  Path? _outline;

  /// The fused body's outline (morph local patch): with it the backdrop
  /// and the surfaces are clipped to the body, its neck tinted like its
  /// first shape, instead of drawn per shape.
  Path? get outline => _outline;
  set outline(Path? value) {
    if (identical(_outline, value)) return;
    _outline = value;
    markNeedsPaint();
  }

  FragmentShader? _surfaceShader;
  FragmentShader? get surfaceShader => _surfaceShader;

  @visibleForTesting
  FragmentShader? get debugSurfaceShader => _surfaceShader;
  set surfaceShader(FragmentShader? value) {
    if (identical(_surfaceShader, value)) return;
    _surfaceShader = value;
    markNeedsPaint();
  }

  final _backdropLayer = LayerHandle<BackdropFilterLayer>();
  final _clipLayer = LayerHandle<ClipPathLayer>();

  /// Capture shared by this layer's own backdrop filters when the user did
  /// not provide a [backdropKey] or [BackdropGroup]. Without it, a
  /// separately served shape would sample the shared filter's output in
  /// overlapping pixels and compound both transfers; sharing one capture
  /// also collapses their backdrop readbacks into one.
  final _ownBackdropKey = BackdropKey();

  BackdropKey get _effectiveBackdropKey => backdropKey ?? _ownBackdropKey;

  /// Per-shape backdrop passes for shapes the shared union clip cannot
  /// serve: shapes that are fading (0 < visibility < 1) or whose appearance
  /// needs a different backdrop transfer than the layer's. They sit between
  /// the shared opaque-shape filter and the surfaces so a fading shape keeps
  /// its own clipped backdrop filter instead of swapping its widget subtree.
  final Map<LiquidGlassShapeRenderObject, _SeparateBackdropLayers>
  _separateBackdropLayers = {};
  ImageFilter? _cachedFilter;

  /// Shorter side of the smallest shape sharing the consolidated filter.
  double _shortSide = 10000;
  Path? _cachedClipPath;
  Path? _lastBackdropClipPath;
  Rect? _cachedClipBounds;
  List<int> _cachedClipClasses = const [];
  bool _repaintAfterCompositingScheduled = false;

  bool get _hasBlur => settings.effectiveFrost > 0;
  bool get _hasColorTransfer =>
      defaultAppearance.saturation != 1 ||
      defaultAppearance.transmissionGamma != 1 ||
      defaultAppearance.colorModel.faceTransfer(_shortSide) != null;
  bool get _hasBackdropEffect => _hasBlur || _hasColorTransfer;

  /// Whether [appearance] can be served by the layer's shared backdrop
  /// filter - that is, it differs from [defaultAppearance] only in fields
  /// the surface pass and opacity handle (tint, vibrancy, visibility).
  bool _sharesLayerBackdrop(LiquidGlassAppearance appearance) =>
      appearance.saturation == defaultAppearance.saturation &&
      appearance.transmissionGamma == defaultAppearance.transmissionGamma &&
      appearance.colorModel == defaultAppearance.colorModel;

  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _backdropLayer.layer;

  /// The retained per-shape clipped backdrop passes, keyed by shape.
  @visibleForTesting
  Iterable<BackdropFilterLayer> get debugSeparateBackdropLayers =>
      _separateBackdropLayers.values
          .map((layers) => layers.backdrop.layer)
          .nonNulls;

  @visibleForTesting
  Rect? debugClipBounds;

  @visibleForTesting
  Path? get debugClipPath => _lastBackdropClipPath;

  final List<_FakeGlassPaintStage> _debugLastPaintStages = [];

  @visibleForTesting
  List<String> get debugLastPaintStages =>
      _debugLastPaintStages.map((stage) => stage.name).toList(growable: false);

  // MARK: Retained frame hooks

  // The fake effect encodes no matte, so a fully-hidden frame retains
  // nothing that must stay compositor-only.
  @override
  GlassFrameState get hiddenFrameState => GlassFrameState.empty;

  // Without a matte, every shape is drawable.
  @override
  bool hasDrawableGlass(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => true;

  @override
  bool isSnapshotCurrent(
    RenderLiquidGlassGeometry geometry,
    GeometryCache snapshot,
  ) => geometry.hasCurrentGeometryCache(snapshot);

  @override
  double get materialOutset => fakeGlassSurfaceOutset(settings);

  // One extra logical pixel covers the kernel's rounding at any DPR.
  @override
  double effectSamplingReach(Rect material) =>
      _hasBlur ? settings.effectiveFrost * 3 + 1 : 0.0;

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    _cachedFilter = null;
    markNeedsCompositingBitsUpdate();
  }

  @override
  void onAppearanceChanged() {
    _cachedFilter = null;
    markNeedsCompositingBitsUpdate();
  }

  // MARK: Painting

  @override
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    assert(() {
      _debugLastPaintStages.clear();
      return true;
    }(), 'Reset paint-order diagnostics.');
    if (frameState == GlassFrameState.empty && shapesWithGeometry.isEmpty) {
      debugClipBounds = null;
      effectPaintBounds = Offset.zero & size;
      _clearClipCache();
      clearFrameInputs();
      _releaseLayers();
      return;
    }

    if (!_clipInputsMatch()) {
      Rect? rebuiltBounds;
      var rebuiltShortSide = double.infinity;
      final rebuiltPath = Path();
      final rebuiltClasses = <int>[];
      for (final (_, geometry, transform) in shapesWithGeometry) {
        for (final shape in geometry.shapes) {
          final backdropClass = _backdropClass(shape.appearance);
          rebuiltClasses.add(backdropClass);
          if (backdropClass == 0) continue;
          final shapeToLayer = shape.shapeToGeometry == null
              ? transform
              : transform.multiplied(shape.shapeToGeometry!);
          final shapeBounds = Offset.zero & shape.renderObject.size;
          final transformedBounds = MatrixUtils.transformRect(
            shapeToLayer,
            shapeBounds,
          );
          rebuiltBounds =
              rebuiltBounds?.expandToInclude(transformedBounds) ??
              transformedBounds;
          // The shared union clip covers only fully visible shapes whose
          // backdrop transfer matches the layer's; every other visible shape
          // gets its own clipped pass below.
          if (backdropClass == 2) {
            rebuiltShortSide = math.min(
              rebuiltShortSide,
              shape.renderObject.size.shortestSide,
            );
            rebuiltPath.addPath(
              shape.shape.getOuterPath(shapeBounds),
              Offset.zero,
              matrix4: shapeToLayer.storage,
            );
          }
        }
      }
      if (rebuiltShortSide != _shortSide) {
        _shortSide = rebuiltShortSide;
        _cachedFilter = null;
      }
      _cachedClipPath = rebuiltPath;
      _cachedClipBounds = rebuiltBounds;
      _cachedClipClasses = rebuiltClasses;
      rememberFrameInputs();
    }
    final outline = _outline;
    final bounds = outline == null
        ? _cachedClipBounds
        : _cachedClipBounds?.expandToInclude(outline.getBounds());
    if (bounds == null) {
      debugClipBounds = null;
      effectPaintBounds = Offset.zero & size;
      _releaseLayers();
      return;
    }
    final clipPath = outline ?? _cachedClipPath!;
    final sharedExclusions = <Path>[];
    if (outline != null && _cachedClipClasses.any((value) => value != 2)) {
      for (final (_, geometry, transform) in shapesWithGeometry) {
        for (final shape in geometry.shapes) {
          if (_backdropClass(shape.appearance) == 2) continue;
          final shapeToLayer = shape.shapeToGeometry == null
              ? transform
              : transform.multiplied(shape.shapeToGeometry!);
          final path = Path();
          path.addPath(
            shape.shape.getOuterPath(Offset.zero & shape.renderObject.size),
            Offset.zero,
            matrix4: shapeToLayer.storage,
          );
          sharedExclusions.add(_outside(path, bounds));
        }
      }
    }
    _lastBackdropClipPath = clipPath;
    debugClipBounds = bounds;
    effectPaintBounds = expandEffectBounds(bounds);
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.shadows);
      return true;
    }(), 'Record shadow composition order.');
    paintRetainedEffect(context, offset, (effectContext, effectOffset) {
      drawGlassShadows(effectContext.canvas, effectOffset);

      // The shared filter only exists while a fully visible shape shares
      // the layer's backdrop transfer.
      final sharedBackdropActive =
          _hasBackdropEffect && _cachedClipClasses.contains(2);
      var paintedBackdrop = sharedBackdropActive;
      if (sharedBackdropActive) {
        final backdropLayer = (_backdropLayer.layer ??= BackdropFilterLayer())
          ..filter = _cachedFilter ??= _buildBackdropFilter()
          ..blendMode = BlendMode.srcOver
          ..backdropKey = _effectiveBackdropKey;
        GlassLayerOwners.note(backdropLayer, this);
        assert(() {
          debugRegisterBackdropCapture(this, _effectiveBackdropKey);
          return true;
        }(), 'Count independent backdrop captures in debug builds.');
        _clipLayer.layer = effectContext.pushClipPath(
          true,
          effectOffset,
          bounds,
          clipPath,
          (clipContext, clipOffset) {
            void paintShared(
              PaintingContext nested,
              Offset nestedOffset,
              int index,
            ) {
              if (index == sharedExclusions.length) {
                nested.pushLayer(backdropLayer, (_, _) {}, nestedOffset);
                return;
              }
              nested.pushClipPath(
                true,
                nestedOffset,
                bounds,
                sharedExclusions[index],
                (next, nextOffset) => paintShared(next, nextOffset, index + 1),
              );
            }

            paintShared(clipContext, clipOffset, 0);
          },
          oldLayer: _clipLayer.layer,
        );
      } else {
        _backdropLayer.layer = null;
        _clipLayer.layer = null;
      }
      paintedBackdrop =
          _paintSeparateBackdrops(
            effectContext,
            effectOffset,
            shapesWithGeometry,
          ) ||
          paintedBackdrop;
      assert(() {
        if (paintedBackdrop) {
          _debugLastPaintStages.add(_FakeGlassPaintStage.backdrop);
        }
        return true;
      }(), 'Record backdrop composition order.');

      assert(() {
        _debugLastPaintStages.add(_FakeGlassPaintStage.surfaces);
        return true;
      }(), 'Record layer-owned surface composition order.');
      _paintSurfaces(effectContext.canvas, effectOffset, shapesWithGeometry);
    });
    assert(() {
      _debugLastPaintStages.add(_FakeGlassPaintStage.contents);
      return true;
    }(), 'Record normal subtree composition order.');
  }

  void _paintSurfaces(
    Canvas canvas,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    final shader = surfaceShader;
    final outline = _outline;
    if (outline == null) {
      if (shader != null) {
        _paintShapeSurfaces(canvas, offset, shader, geometries);
      }
      return;
    }
    final shapes = _bodyShapes(geometries);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipPath(outline);
    _paintNeck(canvas, outline, shapes);
    if (shader != null) {
      for (final (i, shape) in shapes.indexed) {
        canvas.save();
        for (final (j, other) in shapes.indexed) {
          if (_covers(other, j, shape, i)) {
            canvas.clipPath(_outside(other.path, outline.getBounds()));
          }
        }
        canvas.transform(shape.toLayer.storage);
        paintFakeGlassSurface(
          canvas,
          shader: shader,
          size: shape.shape.renderObject.size,
          shape: shape.shape.shape,
          settings: settings,
          appearance: shape.shape.appearance,
          devicePixelRatio: devicePixelRatio,
        );
        canvas.restore();
      }
    }
    canvas.restore();
  }

  /// The shapes of the fused body, each with its outline in the layer's
  /// coordinates and its area.
  List<_BodyShape> _bodyShapes(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => [
    for (final (_, geometry, geometryToLayer) in geometries)
      for (final shape in geometry.shapes)
        () {
          final toLayer = shape.shapeToGeometry == null
              ? geometryToLayer
              : geometryToLayer.multiplied(shape.shapeToGeometry!);
          final local = Offset.zero & shape.renderObject.size;
          final bounds = MatrixUtils.transformRect(toLayer, local);
          return _BodyShape(
            shape: shape,
            toLayer: toLayer,
            path: shape.shape.getOuterPath(local).transform(toLayer.storage),
            area: bounds.width * bounds.height,
          );
        }(),
  ];

  /// Whether [other] (index [j]) wins the part of the body it shares with
  /// [shape] (index [i]): the larger shape, the later one on a tie. Its
  /// face and rim are drawn there, so a shape lying under another - a
  /// menu's button under the menu - draws no rim inside the body.
  static bool _covers(_BodyShape other, int j, _BodyShape shape, int i) =>
      j != i &&
      (other.area > shape.area || (other.area == shape.area && j > i));

  static Path _outside(Path path, Rect bounds) {
    final outside = Path();
    outside.fillType = PathFillType.evenOdd;
    outside.addRect(bounds.inflate(bounds.longestSide + 64));
    outside.addPath(path, Offset.zero);
    return outside;
  }

  /// Tints the part of the fused body no shape covers - the neck - like
  /// the first shape.
  ///
  /// The neck is the outline clipped to the outside of every shape in
  /// turn: no path boolean, which Skia's path ops refuse for an outline
  /// that runs along its shapes' edges, and no even-odd union, which would
  /// tint the overlap of two shapes a second time.
  void _paintNeck(Canvas canvas, Path outline, List<_BodyShape> shapes) {
    if (shapes.isEmpty) return;
    final first = shapes.first.shape.appearance;
    final tint = first.colorModel.approximateSurfaceTint(first.tint);
    final paint = Paint();
    paint.color = tint.withValues(
      alpha: tint.a * first.visibility.clamp(0.0, 1.0),
    );
    canvas.save();
    for (final shape in shapes) {
      canvas.clipPath(_outside(shape.path, outline.getBounds()));
    }
    canvas.drawPath(outline, paint);
    canvas.restore();
  }

  void _paintShapeSurfaces(
    Canvas canvas,
    Offset offset,
    FragmentShader shader,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        canvas
          ..save()
          ..translate(offset.dx, offset.dy)
          ..transform(geometryToLayer.storage);
        if (shape.shapeToGeometry case final transform?) {
          canvas.transform(transform.storage);
        }
        paintFakeGlassSurface(
          canvas,
          shader: shader,
          size: shape.renderObject.size,
          shape: shape.shape,
          settings: settings,
          appearance: shape.appearance,
          devicePixelRatio: devicePixelRatio,
        );
        canvas.restore();
      }
    }
  }

  /// Paints each separately served shape's own clipped backdrop filter so
  /// its transfer applies independently while the shape stays registered
  /// with this layer. Layers are retained across frames keyed by the
  /// shape's render object; entries for shapes that rejoined the shared
  /// clip or hid are released. Returns whether any pass was painted.
  bool _paintSeparateBackdrops(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    final active = <LiquidGlassShapeRenderObject>{};
    for (final (_, geometry, geometryToLayer) in geometries) {
      for (final shape in geometry.shapes) {
        if (_backdropClass(shape.appearance) != 1) continue;
        // The shape's own appearance carries its visibility and any
        // backdrop-transfer override, so fading keeps the same transfer the
        // shared filter applied while it was fully visible.
        final filter = fakeGlassBackdropFilter(
          settings,
          shape.appearance,
          devicePixelRatio: devicePixelRatio,
          shortSide: shape.renderObject.size.shortestSide,
        );
        if (filter == null) continue;
        final renderObject = shape.renderObject;
        active.add(renderObject);
        final layers = _separateBackdropLayers.putIfAbsent(
          renderObject,
          _SeparateBackdropLayers.new,
        );
        final backdropLayer = (layers.backdrop.layer ??= BackdropFilterLayer())
          ..filter = filter
          ..blendMode = BlendMode.srcOver
          ..backdropKey = _effectiveBackdropKey;
        GlassLayerOwners.note(backdropLayer, this);
        assert(() {
          debugRegisterBackdropCapture(this, _effectiveBackdropKey);
          return true;
        }(), 'Count independent backdrop captures in debug builds.');
        final shapeToLayer = shape.shapeToGeometry == null
            ? geometryToLayer
            : geometryToLayer.multiplied(shape.shapeToGeometry!);
        final shapeBounds = Offset.zero & renderObject.size;
        layers.clip.layer = context.pushClipPath(
          true,
          offset,
          MatrixUtils.transformRect(shapeToLayer, shapeBounds),
          shape.shape.getOuterPath(shapeBounds).transform(shapeToLayer.storage),
          (clipContext, clipOffset) {
            clipContext.pushLayer(backdropLayer, (_, _) {}, clipOffset);
          },
          oldLayer: layers.clip.layer,
        );
      }
    }
    for (final renderObject in _separateBackdropLayers.keys.toList()) {
      if (active.contains(renderObject)) continue;
      _separateBackdropLayers.remove(renderObject)!.dispose();
    }
    return active.isNotEmpty;
  }

  bool _clipInputsMatch() {
    if (!encodedInputsMatch(shapesWithGeometry)) return false;
    var shapeIndex = 0;
    for (final (_, geometry, _) in shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (shapeIndex >= _cachedClipClasses.length ||
            _cachedClipClasses[shapeIndex] !=
                _backdropClass(shape.appearance)) {
          return false;
        }
        shapeIndex++;
      }
    }
    return shapeIndex == _cachedClipClasses.length;
  }

  /// 0: hidden, 1: needs its own clipped backdrop pass - fading visibility,
  /// or a backdrop transfer that differs from the layer's shared one,
  /// 2: fully visible and covered by the shared union clip.
  int _backdropClass(LiquidGlassAppearance appearance) {
    final visibility = appearance.visibility.clamp(0.0, 1.0);
    if (visibility <= 0) return 0;
    if (visibility >= 1 && _sharesLayerBackdrop(appearance)) return 2;
    return 1;
  }

  void _clearClipCache() {
    _lastBackdropClipPath = null;
    _cachedClipPath = null;
    _cachedClipBounds = null;
    _cachedClipClasses = const [];
  }

  ImageFilter _buildBackdropFilter() {
    // Every shape the shared clip covers is fully visible, so the shared
    // transfer always applies at full strength.
    return fakeGlassBackdropFilter(
      settings,
      defaultAppearance.copyWith(visibility: 1),
      devicePixelRatio: devicePixelRatio,
      shortSide: _shortSide,
    )!;
  }

  // MARK: Compositing

  @override
  void onTransformChanged() {
    // The clip, backdrop filter, and analytic surface are local to this layer
    // and therefore move with the retained ancestor tree without repainting.
  }

  @override
  void onCompositing() {
    if (!attached) return;
    runCompositorPoll();
  }

  @override
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  ) {
    if (motion.needsRepaint) _repaintAfterCompositing();
  }

  // The retained layers of this frame are already in the scene.
  void _repaintAfterCompositing() {
    if (_repaintAfterCompositingScheduled) return;
    _repaintAfterCompositingScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _repaintAfterCompositingScheduled = false;
      if (attached) markNeedsPaint();
    });
  }

  void _releaseGlassLayers() {
    _backdropLayer.layer = null;
    _clipLayer.layer = null;
    for (final layers in _separateBackdropLayers.values) {
      layers.dispose();
    }
    _separateBackdropLayers.clear();
  }

  void _releaseLayers() {
    _releaseGlassLayers();
    releaseRetainedEffectLayer();
  }

  @override
  void dispose() {
    _repaintAfterCompositingScheduled = false;
    _releaseLayers();
    super.dispose();
  }
}

/// One shape of a fused body in the layer's coordinates.
class _BodyShape {
  const _BodyShape({
    required this.shape,
    required this.toLayer,
    required this.path,
    required this.area,
  });

  final ShapeGeometry shape;
  final Matrix4 toLayer;
  final Path path;
  final double area;
}

/// Retained layer handles for one shape's own clipped backdrop pass.
class _SeparateBackdropLayers {
  final clip = LayerHandle<ClipPathLayer>();
  final backdrop = LayerHandle<BackdropFilterLayer>();

  void dispose() {
    clip.layer = null;
    backdrop.layer = null;
  }
}
