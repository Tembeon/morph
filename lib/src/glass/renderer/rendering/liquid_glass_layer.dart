// ignore_for_file: avoid_setters_without_getters, cascade_invocations

import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/liquid_field.dart' show liquidMinMergeWidth;
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/internal/ancestor_clip.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_capture_debug.dart';
import 'package:morph/src/glass/renderer/internal/blur_reach.dart';
import 'package:morph/src/glass/renderer/internal/filter_pass_transform.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer.dart';
import 'package:morph/src/glass/renderer/internal/glass_live.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/internal/raster_phase.dart';
import 'package:morph/src/glass/renderer/internal/render_liquid_glass_geometry.dart';
import 'package:morph/src/glass/renderer/internal/rounded_superellipse_parameters.dart';
import 'package:morph/src/glass/renderer/internal/shader_filter.dart';
import 'package:morph/src/glass/renderer/internal/snap_rect_to_pixels.dart';
import 'package:morph/src/glass/renderer/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:morph/src/glass/renderer/liquid_glass_render_scope.dart';
import 'package:morph/src/glass/renderer/liquid_glass_settings.dart';
import 'package:morph/src/glass/renderer/rendering/consolidated_fake_glass_layer.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_render_object.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

/// Shades independently registered shapes or an owner-supplied fused field.
///
/// The owner computes every union before supplying [field]. Shapes provide
/// the material and shadows; this layer never fuses their geometry.
class LiquidGlassLayer extends StatefulWidget {
  /// Creates a new [LiquidGlassLayer] with the given [child] and [settings].
  const LiquidGlassLayer({
    required this.child,
    this._settings = const LiquidGlassSettings(),
    this.defaultAppearance,
    this.fake = false,
    this.useBackdropGroup = false,
    this.backdropKey,
    this.blursOwnBackdrop = false,
    this._field,
    super.key,
  }) : live = null,
       settingsOf = null,
       fieldOf = null,
       outlineOf = null;

