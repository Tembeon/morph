// ignore_for_file: avoid_setters_without_getters, cascade_invocations

import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_cache.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/internal/ancestor_clip.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_capture_debug.dart';
import 'package:morph/src/glass/renderer/internal/blur_reach.dart';
import 'package:morph/src/glass/renderer/internal/filter_pass_transform.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/internal/raster_phase.dart';
import 'package:morph/src/glass/renderer/internal/render_liquid_glass_geometry.dart';
import 'package:morph/src/glass/renderer/internal/snap_rect_to_pixels.dart';
import 'package:morph/src/glass/renderer/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:morph/src/glass/renderer/liquid_glass_glow.dart';
import 'package:morph/src/glass/renderer/liquid_glass_render_scope.dart';
import 'package:morph/src/glass/renderer/geometry/glass_geometry.dart';
import 'package:morph/src/glass/renderer/geometry/glass_rest.dart';
import 'package:morph/src/glass/renderer/geometry/glass_shape_pack.dart';
import 'package:morph/src/glass/renderer/pass/final_pass.dart';
import 'package:morph/src/glass/renderer/pass/glass_frost.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_render_object.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

/// Shades independently registered shapes or an owner-supplied fused field.
///
/// The owner computes every union before supplying [field]. Shapes provide
/// the material and shadows; this layer never fuses their geometry.
///
/// The glass needs Impeller's shader filters and the Flutter GPU geometry
/// renderer. Until the renderer has loaded, and wherever shader filters are
/// unsupported, the layer paints its child with no glass.
class LiquidGlassLayer extends StatefulWidget {
  /// Creates a new [LiquidGlassLayer] with the given [child] and [settings].
  const LiquidGlassLayer({
    required this.child,
    this._settings = const LiquidGlassSettings(),
    this.defaultAppearance,
    this.useBackdropGroup = false,
    this.backdropKey,
    this.blursOwnBackdrop = false,
    this.solidBackdrop,
    this._field,
    super.key,
  }) : live = null,
       settingsOf = null,
       fieldOf = null,
       glowOf = null,
       glows = null;

  /// Creates a layer whose settings and field follow [live].
  ///
  /// Every notification of [live] writes [settingsOf], [fieldOf] and
  /// [glowOf] into the layer's render object and into its shapes without
  /// rebuilding them; a notification of [glows] writes [glowOf] alone.
  const LiquidGlassLayer.live({
    required this.child,
    required this.live,
    required LiquidGlassSettings Function() this.settingsOf,
    this.fieldOf,
    this.glowOf,
    this.glows,
    this.defaultAppearance,
    this.useBackdropGroup = false,
    this.backdropKey,
    this.blursOwnBackdrop = false,
    this.solidBackdrop,
    super.key,
  }) : _settings = const LiquidGlassSettings(),
       _field = null;

  /// The source of a live layer's settings and field, or null for fixed
  /// ones.
  final Listenable? live;

  /// The settings now, for a live layer.
  final LiquidGlassSettings Function()? settingsOf;

  /// The field now, for a live layer; null for a layer without a field.
  final GlassField? Function()? fieldOf;

  /// The touch glow the final pass applies now, for a live layer; null for
  /// a layer that never glows.
  final LiquidGlassGlow? Function()? glowOf;

  /// Notifies when only [glowOf] changed, for a live layer: the layer then
  /// hands its final pass the new glow, a change of uniforms that paints
  /// nothing while its backdrop filter can be kept
  /// ([RenderLiquidGlassLayer.glow]).
  final Listenable? glows;

  final LiquidGlassSettings _settings;

  final GlassField? _field;

  /// The distance field of the one body the layer's shapes form, when its
  /// owner has fused them already.
  ///
  /// With a field the geometry pass shades the body the field describes
  /// instead of the shapes' own outlines or blend groups; the shapes still
  /// supply the appearance, the shadows and the bounds of the matte, which
  /// must contain the body.
  GlassField? get field => fieldOf != null ? fieldOf!() : _field;

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [LiquidGlassLayer] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  LiquidGlassSettings get settings => settingsOf?.call() ?? _settings;

  /// Appearance inherited by shapes that do not provide an override.
  ///
  /// When omitted, the fitted iOS 27 toolbar appearance follows the ambient
  /// platform brightness.
  final LiquidGlassAppearance? defaultAppearance;

  /// Whether to share a [BackdropGroup] capture for backdrop effects.
  ///
  /// The nearest ancestor group is used when one exists. Otherwise this layer
  /// creates a local group so its shapes can share backdrop capture work.
  /// Multiple [LiquidGlassLayer]s need a common ancestor group or an
  /// explicit shared [backdropKey] to share across layer boundaries.
  ///
  /// On Impeller, each independent backdrop capture does a full-screen
  /// readback (~115 mW GPU at 120 Hz on a Pixel 10) before blur or glass
  /// work. Sharing one [BackdropGroup] or [BackdropKey] pays that readback
  /// once: two real layers dropped from 797 mW to 688 mW, two plain sigma7 blurs
  /// from 426 mW to 312 mW, on the same device.
  ///
  /// Shared members do not see content painted between them. Group only
  /// elements that sit over the same content plane (for example all root
  /// chrome). Do not put a sheet and the FAB above it in one group.
  ///
  /// [backdropKey] takes precedence when both are provided.
  ///
  /// Defaults to false.
  final bool useBackdropGroup;

  /// An explicit backdrop capture key for blur and refraction sharing.
  ///
  /// Multiple non-overlapping glass effects can reuse the same key to avoid
  /// repeated backdrop captures. Effects that overlap should use different
  /// keys because Flutter treats a shared key as a single backdrop filter.
  final BackdropKey? backdropKey;

  /// Whether a frost that needs a blur pass blurs a copy of the backdrop
  /// around this layer's glass instead of the whole pass it paints in.
  ///
  /// The copy is one more backdrop read; it pays for a small surface whose
  /// frost animates (a lifted lens): a blur composed under the glass shader
  /// reads the whole enclosing pass, and an animated frost resizes its
  /// full-size targets on every frame. A large or still frost (a bar, a
  /// menu, a sheet) blurs cheaper without it. Ignored inside a backdrop
  /// group.
  final bool blursOwnBackdrop;

  /// The opaque color that fills everything this layer's glass would read,
  /// or null to read the backdrop.
  ///
  /// When the layer is painted directly over one opaque color - a card its
  /// glass sits on, with nothing painted between the card and the layer -
  /// refraction, dispersion and frost of that backdrop are that color. The
  /// layer then draws its glass as an ordinary paint shaded over this
  /// color instead of a backdrop filter: no backdrop read, no filter pass,
  /// and the pixels match the filter's over that color. A color that is
  /// not fully opaque is ignored. The color must really be what lies under
  /// the glass: the layer cannot tell, and anything else painted under its
  /// shapes (an image, text, a second fill) would not show through the
  /// glass.
  final Color? solidBackdrop;

  @override
  State<LiquidGlassLayer> createState() => _LiquidGlassLayerState();
}

class _LiquidGlassLayerState extends State<LiquidGlassLayer> {
  late final GeometryRenderLink _link = GeometryRenderLink();

  late final _LayerSettings _settingsLive = _LayerSettings(this);

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
  bool _triedGpuGeometryRenderer = false;
  bool _gpuInitializationScheduled = false;
  bool _loggedFallback = false;

  // The glass and the bare child never coexist, so one key keeps the user's
  // subtree alive when the renderer arrives without ever mounting it twice.
  final _childKey = GlobalKey(debugLabel: 'LiquidGlassLayer.child');

