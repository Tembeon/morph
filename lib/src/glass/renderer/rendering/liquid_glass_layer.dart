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
import 'package:morph/src/live.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/internal/raster_phase.dart';
import 'package:morph/src/glass/renderer/internal/render_liquid_glass_geometry.dart';
import 'package:morph/src/glass/renderer/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:morph/src/glass/renderer/liquid_glass_glow.dart';
import 'package:morph/src/glass/renderer/liquid_glass_render_scope.dart';
import 'package:morph/src/glass/renderer/composition/glass_backdrop_draw.dart';
import 'package:morph/src/glass/renderer/geometry/glass_geometry.dart';
import 'package:morph/src/glass/renderer/geometry/glass_rest.dart';
import 'package:morph/src/glass/renderer/geometry/glass_shape_pack.dart';
import 'package:morph/src/glass/renderer/pass/final_pass.dart';
import 'package:morph/src/glass/renderer/pass/glass_frost.dart';
import 'package:morph/src/glass/renderer/plane/render_glass_plane.dart';
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
    this.read = GlassRead.own,
    this.solidBackdrop,
    this.reach,
    this.planePass = false,
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
    this.read = GlassRead.own,
    this.solidBackdrop,
    this.reach,
    super.key,
  }) : planePass = false,
       _settings = const LiquidGlassSettings(),
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

  /// Where the layer's glass reads its backdrop: its plane's one read
  /// ([GlassRead.plane]: the nearest [GlassPlaneScope] or [BackdropGroup],
  /// else a read of its own key), a read of its own at its own place in
  /// paint order ([GlassRead.own], over a cached copy where a
  /// [GlassPlaneScope.backdrop] above declares one), or a read of its own
  /// around its glass for a small frost that animates ([GlassRead.lifted]).
  ///
  /// On Impeller every independent backdrop read copies the whole pass;
  /// glass in one plane pays it once, but does not see what is painted
  /// between its members.
  final GlassRead read;

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

  /// How far around its box the layer may paint, or null for anywhere.
  ///
  /// The backdrop pass the renderer blurs then covers the layer's control
  /// instead of the whole screen.
  final double? reach;

  /// Whether the layer is the pass of a plane, shading the glass merged
  /// into it; it is no member of a plane itself.
  final bool planePass;

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
    if (widget.read == GlassRead.plane && BackdropGroup.of(context) == null) {
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
    final backdropKey = widget.read == GlassRead.plane
        ? BackdropGroup.of(context)?.backdropKey
        : null;
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
    final backdropCache = backdropKey == null
        ? GlassPlaneScope.cacheOf(context)
        : null;
    final scope = LiquidGlassRenderScope(
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
                  blursOwnBackdrop: widget.read == GlassRead.lifted,
                  solidBackdrop: widget.solidBackdrop,
                  // A plane reads its own copy on purpose (glass painted
                  // in between belongs in it); only a read of its own is
                  // cached.
                  backdropCache: backdropCache,
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
    );
    if (widget.planePass) return RepaintBoundary(child: scope);
    return _GlassMember(
      read: widget.read,
      link: _link,
      inputsOf: () => (
        settings: widget.settings,
        fused: widget.field != null,
        glows: widget.glowOf?.call() != null,
      ),
      live: live,
      glows: widget.glows,
      reach: widget.reach,
      painted: (widget.solidBackdrop?.a ?? 0) == 1 || backdropCache != null,
      backdropKey: backdropKey,
      child: scope,
    );
  }
}

class _GlassMember extends SingleChildRenderObjectWidget {
  const _GlassMember({
    required this.read,
    required this.link,
    required this.inputsOf,
    required this.live,
    required this.glows,
    required this.reach,
    required this.painted,
    required this.backdropKey,
    required super.child,
  });

  final GlassRead read;
  final GeometryRenderLink link;
  final GlassMemberInputs Function() inputsOf;
  final Listenable? live;
  final Listenable? glows;
  final double? reach;
  final bool painted;
  final BackdropKey? backdropKey;

