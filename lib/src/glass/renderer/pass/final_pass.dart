import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:morph/src/glass/renderer/geometry/glass_shape_pack.dart';
import 'package:morph/src/glass/renderer/internal/shader_uniforms.dart';
import 'package:morph/src/glass/renderer/internal/shader_filter.dart';
import 'package:morph/src/glass/renderer/liquid_glass_glow.dart';
import 'package:morph/src/glass/renderer/liquid_glass_settings.dart';
import 'package:morph/src/glass/renderer/liquid_shader_variants.dart';
import 'package:morph/src/glass/renderer/pass/final_pass_layout.dart';
import 'package:morph/src/glass/renderer/pass/glass_frost.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

/// What a [GlassFinalPass] reads from the glass layer it shades.
@internal
abstract interface class GlassPassSource {
  /// The layer's settings.
  LiquidGlassSettings get settings;

  /// The layer's device pixel ratio.
  double get devicePixelRatio;

  /// The appearance of shapes without one of their own.
  LiquidGlassAppearance get defaultAppearance;

  /// Where the layer's frost is blurred.
  GlassFrost get frost;

  /// The center of the layer's glass in its matte, in logical pixels.
  Offset get materialCenter;

  /// The size of the layer's glass in its matte, in logical pixels.
  Size get materialSize;

  /// Shorter side in logical pixels of the smallest shape of the layer.
  double get materialShortSide;

  /// The shapes of the current analytic frame, or null for a matte frame.
  GlassShapePack? get analyticShapes;
}

/// The final shader of one glass layer: its variant, its uniforms and the
/// image filter over them.
///
/// The engine copies a shader's uniforms into the native image filter when
/// that filter is first converted, so a filter wrapping the shader may only
/// be reused while [takeInputsChanged] stays false. A new [FragmentShader]'s
/// uniforms are not zeroed (SkData::MakeUninitialized), so every shader is
/// written in full before it first draws. Every uniform write goes through
/// this class, at the indices of [FinalPassLayout].
@internal
final class GlassFinalPass {
  /// Shades [_source] with [matteShaders], one per [matteVariants] entry
  /// in its order.
  GlassFinalPass(this._source, List<FragmentShader> matteShaders)
    : _matte = {
        for (final (index, variant) in matteVariants.indexed)
          variant: matteShaders[index],
      };

  /// The matte variants, in the order of [ShaderKeys.liquidGlassRenders].
  static final List<LiquidShaderVariant> matteVariants = [
    for (final variant in LiquidShaderVariant.values)
      if (!variant.analyticGeometry) variant,
  ];

  final GlassPassSource _source;
  final Map<LiquidShaderVariant, FragmentShader> _matte;

  // The analytic shaders for separate shapes and for merged boxes, created
  // once all programs of their kind have loaded.
  Map<LiquidShaderVariant, FragmentShader>? _analytic;
  Map<LiquidShaderVariant, FragmentShader>? _analyticFused;

  // MARK: Programs

  static final Map<String, Future<FragmentProgram?>> _loads = {};
  static final Map<String, FragmentProgram> _programs = {};

  /// Counts the analytic programs loaded, so layers waiting on them can
  /// draw a new geometry frame.
  static final ValueNotifier<int> analyticProgramsLoaded = ValueNotifier(0);

  /// Loads the analytic final shader programs; completes when each has
  /// loaded or failed. A program that fails to load leaves every layer on
  /// the matte path.
  static Future<void> precacheAnalyticShaders() => Future.wait([
    for (final key in [
      ...ShaderKeys.liquidGlassAnalyticRenders,
      ...ShaderKeys.liquidGlassAnalyticFusedRenders,
    ])
      _load(key),
  ]);