  void _logDebugFallback(String message) {
    if (!kDebugMode || _loggedFallback) return;
    _loggedFallback = true;
    debugPrint('morph: $message');
  }

  void _tryCreateCachedGpuGeometryRenderer() {
    if (!ImageFilter.isShaderFilterSupported || _triedGpuGeometryRenderer) {
      return;
    }
    final renderer = FlutterGpuGeometryRenderer.tryCreateCached(
      ShaderKeys.gpuGeometryShaderBundle,
    );
    if (renderer == null) return;
    _gpuGeometryRenderer = renderer;
    _triedGpuGeometryRenderer = true;
  }

  void _scheduleGpuGeometryRendererInitialization() {
    if (_triedGpuGeometryRenderer || _gpuInitializationScheduled) return;
    _gpuInitializationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _gpuInitializationScheduled = false;
      if (!mounted || _triedGpuGeometryRenderer) return;

      _triedGpuGeometryRenderer = true;
      try {
        final renderer = await FlutterGpuGeometryRenderer.fromAsset(
          ShaderKeys.gpuGeometryShaderBundle,
        );
        if (!mounted) {
          renderer.dispose();
          return;
        }
        _gpuGeometryRenderer = renderer;
      } on Object catch (error) {
        if (!mounted) return;
        _logDebugFallback(
          'Flutter GPU is unavailable; LiquidGlassLayer draws no glass. '
          'Enable Impeller and Flutter GPU for the glass effect. $error',
        );
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _tryCreateCachedGpuGeometryRenderer();
  }

  @override
  void didUpdateWidget(covariant LiquidGlassLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.live, widget.live)) _settingsLive.follow();
  }

  @override
  void dispose() {
    _gpuGeometryRenderer?.dispose();
    _link.dispose();
    _settingsLive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.backdropKey == null &&
        widget.useBackdropGroup &&
        BackdropGroup.of(context) == null) {
      return BackdropGroup(child: Builder(builder: _buildLayer));
    }
    return _buildLayer(context);
  }

  Widget _buildLayer(BuildContext context) {
    final defaultAppearance =
        widget.defaultAppearance ??
        LiquidGlassAppearance.ios27Toolbar(
          brightness: MediaQuery.platformBrightnessOf(context),
        );
    final backdropKey =
        widget.backdropKey ??
        (widget.useBackdropGroup
            ? BackdropGroup.of(context)?.backdropKey
            : null);
    final shaderFiltersSupported = ImageFilter.isShaderFilterSupported;
    if (shaderFiltersSupported) {
      // Android's Impeller context is not available until its first surface
      // frame has been established. Creating flutter_gpu resources directly
      // from build can therefore block the UI isolate before the first frame.
      _scheduleGpuGeometryRendererInitialization();
    } else {
      _logDebugFallback(
        'Impeller shader filters are unavailable; LiquidGlassLayer draws no '
        'glass. Enable Impeller and Flutter GPU for the glass effect.',
      );
    }
    final gpuRenderer = _gpuGeometryRenderer;
    final live = widget.live;
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    return RepaintBoundary(
      child: LiquidGlassRenderScope(
        settings: widget.settings,
        settingsLive: live == null ? null : _settingsLive,
        defaultAppearance: defaultAppearance,
        backdropKey: backdropKey,
        child: InheritedGeometryRenderLink(
          link: _link,
          child: !shaderFiltersSupported || gpuRenderer == null
              ? child
              : MultiShaderBuilder(assetKeys: ShaderKeys.liquidGlassRenders, (
                  context,
                  shaders,
                  child,
                ) {
                  return _RawShapes(
                    matteShaders: shaders,
                    backdropKey: backdropKey,
                    blursOwnBackdrop: widget.blursOwnBackdrop,
                    solidBackdrop: widget.solidBackdrop,
                    // A keyed group reads its own copy on purpose (glass
                    // painted in between belongs in it); only an unkeyed
                    // read is cached.
                    backdropCache: backdropKey == null
                        ? GlassBackdropCacheScope.maybeOf(context)
                        : null,
                    live: live,
                    settingsOf: () => widget.settings,
                    defaultAppearance: defaultAppearance,
                    link: _link,
                    gpuGeometryRenderer: gpuRenderer,
                    fieldOf: () => widget.field,
                    glowOf: () => widget.glowOf?.call(),
                    glows: widget.glows,
                    child: child!,
                  );
                }, child: child),
        ),
      ),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.matteShaders,
    required this.backdropKey,
    required this.blursOwnBackdrop,
    required this.solidBackdrop,
    required this.backdropCache,
    required this.live,
    required this.settingsOf,
    required this.defaultAppearance,
    required Widget super.child,
    required this.link,
    required this.fieldOf,
    required this.glowOf,
    required this.glows,
    this.gpuGeometryRenderer,
  });

  final List<FragmentShader> matteShaders;
  final BackdropKey? backdropKey;
  final bool blursOwnBackdrop;
  final Color? solidBackdrop;
  final GlassBackdropCache? backdropCache;
  final Listenable? live;
  final LiquidGlassSettings Function() settingsOf;
  final LiquidGlassAppearance defaultAppearance;
  final GeometryRenderLink link;
  final FlutterGpuGeometryRenderer? gpuGeometryRenderer;
  final GlassField? Function() fieldOf;
  final LiquidGlassGlow? Function() glowOf;
  final Listenable? glows;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final layer = RenderLiquidGlassLayer(
      field: fieldOf(),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      matteShaders: matteShaders,
      backdropKey: backdropKey,
      settings: settingsOf(),
      defaultAppearance: defaultAppearance,
      link: link,
      gpuGeometryRenderer: gpuGeometryRenderer,
    );
    layer.blursOwnBackdrop = blursOwnBackdrop;
    layer.solidBackdrop = solidBackdrop;
    layer.backdropCache = backdropCache;
    layer.glow = glowOf();
    layer.bindLive(live, () => _apply(layer));
    layer.bindGlows(glows, () => layer.glow = glowOf());
    return layer;
  }

  void _apply(RenderLiquidGlassLayer layer) {
    layer.settings = settingsOf();
    layer.field = fieldOf();
    layer.glow = glowOf();
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassLayer renderObject,
  ) {
    renderObject.link = link;
    renderObject.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    renderObject.defaultAppearance = defaultAppearance;
    renderObject.backdropKey = backdropKey;
    renderObject.gpuGeometryRenderer = gpuGeometryRenderer;
    renderObject.blursOwnBackdrop = blursOwnBackdrop;
    renderObject.solidBackdrop = solidBackdrop;
    renderObject.backdropCache = backdropCache;
    renderObject.glow = glowOf();
    renderObject.bindLive(live, () => _apply(renderObject));
    renderObject.bindGlows(glows, () => renderObject.glow = glowOf());
  }
}

/// The settings of a live layer as one listenable whose identity outlives
/// the layer's widgets: the shapes below follow it.
class _LayerSettings extends ChangeNotifier
    implements ValueListenable<LiquidGlassSettings> {
  _LayerSettings(this._state) {
    follow();
  }

  final _LiquidGlassLayerState _state;
  Listenable? _source;

  /// Listens to the current widget's source.
  void follow() {
    final source = _state.widget.live;
    if (identical(source, _source)) return;
    _source?.removeListener(notifyListeners);
    _source = source;
    source?.addListener(notifyListeners);
  }

  @override
  LiquidGlassSettings get value => _state.widget.settings;

  @override
  void dispose() {
    _source?.removeListener(notifyListeners);
    super.dispose();
  }
}