  @override
  RenderGlassMember createRenderObject(BuildContext context) {
    final member = RenderGlassMember(
      read: read,
      link: link,
      inputsOf: inputsOf,
      reach: reach,
      painted: painted,
      backdropKey: backdropKey,
    );
    member.listen(live, glows);
    return member;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassMember renderObject,
  ) {
    renderObject.read = read;
    renderObject.link = link;
    renderObject.readInputs(inputsOf);
    renderObject.listen(live, glows);
    renderObject.reach = reach;
    renderObject.painted = painted;
    renderObject.backdropKey = backdropKey;
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
        GlassRestHost,
        GlassDrawSource {
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
    _draw = GlassBackdropDraw(this, _pass);
    _pass.updateSettings();
  }

  late final GlassFinalPass _pass;
  late final GlassGeometryEncoder _encoder;
  late final GlassRestWatch _rest;
  late final GlassBackdropDraw _draw;

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
  /// A new glow is a change of the final shader's uniforms only: over
  /// geometry the layer can reuse, the backdrop filter it composited last
  /// is replaced by one over the new uniforms, or glass over a solid
  /// backdrop is recorded again into its slot, and nothing paints. Glass
  /// over a cached backdrop repaints.
  LiquidGlassGlow? get glow => _pass.glow;
  set glow(LiquidGlassGlow? value) {
    if (!_pass.setGlow(value)) return;
    if (!_draw.refreshUniforms()) markNeedsPaint();
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
  @override
  bool get drawableEmpty =>
      shapesWithGeometry.isNotEmpty && !hasDrawableGlass(shapesWithGeometry);

  /// True once geometry is ready to draw again - a matte encoded, or an
  /// analytic frame's shapes written into its shader's uniforms - so
  /// ancestor motion can stay on the compositor without crossing this
  /// layer's repaint boundary.
  @override
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
      _draw.release();
      releaseRetainedEffectLayer();
      return;
    }
    final materialPaintBounds = _prepareGeometryAppearance(geometryBounds);
    switch (frameState) {
      case GlassFrameState.empty:
        _clearGeometryImage();
        _draw.release();
        if (shapesWithGeometry.isEmpty) {
          releaseRetainedEffectLayer();
          return;
        }
        needsGeometryUpdate = false;
        link.markClean();
        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          _draw.paint(effectContext, effectOffset, materialPaintBounds);
        });
      case GlassFrameState.idle:
        // Keep the last matte and its encode snapshot; ancestor motion
        // stays compositor-only while hidden because the translation poll
        // rebaselines on the committed frame, not on that snapshot. Skip
        // the backdrop filter so idle glass does not sample.
        updateIdleAncestorClips();
        _draw.release();
        paintRetainedEffect(context, offset, (effectContext, effectOffset) {});
      case GlassFrameState.active:
        // Analytic shapes have no raster grid; test that before walking
        // the tree for the pass transform.
        if (hasReusableGeometry &&
            !_analytic &&
            _encoder.rasterGridStale(
              _draw.passTransform,
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
            _draw.paint(effectContext, effectOffset, materialPaintBounds);
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
    _draw.syncMapping();
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

  @override
  Matrix4? get compositingScreen => _compositingScreen;

  @override
  Offset get effectTranslation => compositorTranslation;

  @override
  Rect? get effectClipBounds => retainedClipBounds;

  @override
  bool get seededOpacity => compositionProbeSeeding;

  // MARK: Composition inputs

  bool _blursOwnBackdrop = false;

  /// See [LiquidGlassLayer.blursOwnBackdrop].
  @override
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
  @override
  GlassBackdropCache? get backdropCache => _backdropCache;
  set backdropCache(GlassBackdropCache? value) {
    if (identical(value, _backdropCache)) return;
    _backdropCache = value;
    _pass.markInputsChanged();
    markNeedsPaint();
  }

  Color? _solidBackdrop;

  /// See [LiquidGlassLayer.solidBackdrop].
  @override
  Color? get solidBackdrop => _solidBackdrop;
  set solidBackdrop(Color? value) {
    if (_solidBackdrop == value) return;
    _solidBackdrop = value;
    _pass.markInputsChanged();
    markNeedsPaint();
  }

  /// Whether the layer drew its glass as a paint over [solidBackdrop] in
  /// its last frame.
  @visibleForTesting
  bool get debugDrawsOverSolidBackdrop => _draw.drawsOverSolid;

  /// The most recent layer-local clip used by the native glass filter.
  @visibleForTesting
  Rect? get debugFilterBounds => _draw.filterBounds;

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
    _draw.composite();
    _compositingScreen = null;
    _phaseMoved = false;
  }

  @override
  bool setCompositorTranslation(Offset value) {
    final changed = super.setCompositorTranslation(value);
    if (changed) _phaseMoved = true;
    return changed;
  }

  @override
  void onCompositorTranslated(Offset translation) {
    if (_draw.cachesBackdrop) return;
    final mapped = _draw.translated();
    // The poll reaches here on every composited frame, moved or not; a
    // watch on a still frame would ask for the next frame forever.
    if (mapped || _phaseMoved) _watchRasterPhase();
  }

  @override
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  ) {
    if (_draw.cachesBackdrop) return;
    final retained = _draw.missed();
    if (motion.needsRepaint &&
        retained &&
        refreshRetainedGeometry((shapes, bounds, offset) {
          _draw.sync(bounds, offset, retained: true);
        })) {
      return;
    }
    if (motion.needsRepaint) markNeedsPaint();
  }

  @override
  void dispose() {
    _draw.dispose();
    _clearGeometryImage();
    _gpuGeometryRenderer = null;
    _pass.dispose();
    super.dispose();
  }

  // MARK: Geometry

  @protected
  bool needsGeometryUpdate = true;

  /// The matte texels per device pixel of the layer, along x and y, the
  /// latest matte was encoded at ([glassMatteDensity]).
  @visibleForTesting
  ({double x, double y}) get debugMatteDensity => _encoder.matteDensity;

  // Encodes the committed shapes within [bounds].
  GlassGeometry _encode(Rect bounds) {
    _analytic = false;
    return _encoder.encode(
      shapesWithGeometry,
      bounds,
      layer: this,
      layerToPass: _draw.passTransform,
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
    if (_encoder.rasterGridStale(_draw.passTransform, analytic: _analytic)) {
      markNeedsPaint();
    }
  }
}