  static Future<FragmentProgram?> _load(String key) =>
      _loads[key] ??= FragmentProgram.fromAsset(key).then(
        (program) {
          _programs[key] = program;
          analyticProgramsLoaded.value++;
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
  static FragmentProgram? analyticProgram(String key) => _programs[key];

  /// Whether this pass has the analytic shaders a frame of separate shapes
  /// or, with [fused], of merged boxes draws with, creating the four of
  /// that kind once all their programs have loaded and starting the loads
  /// otherwise.
  bool analyticShadersReady({required bool fused}) {
    if ((fused ? _analyticFused : _analytic) != null) return true;
    final variants = [
      for (final variant in LiquidShaderVariant.values)
        if (variant.analyticGeometry && variant.fused == fused) variant,
    ];
    var ready = true;
    for (final variant in variants) {
      final key = ShaderKeys.finalRender(variant);
      if (_programs[key] == null) {
        unawaited(_load(key));
        ready = false;
      }
    }
    if (!ready) return false;
    final shaders = {
      for (final variant in variants)
        variant: _programs[ShaderKeys.finalRender(variant)]!.fragmentShader(),
    };
    if (fused) {
      _analyticFused = shaders;
    } else {
      _analytic = shaders;
    }
    _stale.addAll(shaders.values);
    return true;
  }

  // MARK: Variant

  /// The variant a frame draws with: each compiles only the color models it
  /// can meet, and the one-appearance and tint-only matte variants without
  /// the shader frost fit the register budget of full thread occupancy on a
  /// Mali-G78. The frosted, mixed-appearance and analytic variants run at
  /// half occupancy there.
  static LiquidShaderVariant variantFor({
    required bool analytic,
    required bool fused,
    required bool shapeAppearances,
    required bool tintOnly,
    required bool ios27,
    required bool frost,
  }) {
    if (shapeAppearances && !tintOnly) return LiquidShaderVariant.material;
    final tint = shapeAppearances;
    if (analytic) {
      return switch ((fused, tint, ios27)) {
        (false, false, false) => LiquidShaderVariant.analytic,
        (false, false, true) => LiquidShaderVariant.analyticIos27,
        (false, true, false) => LiquidShaderVariant.analyticTint,
        (false, true, true) => LiquidShaderVariant.analyticTintIos27,
        (true, false, false) => LiquidShaderVariant.analyticFused,
        (true, false, true) => LiquidShaderVariant.analyticFusedIos27,
        (true, true, false) => LiquidShaderVariant.analyticFusedTint,
        (true, true, true) => LiquidShaderVariant.analyticFusedTintIos27,
      };
    }
    return switch ((tint, ios27, frost)) {
      (false, false, true) => LiquidShaderVariant.direct,
      (false, false, false) => LiquidShaderVariant.directUnfrosted,
      (false, true, true) => LiquidShaderVariant.ios27,
      (false, true, false) => LiquidShaderVariant.ios27Unfrosted,
      (true, false, true) => LiquidShaderVariant.tint,
      (true, false, false) => LiquidShaderVariant.tintUnfrosted,
      (true, true, true) => LiquidShaderVariant.tintIos27,
      (true, true, false) => LiquidShaderVariant.tintIos27Unfrosted,
    };
  }

  /// The variant the current appearances, geometry and frost draw with.
  LiquidShaderVariant get variant {
    final shapes = _source.analyticShapes;
    return variantFor(
      analytic: shapes != null,
      fused: shapes?.fused ?? false,
      shapeAppearances: _usesShapeAppearances,
      tintOnly: _usesTintOnlyAppearance,
      ios27:
          (_uniformAppearance ?? _source.defaultAppearance).colorModel
              is! DirectLiquidGlassColorModel,
      frost: _source.frost.shaderSigma > 0,
    );
  }

  FragmentShader _shaderOf(LiquidShaderVariant variant) =>
      (variant.analyticGeometry
      ? (variant.fused ? _analyticFused : _analytic)!
      : _matte)[variant]!;

  /// The shader of [variant], its common uniforms written.
  FragmentShader get shader {
    final shader = _shaderOf(variant);
    _writeStale(shader);
    return shader;
  }

  // MARK: Appearances

  LiquidGlassAppearance? _uniformAppearance;
  List<LiquidGlassAppearance> _shapeAppearances = const [];
  bool _usesShapeAppearances = false;
  bool _usesTintOnlyAppearance = false;

  /// The appearances of the shapes the last geometry frame shaded.
  List<LiquidGlassAppearance> get shapeAppearances => _shapeAppearances;

  /// Whether the shapes differ in appearance, so a matte frame writes a
  /// material map.
  bool get usesShapeAppearances => _usesShapeAppearances;

  /// Whether the shapes differ only in tint.
  bool get usesTintOnlyAppearance => _usesTintOnlyAppearance;

  /// Takes the appearances of a frame's shapes.
  void setShapeAppearances(List<LiquidGlassAppearance> appearances) {
    final (usesShapeAppearances, usesTintOnlyAppearance, uniformAppearance) =
        classifyGlassAppearances(appearances, _source.defaultAppearance);
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
    updateSettings();
  }

  // MARK: Glow

  LiquidGlassGlow? _glow;

  /// The touch glow the pass applies to the glass, or null for none.
  LiquidGlassGlow? get glow => _glow;

  /// Takes [value] as the glow; false when it is the glow already.
  bool setGlow(LiquidGlassGlow? value) {
    if (_glow == value) return false;
    _glow = value;
    updateSettings();
    return true;
  }

  // MARK: Uniforms

  final Set<FragmentShader> _stale = {};

  bool _inputsChanged = true;

  /// Notes a change of something a filter over the shader snapshots.
  void markInputsChanged() => _inputsChanged = true;

  /// Whether a uniform or sampler of [shader] changed since the last call,
  /// which also resets it.
  bool takeInputsChanged() {
    final changed = _inputsChanged;
    _inputsChanged = false;
    return changed;
  }

  /// Writes the settings, the appearance and the glow into every shader
  /// before it next draws, the current one now.
  void updateSettings() {
    _inputsChanged = true;
    _stale.addAll(_matte.values);
    if (_analytic case final shaders?) _stale.addAll(shaders.values);
    if (_analyticFused case final shaders?) _stale.addAll(shaders.values);
    _writeStale(shader);
  }

  void _writeStale(FragmentShader shader) {
    if (!_stale.remove(shader)) return;
    _writeCommon(shader, _uniformAppearance ?? _source.defaultAppearance);
  }

  void _writeCommon(FragmentShader shader, LiquidGlassAppearance appearance) {
    final settings = _source.settings;
    final dpr = _source.devicePixelRatio;
    final materialCenter = _source.materialCenter;
    // The final shader fades the whole material with visibility, so the
    // color factors are written at full strength.
    shader.setFloatUniforms(initialIndex: FinalPassLayout.tint, (value) {
      value
        ..setColor(appearance.tint)
        ..setFloats([
          settings.effectiveDisplacementScale * dpr,
          settings.dispersion,
          settings.effectiveEdgeDistanceRange * dpr,
          settings.highlight,
          1 - settings.effectiveBackdropShrink,
          appearance.saturation,
        ])
        // The final pass folds the light direction, the highlight color
        // and the rim values written below as literals or GlassRim
        // constants (test/glass_rim_constants_test.dart).
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
          GlassRim.highlightWidth * dpr,
          GlassRim.highlightOppositeStrength,
        ])
        ..setFloats([
          settings.contourWidth * dpr,
          0, // contour transmittance
          settings.contourDirectionality,
        ])
        ..setFloats([
          0, // contour offset
          materialCenter.dx * dpr,
          materialCenter.dy * dpr,
          GlassRim.highlightWrap,
        ])
        ..setFloats([
          appearance.transmissionGamma,
          appearance.vibrancy,
          settings.effectiveTintAmount,
        ])
        ..setFloats([
          settings.bevelShadowStrength,
          GlassRim.bevelShadowDepth * dpr,
          GlassRim.bevelShadowOffset * dpr,
        ])
        ..setFloats([
          appearance.colorModel.shaderValue,
          appearance.visibility,
          FlutterGpuGeometryRenderer.materialRasterScale.toDouble(),
          _source.materialShortSide,
        ]);
    });
    // Frosted glass cross-fades its blur away, while unfrosted glass stays
    // alpha-1 and cross-fades its material in the shader, so both match the
    // backdrop exactly at visibility 0.
    final frost = _source.frost;
    shader.setFloat(
      FinalPassLayout.blurFade,
      frost.passSigma > 0 || frost.shaderSigma > 0 ? 1 : 0,
    );
    shader.setFloat(
      FinalPassLayout.soften,
      frost.shaderSigma > 0
          ? 2 + frost.shaderSigma
          : frost.softens
          ? 1
          : 0,
    );
    _writeShrinkAxis(shader);
    // Read the backdrop until a solid frame writes its color.
    for (var i = 0; i < 4; i++) {
      shader.setFloat(FinalPassLayout.solidBackdrop + i, 0);
    }
    shader.setFloatUniforms(
      initialIndex: FinalPassLayout.glow,
      (value) => value.setFloats(LiquidGlassGlow.uniformsOf(_glow, dpr)),
    );
  }