/// The real glass layer: renders the shared shape geometry into a GPU matte
/// and paints the final shader filter over it. All shared machinery - shape
/// registration, transform and compositor-translation polling, retained
/// ancestor clips, shadows, bounds and the frame state - lives in
/// [LiquidGlassRenderObject]; this class implements only the effect.
@internal
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin, MorphLiveBinding
    implements
        LiquidGlassLayerRenderObject,
        GlassPassSource,
        GlassGeometrySource,
        GlassRestHost {
  RenderLiquidGlassLayer({
    required List<FragmentShader> matteShaders,
    required super.backdropKey,
    required super.devicePixelRatio,
    required super.settings,
    required super.defaultAppearance,
    required super.link,
    this._gpuGeometryRenderer,
    this._field,
  }) {
    _pass = GlassFinalPass(this, matteShaders);
    _encoder = GlassGeometryEncoder(this, _pass);
    _rest = GlassRestWatch(this);
    _pass.updateSettings();
  }

  late final GlassFinalPass _pass;
  late final GlassGeometryEncoder _encoder;
  late final GlassRestWatch _rest;

  GlassField? _field;

  /// The fused body's distance field, or null to shade the shapes.
  @override
  GlassField? get field => _field;
  set field(GlassField? value) {
    if (identical(_field, value)) return;
    _field = value;
    needsGeometryUpdate = true;
    _rest.inputsChanged();
    markNeedsPaint();
  }

  /// The touch glow the final pass applies to the glass, or null for none.
  ///
  /// A new glow is a change of the final shader's uniforms only: while the
  /// layer draws through the backdrop filter it composited last, over
  /// geometry it can reuse, the filter is replaced by one over the new
  /// uniforms and nothing paints. Glass recorded into a picture (over a
  /// solid or a cached backdrop) repaints.
  LiquidGlassGlow? get glow => _pass.glow;
  set glow(LiquidGlassGlow? value) {
    if (!_pass.setGlow(value)) return;
    final filter = _shaderHandle.layer;
    if (filter != null &&
        attached &&
        !drawableEmpty &&
        hasReusableGeometry &&
        _solidHandle.layer == null) {
      filter.filter = _updateShaderFilter();
    } else {
      markNeedsPaint();
    }
  }

  Listenable? _glows;
  VoidCallback? _glowsApply;

  /// Follows [source], whose notifications change only the [glow], writing
  /// it through [apply].
  void bindGlows(Listenable? source, VoidCallback apply) {
    _glowsApply = apply;
    if (identical(source, _glows)) return;
    if (attached) {
      _glows?.removeListener(_onGlows);
      source?.addListener(_onGlows);
    }
    _glows = source;
  }

  void _onGlows() => _glowsApply?.call();

  /// Whether the layer rests on a matte in [AnalyticGeometryMode.changes].
  @visibleForTesting
  bool get debugResting => _rest.resting;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // Only a debug override or a build with analytic geometry ever asks
    // the attached layers for a new frame.
    if (!kReleaseMode || ShaderKeys.analyticGeometry) {
      GlassGeometryFlags.invalidations.addListener(requestGeometryFrame);
      GlassFinalPass.analyticProgramsLoaded.addListener(requestGeometryFrame);
    }
    _glows?.addListener(_onGlows);
  }

  @override
  void detach() {
    GlassGeometryFlags.invalidations.removeListener(requestGeometryFrame);
    GlassFinalPass.analyticProgramsLoaded.removeListener(requestGeometryFrame);
    _glows?.removeListener(_onGlows);
    super.detach();
  }

  // A switch that moved or a program that loaded may encode this layer's
  // geometry differently.
  @override
  void requestGeometryFrame() {
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  @override
  bool get analyticFrame => _analytic;

  @override
  bool get holdsMatte => _geometryImage != null;

  @override
  int get matteBuilds => _encoder.matteBuilds;

  // Whether the current frame's shapes are evaluated in the final shader
  // instead of read from a geometry matte.
  bool _analytic = false;

  /// Whether the current frame evaluates its shapes in the final shader.
  @visibleForTesting
  bool get debugAnalytic => _analytic;

  /// Why the latest geometry frame took the matte path, or null when it
  /// was analytic.
  @visibleForTesting
  String? get debugAnalyticIneligibility => _encoder.analyticIneligibility;

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
  @override
  FlutterGpuGeometryRenderer? get gpuGeometryRenderer => _gpuGeometryRenderer;
  set gpuGeometryRenderer(FlutterGpuGeometryRenderer? value) {
    if (_gpuGeometryRenderer == value) return;
    _gpuGeometryRenderer = value;
    markNeedsPaint();
  }

  // MARK: Shader inputs

  /// Whether the latest geometry pass writes per-shape contributor data.
  @visibleForTesting
  bool get debugUsesShapeAppearances => _pass.usesShapeAppearances;

  /// Whether only tint differs, allowing one filtered appearance lookup.
  @visibleForTesting
  bool get debugUsesTintOnlyAppearance => _pass.usesTintOnlyAppearance;

  /// The optional contributor texture sampled by the final material pass.
  @visibleForTesting
  ui.Image? get debugMaterialImage => _materialImage;

  @override
  double get materialShortSide => _encoder.materialShortSide;

  @override
  Offset get materialCenter => _materialCenterInMatte;

  @override
  Size get materialSize => _materialSizeInMatte;

  @override
  GlassShapePack? get analyticShapes => _analytic ? _encoder.pack : null;

  @override
  GlassFrost get frost => GlassFrost.of(
    frost: settings.effectiveFrost,
    dispersion: settings.dispersion,
    devicePixelRatio: devicePixelRatio,
    ownBackdrop: _blursOwnBackdrop,
  );

  // MARK: Retained frame hooks

  /// Whether the committed shapes exist but none can be drawn by this
  /// effect - a function of the committed geometry, so it stays correct
  /// when a retained refresh commits new shapes between paints.
  bool get drawableEmpty =>
      shapesWithGeometry.isNotEmpty && !hasDrawableGlass(shapesWithGeometry);

  /// True once geometry is ready to draw again - a matte encoded, or an
  /// analytic frame's shapes written into its shader's uniforms - so
  /// ancestor motion can stay on the compositor without crossing this
  /// layer's repaint boundary.
  @protected
  bool get hasReusableGeometry => _geometryImage != null || _analytic;

  @override
  GlassFrameState get hiddenFrameState => GlassFrameState.idle;

  @override
  bool hasDrawableGlass(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => geometries.any(
    (entry) => entry.$2.shapes.any(
      (shape) =>
          GlassGeometryEncoder.shapeBasis(entry.$3, shape.shapeToGeometry) !=
          null,
    ),
  );

  @override
  bool isSnapshotCurrent(
    RenderLiquidGlassGeometry geometry,
    GeometryCache snapshot,
  ) => geometry.hasCurrentMatteRevision(snapshot.matteRevision);

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    final geometryInputsChanged =
        old.effectiveRefractionHeight != settings.effectiveRefractionHeight ||
        old.effectiveRefractionAmount != settings.effectiveRefractionAmount ||
        old.refractionFitsShape != settings.refractionFitsShape ||
        old.contourWidth != settings.contourWidth;
    _pass.updateSettings();
    if (geometryInputsChanged) {
      needsGeometryUpdate = true;
      _rest.inputsChanged();
    }
  }

  @override
  void onAppearanceChanged() => _pass.updateSettings();

  @override
  void onDevicePixelRatioChanged() {
    _pass.updateSettings();
    needsGeometryUpdate = true;
    _rest.inputsChanged();
  }

  // MARK: Retained matte

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;
  ui.Image? _materialImage;
  bool _ownsGeometryImages = false;

  /// The bounding box of the geometry matte in the coordinate space of the
  /// shader
  Rect _geometryMatteBounds = Rect.zero;
  Offset _materialCenterInMatte = Offset.zero;
  Size _materialSizeInMatte = Size.zero;
  // The matte and material map fill the top-left of textures that only grow.
  Size _geometryTextureSize = Size.zero;
  Size _materialTextureSize = const Size(1, 1);

  /// The pre-rendered geometry texture in screen space.
  @protected
  ui.Image? get geometryImage => _geometryImage;

  @visibleForTesting
  ui.Image? get debugGeometryImage => _geometryImage;

  /// The bounding box of the geometry matte in screen space.
  @protected
  Rect get geometryMatteBounds => _geometryMatteBounds;

  /// Layer-local bounds of the geometry matte. Ancestor transforms must not
  /// change this: they are applied by the compositor, not the shader.
  @visibleForTesting
  Rect get debugGeometryMatteBounds => _geometryMatteBounds;

  /// Refreshes already recorded contributors before layer-tree descent.
  /// No child painting occurs here, and the unchanged/translation paths do
  /// not call this method or evaluate geometry.
  @protected
  bool refreshRetainedGeometry(
    void Function(
      List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>,
      Rect,
      Offset,
    )
    updateMaterial,
  ) {
    if ((!hasReusableGeometry && !drawableEmpty) ||
        frameState == GlassFrameState.idle) {
      return false;
    }
    final candidate = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = collectFrameGeometry(candidate);
    // Topology changes need normal painting to rebuild clip ancestry.
    if (bounds == null || !matchesRetainedStructure(candidate)) {
      return false;
    }
    commitFrameGeometry(candidate, sameStructure: true);
    final unchanged = encodedMatteDelta(bounds) != null;
    final materialBounds = _prepareGeometryAppearance(bounds);
    // A drawable-empty refresh encodes nothing; the committed list alone
    // is the compositor-translation poll's baseline.
    if (hasDrawableGlass(shapesWithGeometry)) {
      // Keep old borrowed handles valid until the replacement is installed.
      if (!_ownsGeometryImages && _geometryImage != null) {
        final geometry = _geometryImage!.clone();
        ui.Image? material;
        try {
          material = _materialImage?.clone();
        } catch (_) {
          geometry.dispose();
          rethrow;
        }
        _geometryImage = geometry;
        _materialImage = material;
        _ownsGeometryImages = true;
      }
      _rest.noteFrame(unchanged: unchanged);
      final geometry = _encode(bounds);
      _releaseGeometryImageHandles();
      _adopt(geometry, bounds);
      _bindGeometryShader(_geometryImage);
    }
    needsGeometryUpdate = false;
    link
      ..updateAllGeometries()
      ..markClean();
    updateMaterial(shapesWithGeometry, materialBounds, retainedPaintOffset);
    syncAncestorClips();
    return true;
  }

  void _clearGeometryImage() {
    _releaseGeometryImageHandles();
    clearFrameInputs();
  }

  void _releaseGeometryImageHandles() {
    if (_ownsGeometryImages) {
      _geometryImage?.dispose();
      _materialImage?.dispose();
      _ownsGeometryImages = false;
    }
    _geometryImage = null;
    _materialImage = null;
    _analytic = false;
  }

  void _rememberEncodedGeometry(Rect bounds) {
    encodedGeometryBounds = bounds;
    rememberFrameInputs();
  }

  bool _reuseUniformlyTranslatedGeometry(Rect bounds) {
    final delta = encodedMatteDelta(bounds);
    if (delta == null) return false;
    if (_encoder.encodedPassPhase != null) return false;
    _geometryMatteBounds = _geometryMatteBounds.shift(delta);
    _materialCenterInMatte += delta;
    if (_analytic) {
      _encoder.pack.translate(delta * devicePixelRatio);
      _pass.markInputsChanged();
    }
    _rememberEncodedGeometry(bounds);
    return true;
  }

  // MARK: Painting

  @override
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    // The commit rebased the compositor translation onto the shapes'
    // painted transforms; that moves no pass phase.
    _phaseMoved = false;
    if (geometryBounds == null) {
      _clearGeometryImage();
      _releaseCompositorFilter();
      releaseRetainedEffectLayer();
      return;
    }
    final materialPaintBounds = _prepareGeometryAppearance(geometryBounds);
    switch (frameState) {
      case GlassFrameState.empty:
        _clearGeometryImage();
        _releaseCompositorFilter();
        if (shapesWithGeometry.isEmpty) {
          releaseRetainedEffectLayer();
          return;
        }
        needsGeometryUpdate = false;
        link.markClean();
        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          _paintMaterialFilter(
            effectContext,
            effectOffset,
            materialPaintBounds,
          );
        });
      case GlassFrameState.idle:
        // Keep the last matte and its encode snapshot; ancestor motion
        // stays compositor-only while hidden because the translation poll
        // rebaselines on the committed frame, not on that snapshot. Skip
        // the backdrop filter so idle glass does not sample.
        updateIdleAncestorClips();
        _releaseCompositorFilter();
        paintRetainedEffect(context, offset, (effectContext, effectOffset) {});
      case GlassFrameState.active:
        // Analytic shapes have no raster grid; test that before walking
        // the tree for the pass transform.
        if (hasReusableGeometry &&
            !_analytic &&
            _encoder.rasterGridStale(
              shaderCoordinateTransform,
              analytic: _analytic,
            )) {
          needsGeometryUpdate = true;
        }
        if (needsGeometryUpdate || !hasReusableGeometry || link.isDirty) {
          link
            ..updateAllGeometries()
            ..markClean();

          final canReuseTranslatedGeometry =
              !needsGeometryUpdate &&
              hasReusableGeometry &&
              _reuseUniformlyTranslatedGeometry(geometryBounds);
          needsGeometryUpdate = false;

          if (!canReuseTranslatedGeometry) {
            _rest.noteFrame(
              unchanged: encodedMatteDelta(geometryBounds) != null,
            );
            _clearGeometryImage();
            _adopt(_encode(geometryBounds), geometryBounds);
          }
        }

        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          if (hasReusableGeometry) {
            _bindGeometryShader(_geometryImage);
            _paintMaterialFilter(
              effectContext,
              effectOffset,
              materialPaintBounds,
            );
          }
        });
    }
  }

  Rect _prepareGeometryAppearance(Rect boundingBox) {
    final usedShapeAppearances = _pass.usesShapeAppearances;
    final usedTintOnlyAppearance = _pass.usesTintOnlyAppearance;
    final appearanceValuesChanged = !_committedAppearancesMatch();
    _pass.setShapeAppearances(
      appearanceValuesChanged
          ? [
              for (final (_, geometry, _) in shapesWithGeometry)
                for (final shape in geometry.shapes) shape.appearance,
            ]
          : _pass.shapeAppearances,
    );
    if (usedShapeAppearances != _pass.usesShapeAppearances ||
        usedTintOnlyAppearance != _pass.usesTintOnlyAppearance ||
        (_pass.usesShapeAppearances && appearanceValuesChanged)) {
      // Mixed material data is encoded in the geometry render target. Only
      // uniform appearance changes can be applied with final-pass uniforms.
      needsGeometryUpdate = true;
      _rest.inputsChanged();
    }
    final materialBounds = boundingBox.inflate(
      GlassGeometryEncoder.contourOutset(settings, devicePixelRatio),
    );
    // Liquid shapes paint their own shadows (GlassShadowCaster), outside
    // the layer's effect.
    effectPaintBounds = materialBounds;
    return materialBounds;
  }

  // Whether the committed shapes' appearances equal the last appearance list,
  // element by element, without building the list.
  bool _committedAppearancesMatch() {
    final last = _pass.shapeAppearances;
    var index = 0;
    for (final (_, geometry, _) in shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (index >= last.length || last[index] != shape.appearance) {
          return false;
        }
        index++;
      }
    }
    return index == last.length;
  }

  // Resource binding is separate from recording/painting children so a
  // changed geometry frame can be prepared without invoking child paint.
  void _bindGeometryShader(ui.Image? geometryImage) {
    syncCoordinateMapping();
    _pass.bindGeometry(
      geometryImage: geometryImage,
      materialImage: _materialImage,
      matteBounds: _geometryMatteBounds,
      geometryTextureSize: _geometryTextureSize,
      materialTextureSize: _materialTextureSize,
    );
  }

  // MARK: Coordinate mapping

  // The screen transform the compositing hook tracked this frame, reused by
  // the hook's own coordinate mapping instead of walking the tree twice.
  Matrix4? _compositingScreen;

  @override
  Matrix4 trackedTransform() {
    final transform = getTransformTo(null);
    _compositingScreen = transform;
    return transform;
  }

  /// This layer's transform into the pass its filter samples. During
  /// compositing it may be the tracked screen transform itself: callers
  /// read it and never modify it.
  Matrix4 get shaderCoordinateTransform {
    final seeding = compositionProbeSeeding;
    final translation = compositorTranslation;
    final screen = _compositingScreen;
    final ownPass = _seedsBlur;
    final transform = filterPassTransform(
      this,
      screen: seeding || ownPass || translation != Offset.zero
          ? screen?.clone()
          : screen,
      seeding: seeding,
      devicePixelRatio: devicePixelRatio,
      translation: translation,
    );
    if (ownPass) {
      final origin = _seedPassOrigin(transform);
      transform.leftTranslateByDouble(-origin.dx, -origin.dy, 0, 1);
    }
    return transform;
  }

  (double, double, double, double, double, double)? _coordinateMapping;
  Rect? _backdropBounds;

  /// Layer-local rect the native filter captures backdrop for, or `null`
  /// when it is unbounded. Refraction mirrors samples that would leave it:
  /// outside the clip the filter input is transparent.
  @protected
  Rect? get backdropSampleBounds {
    final clip = _filterClip;
    if (clip == null || frost.passSigma <= 0) return clip;
    final translation = compositorTranslation;
    var captured = clip.shift(translation);
    if (retainedClipBounds case final retained?) {
      captured = captured.intersect(retained);
    }
    if (localPaintClipAbove(this) case final above?) {
      captured = captured.intersect(above);
    }
    return captured.shift(-translation);
  }

  /// The [backdropSampleBounds] last written to the shader.
  @visibleForTesting
  Rect? get debugBackdropSampleBounds => _backdropBounds;

  @protected
  bool syncCoordinateMapping() {
    final solid = _solid != null;
    final mapping = solid
        ? _solidCoordinateMapping()
        : _currentCoordinateMapping();
    final backdropBounds = solid ? null : backdropSampleBounds;
    final changed =
        mapping != _coordinateMapping || backdropBounds != _backdropBounds;
    _coordinateMapping = mapping;
    _backdropBounds = backdropBounds;
    if (changed) _pass.markInputsChanged();
    _pass.writeMapping(mapping, backdropBounds);
    return changed;
  }

  (double, double, double, double, double, double) _currentCoordinateMapping() {
    final layerToPass = shaderCoordinateTransform;
    final globalToMatte = _globalToMatte;
    if (globalToMatte.copyInverse(layerToPass) == 0.0) {
      throw ArgumentError.value(
        layerToPass,
        'other',
        'Matrix cannot be inverted',
      );
    }
    final m = globalToMatte.storage;
    final originX = _mappedX(m, 0, 0);
    final originY = _mappedY(m, 0, 0);
    return (
      _mappedX(m, 1, 0) - originX,
      _mappedX(m, 0, 1) - originX,
      _mappedY(m, 1, 0) - originY,
      _mappedY(m, 0, 1) - originY,
      originX * devicePixelRatio,
      originY * devicePixelRatio,
    );
  }

  // Over a solid backdrop the glass is a paint, whose fragment coordinates
  // are the logical canvas coordinates it is recorded in: the layer's own
  // coordinates shifted by its paint offset. The matte is the layer's own
  // coordinates in device pixels, so neither the pass nor any ancestor
  // transform enters, and compositor motion never changes the mapping.
  (double, double, double, double, double, double) _solidCoordinateMapping() {
    final offset = retainedPaintOffset;
    return (
      devicePixelRatio,
      0,
      0,
      devicePixelRatio,
      -offset.dx * devicePixelRatio,
      -offset.dy * devicePixelRatio,
    );
  }

  final Matrix4 _globalToMatte = Matrix4.zero();

  // MatrixUtils.transformPoint, one coordinate at a time.
  static double _mappedX(Float64List m, double x, double y) {
    final rx = m[0] * x + m[4] * y + m[12];
    final rw = m[3] * x + m[7] * y + m[15];
    return rw == 1.0 ? rx : rx / rw;
  }

  static double _mappedY(Float64List m, double x, double y) {
    final ry = m[1] * x + m[5] * y + m[13];
    final rw = m[3] * x + m[7] * y + m[15];
    return rw == 1.0 ? ry : ry / rw;
  }

  // MARK: Native filter

  final _shaderHandle = LayerHandle<BackdropFilterLayer>();
  final _clipRectLayerHandle = LayerHandle<ClipRectLayer>();
  final _seedClipHandle = LayerHandle<ClipRectLayer>();
  final _seedHandle = LayerHandle<BackdropFilterLayer>();

  /// Whether a layer that [blursOwnBackdrop] copies its backdrop; off
  /// blurs the whole pass as every other layer does, for an A/B.
  @visibleForTesting
  static bool debugSeedsBlur = true;

  static final BackdropKey _probeKey = BackdropKey();
  static final Set<String> _probeLogged = {};

  bool _blursOwnBackdrop = false;

  /// See [LiquidGlassLayer.blursOwnBackdrop].
  bool get blursOwnBackdrop => _blursOwnBackdrop;
  set blursOwnBackdrop(bool value) {
    if (_blursOwnBackdrop == value) return;
    _blursOwnBackdrop = value;
    _pass.markInputsChanged();
    markNeedsPaint();
  }

  GlassBackdropCache? _backdropCache;

  /// The cached backdrop the glass paints over instead of reading its
  /// backdrop, while [debugMorphBackdropCache] is on.
  GlassBackdropCache? get backdropCache => _backdropCache;
  set backdropCache(GlassBackdropCache? value) {
    if (identical(value, _backdropCache)) return;
    _backdropCache = value;
    _pass.markInputsChanged();
    markNeedsPaint();
  }

  // Decided when the layer paints; the copy itself is taken while the
  // frame composites.
  bool _cachesBackdrop = false;

  bool get _wantsCachedBackdrop =>
      _backdropCache != null &&
      debugMorphBackdropCache &&
      debugGlassCostProbe == GlassCostProbe.off &&
      _backdropCache!.ready;

  Color? _solidBackdrop;

  /// See [LiquidGlassLayer.solidBackdrop].
  Color? get solidBackdrop => _solidBackdrop;
  set solidBackdrop(Color? value) {
    if (_solidBackdrop == value) return;
    _solidBackdrop = value;
    _pass.markInputsChanged();
    markNeedsPaint();
  }

  /// The opaque color the glass is shaded over without a backdrop read, or
  /// null when the layer reads its backdrop.
  Color? get _solid {
    if (debugGlassCostProbe == GlassCostProbe.solid) {
      return const Color(0xFF000000);
    }
    final color = _solidBackdrop;
    return color != null && color.a == 1 ? color : null;
  }

  // The slot of the picture the glass is recorded into over a solid
  // backdrop; a retained geometry refresh replaces the picture in it.
  final _solidHandle = LayerHandle<ContainerLayer>();

  /// Whether the layer drew its glass as a paint over [solidBackdrop] in
  /// its last frame.
  @visibleForTesting
  bool get debugDrawsOverSolidBackdrop => _solidHandle.layer != null;

  bool get _seedsBlur =>
      _blursOwnBackdrop &&
      debugSeedsBlur &&
      frost.passSigma > 0 &&
      backdropKey == null &&
      !compositionProbeSeeding;

  /// The logical pixels around the blurred coverage the frost blur reads.
  double get _seedMargin => morphBlurReach(frost.passSigma, devicePixelRatio);

  // The seed pass's clip in the translated frame, on the filter clip's
  // pixel buckets so retained motion does not resize the pass.
  Rect? get _seedClip {
    final clip = _filterClip;
    if (clip == null) return null;
    final translation = compositorTranslation;
    return clip
        .shift(translation)
        .inflate(_seedMargin)
        .expandToPixelBuckets(devicePixelRatio)
        .shift(-translation);
  }

  // Impeller bounds the seed pass by its clip and every clip above it,
  // rounded out to device pixels; the glass shader's fragment coordinates
  // start at that origin.
  Offset _seedPassOrigin(Matrix4 layerToScreen) {
    final seed = _seedClip;
    if (seed == null) return Offset.zero;
    var screen = MatrixUtils.transformRect(layerToScreen, seed);
    if (screenClipAbove(this) case final above?) {
      screen = screen.intersect(above);
    }
    return Offset(
      (screen.left * devicePixelRatio).floorToDouble() / devicePixelRatio,
      (screen.top * devicePixelRatio).floorToDouble() / devicePixelRatio,
    );
  }

  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _shaderHandle.layer;

  /// The most recent layer-local clip used by the native glass filter.
  ///
  /// This intentionally excludes exterior-shadow support, which is painted in
  /// a separate canvas layer before the clipped filter pass.
  @visibleForTesting
  Rect? debugFilterBounds;
  Rect? _filterMaterialBounds;
  // The bounds the last sync was given, before a shader frost grew them.
  Rect? _filterGlassBounds;
  Offset _filterPaintOffset = Offset.zero;

  // The native filter clip, kept on stable pixel buckets in the translated
  // frame so retained compositor motion does not resize its render target.
  Rect? get _filterClip {
    final bounds = _filterMaterialBounds;
    if (bounds == null) return null;
    final translation = compositorTranslation;
    return bounds
        .shift(translation)
        .expandToPixelBuckets(devicePixelRatio)
        .shift(-translation);
  }

  // Unblurred, the filter input is the backdrop inside the filter's own clip.
  // With a blur pass, Impeller re-rasterizes the blurred input into the
  // filter's coverage, which every clip around the filter narrows: the
  // retained clips between this layer and its shapes, and the clips above
  // this layer up to its pass. The texture is transparent outside it.
  ImageFilter? _cachedFilter;

  ImageFilter _updateShaderFilter() {
    final inputsChanged = _pass.takeInputsChanged();
    if (_cachedFilter != null && !inputsChanged) return _cachedFilter!;
    if (debugGlassCostProbe == GlassCostProbe.copy) {
      return _cachedFilter = morphBackdropSeed;
    }
    final shader = _pass.shaderFilter();
    final frostSigma = frost.passSigma;
    if (debugGlassCostProbe != GlassCostProbe.off && _probeLogged.length < 60) {
      final bounds = debugFilterBounds;
      final screen = bounds == null || !attached
          ? null
          : MatrixUtils.transformRect(getTransformTo(null), bounds);
      final key =
          'sigma ${frostSigma.toStringAsFixed(2)} '
          '${(screen?.width ?? 0) ~/ 20 * 20}x${(screen?.height ?? 0) ~/ 20 * 20} '
          'top ${(screen?.top ?? 0) ~/ 100 * 100}';
      if (_probeLogged.add(key)) debugPrint('MORPH_GLASS_LAYER $key');
    }
    if (debugGlassCostProbe == GlassCostProbe.nofrost) {
      return _cachedFilter = shader;
    }
    final filter = frostSigma > 0
        ? ImageFilter.compose(inner: _pass.frostBlur(frostSigma), outer: shader)
        : shader;
    _cachedFilter = filter;
    return filter;
  }

  // Both painting and retained geometry updates need the same native filter
  // bounds. This only updates existing handles; it never paints children.
  Rect _syncMaterialFilter(
    Rect glassBounds,
    Offset offset, {
    bool retained = false,
  }) {
    // A frost the final pass blurs reads three sigma past the rim.
    final shaderFrost = frost.shaderSigma;
    final materialBounds = shaderFrost > 0
        ? glassBounds.inflate(3 * shaderFrost / devicePixelRatio)
        : glassBounds;
    final filterBounds = materialBounds.expandToPixelBuckets(devicePixelRatio);
    _filterGlassBounds = glassBounds;
    _filterMaterialBounds = materialBounds;
    _filterPaintOffset = offset;
    debugFilterBounds = filterBounds;
    if (_solid case final solid?) {
      _recordSolidMaterial(solid, filterBounds, offset);
      return filterBounds;
    }
    _clipRectLayerHandle.layer?.clipRect = filterBounds.shift(offset);
    if (_seedClipHandle.layer case final seedClip?) {
      if (_seedClip case final seed?) seedClip.clipRect = seed.shift(offset);
    }
    if (retained &&
        (_seedsBlur && !drawableEmpty) != (_seedClipHandle.layer != null)) {
      markNeedsPaint();
    }
    if (drawableEmpty) {
      _shaderHandle.layer?.remove();
      _shaderHandle.layer = null;
      _cachedFilter = null;
    } else {
      syncCoordinateMapping();
      _pass.readBackdrop();
      final shader = (_shaderHandle.layer ??= BackdropFilterLayer())
        ..filter = _updateShaderFilter()
        ..backdropKey = switch (debugGlassCostProbe) {
          GlassCostProbe.shared => _probeKey,
          _ => backdropKey,
        };
      GlassLayerOwners.note(shader, this);
      if (_clipRectLayerHandle.layer case final clip?) {
        if (!identical(shader.parent, clip)) {
          shader.remove();
          clip.append(shader);
        }
      }
    }
    return filterBounds;
  }

  void _paintMaterialFilter(
    PaintingContext context,
    Offset offset,
    Rect materialBounds,
  ) {
    if (!attached) return;
    if (debugGlassCostProbe == GlassCostProbe.skip) {
      _releaseCompositorFilter();
      return;
    }
    _cachesBackdrop = _wantsCachedBackdrop;
    if (_cachesBackdrop) {
      // The filter stays ready: a frame whose copy is not exact reads the
      // backdrop through it. Compositing picks the path.
      _seedClipHandle.layer = null;
      _seedHandle.layer = null;
      _syncMaterialFilter(materialBounds, offset);
      context.addLayer(_solidHandle.layer ??= ContainerLayer());
      return;
    }
    if (_solid != null) {
      _releaseBackdropFilter();
      _syncMaterialFilter(materialBounds, offset);
      context.addLayer(_solidHandle.layer!);
      return;
    }
    _solidHandle.layer = null;
    // The engine snapshots this shader's uniforms into the native image
    // filter at creation, so the composed filter can only be reused while
    // every snapshotted input is unchanged. Repaints with identical shader
    // inputs (for example a static layer invalidated by foreground content)
    // skip all Dart and native filter allocation.
    final filterBounds = _syncMaterialFilter(materialBounds, offset);
    final shaderLayer = _shaderHandle.layer;
    assert(() {
      if (!drawableEmpty && shaderLayer != null) {
        debugRegisterBackdropCapture(this, backdropKey);
      }
      return true;
    }(), 'Count independent backdrop captures in debug builds.');

    void paintFilter(PaintingContext context, Offset offset) {
      _clipRectLayerHandle.layer = context.pushClipRect(
        needsCompositing,
        offset,
        filterBounds,
        (context, offset) {
          if (drawableEmpty) return;
          context.pushLayer(shaderLayer!, (context, offset) {}, offset);
        },
        oldLayer: _clipRectLayerHandle.layer,
      );
    }

    final seed = _seedsBlur && !drawableEmpty ? _seedClip : null;
    if (seed == null) {
      _seedClipHandle.layer = null;
      _seedHandle.layer = null;
      paintFilter(context, offset);
      return;
    }
    final seedLayer = _seedHandle.layer ??= BackdropFilterLayer(
      filter: morphBackdropSeed,
    );
    GlassLayerOwners.note(seedLayer, this);
    _seedClipHandle.layer = context.pushClipRect(
      needsCompositing,
      offset,
      seed,
      (context, offset) => context.pushLayer(seedLayer, paintFilter, offset),
      oldLayer: _seedClipHandle.layer,
    );
  }

  // Records the glass as one rect painted with the final shader over
  // [solid], into the layer's own picture so a retained geometry refresh
  // can replace it without painting. The shader snapshots its uniforms and
  // samplers when the rect is recorded, as the filter does when it is
  // created. The background sampler keeps whatever image is bound to it
  // (the matte or the blank image); the shader never reads it.
  void _recordSolidMaterial(Color solid, Rect filterBounds, Offset offset) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = filterBounds.shift(offset);
    if (!drawableEmpty) {
      syncCoordinateMapping();
      final shader = _pass.overSolid(
        solid,
        filterBounds.size * devicePixelRatio,
      );
      final paint = Paint();
      paint.shader = shader;
      // The filter path clips its output to this rect with a hard edge.
      paint.isAntiAlias = false;
      canvas.drawRect(rect, paint);
    }
    final slot = _solidHandle.layer ??= ContainerLayer();
    slot.removeAllChildren();
    final picture = PictureLayer(rect);
    picture.picture = recorder.endRecording();
    slot.append(picture);
  }

  /// Drops native backdrop-filter state while this sample is idle.
  void _releaseCompositorFilter() {
    _releaseBackdropFilter();
    _solidHandle.layer = null;
  }

  void _releaseBackdropFilter() {
    _shaderHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _seedClipHandle.layer = null;
    _seedHandle.layer = null;
    _cachedFilter = null;
  }

  // MARK: Compositing

  @override
  void onTransformChanged() {
    _phaseMoved = true;
    // A layer without shapes has no mapping to synchronize; a shape that
    // registers repaints through it.
    if (link.shapes.isEmpty) return;
    // Synchronize the frame's mapping after retained translation is resolved.
    if (!hasReusableGeometry && !hasReusableIdleContents) markNeedsPaint();
  }

  @override
  void onCompositing() {
    if (!attached) {
      _compositingScreen = null;
      return;
    }
    runCompositorPoll();
    if (_backdropCache != null && _cachesBackdrop != _wantsCachedBackdrop) {
      // The source came or went: paint picks the path again next frame.
      markNeedsPaint();
    } else if (_cachesBackdrop) {
      _composeCachedBackdrop();
    }
    _compositingScreen = null;
    _phaseMoved = false;
  }

  // Records the glass as one rect painted with the final shader over the
  // cache's copy of the backdrop. The rect is drawn in screen device pixels
  // (the canvas undoes the layer's transform), so the shader's fragment
  // coordinates are the screen coordinates its filter mapping expects and
  // the copy is sampled where the backdrop filter would have read.
  void _composeCachedBackdrop() {
    final slot = _solidHandle.layer;
    final bounds = _filterGlassBounds;
    if (slot == null || bounds == null) return;
    slot.removeAllChildren();
    if (drawableEmpty) return;
    if (_recordCachedMaterial(slot, bounds)) return;
    // No exact copy this frame: the backdrop filter, its mapping synced to
    // this frame's transform.
    final offset = _filterPaintOffset;
    final filterBounds = _syncMaterialFilter(bounds, offset);
    final shaderLayer = _shaderHandle.layer;
    if (shaderLayer == null) return;
    final clip = _clipRectLayerHandle.layer ??= ClipRectLayer();
    clip.clipRect = filterBounds.shift(offset);
    clip.clipBehavior = Clip.hardEdge;
    if (!identical(shaderLayer.parent, clip)) {
      shaderLayer.remove();
      clip.append(shaderLayer);
    }
    slot.append(clip);
  }

  bool _recordCachedMaterial(ContainerLayer slot, Rect bounds) {
    final cache = _backdropCache!;
    final dpr = devicePixelRatio;
    final translation = compositorTranslation;
    final screen = getTransformTo(null);
    screen.multiply(
      Matrix4.translationValues(translation.dx, translation.dy, 0),
    );
    final filterBounds = bounds.expandToPixelBuckets(dpr);
    final logical = MatrixUtils.transformRect(screen, filterBounds);
    final sigma = frost.passSigma;
    // Everything the glass may sample: its bounds, the frost's kernel and
    // the refraction's reach (dispersion stays inside it).
    final copy = cache.imageFor(
      sigma: sigma,
      devicePixelRatio: dpr,
      region: logical.inflate(
        3 * sigma + settings.effectiveRefractionAmount + 2,
      ),
    );
    if (copy == null) return false;
    final (image, corner) = copy;
    syncCoordinateMapping();
    // The copy starts at [corner]: fragment coordinates are taken from
    // there, so the filter->matte offset moves by the basis times it.
    final origin = corner * dpr;
    final shader = _pass.overCopy(
      image,
      filterToMatteOffset: switch (_coordinateMapping) {
        (final b0, final b1, final b2, final b3, final ox, final oy) => Offset(
          ox + b0 * origin.dx + b1 * origin.dy,
          oy + b2 * origin.dx + b3 * origin.dy,
        ),
        null => null,
      },
      overlay: cache.overlay,
    );
    final device = Rect.fromLTRB(
      logical.left * dpr,
      logical.top * dpr,
      logical.right * dpr,
      logical.bottom * dpr,
    );
    final canvasToScreen = screen.clone();
    canvasToScreen.multiply(
      Matrix4.translationValues(
        -_filterPaintOffset.dx,
        -_filterPaintOffset.dy,
        0,
      ),
    );
    final screenToCanvas = Matrix4.zero();
    if (screenToCanvas.copyInverse(canvasToScreen) == 0) return false;
    screenToCanvas.multiply(Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1));
    screenToCanvas.multiply(Matrix4.translationValues(origin.dx, origin.dy, 0));
    final drawn = device.shift(-origin);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.transform(screenToCanvas.storage);
    final paint = Paint();
    paint.shader = shader;
    paint.isAntiAlias = false;
    canvas.drawRect(drawn, paint);
    final picture = PictureLayer(
      MatrixUtils.transformRect(screenToCanvas, drawn),
    );
    picture.picture = recorder.endRecording();
    slot.append(picture);
    return true;
  }

  @override
  bool setCompositorTranslation(Offset value) {
    final changed = super.setCompositorTranslation(value);
    if (changed) _phaseMoved = true;
    return changed;
  }

  @override
  void onCompositorTranslated(Offset translation) {
    if (_cachesBackdrop) return;
    final clip = _filterClip;
    if (clip != null && _clipRectLayerHandle.layer != null) {
      _clipRectLayerHandle.layer!.clipRect = clip.shift(_filterPaintOffset);
    }
    if (_seedClipHandle.layer case final seedClip?) {
      if (_seedClip case final seed?) {
        seedClip.clipRect = seed.shift(_filterPaintOffset);
      }
    }
    final mapped =
        !drawableEmpty && hasReusableGeometry && syncCoordinateMapping();
    if (mapped) _shaderHandle.layer?.filter = _updateShaderFilter();
    // The poll reaches here on every composited frame, moved or not; a
    // watch on a still frame would ask for the next frame forever.
    if (mapped || _phaseMoved) _watchRasterPhase();
  }

  @override
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  ) {
    if (_cachesBackdrop) return;
    // A pass-origin change - the probe enabling, or a capture's clip moving
    // with paint-only changes inside it - moves no tracked transform, so the
    // translation poll misses it. Re-sync the coordinate mapping into the
    // retained filter, or repaint when its inputs cannot be reused.
    if (syncCoordinateMapping()) {
      if (!drawableEmpty &&
          hasReusableGeometry &&
          _shaderHandle.layer != null) {
        _shaderHandle.layer!.filter = _updateShaderFilter();
      } else {
        markNeedsPaint();
      }
    }
    final retained = _solid != null
        ? _solidHandle.layer != null
        : (_shaderHandle.layer != null || drawableEmpty) &&
              _clipRectLayerHandle.layer != null;
    if (motion.needsRepaint &&
        retained &&
        refreshRetainedGeometry((shapes, bounds, offset) {
          _syncMaterialFilter(bounds, offset, retained: true);
        })) {
      return;
    }
    if (motion.needsRepaint) markNeedsPaint();
  }

  @override
  void dispose() {
    _shaderHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _seedClipHandle.layer = null;
    _seedHandle.layer = null;
    _solidHandle.layer = null;
    _cachedFilter = null;
    _clearGeometryImage();
    _gpuGeometryRenderer = null;
    _pass.dispose();
    super.dispose();
  }

  // MARK: Geometry

  @protected
  bool needsGeometryUpdate = true;

  /// The matte texels per device pixel of the layer the latest matte was
  /// encoded at ([glassMatteDensity]).
  @visibleForTesting
  double get debugMatteDensity => _encoder.matteDensity;

  // Encodes the committed shapes within [bounds].
  GlassGeometry _encode(Rect bounds) {
    _analytic = false;
    return _encoder.encode(
      shapesWithGeometry,
      bounds,
      layer: this,
      layerToPass: shaderCoordinateTransform,
      flags: (
        analyticEnabled: GlassGeometryFlags.analyticGeometryEnabled,
        resting: _rest.resting,
        capsule: GlassGeometryFlags.analyticCapsuleEnabled,
        flatFace: GlassGeometryFlags.analyticFlatFace,
      ),
    );
  }

  // Takes [geometry], encoded within [bounds], as the current frame.
  void _adopt(GlassGeometry geometry, Rect bounds) {
    switch (geometry) {
      case MatteGeometry(:final image, :final material):
        _geometryImage = image;
        _materialImage = material;
        _materialTextureSize = geometry.materialTextureSize;
        _analytic = false;
      case AnalyticGeometry():
        _geometryImage = null;
        _materialImage = null;
        _materialTextureSize = const Size(1, 1);
        _analytic = true;
    }
    _rest.afterFrame();
    _geometryMatteBounds = geometry.matteBounds;
    _geometryTextureSize = geometry.textureSize;
    _materialCenterInMatte = geometry.materialCenter;
    _materialSizeInMatte = geometry.materialSize;
    _pass.setShapeAppearances(geometry.appearances);
    _rememberEncodedGeometry(bounds);
  }

  Duration? _movedAt;
  bool _phaseWatched = false;
  // Whether this frame moved the layer on screen or changed the compositor
  // translation, either of which moves the pass phase.
  bool _phaseMoved = false;

  // Compositor motion moves the pass phase without a paint, so the shifts
  // baked into the matte go stale. A paint re-encodes them; it is asked for
  // once the motion has stopped for a frame, so the motion itself stays on
  // the compositor.
  void _watchRasterPhase() {
    if (_geometryImage == null) return;
    final scheduler = SchedulerBinding.instance;
    _movedAt = scheduler.currentSystemFrameTimeStamp;
    if (_phaseWatched) return;
    _phaseWatched = true;
    scheduler.addPostFrameCallback(_checkRasterPhase);
  }

  void _checkRasterPhase(Duration _) {
    _phaseWatched = false;
    if (!attached || _geometryImage == null) return;
    final scheduler = SchedulerBinding.instance;
    if (_movedAt == scheduler.currentSystemFrameTimeStamp) {
      _phaseWatched = true;
      scheduler.addPostFrameCallback(_checkRasterPhase);
      scheduler.scheduleFrame();
      return;
    }
    if (_encoder.rasterGridStale(
      shaderCoordinateTransform,
      analytic: _analytic,
    )) {
      markNeedsPaint();
    }
  }
}

/// A device timing probe that replaces one part of every liquid layer's
/// composition; [GlassCostProbe.off] draws the glass as it is.
///
/// The probes change pixels: they exist to split the cost of a glass
/// surface on the device (tool/audit/2026-10-12-glass-composition.md).
@visibleForTesting
GlassCostProbe debugGlassCostProbe = GlassCostProbe.off;

/// The part of a liquid layer's composition that [debugGlassCostProbe]
/// replaces, to time it on a device.
@visibleForTesting
enum GlassCostProbe {
  /// The glass as it is.
  off,

  /// The glass filter is an identity color matrix: the backdrop read, the
  /// layer's offscreen pass and its composite stay, the frost blur and the
  /// glass shader go.
  copy,

  /// No backdrop filter at all: the floor the other probes are read from.
  skip,

  /// Every liquid layer reads one backdrop key: a single backdrop read per
  /// frame, each layer still filtered in its own offscreen pass.
  shared,

  /// The frost blur goes, the glass shader stays in the filter.
  nofrost,

  /// Every liquid layer draws its glass as a paint over opaque black: the
  /// glass shader over the layer's area without a backdrop read or an
  /// offscreen pass.
  solid,
}
