import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';
import 'package:morph/src/live.dart';
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
    this.present = true,
  });

  /// The geometry shaded by the containing layer.
  final LiquidShape shape;

  /// The material and visibility override.
  final LiquidGlassAppearance? appearance;

  /// Shadows around the shape.
  final List<BoxShadow> shadows;

  /// Whether the shape is in its layer: an absent shape is left out of
  /// the layer's shapes, as if it were not in the tree, until a frame
  /// brings it back.
  final bool present;
}

/// One independently shaded shape in a [LiquidGlassLayer].
class LiquidGlass extends StatefulWidget {
  /// Creates a shape registered with the nearest layer.
  const LiquidGlass({
    required LiquidShape this._shape,
    this.child,
    this.clipBehavior = Clip.hardEdge,
    this._shadows = const [],
    this._appearance,
    super.key,
  }) : live = null;

  /// Creates a shape whose geometry, material and shadows follow [live].
  ///
  /// Every notification of [live] writes the new frame straight into the
  /// shape's render objects; the widget rebuilds only when the kind of
  /// shape changes.
  const LiquidGlass.live({
    required ValueListenable<LiquidGlassShapeFrame> this.live,
    this.child,
    this.clipBehavior = Clip.hardEdge,
    super.key,
  }) : _shape = null,
       _shadows = const [],
       _appearance = null;

  /// Content painted above the shape, clipped to it and faded by its
  /// visibility; null for a shape without content, which fills the space
  /// it is given and carries no clip or fade.
  final Widget? child;

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

  Type? _form;

  LiquidGlassShapeFrame? _resolvedFrame;
  LiquidGlassAppearance? _resolvedBase;
  double _resolvedFactor = 1;
  LiquidGlassAppearance? _resolved;

  // A shape without content reaches its render objects through their live
  // setters whatever its kind; only a clip around content is built for it.
  Type? _formOf() => widget.child == null ? null : widget.shape.runtimeType;

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
    if (_formOf() != _form) setState(() {});
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
    final child = widget.child;
    final Widget registered;
    if (child == null) {
      registered = const SizedBox.expand();
    } else {
      registered = GlassLiveShapeClip(
        live: live,
        shapeOf: shape,
        clipBehavior: widget.clipBehavior,
        child: MorphLiveOpacity(
          live: live,
          opacityOf: () => appearance().visibility.clamp(0.0, 1.0),
          child: KeyedSubtree(key: _childKey, child: child),
        ),
      );
    }
    return _RawLiquidGlass(
      renderLink: InheritedGeometryRenderLink.of(context),
      live: live,
      presentOf: () => widget.live?.value.present ?? true,
      settingsOf: settings,
      appearanceOf: appearance,
      shadowsOf: () => widget.shadows,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shapeOf: shape,
      child: registered,
    );
  }
}

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required super.child,
    required this.live,
    required this.presentOf,
    required this.shapeOf,
    required this.renderLink,
    required this.settingsOf,
    required this.appearanceOf,
    required this.shadowsOf,
    required this.devicePixelRatio,
  });

  final Listenable? live;
  final bool Function() presentOf;
  final LiquidShape Function() shapeOf;
  final GeometryRenderLink? renderLink;
  final LiquidGlassSettings Function() settingsOf;
  final LiquidGlassAppearance Function() appearanceOf;
  final List<BoxShadow> Function() shadowsOf;
  final double devicePixelRatio;

  void _apply(RenderLiquidGlass renderObject) {
    renderObject.present = presentOf();
    renderObject.shape = shapeOf();
    renderObject.settings = settingsOf();
    renderObject.appearance = appearanceOf();
    renderObject.shadows = shadowsOf();
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    final glass = RenderLiquidGlass(
      shape: shapeOf(),
      renderLink: renderLink,
      settings: settingsOf(),
      appearance: appearanceOf(),
      shadows: shadowsOf(),
      devicePixelRatio: devicePixelRatio,
      present: presentOf(),
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

/// Geometry of one independently registered shape, which paints the
/// shape's shadows behind its content.
@internal
class RenderLiquidGlass extends RenderLiquidGlassGeometry
    with LiquidGlassShapeRenderObject, MorphLiveBinding, GlassShadowCaster {
  /// Creates the geometry and material registration for a shape.
  RenderLiquidGlass({
    required this._shape,
    required super.settings,
    required this._appearance,
    required super.devicePixelRatio,
    this._shadows = const [],
    super.renderLink,
    super.present,
  });

  LiquidGlassAppearance _appearance;

  @override
  LiquidGlassAppearance get appearance => _appearance;

  /// The material registered with the layer.
  set appearance(LiquidGlassAppearance value) {
    if (_appearance == value) return;
    final shown = _appearance.visibility > 0;
    _appearance = value;
    markGeometryNeedsUpdate();
    markNeedsPaint();
    if (shown != value.visibility > 0) renderLink?.markShapesChanged();
  }

  LiquidShape _shape;

  /// The shape registered with the layer.
  @override
  LiquidShape get shape => _shape;

  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
    markGeometryNeedsUpdate(force: true);
  }

  List<BoxShadow> _shadows;

  /// The shadows around the shape.
  @override
  List<BoxShadow> get shadows => _shadows;

  set shadows(List<BoxShadow> value) {
    if (_shadows == value) return;
    _shadows = value;
    markNeedsPaint();
  }

  @override
  double get shadowVisibility => appearance.visibility.clamp(0.0, 1.0);

  @override
  void paint(PaintingContext context, Offset offset) {
    paintShadows(context, offset);
    super.paint(context, offset);
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
    );
    final cached = geometry?.shapes ?? const <ShapeGeometry>[];
    final changed =
        cached.length != 1 ||
        cached.first.shapeBounds != shapeData.shapeBounds ||
        cached.first.shape != shapeData.shape;

    return (shapeData.shapeBounds, [shapeData], changed);
  }
}