  // uBackdropShrinkAxis: half the line the backdrop shrinks about, in
  // device pixels from the material center.
  void _writeShrinkAxis(FragmentShader shader) {
    final size = _source.materialSize;
    final rim = _source.settings.effectiveBackdropShrinkRim;
    final half =
        rim *
        (size.longestSide - size.shortestSide) /
        2 *
        _source.devicePixelRatio;
    final alongX = size.width >= size.height;
    shader.setFloat(FinalPassLayout.backdropShrinkAxis, alongX ? half : 0);
    shader.setFloat(FinalPassLayout.backdropShrinkAxis + 1, alongX ? 0 : half);
  }

  /// Writes the fragment-to-matte mapping and the device rect the backdrop
  /// is captured for (unbounded when null).
  void writeMapping(
    (double, double, double, double, double, double) mapping,
    Rect? backdropBounds,
  ) {
    final shader = this.shader;
    final dpr = _source.devicePixelRatio;
    const basis = FinalPassLayout.filterToMatteBasis;
    shader.setFloat(basis, mapping.$1);
    shader.setFloat(basis + 1, mapping.$2);
    shader.setFloat(basis + 2, mapping.$3);
    shader.setFloat(basis + 3, mapping.$4);
    shader.setFloat(FinalPassLayout.filterToMatteOffset, mapping.$5);
    shader.setFloat(FinalPassLayout.filterToMatteOffset + 1, mapping.$6);
    const bounds = FinalPassLayout.backdropBounds;
    final matteBounds = backdropBounds ?? Rect.largest;
    shader.setFloat(bounds, matteBounds.left * dpr);
    shader.setFloat(bounds + 1, matteBounds.top * dpr);
    shader.setFloat(bounds + 2, matteBounds.right * dpr);
    shader.setFloat(bounds + 3, matteBounds.bottom * dpr);
  }