  /// Creates a layer whose settings and field follow [live].
  ///
  /// Every notification of [live] writes [settingsOf] and [fieldOf] into
  /// the layer's render object and into its shapes without rebuilding
  /// them.
  const LiquidGlassLayer.live({
    required this.child,
    required this.live,
    required LiquidGlassSettings Function() this.settingsOf,
    this.fieldOf,
    this.outlineOf,
    this.defaultAppearance,
    this.fake = false,
    this.useBackdropGroup = false,
    this.backdropKey,
    this.blursOwnBackdrop = false,
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

  /// The outline of the one body the layer's shapes form when its owner
  /// fused them without a field (a plain union of the shapes), for a live
  /// layer.
  ///
  /// The liquid geometry pass shades such a body from the shapes
  /// themselves; fake glass clips its backdrop and surfaces to it as it
  /// does to a field's [GlassField.outline].
  final Path? Function()? outlineOf;

  final LiquidGlassSettings _settings;

  final GlassField? _field;

  /// The distance field of the one body the layer's shapes form, when its
  /// owner has fused them already.
  ///
  /// With a field the geometry pass shades the body the field describes
  /// instead of the shapes' own outlines or blend groups; the shapes still
  /// supply the appearance, the shadows and the bounds of the matte, which
  /// must contain the body. Fake glass, which shades no field, clips its
  /// backdrop and surfaces to the field's [GlassField.outline] instead.
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

  /// Whether to replace all liquid glass effects in this layer with
  /// [FakeGlass] effects.
  ///
  /// The layer also uses [FakeGlass] when Impeller shader filters or Flutter
  /// GPU are unavailable, for example on Skia.
  final bool fake;

  /// Whether to share a [BackdropGroup] capture for backdrop effects.
  ///
  /// The nearest ancestor group is used when one exists. Otherwise this layer
  /// creates a local group so its FakeGlass shapes can share backdrop capture
  /// work. Multiple [LiquidGlassLayer]s need a common ancestor group or an
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
  /// This applies consistently to real and fake glass.
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

  /// Whether there is a [LiquidGlassLayer] in the widget tree above the given
  /// [context].
  static bool existsIn(BuildContext context, {bool watch = true}) {
    return LiquidGlassRenderScope.maybeOf(context, watch: watch) != null;
  }

  @override
  State<LiquidGlassLayer> createState() => _LiquidGlassLayerState();
}

class _LiquidGlassLayerState extends State<LiquidGlassLayer>
    with SingleTickerProviderStateMixin {
  static List<String> get _fakeSurfaceShaderAssets => [
    ShaderKeys.fakeGlassSurface,
  ];

  late final GeometryRenderLink _link = GeometryRenderLink();

  late final _LayerSettings _settingsLive = _LayerSettings(this);

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
  final List<FlutterGpuGeometryRenderer> _retiredGpuGeometryRenderers = [];
  bool _triedGpuGeometryRenderer = false;
  bool _gpuInitializationScheduled = false;
  bool _loggedFallback = false;

  // Fake and real subtrees never coexist, so one key keeps the user's subtree
  // alive across a renderer swap without ever being mounted twice.
  final _childKey = GlobalKey(debugLabel: 'LiquidGlassLayer.child');

  void _logDebugFallback(String message) {
    if (!kDebugMode || _loggedFallback) return;
    _loggedFallback = true;
    debugPrint('morph: $message');
  }

  void _tryCreateCachedGpuGeometryRenderer() {
    if (widget.fake ||
        !ImageFilter.isShaderFilterSupported ||
        _triedGpuGeometryRenderer) {
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
      if (!mounted || widget.fake || _triedGpuGeometryRenderer) return;

      _triedGpuGeometryRenderer = true;
      try {
        final renderer = await FlutterGpuGeometryRenderer.fromAsset(
          ShaderKeys.gpuGeometryShaderBundle,
        );
        if (!mounted || widget.fake) {
          renderer.dispose();
          return;
        }
        _gpuGeometryRenderer = renderer;
      } on Object catch (error) {
        if (!mounted) return;
        _logDebugFallback(
          'Flutter GPU is unavailable; LiquidGlassLayer is using FakeGlass. '
          'Enable Impeller and Flutter GPU for the full glass effect. $error',
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
    if (oldWidget.fake && !widget.fake) {
      _tryCreateCachedGpuGeometryRenderer();
    }
    if (!oldWidget.fake && widget.fake) {
      final renderer = _gpuGeometryRenderer;
      _gpuGeometryRenderer = null;
      _triedGpuGeometryRenderer = false;
      if (renderer != null) {
        // The old real render subtree is removed during this rebuild. Retire
        // its textures after that frame so it cannot contaminate subsequent
        // fake-only measurements, without invalidating a sampler still used by
        // the outgoing subtree.
        _retiredGpuGeometryRenderers.add(renderer);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_retiredGpuGeometryRenderers.remove(renderer)) return;
          renderer.dispose();
        });
      }
    }
  }

  @override
  void dispose() {
    _gpuGeometryRenderer?.dispose();
    for (final renderer in _retiredGpuGeometryRenderers) {
      renderer.dispose();
    }
    _retiredGpuGeometryRenderers.clear();
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
    if (!widget.fake && shaderFiltersSupported) {
      // Android's Impeller context is not available until its first surface
      // frame has been established. Creating flutter_gpu resources directly
      // from build can therefore block the UI isolate before the first frame.
      _scheduleGpuGeometryRendererInitialization();
    }
    final gpuRenderer = _gpuGeometryRenderer;
    final useFake =
        widget.fake || !shaderFiltersSupported || gpuRenderer == null;
    if (useFake) {
      if (!widget.fake && !shaderFiltersSupported && kDebugMode) {
        _logDebugFallback(
          'Impeller shader filters are unavailable; LiquidGlassLayer is using '
          'FakeGlass. Enable Impeller and Flutter GPU for the full effect.',
        );
      }

      return _buildFakeLayer(
        backdropKey: backdropKey,
        defaultAppearance: defaultAppearance,
        settings: widget.settings,
        child: KeyedSubtree(key: _childKey, child: widget.child),
      );
    }

    final live = widget.live;
    return RepaintBoundary(
      child: LiquidGlassRenderScope(
        settings: widget.settings,
        settingsLive: live == null ? null : _settingsLive,
        defaultAppearance: defaultAppearance,
        backdropKey: backdropKey,
        child: InheritedGeometryRenderLink(
          link: _link,
          child: MultiShaderBuilder(assetKeys: ShaderKeys.liquidGlassRenders, (
            context,
            shaders,
            child,
          ) {
            return _RawShapes(
              defaultRenderShader: shaders[0],
              ios27RenderShader: shaders[1],
              materialRenderShader: shaders[2],
              tintRenderShader: shaders[3],
              tintIos27RenderShader: shaders[4],
              backdropKey: backdropKey,
              blursOwnBackdrop: widget.blursOwnBackdrop,
              live: live,
              settingsOf: () => widget.settings,
              defaultAppearance: defaultAppearance,
              link: _link,
              gpuGeometryRenderer: gpuRenderer,
              fieldOf: () => widget.field,
              child: child!,
            );
          }, child: KeyedSubtree(key: _childKey, child: widget.child)),
        ),
      ),
    );
  }

  Widget _buildFakeLayer({
    required BackdropKey? backdropKey,
    required LiquidGlassAppearance defaultAppearance,
    required LiquidGlassSettings settings,
    required Widget child,
  }) {
    // Match the full renderer's retained subtree boundary. FakeGlass paints
    // several contour-following canvas bands; without this boundary an
    // ancestor/compositor transform can make every band record again even
    // though neither the shape nor material changed.
    final live = widget.live;
    Widget buildFakeSurfaceLayer(FragmentShader? surfaceShader) {
      return RepaintBoundary(
        child: LiquidGlassRenderScope(
          settings: settings,
          settingsLive: live == null ? null : _settingsLive,
          defaultAppearance: defaultAppearance,
          consolidatesFakeBackdrop: true,
          consolidatesFakeSurface: true,
          backdropKey: backdropKey,
          child: InheritedGeometryRenderLink(
            link: _link,
            child: ConsolidatedFakeGlassLayer(
              link: _link,
              live: live,
              settingsOf: () => widget.settings,
              defaultAppearance: defaultAppearance,
              backdropKey: backdropKey,
              surfaceShader: surfaceShader,
              outlineOf: () =>
                  widget.field?.outline ?? widget.outlineOf?.call(),
              child: child,
            ),
          ),
        ),
      );
    }

    return MultiShaderBuilder(
      assetKeys: _fakeSurfaceShaderAssets,
      (_, shaders, _) => buildFakeSurfaceLayer(shaders.firstOrNull),
      child: buildFakeSurfaceLayer(null),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.defaultRenderShader,
    required this.ios27RenderShader,
    required this.materialRenderShader,
    required this.tintRenderShader,
    required this.tintIos27RenderShader,
    required this.backdropKey,
    required this.blursOwnBackdrop,
    required this.live,
    required this.settingsOf,
    required this.defaultAppearance,
    required Widget super.child,
    required this.link,
    required this.fieldOf,
    this.gpuGeometryRenderer,
  });

  final FragmentShader defaultRenderShader;
  final FragmentShader ios27RenderShader;
  final FragmentShader materialRenderShader;
  final FragmentShader tintRenderShader;
  final FragmentShader tintIos27RenderShader;
  final BackdropKey? backdropKey;
  final bool blursOwnBackdrop;
  final Listenable? live;
  final LiquidGlassSettings Function() settingsOf;
  final LiquidGlassAppearance defaultAppearance;
  final GeometryRenderLink link;
  final FlutterGpuGeometryRenderer? gpuGeometryRenderer;
  final GlassField? Function() fieldOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final layer = RenderLiquidGlassLayer(
      field: fieldOf(),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      defaultRenderShader: defaultRenderShader,
      ios27RenderShader: ios27RenderShader,
      materialRenderShader: materialRenderShader,
      tintRenderShader: tintRenderShader,
      tintIos27RenderShader: tintIos27RenderShader,
      backdropKey: backdropKey,
      settings: settingsOf(),
      defaultAppearance: defaultAppearance,
      link: link,
      gpuGeometryRenderer: gpuGeometryRenderer,
    );
    layer.blursOwnBackdrop = blursOwnBackdrop;
    layer.bindLive(live, () => _apply(layer));
    return layer;
  }

  void _apply(RenderLiquidGlassLayer layer) {
    layer.settings = settingsOf();
    layer.field = fieldOf();
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
    renderObject.bindLive(live, () => _apply(renderObject));
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
    with TransformTrackingRenderObjectMixin, GlassLiveBinding
    implements LiquidGlassLayerRenderObject {
  RenderLiquidGlassLayer({
    required this.defaultRenderShader,
    required this.ios27RenderShader,
    required this.materialRenderShader,
    required this.tintRenderShader,
    required this.tintIos27RenderShader,
    required super.backdropKey,
    required super.devicePixelRatio,
    required super.settings,
    required super.defaultAppearance,
    required super.link,
    this._gpuGeometryRenderer,
    this._field,
  }) {
    _updateShaderSettings();
  }

  GlassField? _field;

  /// The fused body's distance field, or null to shade the shapes.
  GlassField? get field => _field;
  set field(GlassField? value) {
    if (identical(_field, value)) return;
    _field = value;
    needsGeometryUpdate = true;
    _geometryInputsChanged = true;
    markNeedsPaint();
  }

  /// One appearance for the layer, the direct color model.
  final FragmentShader defaultRenderShader;

  /// One appearance for the layer, an iOS 27 color model.
  final FragmentShader ios27RenderShader;

  /// Shapes with their own appearances, any color models.
  final FragmentShader materialRenderShader;

  /// Shapes that differ only by tint, the direct color model.
  final FragmentShader tintRenderShader;

  /// Shapes that differ only by tint, an iOS 27 color model.
  final FragmentShader tintIos27RenderShader;

  /// The analytic final shaders of this layer for separate shapes, in the
  /// order of [ShaderKeys.liquidGlassAnalyticRenders], or null until
  /// analytic geometry is enabled and their programs have loaded.
  List<FragmentShader>? _analyticShaders;

  /// The analytic final shaders for a fused body of merged boxes, in the
  /// order of [ShaderKeys.liquidGlassAnalyticFusedRenders], or null until
  /// a layer needs them and their programs have loaded.
  List<FragmentShader>? _analyticFusedShaders;

  /// The most shapes a layer evaluates in its final shader; a layer with
  /// more renders a geometry matte. Matches ANALYTIC_MAX_SHAPES in
  /// shaders/analytic_geometry.glsl.
  static const int analyticMaxShapes = 8;

  static bool? _debugAnalyticGeometry;

  /// Overrides [ShaderKeys.analyticGeometry] for every layer when not null,
  /// for an A/B of the analytic and the matte geometry. Setting it asks
  /// every attached layer for a new geometry frame.
  @visibleForTesting
  static bool? get debugAnalyticGeometry => _debugAnalyticGeometry;
  @visibleForTesting
  static set debugAnalyticGeometry(bool? value) {
    if (_debugAnalyticGeometry == value) return;
    _debugAnalyticGeometry = value;
    if (analyticGeometryEnabled) unawaited(precacheAnalyticShaders());
    _invalidateAttachedLayers();
    _analyticChanges.value++;
  }

  static final ValueNotifier<int> _analyticChanges = ValueNotifier(0);

  static AnalyticGeometryMode? _debugAnalyticMode;

  /// Overrides [ShaderKeys.analyticMode] for every layer when not null.
  /// Setting it asks every attached layer for a new geometry frame.
  @visibleForTesting
  static AnalyticGeometryMode? get debugAnalyticMode => _debugAnalyticMode;
  @visibleForTesting
  static set debugAnalyticMode(AnalyticGeometryMode? value) {
    if (_debugAnalyticMode == value) return;
    _debugAnalyticMode = value;
    _invalidateAttachedLayers();
  }

  /// When analytic geometry shades: [debugAnalyticMode], else
  /// [ShaderKeys.analyticMode].
  static AnalyticGeometryMode get analyticMode =>
      _debugAnalyticMode ??
      (ShaderKeys.analyticMode == 'changes'
          ? AnalyticGeometryMode.changes
          : AnalyticGeometryMode.always);

  static bool? _debugAnalyticCapsule;

  /// Overrides [ShaderKeys.analyticCapsule] for every layer when not null.
  @visibleForTesting
  static bool? get debugAnalyticCapsule => _debugAnalyticCapsule;
  @visibleForTesting
  static set debugAnalyticCapsule(bool? value) {
    if (_debugAnalyticCapsule == value) return;
    _debugAnalyticCapsule = value;
    _invalidateAttachedLayers();
  }

  /// Whether analytic frames shade full-radius rounded superellipses as
  /// stadiums: [debugAnalyticCapsule], else [ShaderKeys.analyticCapsule].
  static bool get analyticCapsuleEnabled =>
      _debugAnalyticCapsule ?? ShaderKeys.analyticCapsule;

  /// The consecutive frames a layer's geometry must stay unchanged before,
  /// in [AnalyticGeometryMode.changes], it encodes a matte to rest on.
  static const int analyticRestFrames = 2;

  /// The analytic geometry frames in a row after which, in
  /// [AnalyticGeometryMode.changes], a layer hands its matte textures back.
  static const int analyticReleaseFrames = 120;

  // Whether the geometry inputs a matte does not track by its own revision
  // changed since the last geometry frame: the field, the optics settings,
  // the pixel ratio, mixed appearances.
  bool _geometryInputsChanged = true;
  // Geometry changes seen, for the rest watch.
  int _geometryChanges = 0;
  // Whether this layer rests on a matte, and whether its next unchanged
  // geometry frame starts resting.
  bool _resting = false;
  bool _restRequested = false;
  bool _restWatched = false;
  int _analyticSinceMatte = 0;

  /// Whether the layer rests on a matte in [AnalyticGeometryMode.changes].
  @visibleForTesting
  bool get debugResting => _resting;

  // Notes before a geometry frame whether its geometry is [unchanged] since
  // the last one, up to a uniform translation.
  void _noteGeometryFrame({required bool unchanged}) {
    final changed = !unchanged || _geometryInputsChanged;
    _geometryInputsChanged = false;
    if (analyticMode != AnalyticGeometryMode.changes) {
      _resting = false;
      _restRequested = false;
      return;
    }
    if (changed) {
      _geometryChanges++;
      _resting = false;
      _restRequested = false;
    } else if (_restRequested) {
      _restRequested = false;
      _resting = true;
    }
  }

  // After an analytic frame in [AnalyticGeometryMode.changes]: once the
  // geometry stayed unchanged for [analyticRestFrames] frames - or no frame
  // is coming, so it cannot change - asks for one matte frame to rest on.
  void _watchRest() {
    if (_restWatched) return;
    _restWatched = true;
    var start = _geometryChanges;
    // The frame that changed the geometry does not count.
    var still = -1;
    final scheduler = SchedulerBinding.instance;
    void check(Duration _) {
      if (!attached || !_analytic) {
        _restWatched = false;
        return;
      }
      if (_geometryChanges != start) {
        start = _geometryChanges;
        still = 0;
      } else {
        still++;
      }
      if (still >= analyticRestFrames || !scheduler.hasScheduledFrame) {
        _restWatched = false;
        _restRequested = true;
        needsGeometryUpdate = true;
        markNeedsPaint();
        return;
      }
      scheduler.addPostFrameCallback(check);
    }

    scheduler.addPostFrameCallback(check);
  }

  // After a geometry frame: in [AnalyticGeometryMode.changes] an analytic
  // frame watches for rest and hands the matte back only after a long run;
  // otherwise the matte goes back after two analytic frames.
  void _afterGeometryFrame() {
    if (analyticMode == AnalyticGeometryMode.changes) {
      if (!_analytic) {
        _analyticSinceMatte = 0;
        return;
      }
      _watchRest();
      if (++_analyticSinceMatte == analyticReleaseFrames) {
        final renderer = _gpuGeometryRenderer;
        if (renderer != null &&
            renderer.holdsOutput &&
            _geometryImage == null) {
          renderer.releaseOutput();
          assert(() {
            debugMatteReleases++;
            return true;
          }());
        }
      }
      return;
    }
    if (_analytic) _scheduleMatteRelease();
  }

  /// Notifies when [debugAnalyticGeometry] changes, so whatever chose its
  /// glass by [analyticGeometryEnabled] chooses again.
  static Listenable get analyticGeometryChanges => _analyticChanges;

  /// Whether liquid layers evaluate their geometry in the final shader:
  /// [debugAnalyticGeometry], else [ShaderKeys.analyticGeometry].
  ///
  /// A frame is analytic when it has at most [analyticMaxShapes] separate
  /// shapes, or a [GlassBoxField] of at most [GlassBoxField.maxBoxes]
  /// merged boxes, and one appearance or appearances that differ only by
  /// tint; every other frame renders a matte. Separate shapes draw the
  /// same shading as the matte path, only the matte's quantization and
  /// nearest sampling gone; merged boxes follow the container's merge law
  /// exactly, where the sampled field approximates it on a 4 pt grid. Its culling rect
  /// and the bevel shadow's size response (written as 0, so inert today)
  /// read the geometry bounds rounded out to device pixels, not a texture
  /// size bucket. Shapes are evaluated where they are, without the matte's
  /// raster-phase shifts.
  static bool get analyticGeometryEnabled =>
      _debugAnalyticGeometry ?? ShaderKeys.analyticGeometry;

  static final Set<RenderLiquidGlassLayer> _attachedLayers = {};

  static void _invalidateAttachedLayers() {
    for (final layer in _attachedLayers) {
      layer.needsGeometryUpdate = true;
      layer.markNeedsPaint();
    }
  }

  static final Map<String, Future<FragmentProgram?>> _analyticLoads = {};
  static final Map<String, FragmentProgram> _analyticPrograms = {};

  /// Loads the analytic final shader programs; completes when each has
  /// loaded or failed. A program that fails to load leaves every layer on
  /// the matte path. Layers ask for a new geometry frame once a load
  /// completes.
  static Future<void> precacheAnalyticShaders() => Future.wait([
    for (final key in [
      ...ShaderKeys.liquidGlassAnalyticRenders,
      ...ShaderKeys.liquidGlassAnalyticFusedRenders,
    ])
      _loadAnalyticProgram(key),
  ]);

  static Future<FragmentProgram?> _loadAnalyticProgram(String key) =>
      _analyticLoads[key] ??= FragmentProgram.fromAsset(key).then(
        (program) {
          _analyticPrograms[key] = program;
          _invalidateAttachedLayers();
          return program;
        },
        onError: (Object error) {
          if (kDebugMode) {
            debugPrint('morph: analytic glass shader unavailable: $error');
          }
          return null;
        },
      );

  /// The loaded analytic program for [key], or null when it has not loaded
  /// (yet).
  static FragmentProgram? analyticProgram(String key) => _analyticPrograms[key];

  // Whether this layer has the analytic shaders a frame of separate shapes
  // or, with [fused], of merged boxes draws with, creating the four of that
  // kind once all their programs have loaded and starting the loads
  // otherwise.
  bool _analyticShadersReady({required bool fused}) {
    if ((fused ? _analyticFusedShaders : _analyticShaders) != null) {
      return true;
    }
    final keys = fused
        ? ShaderKeys.liquidGlassAnalyticFusedRenders
        : ShaderKeys.liquidGlassAnalyticRenders;
    var ready = true;
    for (final key in keys) {
      if (_analyticPrograms[key] == null) {
        unawaited(_loadAnalyticProgram(key));
        ready = false;
      }
    }
    if (!ready) return false;
    final shaders = [
      for (final key in keys) _analyticPrograms[key]!.fragmentShader(),
    ];
    if (fused) {
      _analyticFusedShaders = shaders;
    } else {
      _analyticShaders = shaders;
    }
    _staleShaders.addAll(shaders);
    return true;
  }

  // The analytic shaders of the current frame: merged boxes or separate
  // shapes.
  List<FragmentShader> get _analyticSet =>
      _analyticBoxCount > 0 ? _analyticFusedShaders! : _analyticShaders!;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // Only a debug override or a build with analytic geometry ever asks
    // the attached layers for a new frame.
    if (!kReleaseMode || ShaderKeys.analyticGeometry) _attachedLayers.add(this);
  }

  @override
  void detach() {
    _attachedLayers.remove(this);
    super.detach();
  }

  // Whether the current frame's shapes are evaluated in the final shader
  // instead of read from a geometry matte.
  bool _analytic = false;

  // Geometry frames rendered as a matte, counted so a release waits for a
  // run of analytic frames without one.
  int _matteBuilds = 0;
  bool _matteReleaseScheduled = false;

  // Hands the renderer's matte and material textures back once this layer
  // has drawn analytic frames for two frames with no matte between them;
  // the next matte frame takes textures again.
  void _scheduleMatteRelease() {
    if (_matteReleaseScheduled) return;
    final renderer = _gpuGeometryRenderer;
    if (renderer == null || !renderer.holdsOutput) return;
    _matteReleaseScheduled = true;
    final builds = _matteBuilds;
    final scheduler = SchedulerBinding.instance;
    scheduler.addPostFrameCallback((_) {
      if (!attached || !_analytic || _matteBuilds != builds) {
        _matteReleaseScheduled = false;
        return;
      }
      scheduler.addPostFrameCallback((_) {
        _matteReleaseScheduled = false;
        final renderer = _gpuGeometryRenderer;
        if (attached &&
            _analytic &&
            _matteBuilds == builds &&
            renderer != null &&
            _geometryImage == null) {
          renderer.releaseOutput();
          assert(() {
            debugMatteReleases++;
            return true;
          }());
        }
      });
      scheduler.scheduleFrame();
    });
  }

  /// The times layers handed their matte textures back, in debug builds.
  @visibleForTesting
  static int debugMatteReleases = 0;

  // Why the latest geometry frame was not analytic, or null when it was.
  String? _analyticIneligibility;

  /// Whether the current frame evaluates its shapes in the final shader.
  @visibleForTesting
  bool get debugAnalytic => _analytic;

  /// Why the latest geometry frame took the matte path, or null when it
  /// was analytic.
  @visibleForTesting
  String? get debugAnalyticIneligibility => _analyticIneligibility;

  /// Why shapes cannot be evaluated in the final shader, or null when they
  /// can: analytic geometry is [enabled], the layer has no fused field
  /// ([hasField]) or one of at most [GlassBoxField.maxBoxes] merged boxes
  /// ([fusedBoxes], 0 for a sampled field), there are at most
  /// [analyticMaxShapes] shapes, no
  /// geometry of two or more shapes blends them, the appearances are one
  /// or differ only by tint (against [fallback] when there are none), and
  /// the analytic shaders are ready ([shadersReady]).
  ///
  /// [geometries] holds each geometry's blend and its shapes' appearances.
  @visibleForTesting
  static String? analyticIneligibility({
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
        if (appearances.length == analyticMaxShapes) {
          return 'more than $analyticMaxShapes shapes';
        }
        appearances.add(appearance);
      }
      if (blend != 0 && appearances.length - start > 1) return 'blend group';
    }
    final (mixed, tintOnly, _) = _classifyShapeAppearances(
      appearances,
      fallback,
    );
    if (mixed && !tintOnly) return 'mixed appearances';
    if (!shadersReady()) return 'shaders not loaded';
    return null;
  }

  /// The final shader the current appearances draw with: each variant
  /// compiles only the color models it can meet, which keeps the
  /// one-appearance and tint-only variants inside the register budget of
  /// full thread occupancy on a Mali-G78.
  FragmentShader get renderShader {
    final ios27 =
        (_uniformAppearance ?? defaultAppearance).colorModel
            is! DirectLiquidGlassColorModel;
    final shader = switch ((
      _usesShapeAppearances,
      _usesTintOnlyAppearance,
      ios27,
    )) {
      (false, _, false) when _analytic => _analyticSet[0],
      (false, _, true) when _analytic => _analyticSet[1],
      (true, true, false) when _analytic => _analyticSet[2],
      (true, true, true) when _analytic => _analyticSet[3],
      (false, _, false) => defaultRenderShader,
      (false, _, true) => ios27RenderShader,
      (true, true, false) => tintRenderShader,
      (true, true, true) => tintIos27RenderShader,
      (true, false, _) => materialRenderShader,
    };
    _writeStaleShaderSettings(shader);
    return shader;
  }

  final Set<FragmentShader> _staleShaders = {};

  void _writeStaleShaderSettings(FragmentShader shader) {
    if (!_staleShaders.remove(shader)) return;
    _writeCommonShaderUniforms(
      shader,
      _uniformAppearance ?? defaultAppearance,
      _materialCenterInMatte,
    );
  }

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
  FlutterGpuGeometryRenderer? get gpuGeometryRenderer => _gpuGeometryRenderer;
  set gpuGeometryRenderer(FlutterGpuGeometryRenderer? value) {
    if (_gpuGeometryRenderer == value) return;
    _gpuGeometryRenderer = value;
    markNeedsPaint();
  }

  // MARK: Shader inputs

  LiquidGlassAppearance? _uniformAppearance;
  List<LiquidGlassAppearance> _shapeAppearances = const [];
  bool _usesShapeAppearances = false;
  bool _usesTintOnlyAppearance = false;

  /// Whether the latest geometry pass writes per-shape contributor data.
  @visibleForTesting
  bool get debugUsesShapeAppearances => _usesShapeAppearances;

  /// Whether only tint differs, allowing one filtered appearance lookup.
  @visibleForTesting
  bool get debugUsesTintOnlyAppearance => _usesTintOnlyAppearance;

  /// The optional contributor texture sampled by the final material pass.
  @visibleForTesting
  ui.Image? get debugMaterialImage => _materialImage;

  /// Shorter side in logical pixels of the smallest shape in this layer.
  /// Adaptive color models use it to choose the material density; it is
  /// resolved once per geometry update, never per fragment.
  double _materialShortSide = 10000;

  bool _shaderInputsChanged = true;

  /// Whether a uniform or sampler of [renderShader] changed since the last
  /// call, which also resets it.
  ///
  /// The engine copies a shader's uniforms into the native image filter when
  /// that filter is first converted (see
  /// `ReusableFragmentShader::as_image_filter`), so a filter wrapping this
  /// shader may only be reused while this stays false.
  @protected
  bool takeShaderInputsChanged() {
    final changed = _shaderInputsChanged;
    _shaderInputsChanged = false;
    return changed;
  }

  void _updateShaderSettings() {
    _shaderInputsChanged = true;
    _staleShaders.add(defaultRenderShader);
    _staleShaders.add(ios27RenderShader);
    _staleShaders.add(materialRenderShader);
    _staleShaders.add(tintRenderShader);
    _staleShaders.add(tintIos27RenderShader);
    if (_analyticShaders case final shaders?) _staleShaders.addAll(shaders);
    if (_analyticFusedShaders case final shaders?) {
      _staleShaders.addAll(shaders);
    }
    _writeStaleShaderSettings(renderShader);
  }

  void _writeCommonShaderUniforms(
    FragmentShader shader,
    LiquidGlassAppearance appearance,
    Offset materialCenter,
  ) {
    // The final shader fades the whole material with visibility, so the
    // color factors are written at full strength.
    shader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setColor(appearance.tint)
        ..setFloats([
          settings.effectiveDisplacementScale * devicePixelRatio,
          settings.dispersion,
          settings.effectiveEdgeDistanceRange * devicePixelRatio,
          settings.highlight,
          1 - settings.effectiveBackdropShrink,
          appearance.saturation,
        ])
        ..setOffset(const Offset(0, 1))
        ..setColor(const Color.fromARGB(255, 255, 255, 255))
        ..setColor(
          Color.fromARGB(
            (settings.contourStrength.clamp(0.0, 1.0) * 255).round(),
            0,
            0,
            0,
          ),
        )
        // Rim geometry the presets share; see [GlassRim].
        ..setFloats([
          GlassRim.bevelShadowDirectionality,
          0, // bevel shadow size response
          GlassRim.highlightWidth * devicePixelRatio,
          GlassRim.highlightOppositeStrength,
        ])
        ..setFloats([
          settings.contourWidth * devicePixelRatio,
          0, // contour transmittance
          settings.contourDirectionality,
        ])
        ..setFloats([
          0, // contour offset
          materialCenter.dx * devicePixelRatio,
          materialCenter.dy * devicePixelRatio,
          GlassRim.highlightWrap,
        ])
        ..setFloats([
          appearance.transmissionGamma,
          appearance.vibrancy,
          settings.effectiveTintAmount,
        ])
        ..setFloats([
          settings.bevelShadowStrength,
          GlassRim.bevelShadowDepth * devicePixelRatio,
          GlassRim.bevelShadowOffset * devicePixelRatio,
        ])
        ..setFloats([
          appearance.colorModel.shaderValue,
          appearance.visibility,
          FlutterGpuGeometryRenderer.materialRasterScale.toDouble(),
          _materialShortSide,
        ]);
    });
    // Float indices 53 and 54, after the 47-float common block and the
    // 6-float filter->matte mapping: frosted glass cross-fades its blur away,
    // while unfrosted glass stays alpha-1 and cross-fades its material in the
    // shader, so both match the backdrop exactly at visibility 0.
    shader
      ..setFloat(53, blurPassSigma > 0 ? 1 : 0)
      ..setFloat(54, softensInShader ? 1 : 0);
    _writeBackdropShrinkAxis(shader);
  }

  /// Writes uBackdropShrinkAxis (float indices 63 and 64): half the line the
  /// backdrop shrinks about, in device pixels from the material center.
  void _writeBackdropShrinkAxis(FragmentShader shader) {
    final size = _materialSizeInMatte;
    final rim = settings.effectiveBackdropShrinkRim;
    final half =
        rim * (size.longestSide - size.shortestSide) / 2 * devicePixelRatio;
    final alongX = size.width >= size.height;
    shader
      ..setFloat(63, alongX ? half : 0)
      ..setFloat(64, alongX ? 0 : half);
  }

  /// Largest frost, in device pixels, folded into the final pass instead of
  /// a separate blur pass. Enabling the blur pass costs about four command
  /// buffers per frame on Metal regardless of its radius.
  static const double shaderSofteningMaxDeviceSigma = 1.25;

  /// Whether the frost is small enough for the final pass's softening kernel.
  bool get softensInShader {
    final frost = _frostSigma;
    return frost > 0 &&
        frost * devicePixelRatio <= shaderSofteningMaxDeviceSigma;
  }

  /// Sigma of the separate backdrop blur pass; `0` when there is none.
  ///
  /// A frost just below the sigma Impeller blurs at half resolution is
  /// raised to it ([morphHalfResolutionSigma]), unless the layer blurs its
  /// own backdrop: that blur is already small, and its frost animates.
  double get blurPassSigma {
    if (softensInShader) return 0;
    final frost = _frostSigma;
    if (_blursOwnBackdrop) return frost;
    return morphHalfResolutionSigma(frost, devicePixelRatio);
  }

  double get _frostSigma => settings.effectiveFrost;

  List<double> _appearanceLookupData(List<LiquidGlassAppearance> appearances) {
    // This is used only for mixed frames; unused lookup rows must not depend
    // on the owner's active (possibly different) uniform frame.
    final fallback = defaultAppearance;
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

  void _setShapeAppearances(List<LiquidGlassAppearance> appearances) {
    final (usesShapeAppearances, usesTintOnlyAppearance, uniformAppearance) =
        _classifyShapeAppearances(appearances, defaultAppearance);
    if (_usesShapeAppearances == usesShapeAppearances &&
        _usesTintOnlyAppearance == usesTintOnlyAppearance &&
        _uniformAppearance == uniformAppearance &&
        listEquals(_shapeAppearances, appearances)) {
      return;
    }
    _usesShapeAppearances = usesShapeAppearances;
    _usesTintOnlyAppearance = usesTintOnlyAppearance;
    _uniformAppearance = uniformAppearance;
    _shapeAppearances = List.unmodifiable(appearances);
    _updateShaderSettings();
  }

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
          _matteShapeBasis(entry.$3, shape.shapeToGeometry ?? _identity) !=
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
    _updateShaderSettings();
    if (geometryInputsChanged) {
      needsGeometryUpdate = true;
      _geometryInputsChanged = true;
    }
  }

  @override
  void onAppearanceChanged() => _updateShaderSettings();

  @override
  void onDevicePixelRatioChanged() {
    _updateShaderSettings();
    needsGeometryUpdate = true;
    _geometryInputsChanged = true;
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

  final _originalShadows = LayerHandle<ContainerLayer>();

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
    if (bounds == null ||
        !listEquals(retainedStructure, geometryStructure(candidate))) {
      return false;
    }
    commitFrameGeometry(candidate);
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
      _noteGeometryFrame(unchanged: unchanged);
      final result = _buildGpuGeometryImage(shapesWithGeometry, bounds);
      _releaseGeometryImageHandles();
      _geometryImage = result.image;
      _analytic = result.analytic;
      _afterGeometryFrame();
      _materialImage = result.materialImage;
      _geometryMatteBounds = result.matteBounds;
      _geometryTextureSize = result.textureSize;
      _materialTextureSize = result.materialTextureSize;
      _materialCenterInMatte = result.materialCenter;
      _materialSizeInMatte = result.materialSize;
      _setShapeAppearances(result.appearances);
      _rememberEncodedGeometry(bounds);
      _bindGeometryShader(result.image);
    }
    needsGeometryUpdate = false;
    link
      ..updateAllGeometries()
      ..markClean();
    _recordOriginalShadows(retainedPaintOffset);
    updateMaterial(shapesWithGeometry, materialBounds, retainedPaintOffset);
    syncAncestorClips();
    return true;
  }

  void _clearGeometryImage() {
    _originalShadows.layer = null;
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
    if (_encodedPassPhase != null) return false;
    _geometryMatteBounds = _geometryMatteBounds.shift(delta);
    _materialCenterInMatte += delta;
    if (_analytic) _shiftAnalyticShapes(delta * devicePixelRatio);
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
          _recordOriginalShadows(effectOffset);
          if (_originalShadows.layer case final shadows?) {
            effectContext.addLayer(shadows);
          }
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
        if (hasReusableGeometry &&
            _rasterGridStale(shaderCoordinateTransform)) {
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
            _noteGeometryFrame(
              unchanged: encodedMatteDelta(geometryBounds) != null,
            );
            _clearGeometryImage();
            final gpuResult = _buildGpuGeometryImage(
              shapesWithGeometry,
              geometryBounds,
            );
            _geometryImage = gpuResult.image;
            _analytic = gpuResult.analytic;
            _afterGeometryFrame();
            _materialImage = gpuResult.materialImage;
            _geometryMatteBounds = gpuResult.matteBounds;
            _geometryTextureSize = gpuResult.textureSize;
            _materialTextureSize = gpuResult.materialTextureSize;
            _materialCenterInMatte = gpuResult.materialCenter;
            _materialSizeInMatte = gpuResult.materialSize;
            _setShapeAppearances(gpuResult.appearances);
            _rememberEncodedGeometry(geometryBounds);
          }
        }

        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          if (hasReusableGeometry) {
            _bindGeometryShader(_geometryImage);
            _recordOriginalShadows(effectOffset);
            if (_originalShadows.layer case final shadows?) {
              effectContext.addLayer(shadows);
            }
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
    final usedShapeAppearances = _usesShapeAppearances;
    final usedTintOnlyAppearance = _usesTintOnlyAppearance;
    final appearanceValuesChanged = !_committedAppearancesMatch();
    _setShapeAppearances(
      appearanceValuesChanged
          ? [
              for (final (_, geometry, _) in shapesWithGeometry)
                for (final shape in geometry.shapes) shape.appearance,
            ]
          : _shapeAppearances,
    );
    if (usedShapeAppearances != _usesShapeAppearances ||
        usedTintOnlyAppearance != _usesTintOnlyAppearance ||
        (_usesShapeAppearances && appearanceValuesChanged)) {
      // Mixed material data is encoded in the geometry render target. Only
      // uniform appearance changes can be applied with final-pass uniforms.
      needsGeometryUpdate = true;
      _geometryInputsChanged = true;
    }
    final materialBounds = boundingBox.inflate(_contourOutset);
    effectPaintBounds = expandBoundsForShadows(materialBounds);
    return materialBounds;
  }

  // Whether the committed shapes' appearances equal the last appearance list,
  // element by element, without building the list.
  bool _committedAppearancesMatch() {
    final last = _shapeAppearances;
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
    final activeRenderShader = renderShader;
    activeRenderShader
      ..setFloatUniforms(initialIndex: 2, (value) {
        value
          ..setOffset(_geometryMatteBounds.topLeft * devicePixelRatio)
          ..setSize(_geometryMatteBounds.size * devicePixelRatio);
      })
      ..setFloatUniforms(initialIndex: 34, (value) {
        value.setOffset(_materialCenterInMatte * devicePixelRatio);
      })
      // Float index 59, after uBackdropBounds.
      ..setFloatUniforms(initialIndex: 59, (value) {
        final matteSize = _geometryMatteBounds.size * devicePixelRatio;
        value.setFloats([
          if (_geometryTextureSize.isEmpty) ...[
            1,
            1,
          ] else ...[
            matteSize.width / _geometryTextureSize.width,
            matteSize.height / _geometryTextureSize.height,
          ],
          _materialTextureSize.width,
          _materialTextureSize.height,
        ]);
      });
    if (geometryImage == null) {
      // Older engines retain this sampler's quality when replacing its
      // texture. Newer engines use morphGlassShaderFilter's explicit quality.
      activeRenderShader.setImageSampler(
        0,
        _holdBlankImage(),
        filterQuality: FilterQuality.low,
      );
      _writeAnalyticUniforms(activeRenderShader);
    } else {
      activeRenderShader
        ..setImageSampler(0, geometryImage, filterQuality: FilterQuality.low)
        // Nearest: the matte packs 12-bit normal angle and displacement codes
        // across byte boundaries, which filtering between texels would mix.
        ..setImageSampler(1, geometryImage);
    }
    _writeBackdropShrinkAxis(activeRenderShader);
    if (_materialImage case final materialImage?) {
      if (_usesTintOnlyAppearance) {
        activeRenderShader.setImageSampler(
          2,
          materialImage,
          filterQuality: FilterQuality.low,
        );
      } else {
        activeRenderShader
          ..setImageSampler(2, materialImage)
          ..setImageSampler(3, materialImage, filterQuality: FilterQuality.low);
      }
    }
    if (!identical(geometryImage, _boundGeometryImage) ||
        !identical(_materialImage, _boundMaterialImage) ||
        !identical(activeRenderShader, _boundShader) ||
        _geometryMatteBounds != _boundMatteBounds) {
      _boundShader = activeRenderShader;
      _boundGeometryImage = geometryImage;
      _boundMaterialImage = _materialImage;
      _boundMatteBounds = _geometryMatteBounds;
      _shaderInputsChanged = true;
    }
  }

  FragmentShader? _boundShader;
  ui.Image? _boundGeometryImage;
  ui.Image? _boundMaterialImage;
  Rect? _boundMatteBounds;

  // The image bound to the background sampler before the native filter
  // replaces it with its input, when no matte exists to bind there: one
  // 1x1 image every analytic layer shares, disposed with the last layer
  // that bound it. A shader keeps its own reference to a bound image, so
  // disposing the handle never pulls it from under a filter.
  static ui.Image? _blankImage;
  static int _blankImageHolders = 0;
  bool _holdsBlankImage = false;

  ui.Image _holdBlankImage() {
    if (!_holdsBlankImage) {
      _holdsBlankImage = true;
      _blankImageHolders++;
    }
    return _blankImage ??= () {
      final recorder = ui.PictureRecorder();
      Canvas(recorder);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(1, 1);
      picture.dispose();
      return image;
    }();
  }

  void _releaseBlankImage() {
    if (!_holdsBlankImage) return;
    _holdsBlankImage = false;
    if (--_blankImageHolders == 0) {
      _blankImage?.dispose();
      _blankImage = null;
    }
  }

  /// Whether the shared placeholder image exists, for tests.
  @visibleForTesting
  static bool get debugHasBlankImage => _blankImage != null;

  /// Float index of uAnalyticOptics, the first analytic uniform, after the
  /// 65 common floats (shaders/analytic_geometry.glsl).
  @visibleForTesting
  static const int analyticUniformIndex = 65;

  /// Float index of uShapeData, after uAnalyticOptics and uAnalyticRanges.
  @visibleForTesting
  static const int analyticShapeDataIndex = analyticUniformIndex + 8;

  /// Float index of uRseData, after 3 vec4 of uShapeData per shape.
  @visibleForTesting
  static const int analyticRseDataIndex =
      analyticShapeDataIndex + analyticMaxShapes * 12;

  /// Float index of uShapeBounds, after 3 vec4 of uRseData per shape.
  @visibleForTesting
  static const int analyticBoundsIndex =
      analyticRseDataIndex + analyticMaxShapes * 12;

  /// Float index of uShapeCull, after one vec4 of uShapeBounds per shape:
  /// one float per shape, four to a vec4.
  @visibleForTesting
  static const int analyticCullIndex =
      analyticBoundsIndex + analyticMaxShapes * 4;

  /// Float index of uFusedBoxes, after uShapeCull; only the fused variants
  /// declare it.
  @visibleForTesting
  static const int analyticFusedBoxesIndex =
      analyticCullIndex + analyticMaxShapes;

  /// Float index of uShapeTints in the separate-shape tint variants,
  /// after uShapeCull.
  @visibleForTesting
  static const int analyticTintsIndex = analyticCullIndex + analyticMaxShapes;

  /// Float index of uShapeTints in the fused tint variants, after 2 vec4
  /// of uFusedBoxes per fused box.
  @visibleForTesting
  static const int analyticFusedTintsIndex =
      analyticFusedBoxesIndex + GlassBoxField.maxBoxes * 8;

  // The geometry pass's optical inputs of the current analytic frame.
  double _analyticRefractionHeight = 0;
  double _analyticRefractionAmount = 1e-3;
  bool _analyticFitsShape = false;
  double _analyticContourExtent = 0.5;
  int _analyticShapeCount = 0;
  final List<double> _analyticTints = [];
  // The fused body's boxes in device pixels, 8 floats per box (center,
  // half extents, clamped radius, 3 unused), and its merge spacing; empty
  // for separate shapes.
  final Float64List _analyticBoxes = Float64List(GlassBoxField.maxBoxes * 8);
  int _analyticBoxCount = 0;
  double _analyticSpacing = 0;

  // Writes the analytic frame's shapes and the geometry pass's optical
  // inputs into [shader], from float index 65.
  void _writeAnalyticUniforms(FragmentShader shader) {
    shader.setFloat(analyticUniformIndex, _analyticRefractionHeight);
    shader.setFloat(analyticUniformIndex + 1, _analyticRefractionAmount);
    shader.setFloat(analyticUniformIndex + 2, _analyticFitsShape ? 1 : 0);
    shader.setFloat(analyticUniformIndex + 3, _analyticShapeCount.toDouble());
    shader.setFloat(analyticUniformIndex + 4, _analyticContourExtent);
    shader.setFloat(analyticUniformIndex + 5, _analyticBoxCount.toDouble());
    shader.setFloat(analyticUniformIndex + 6, _analyticSpacing);
    shader.setFloat(
      analyticUniformIndex + 7,
      liquidMinMergeWidth * devicePixelRatio,
    );
    final fused = _analyticBoxCount > 0;
    // Only the fused variants declare uFusedBoxes.
    if (fused) {
      for (var i = 0; i < _analyticBoxCount * 8; i++) {
        shader.setFloat(analyticFusedBoxesIndex + i, _analyticBoxes[i]);
      }
    }
    for (var i = 0; i < _cullData.length && i < analyticMaxShapes; i++) {
      shader.setFloat(analyticCullIndex + i, _cullData[i]);
    }
    for (var i = 0; i < _shapeData.length; i++) {
      shader.setFloat(analyticShapeDataIndex + i, _shapeData[i]);
    }
    for (var i = 0; i < _rseData.length; i++) {
      shader.setFloat(analyticRseDataIndex + i, _rseData[i]);
    }
    for (var i = 0; i < _boundsData.length; i++) {
      shader.setFloat(analyticBoundsIndex + i, _boundsData[i]);
    }
    // Only the tint variants declare uShapeTints.
    final shaders = _analyticSet;
    if (identical(shader, shaders[2]) || identical(shader, shaders[3])) {
      final at = fused ? analyticFusedTintsIndex : analyticTintsIndex;
      for (var i = 0; i < _analyticTints.length; i++) {
        shader.setFloat(at + i, _analyticTints[i]);
      }
    }
  }

  // Moves the analytic frame's shapes by [delta] device pixels, as a
  // uniformly translated matte moves its bounds.
  void _shiftAnalyticShapes(Offset delta) {
    for (var i = 0; i < _analyticShapeCount; i++) {
      _shapeData[i * 12 + 8] += delta.dx;
      _shapeData[i * 12 + 9] += delta.dy;
      _boundsData[i * 4] += delta.dx;
      _boundsData[i * 4 + 1] += delta.dy;
      _boundsData[i * 4 + 2] += delta.dx;
      _boundsData[i * 4 + 3] += delta.dy;
    }
    for (var i = 0; i < _analyticBoxCount * 8; i += 8) {
      _analyticBoxes[i] += delta.dx;
      _analyticBoxes[i + 1] += delta.dy;
    }
    _shaderInputsChanged = true;
  }

  // Why [geometries] cannot be evaluated in the final shader, or null.
  String? _analyticIneligibilityOf(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    if (!analyticGeometryEnabled) return 'disabled';
    if (_resting) return 'resting';
    return analyticIneligibility(
      enabled: true,
      hasField: _field != null,
      fusedBoxes: switch (_field) {
        GlassBoxField(:final boxes) => boxes.length,
        _ => 0,
      },
      shadersReady: () => _analyticShadersReady(fused: _field is GlassBoxField),
      geometries: [
        for (final (_, geometry, _) in geometries)
          (
            geometry.blend,
            [for (final shape in geometry.shapes) shape.appearance],
          ),
      ],
      fallback: defaultAppearance,
    );
  }

  // Own a replaceable picture rather than recording shadows together with
  // unrelated foreground. Geometry refresh may replace this before submission
  // without asking any child render object to paint outside the paint phase.
  void _recordOriginalShadows(Offset offset) {
    final hasShadows = shapesWithGeometry.any(
      (entry) => entry.$2.shapes.any((shape) => shape.shadows.isNotEmpty),
    );
    if (!hasShadows) {
      _originalShadows.layer = null;
      return;
    }
    final slot = _originalShadows.layer ??= ContainerLayer();
    slot.removeAllChildren();
    if (drawableEmpty) return;
    final recorder = ui.PictureRecorder();
    drawGlassShadows(Canvas(recorder), offset);
    final picture = PictureLayer(effectPaintBounds.shift(offset))
      ..picture = recorder.endRecording();
    slot.append(picture);
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
    if (clip == null || blurPassSigma <= 0) return clip;
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
    final mapping = _currentCoordinateMapping();
    final backdropBounds = backdropSampleBounds;
    final changed =
        mapping != _coordinateMapping || backdropBounds != _backdropBounds;
    _coordinateMapping = mapping;
    _backdropBounds = backdropBounds;
    if (changed) _shaderInputsChanged = true;
    _writeCoordinateMapping(renderShader, mapping, backdropBounds);
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

  void _writeCoordinateMapping(
    FragmentShader shader,
    (double, double, double, double, double, double) mapping,
    Rect? backdropBounds,
  ) {
    shader.setFloat(47, mapping.$1);
    shader.setFloat(48, mapping.$2);
    shader.setFloat(49, mapping.$3);
    shader.setFloat(50, mapping.$4);
    shader.setFloat(51, mapping.$5);
    shader.setFloat(52, mapping.$6);
    // Float index 55, after the frost flags.
    final matteBounds = backdropBounds ?? Rect.largest;
    shader.setFloat(55, matteBounds.left * devicePixelRatio);
    shader.setFloat(56, matteBounds.top * devicePixelRatio);
    shader.setFloat(57, matteBounds.right * devicePixelRatio);
    shader.setFloat(58, matteBounds.bottom * devicePixelRatio);
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

  bool _blursOwnBackdrop = false;

  /// See [LiquidGlassLayer.blursOwnBackdrop].
  bool get blursOwnBackdrop => _blursOwnBackdrop;
  set blursOwnBackdrop(bool value) {
    if (_blursOwnBackdrop == value) return;
    _blursOwnBackdrop = value;
    _shaderInputsChanged = true;
    markNeedsPaint();
  }

  bool get _seedsBlur =>
      _blursOwnBackdrop &&
      debugSeedsBlur &&
      blurPassSigma > 0 &&
      backdropKey == null &&
      !compositionProbeSeeding;

  /// The logical pixels around the blurred coverage the frost blur reads.
  double get _seedMargin => morphBlurReach(blurPassSigma, devicePixelRatio);

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
    final inputsChanged = takeShaderInputsChanged();
    if (_cachedFilter != null && !inputsChanged) return _cachedFilter!;
    final shader = morphGlassShaderFilter(renderShader);
    final frostSigma = blurPassSigma;
    final filter = frostSigma > 0
        ? ImageFilter.compose(inner: _frostBlur(frostSigma), outer: shader)
        : shader;
    _cachedFilter = filter;
    return filter;
  }

  ImageFilter? _blur;
  double _blurSigma = 0;

  ImageFilter _frostBlur(double sigma) {
    final kept = _blur;
    if (kept != null && _blurSigma == sigma) return kept;
    final blur = ImageFilter.blur(
      tileMode: TileMode.mirror,
      sigmaX: sigma,
      sigmaY: sigma,
    );
    _blur = blur;
    _blurSigma = sigma;
    return blur;
  }

  // Both painting and retained geometry updates need the same native filter
  // bounds. This only updates existing handles; it never paints children.
  Rect _syncMaterialFilter(
    Rect materialBounds,
    Offset offset, {
    bool retained = false,
  }) {
    final filterBounds = materialBounds.expandToPixelBuckets(devicePixelRatio);
    _filterMaterialBounds = materialBounds;
    _filterPaintOffset = offset;
    debugFilterBounds = filterBounds;
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
      final shader = (_shaderHandle.layer ??= BackdropFilterLayer())
        ..filter = _updateShaderFilter()
        ..backdropKey = backdropKey;
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

  /// Drops native backdrop-filter state while this sample is idle.
  void _releaseCompositorFilter() {
    _shaderHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _seedClipHandle.layer = null;
    _seedHandle.layer = null;
    _cachedFilter = null;
  }

  // MARK: Compositing

  @override
  void onTransformChanged() {
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
    _compositingScreen = null;
  }

  @override
  void onCompositorTranslated(Offset translation) {
    _watchRasterPhase();
    final clip = _filterClip;
    if (clip != null && _clipRectLayerHandle.layer != null) {
      _clipRectLayerHandle.layer!.clipRect = clip.shift(_filterPaintOffset);
    }
    if (_seedClipHandle.layer case final seedClip?) {
      if (_seedClip case final seed?) {
        seedClip.clipRect = seed.shift(_filterPaintOffset);
      }
    }
    if (!drawableEmpty && hasReusableGeometry && syncCoordinateMapping()) {
      _shaderHandle.layer?.filter = _updateShaderFilter();
    }
  }

  @override
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  ) {
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
    if (motion.needsRepaint &&
        (_shaderHandle.layer != null || drawableEmpty) &&
        _clipRectLayerHandle.layer != null &&
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
    _cachedFilter = null;
    _clearGeometryImage();
    _gpuGeometryRenderer = null;
    _releaseBlankImage();
    for (final shaders in [?_analyticShaders, ?_analyticFusedShaders]) {
      _staleShaders.removeAll(shaders);
      for (final shader in shaders) {
        shader.dispose();
      }
    }
    _analyticShaders = null;
    _analyticFusedShaders = null;
    super.dispose();
  }

  // MARK: Geometry

  @protected
  bool needsGeometryUpdate = true;

  final List<double> _shapeData = [];
  final List<double> _rseData = [];
  final List<double> _boundsData = [];
  final List<double> _cullData = [];
  static final Matrix4 _identity = Matrix4.identity();

  @override
  double get materialOutset => _contourOutset;

  double get _contourOutset {
    if (settings.contourWidth <= 0) return 0;
    return max(
      0.5 / devicePixelRatio,
      settings.contourWidth + 1.0 / devicePixelRatio,
    );
  }

  /// How far outside the material the composed filter reads the backdrop:
  /// the blur kernel (3 sigma), the peak edge displacement including its
  /// dispersion, and, with [LiquidGlassSettings.backdropShrink], the extra
  /// content revealed on the face. A backdrop group must contain this
  /// reach or the filter samples its own edge.
  double backdropSamplingReach(Rect material) {
    final blur = blurPassSigma > 0
        ? blurPassSigma * 3 + 1 / devicePixelRatio
        : (softensInShader ? 1 / devicePixelRatio : 0.0);
    final displacement =
        settings.effectiveDisplacementScale *
        (1 + settings.dispersion.abs() * 0.5);
    final scale = 1 - settings.effectiveBackdropShrink;
    final revealed = (1 / scale - 1) * max(material.width, material.height) / 2;
    return blur + displacement + revealed;
  }

  @override
  double effectSamplingReach(Rect material) => backdropSamplingReach(material);

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
        case RawShapeType.squircle:
          return x.abs() * halfSize.width + y.abs() * halfSize.height;
      }
    }

    return Size(extent(axisX.dx, axisY.dx), extent(axisX.dy, axisY.dy));
  }

  // The encoder's drawable-shape decision. Called only while preparing
  // geometry, never during retained compositing sync.
  ({Offset axisX, Offset axisY, double determinant})? _matteShapeBasis(
    Matrix4 geometryToLayer,
    Matrix4 shapeToGeometry,
  ) {
    Offset toMatte(Offset point) => MatrixUtils.transformPoint(
      geometryToLayer,
      MatrixUtils.transformPoint(shapeToGeometry, point),
    );
    final origin = toMatte(Offset.zero);
    final axisX = toMatte(const Offset(1, 0)) - origin;
    final axisY = toMatte(const Offset(0, 1)) - origin;
    final determinant = axisX.dx * axisY.dy - axisY.dx * axisX.dy;
    if (determinant.abs() < 1e-8) return null;
    return (axisX: axisX, axisY: axisY, determinant: determinant);
  }

  // The pass phase the matte was encoded at when it shifts shapes onto
  // their own raster grids or moves its grid off a tie; null when it does
  // neither.
  Offset? _encodedPassPhase;

  // Whether a matte encoded for another pass phase would be encoded
  // differently now: its shifts moved, or a matte encoded on the layer's own
  // grid now falls within the tie band.
  bool _rasterGridStale(Matrix4 layerToPass) {
    // Analytic shapes have no raster grid.
    if (_analytic) return false;
    if (_encodedPassPhase case final phase?) {
      return _passPhase(layerToPass) != phase;
    }
    if (_field != null) return false;
    return glassRasterGrid(layerToPass, devicePixelRatio)?.biased ?? false;
  }

  Duration? _movedAt;
  bool _phaseWatched = false;

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
    if (_rasterGridStale(shaderCoordinateTransform)) markNeedsPaint();
  }

  Offset _passPhase(Matrix4 layerToPass) {
    final origin = MatrixUtils.transformPoint(layerToPass, Offset.zero);
    return Offset(
      glassRasterPhase(origin.dx * devicePixelRatio),
      glassRasterPhase(origin.dy * devicePixelRatio),
    );
  }

  _GpuGeometryFrame _buildGpuGeometryImage(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds,
  ) {
    final renderer = _gpuGeometryRenderer;
    if (renderer == null) {
      throw StateError(
        'Flutter GPU is required for LiquidGlass. Enable it in the platform '
        'manifest or with --enable-flutter-gpu.',
      );
    }

    try {
      // Centered SDF antialiasing needs half a physical pixel outside the
      // mathematical shape. Keep that margin in the persistent geometry
      // texture so the positive side of the fade is not clipped at the matte
      // edge.
      final ineligibility = _analyticIneligibilityOf(geometries);
      _analyticIneligibility = ineligibility;
      final analytic = ineligibility == null;
      final layerToPass = shaderCoordinateTransform;
      // Analytic shapes are evaluated where they are: no matte grid to
      // move or to shift them onto.
      final grid = analytic
          ? null
          : glassRasterGrid(
              layerToPass,
              devicePixelRatio,
              movable: _field == null,
            );
      final shifts = [
        for (final (owner, _, _) in geometries)
          grid == null
              ? Offset.zero
              : glassRasterPhaseShift(this, owner, grid, devicePixelRatio),
      ];
      final biased = grid?.biased ?? false;
      final anchored = shifts.any((Offset shift) => shift != Offset.zero);
      _encodedPassPhase = anchored || biased ? _passPhase(layerToPass) : null;
      final aaPadding = max(0.5 / devicePixelRatio, _contourOutset);
      final shiftPadding = anchored ? 0.5 / devicePixelRatio : 0.0;
      // The matte is in this layer's local coordinates. Ancestor transforms
      // are applied once by the compositor; baking them in would apply scale
      // and rotation twice.
      final snapped = bounds
          .inflate(aaPadding + shiftPadding)
          .snapToPixels(devicePixelRatio);
      final boundsInMatteSpace = biased
          ? snapped.shift(grid!.bias / devicePixelRatio)
          : snapped;
      final materialCenter = bounds.center;

      final textureWidth = (boundsInMatteSpace.width * devicePixelRatio).ceil();
      final textureHeight = (boundsInMatteSpace.height * devicePixelRatio)
          .ceil();

      if (textureWidth <= 0 || textureHeight <= 0) {
        throw StateError('Cannot render empty liquid-glass geometry.');
      }

      // Gather shapes in cache order. A negative blend marker starts a new
      // group; this preserves smooth unions within a group without blending
      // unrelated standalone glass widgets together.
      // The analytic frame reads these lists; it ends with them.
      _analytic = false;
      _shapeData.clear();
      _rseData.clear();
      _boundsData.clear();
      _cullData.clear();
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
          final basis = _matteShapeBasis(geometryToLayer, shapeToGeometry);
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
          _cullData.add(largest > 0 ? distanceScale / largest * sqrt1_2 : 0);

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
              analyticCapsuleEnabled &&
              shape.rawShapeType == RawShapeType.squircle &&
              shape.rawCornerRadius >= size.shortestSide / 2;
          final rseParameters = roundedSuperellipseParameters(
            size,
            shape.rawCornerRadius,
            scale: devicePixelRatio,
          );
          // The geometry shader tests each cap's angular span as
          // 1 - cos(span); FakeGlass reads the spans themselves.
          rseParameters[2] = 1.0 - cos(rseParameters[2]);
          rseParameters[3] = 1.0 - cos(rseParameters[3]);
          _rseData.addAll(rseParameters);
          final center = centerInMatte * devicePixelRatio;
          final halfExtents = _matteHalfExtents(
            shape.rawShapeType,
            size * devicePixelRatio / 2,
            shape.rawCornerRadius * devicePixelRatio,
            axisX,
            axisY,
          );
          _boundsData
            ..add(center.dx - halfExtents.width)
            ..add(center.dy - halfExtents.height)
            ..add(center.dx + halfExtents.width)
            ..add(center.dy + halfExtents.height);
          final blendMarker = firstInGroup
              ? -(geometry.blend * devicePixelRatio + 1)
              : geometry.blend * devicePixelRatio;

          _shapeData
            // vec4 0: primitive parameters.
            ..add(
              shape.appearance.visibility <= 0
                  ? 0
                  : capsule
                  ? RawShapeType.roundedRectangle.shaderIndex
                  : shape.rawShapeType.shaderIndex,
            )
            ..add(size.width * devicePixelRatio)
            ..add(size.height * devicePixelRatio)
            ..add(
              (capsule ? size.shortestSide / 2 : shape.rawCornerRadius) *
                  devicePixelRatio,
            )
            // vec4 1: inverse affine basis.
            ..add(inverse00)
            ..add(inverse01)
            ..add(inverse10)
            ..add(inverse11)
            // vec4 2: transformed center, distance scale, group marker.
            ..add(centerInMatte.dx * devicePixelRatio)
            ..add(centerInMatte.dy * devicePixelRatio)
            ..add(distanceScale)
            ..add(blendMarker);
          appearances.add(shape.appearance);
          shortSide = min(shortSide, size.shortestSide);
          numShapes++;
          firstInGroup = false;
        }
      }

      if (numShapes == 0) {
        throw StateError('No invertible liquid-glass shapes to render.');
      }
      if (shortSide != _materialShortSide) {
        _materialShortSide = shortSide;
        _updateShaderSettings();
      }
      final (usesShapeAppearances, usesTintOnlyAppearance, _) =
          _classifyShapeAppearances(appearances, defaultAppearance);

      if (analytic) {
        _analyticRefractionHeight = max(
          0.0,
          settings.effectiveRefractionHeight * devicePixelRatio,
        );
        _analyticRefractionAmount = max(
          1e-3,
          settings.effectiveRefractionAmount * devicePixelRatio,
        );
        _analyticFitsShape = settings.refractionFitsShape;
        _analyticContourExtent = max(0.5, aaPadding * devicePixelRatio);
        _analyticShapeCount = numShapes;
        _analyticBoxCount = 0;
        _analyticSpacing = 0;
        if (_field case GlassBoxField(:final boxes, :final spacing)) {
          final scale = devicePixelRatio;
          final out = _analyticBoxes;
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
          _analyticBoxCount = boxes.length;
          _analyticSpacing = spacing * scale;
        }
        _analyticTints.clear();
        if (usesTintOnlyAppearance) {
          for (final appearance in appearances) {
            final tint = appearance.tint;
            _analyticTints.addAll([tint.r, tint.g, tint.b, tint.a]);
          }
        }
        _shaderInputsChanged = true;
        return (
          analytic: true,
          image: null,
          materialImage: null,
          materialCenter: materialCenter,
          materialSize: bounds.size,
          textureSize: Size(textureWidth.toDouble(), textureHeight.toDouble()),
          materialTextureSize: const Size(1, 1),
          appearances: appearances,
          matteBounds: Rect.fromLTWH(
            boundsInMatteSpace.left,
            boundsInMatteSpace.top,
            textureWidth / devicePixelRatio,
            textureHeight / devicePixelRatio,
          ),
        );
      }

      _matteBuilds++;
      final result = renderer.render(
        width: textureWidth,
        height: textureHeight,
        shapeData: _shapeData,
        rseData: _rseData,
        boundsData: _boundsData,
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
        field: _field,
        fieldScale: devicePixelRatio,
      );
      return (
        analytic: false,
        image: result.image,
        materialImage: renderer.materialImage,
        materialCenter: materialCenter,
        materialSize: bounds.size,
        textureSize: Size(
          result.textureWidth.toDouble(),
          result.textureHeight.toDouble(),
        ),
        materialTextureSize: switch (renderer.materialImage) {
          final image? => Size(image.width.toDouble(), image.height.toDouble()),
          null => const Size(1, 1),
        },
        appearances: appearances,
        matteBounds: Rect.fromLTWH(
          boundsInMatteSpace.left,
          boundsInMatteSpace.top,
          result.width / devicePixelRatio,
          result.height / devicePixelRatio,
        ),
      );
    } catch (e) {
      throw StateError('Flutter GPU geometry render failed: $e');
    }
  }
}

