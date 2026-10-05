import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';
import 'package:morph/src/glass/renderer/internal/glass_live.dart';
import 'package:morph/src/glass/renderer/internal/optimized_clip.dart';
import 'package:morph/src/glass/renderer/internal/render_liquid_glass_geometry.dart';
import 'package:morph/src/glass/renderer/liquid_glass_render_scope.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_render_object.dart';

/// The shape, material and shadows of one [LiquidGlass] in one frame.
@immutable
class LiquidGlassShapeFrame {
  /// Describes a shape.
  const LiquidGlassShapeFrame({
    required this.shape,
    this.appearance,
    this.shadows = const [],
  });

  /// The geometry shaded by the containing layer.
  final LiquidShape shape;

  /// The material and visibility override.
  final LiquidGlassAppearance? appearance;

  /// Shadows around the shape.
  final List<BoxShadow> shadows;
}

/// One independently shaded shape in a [LiquidGlassLayer].
class LiquidGlass extends StatefulWidget {
  /// Creates a shape registered with the nearest layer.
  const LiquidGlass({
    required this.child,
    required LiquidShape this._shape,
    this.clipBehavior = Clip.hardEdge,
    this._shadows = const [],
    this._appearance,
    super.key,
  }) : live = null;

  /// Creates a shape whose geometry, material and shadows follow [live].
  ///
  /// Every notification of [live] writes the new frame straight into the
  /// shape's render objects; the widget rebuilds only when the kind of
  /// shape changes or its shadows appear or vanish.
  const LiquidGlass.live({
    required this.child,
    required ValueListenable<LiquidGlassShapeFrame> this.live,
    this.clipBehavior = Clip.hardEdge,
    super.key,
  }) : _shape = null,
       _shadows = const [],
       _appearance = null;

  /// Content painted above the shape.
  final Widget child;

  /// The frames of a live shape, or null for a fixed one.
  final ValueListenable<LiquidGlassShapeFrame>? live;

  final LiquidShape? _shape;

  final List<BoxShadow> _shadows;

  final LiquidGlassAppearance? _appearance;

  /// The geometry shaded by the containing layer.
  LiquidShape get shape => live?.value.shape ?? _shape!;

  /// The clipping of the content to the shape.
  final Clip clipBehavior;

  /// Shadows around the shape.
  List<BoxShadow> get shadows => live?.value.shadows ?? _shadows;

  /// The material and visibility override.
  LiquidGlassAppearance? get appearance =>
      live == null ? _appearance : live!.value.appearance;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  final _childKey = GlobalKey(debugLabel: 'LiquidGlass.child');

  (Type, bool)? _form;
  bool _rebuildsOnFrame = false;

  LiquidGlassShapeFrame? _resolvedFrame;
  LiquidGlassAppearance? _resolvedBase;
  double _resolvedFactor = 1;
  LiquidGlassAppearance? _resolved;

  (Type, bool) _formOf() => (widget.shape.runtimeType, widget.shadows.isEmpty);

  @override
  void initState() {
    super.initState();
    widget.live?.addListener(_frameChanged);
  }