  FragmentShader? _boundShader;
  ui.Image? _boundGeometryImage;
  ui.Image? _boundMaterialImage;
  Rect? _boundMatteBounds;

  /// Binds a geometry frame: [geometryImage], or the analytic shapes when
  /// it is null, the material map, and where the matte lies.
  void bindGeometry({
    required ui.Image? geometryImage,
    required ui.Image? materialImage,
    required Rect matteBounds,
    required Size geometryTextureSize,
    required Size materialTextureSize,
  }) {
    final variant = this.variant;
    final shader = _shaderOf(variant);
    _writeStale(shader);
    final dpr = _source.devicePixelRatio;
    shader
      ..setFloatUniforms(initialIndex: FinalPassLayout.geometryOffset, (value) {
        value
          ..setOffset(matteBounds.topLeft * dpr)
          ..setSize(matteBounds.size * dpr);
      })
      ..setFloatUniforms(initialIndex: FinalPassLayout.materialCenter, (value) {
        value.setOffset(_source.materialCenter * dpr);
      })
      ..setFloatUniforms(initialIndex: FinalPassLayout.geometryUVScale, (
        value,
      ) {
        final matteSize = matteBounds.size * dpr;
        value.setFloats([
          if (geometryTextureSize.isEmpty) ...[
            1,
            1,
          ] else ...[
            matteSize.width / geometryTextureSize.width,
            matteSize.height / geometryTextureSize.height,
          ],
          materialTextureSize.width,
          materialTextureSize.height,
        ]);
      });
    if (geometryImage == null) {
      // Older engines retain this sampler's quality when replacing its
      // texture. Newer engines use morphGlassShaderFilter's explicit quality.
      shader.setImageSampler(
        0,
        _holdBlankImage(),
        filterQuality: FilterQuality.low,
      );
      if (_source.analyticShapes case final shapes?) {
        _writeAnalytic(shader, shapes, tint: variant.shapeTint);
      }
    } else {
      shader
        ..setImageSampler(0, geometryImage, filterQuality: FilterQuality.low)
        // Nearest: the matte packs 12-bit normal angle and displacement codes
        // across byte boundaries, which filtering between texels would mix.
        ..setImageSampler(1, geometryImage);
    }
    _writeShrinkAxis(shader);
    if (materialImage != null) {
      if (_usesTintOnlyAppearance) {
        shader.setImageSampler(
          2,
          materialImage,
          filterQuality: FilterQuality.low,
        );
      } else {
        shader
          ..setImageSampler(2, materialImage)
          ..setImageSampler(3, materialImage, filterQuality: FilterQuality.low);
      }
    }
    if (!identical(geometryImage, _boundGeometryImage) ||
        !identical(materialImage, _boundMaterialImage) ||
        !identical(shader, _boundShader) ||
        matteBounds != _boundMatteBounds) {
      _boundShader = shader;
      _boundGeometryImage = geometryImage;
      _boundMaterialImage = materialImage;
      _boundMatteBounds = matteBounds;
      _inputsChanged = true;
    }
  }