// Images here borrow the renderer's handles. A retained temporary frame must
// clone both images before another render can dispose those borrowed handles.
typedef _GpuGeometryFrame = ({
  bool analytic,
  Size textureSize,
  Size materialTextureSize,
  ui.Image? image,
  ui.Image? materialImage,
  Rect matteBounds,
  Offset materialCenter,
  Size materialSize,
  List<LiquidGlassAppearance> appearances,
});

(bool, bool, LiquidGlassAppearance?) _classifyShapeAppearances(
  List<LiquidGlassAppearance> appearances,
  LiquidGlassAppearance fallback,
) {
  final first = appearances.isEmpty ? fallback : appearances.first;
  final mixed = appearances.any((appearance) => appearance != first);
  final tintOnly =
      mixed &&
      appearances.every(
        (appearance) =>
            appearance.saturation == first.saturation &&
            appearance.transmissionGamma == first.transmissionGamma &&
            appearance.vibrancy == first.vibrancy &&
            appearance.visibility == first.visibility &&
            appearance.colorModel == first.colorModel,
      );
  return (mixed, tintOnly, tintOnly || !mixed ? first : null);
}

/// When a liquid layer with analytic geometry shades analytically.
@internal
enum AnalyticGeometryMode {
  /// Every frame it can.
  always,

  /// Only frames whose geometry changed: at rest it encodes a matte once
  /// and shades from it until the geometry changes again.
  changes,
}