  @override
  void didUpdateWidget(LiquidGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.live, widget.live)) {
      oldWidget.live?.removeListener(_frameChanged);
      widget.live?.addListener(_frameChanged);
    }
  }

  @override
  void dispose() {
    widget.live?.removeListener(_frameChanged);
    super.dispose();
  }

  void _frameChanged() {
    if (_rebuildsOnFrame || _formOf() != _form) setState(() {});
  }

  LiquidGlassAppearance _appearanceOf(
    LiquidGlassAppearance fallback,
    double factor,
  ) {
    final live = widget.live;
    final frame = live?.value;
    if (frame != null &&
        identical(frame, _resolvedFrame) &&
        identical(fallback, _resolvedBase) &&
        factor == _resolvedFactor) {
      return _resolved!;
    }
    final base = widget.appearance ?? fallback;
    final appearance = base.copyWith(visibility: base.visibility * factor);
    _resolvedFrame = frame;
    _resolvedBase = fallback;
    _resolvedFactor = factor;
    _resolved = appearance;
    return appearance;
  }

  @override
  Widget build(BuildContext context) {
    _form = _formOf();
    final scope = LiquidGlassRenderScope.of(context);
    final factor = LiquidGlassVisibility.of(context);
    final fallback = scope.defaultAppearance;
    LiquidGlassAppearance appearance() => _appearanceOf(fallback, factor);
    final frame = widget.live;
    final settingsLive = scope.settingsLive;
    final Listenable? live = frame == null && settingsLive == null
        ? null
        : Listenable.merge([?frame, ?settingsLive]);
    LiquidShape shape() => widget.shape;
    LiquidGlassSettings settings() => scope.currentSettings;
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    _rebuildsOnFrame = false;
    if (scope.useFake ||
        (!ImageFilter.isShaderFilterSupported &&
            !scope.consolidatesFakeBackdrop)) {
      _rebuildsOnFrame = frame != null;
      return FakeGlass.inLayerResolved(
        shape: widget.shape,
        appearance: appearance(),
        shadows: widget.shadows,
        child: child,
      );
    }
    final Widget registered;
    if (scope.consolidatesFakeBackdrop) {
      registered = FakeGlass.inLayerLive(
        live: live,
        shapeOf: shape,
        appearanceOf: appearance,
        child: child,
      );
    } else {
      registered = GlassLiveShapeClip(
        live: live,
        shapeOf: shape,
        clipBehavior: widget.clipBehavior,
        child: GlassLiveOpacity(
          live: live,
          opacityOf: () => appearance().visibility.clamp(0.0, 1.0),
          child: child,
        ),
      );
    }
    final content = _RawLiquidGlass(
      renderLink: InheritedGeometryRenderLink.of(context),
      live: live,
      settingsOf: settings,
      appearanceOf: appearance,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shapeOf: shape,
      layerShadowsOf: scope.consolidatesFakeBackdrop
          ? () => widget.shadows
          : () => const [],
      child: registered,
    );
    if (widget.shadows.isEmpty || scope.consolidatesFakeBackdrop) {
      return content;
    }
    return GlassShadow.live(
      live: live,
      shapeOf: shape,
      shadowsOf: () => widget.shadows,
      visibilityOf: () => appearance().visibility,
      settings: scope.currentSettings,
      child: content,
    );
  }
}

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required super.child,
    required this.live,
    required this.shapeOf,
    required this.layerShadowsOf,
    required this.renderLink,
    required this.settingsOf,
    required this.appearanceOf,
    required this.devicePixelRatio,
  });

  final Listenable? live;
  final LiquidShape Function() shapeOf;
  final List<BoxShadow> Function() layerShadowsOf;
  final GeometryRenderLink? renderLink;
  final LiquidGlassSettings Function() settingsOf;
  final LiquidGlassAppearance Function() appearanceOf;
  final double devicePixelRatio;

  void _apply(RenderLiquidGlass renderObject) {
    renderObject.shape = shapeOf();
    renderObject.layerShadows = layerShadowsOf();
    renderObject.settings = settingsOf();
    renderObject.appearance = appearanceOf();
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    final glass = RenderLiquidGlass(
      shape: shapeOf(),
      layerShadows: layerShadowsOf(),
      renderLink: renderLink,
      settings: settingsOf(),
      appearance: appearanceOf(),
      devicePixelRatio: devicePixelRatio,
    );
    glass.bindLive(live, () => _apply(glass));
    return glass;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlass renderObject,
  ) {
    renderObject.bindLive(live, () => _apply(renderObject));
    renderObject.devicePixelRatio = devicePixelRatio;
    renderObject.renderLink = renderLink;
  }
}

/// Geometry of one independently registered shape.
@internal
class RenderLiquidGlass extends RenderLiquidGlassGeometry
    with LiquidGlassShapeRenderObject, GlassLiveBinding {
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