  // The analytic frame's shapes and the geometry pass's optical inputs;
  // [tint] for a variant that declares uShapeTints.
  void _writeAnalytic(
    FragmentShader shader,
    GlassShapePack shapes, {
    required bool tint,
  }) {
    const at = FinalPassLayout.analytic;
    shader.setFloat(at, shapes.refractionHeight);
    shader.setFloat(at + 1, shapes.refractionAmount);
    shader.setFloat(at + 2, shapes.fitsShape ? 1 : 0);
    shader.setFloat(at + 3, shapes.shapeCount.toDouble());
    shader.setFloat(at + 4, shapes.contourExtent);
    shader.setFloat(at + 5, shapes.boxCount.toDouble());
    shader.setFloat(at + 6, shapes.spacing);
    shader.setFloat(at + 7, shapes.mergeMinWidth);
    // Only the fused variants declare uFusedBoxes.
    if (shapes.fused) {
      for (var i = 0; i < shapes.boxCount * 8; i++) {
        shader.setFloat(FinalPassLayout.fusedBoxes + i, shapes.boxes[i]);
      }
    }
    final cull = shapes.cullData;
    for (
      var i = 0;
      i < cull.length && i < FinalPassLayout.analyticMaxShapes;
      i++
    ) {
      shader.setFloat(FinalPassLayout.shapeCull + i, cull[i]);
    }
    shader.setFloat(FinalPassLayout.flatFace, shapes.flatFace ? 1 : 0);
    for (var i = 0; i < shapes.shapeData.length; i++) {
      shader.setFloat(FinalPassLayout.shapeData + i, shapes.shapeData[i]);
    }
    for (var i = 0; i < shapes.rseData.length; i++) {
      shader.setFloat(FinalPassLayout.rseData + i, shapes.rseData[i]);
    }
    for (
      var i = 0;
      shapes.pairCount > 0 && i < shapes.rseLowerData.length;
      i++
    ) {
      shader.setFloat(FinalPassLayout.rseLower + i, shapes.rseLowerData[i]);
    }
    for (var i = 0; i < shapes.boundsData.length; i++) {
      shader.setFloat(FinalPassLayout.shapeBounds + i, shapes.boundsData[i]);
    }
    if (tint) {
      final tints = shapes.fused
          ? FinalPassLayout.fusedTints
          : FinalPassLayout.tints;
      for (var i = 0; i < shapes.tints.length; i++) {
        shader.setFloat(tints + i, shapes.tints[i]);
      }
    }
  }

  // MARK: Filter and paints

  ui.ImageFilter? _blur;
  double _blurSigma = 0;

  /// An image filter over the current shader.
  ui.ImageFilter shaderFilter() => morphGlassShaderFilter(shader);

