import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';
import 'package:morph/src/glass/renderer/internal/optimized_clip.dart';
import 'package:morph/src/glass/renderer/internal/render_liquid_glass_geometry.dart';
import 'package:morph/src/glass/renderer/liquid_glass_render_scope.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

/// One independently shaded shape in a [LiquidGlassLayer].
class LiquidGlass extends StatefulWidget {
  /// Creates a shape registered with the nearest layer.
  const LiquidGlass({
    required this.child,
    required this.shape,
    this.clipBehavior = Clip.hardEdge,
    this.shadows = const [],
    this.appearance,
    super.key,
  });

  /// Content painted above the shape.
  final Widget child;

  /// The geometry shaded by the containing layer.
  final LiquidShape shape;

  /// The clipping of the content to the shape.
  final Clip clipBehavior;

  /// Shadows around the shape.
  final List<BoxShadow> shadows;

  /// The material and visibility override.
  final LiquidGlassAppearance? appearance;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  final _childKey = GlobalKey(debugLabel: 'LiquidGlass.child');

  @override
  Widget build(BuildContext context) {
    final scope = LiquidGlassRenderScope.of(context);
    final base = widget.appearance ?? scope.defaultAppearance;
    final appearance = base.copyWith(
      visibility: base.visibility * LiquidGlassVisibility.of(context),
    );
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (scope.useFake ||
        (!ImageFilter.isShaderFilterSupported &&
            !scope.consolidatesFakeBackdrop)) {
      return FakeGlass.inLayerResolved(
        shape: widget.shape,
        appearance: appearance,
        shadows: widget.shadows,
        child: child,
      );
    }
    final registered = scope.consolidatesFakeBackdrop
        ? FakeGlass.inLayerResolved(
            shape: widget.shape,
            appearance: appearance,
            backdropHandledByLayer: true,
            child: child,
          )
        : OptimizedClip(
            shape: widget.shape,
            clipBehavior: widget.clipBehavior,
            child: Opacity(
              opacity: appearance.visibility.clamp(0.0, 1.0),
              child: child,
            ),
          );
    final content = _RawLiquidGlass(
      renderLink: InheritedGeometryRenderLink.of(context),
      settings: scope.settings,
      appearance: appearance,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shape: widget.shape,
      layerShadows: scope.consolidatesFakeBackdrop ? widget.shadows : const [],
      child: registered,
    );
    if (widget.shadows.isEmpty || scope.consolidatesFakeBackdrop) {
      return content;
    }
    return GlassShadow(
      settings: scope.settings,
      appearanceVisibility: appearance.visibility,
      shape: widget.shape,
      shadows: widget.shadows,
      child: content,
    );
  }
}

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required super.child,
    required this.shape,
    required this.layerShadows,
    required this.renderLink,
    required this.settings,
    required this.appearance,
    required this.devicePixelRatio,
  });

  final LiquidShape shape;
  final List<BoxShadow> layerShadows;
  final GeometryRenderLink? renderLink;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance appearance;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderLiquidGlass(
    shape: shape,
    layerShadows: layerShadows,
    renderLink: renderLink,
    settings: settings,
    appearance: appearance,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlass renderObject,
  ) {
    renderObject.shape = shape;
    renderObject.layerShadows = layerShadows;
    renderObject.settings = settings;
    renderObject.appearance = appearance;
    renderObject.devicePixelRatio = devicePixelRatio;
    renderObject.renderLink = renderLink;
  }
}

/// Geometry of one independently registered shape.
@internal
class RenderLiquidGlass extends RenderLiquidGlassGeometry
    with LiquidGlassShapeRenderObject {
  /// Creates the geometry and material registration for a shape.
  RenderLiquidGlass({
    required this._shape,
    required this._layerShadows,
    required super.settings,
    required this._appearance,
    required super.devicePixelRatio,
    super.renderLink,
  });

  LiquidGlassAppearance _appearance;

  @override
  LiquidGlassAppearance get appearance => _appearance;

  /// The material registered with the layer.
  set appearance(LiquidGlassAppearance value) {
    if (_appearance == value) return;
    _appearance = value;
    markGeometryNeedsUpdate();
    markNeedsPaint();
  }

  LiquidShape _shape;

  /// The shape registered with the layer.
  LiquidShape get shape => _shape;

  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
    markGeometryNeedsUpdate(force: true);
  }

  List<BoxShadow> _layerShadows;

  @override
  List<BoxShadow> get layerShadows => _layerShadows;

  /// The shadows painted by the containing layer.
  set layerShadows(List<BoxShadow> value) {
    if (_layerShadows == value) return;
    _layerShadows = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    super.performLayout();
    markGeometryNeedsUpdate();
  }

  @override
  double get geometryBlend => 0;

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData() {
    if (!hasSize) {
      return (Rect.zero, const [], false);
    }

    final shapeData = ShapeGeometry(
      renderObject: this,
      shape: shape,
      appearance: appearance,
      shapeBounds: Offset.zero & size,
      shadows: layerShadows,
    );
    final cached = geometry?.shapes ?? const <ShapeGeometry>[];
    final changed =
        cached.length != 1 ||
        cached.first.shapeBounds != shapeData.shapeBounds ||
        cached.first.shape != shapeData.shape;

    return (shapeData.shapeBounds, [shapeData], changed);
  }
}