  /// The mirrored frost blur of [sigma], kept while the sigma holds.
  ui.ImageFilter frostBlur(double sigma) {
    final kept = _blur;
    if (kept != null && _blurSigma == sigma) return kept;
    final blur = ui.ImageFilter.blur(
      tileMode: TileMode.mirror,
      sigmaX: sigma,
      sigmaY: sigma,
    );
    _blur = blur;
    _blurSigma = sigma;
    return blur;
  }

  // The shaders whose uSolidBackdrop holds a color now; the others hold
  // zero, which reads the backdrop.
  final Set<FragmentShader> _solid = {};

  /// Makes the current shader read its backdrop again if a solid or a
  /// cached frame wrote a color into it.
  void readBackdrop() {
    final shader = this.shader;
    if (_solid.remove(shader)) {
      shader.setFloat(FinalPassLayout.solidBackdrop + 3, 0);
    }
  }

  /// The current shader set to shade over [solid] as a paint over a rect
  /// of [deviceSize]: every backdrop read returns the color.
  FragmentShader overSolid(Color solid, Size deviceSize) {
    final shader = this.shader;
    _solid.add(shader);
    // uSize: only the backdrop reads divide by it.
    shader.setFloat(FinalPassLayout.size, max(deviceSize.width, 1));
    shader.setFloat(FinalPassLayout.size + 1, max(deviceSize.height, 1));
    // The surface's encoding: sRGB components, extended where the color
    // lies outside sRGB (a Display P3 fill on a wide-gamut surface).
    final color = solid.withValues(colorSpace: ColorSpace.extendedSRGB);
    const at = FinalPassLayout.solidBackdrop;
    shader.setFloat(at, color.r);
    shader.setFloat(at + 1, color.g);
    shader.setFloat(at + 2, color.b);
    shader.setFloat(at + 3, 1);
    return shader;
  }

  /// The current shader set to shade as a paint over [copy], a copy of the
  /// backdrop whose first texel maps to [filterToMatteOffset], with
  /// [overlay] composited over it.
  FragmentShader overCopy(
    ui.Image copy, {
    required Offset? filterToMatteOffset,
    required Color overlay,
  }) {
    final shader = this.shader;
    if (filterToMatteOffset != null) {
      shader.setFloat(
        FinalPassLayout.filterToMatteOffset,
        filterToMatteOffset.dx,
      );
      shader.setFloat(
        FinalPassLayout.filterToMatteOffset + 1,
        filterToMatteOffset.dy,
      );
    }
    shader.setFloat(FinalPassLayout.size, copy.width.toDouble());
    shader.setFloat(FinalPassLayout.size + 1, copy.height.toDouble());
    final color = overlay.withValues(colorSpace: ColorSpace.extendedSRGB);
    const at = FinalPassLayout.solidBackdrop;
    shader.setFloat(at, color.r);
    shader.setFloat(at + 1, color.g);
    shader.setFloat(at + 2, color.b);
    // An alpha in (0, 0.5] composites the color over the read backdrop;
    // above 0.5 it would replace the backdrop (solid).
    shader.setFloat(at + 3, color.a * 0.5);
    _solid.add(shader);
    shader.setImageSampler(0, copy, filterQuality: FilterQuality.low);
    return shader;
  }

  // MARK: Placeholder

  // The image bound to the background sampler before the native filter
  // replaces it with its input, when no matte exists to bind there: one
  // 1x1 image every analytic pass shares, disposed with the last pass that
  // bound it. A shader keeps its own reference to a bound image, so
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

  /// Releases the analytic shaders and the placeholder image.
  void dispose() {
    if (_holdsBlankImage) {
      _holdsBlankImage = false;
      if (--_blankImageHolders == 0) {
        _blankImage?.dispose();
        _blankImage = null;
      }
    }
    for (final shaders in [?_analytic, ?_analyticFused]) {
      _stale.removeAll(shaders.values);
      for (final shader in shaders.values) {
        shader.dispose();
      }
    }
    _analytic = null;
    _analyticFused = null;
  }
}

/// Whether [appearances] differ ("mixed"), whether only by tint, and the
/// one appearance a uniform frame draws ([fallback] without shapes), null
/// for mixed appearances that differ by more than tint.
@internal
(bool, bool, LiquidGlassAppearance?) classifyGlassAppearances(
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
