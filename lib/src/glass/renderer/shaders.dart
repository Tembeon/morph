// ignore_for_file: public_member_api_docs

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/liquid_shader_variants.dart';

@internal
bool isLocalTest = false;

final String _shadersRoot = !kIsWeb && isLocalTest ? '' : 'packages/morph/';

@internal
abstract class ShaderKeys {
  const ShaderKeys._();

  /// The asset folder the final-pass variants load from instead of the
  /// package's own, as `<fileName>.frag` (a harness that renders a second
  /// copy of them in the same app lists them as shaders); null loads the
  /// package's.
  @visibleForTesting
  static String? debugRuntimeRoot;

  /// The asset key of [variant]'s compiled final pass: the library
  /// hook/build.dart writes into the package's `build/shaderbundles/`, or
  /// its copy under [debugRuntimeRoot].
  static String finalRender(LiquidShaderVariant variant) =>
      switch (debugRuntimeRoot) {
        final root? => '$root${variant.fileName}.frag',
        null => '${_shadersRoot}build/shaderbundles/${variant.fileName}.iplr',
      };

  static List<String> _finalRenders(
    bool Function(LiquidShaderVariant variant) test,
  ) => [
    for (final variant in LiquidShaderVariant.values)
      if (test(variant)) finalRender(variant),
  ];

  /// Whether liquid layers evaluate their geometry in the final shader
  /// instead of rendering a geometry matte: up to eight separate shapes,
  /// and a glass container's fused body of up to four boxes (merged by the
  /// container's law, never fused on the CPU). Set at compile time with
  /// `--dart-define=MORPH_ANALYTIC_GEOMETRY=false` to always render the
  /// matte; on by default.
  static const bool analyticGeometry = bool.fromEnvironment(
    'MORPH_ANALYTIC_GEOMETRY',
    defaultValue: true,
  );

  /// When liquid layers shade analytically, with [analyticGeometry] on:
  /// `changes` (the default), only frames whose geometry changed - a layer
  /// at rest encodes a matte once and shades from it until its geometry
  /// changes again - or `always`, every frame. Set at compile time with
  /// `--dart-define=MORPH_ANALYTIC_MODE=always`.
  static const String analyticMode = String.fromEnvironment(
    'MORPH_ANALYTIC_MODE',
    defaultValue: 'changes',
  );

  /// Whether analytic frames shade a rounded superellipse whose corners
  /// are half its short side as the stadium of the same box, instead of
  /// solving the superellipse per pixel: not the same shape (Flutter's
  /// rounded superellipse lies up to 0.39 pt inside the stadium along
  /// its caps), so an approximation, for measurement. Set at compile time
  /// with `--dart-define=MORPH_ANALYTIC_CAPSULE=true`; off by default.
  static const bool analyticCapsule = bool.fromEnvironment(
    'MORPH_ANALYTIC_CAPSULE',
  );

  /// The final shaders a fused body of boxes draws with: the analytic
  /// variants that merge it, in the order of [liquidGlassAnalyticRenders],
  /// then the tint-only matte variants that take its tints from its boxes.
  /// Only a layer whose field is a `GlassBoxField` draws with them, so the
  /// separate-shape variants carry none of the merge law.
  static List<String> get liquidGlassAnalyticFusedRenders =>
      _finalRenders((variant) => variant.fusedSet);

  /// The final shaders that evaluate their shapes analytically: one
  /// appearance with the direct and with an iOS 27 color model, shapes that
  /// differ only by tint with the direct and with an iOS 27 color model.
  ///
  /// Not part of [liquidGlassRenders]: they load only while analytic
  /// geometry is enabled, and a copy of the runtime shaders under
  /// [debugRuntimeRoot] without them leaves its layers on the matte path.
  static List<String> get liquidGlassAnalyticRenders =>
      _finalRenders((variant) => variant.analyticGeometry && !variant.fused);

  /// The final liquid glass shaders in the order a layer binds them: one
  /// appearance with the direct and with an iOS 27 color model, shapes with
  /// their own appearances, shapes that differ only by tint with the direct
  /// and with an iOS 27 color model.
  static List<String> get liquidGlassRenders =>
      _finalRenders((variant) => !variant.analyticGeometry && !variant.boxTint);

  /// The single-pass Gaussian the bar glyphs blur with.
  static String get glyphBlur =>
      '${_shadersRoot}lib/src/widgets/shaders/glyph_blur.frag';

  /// The box reduction the glyph blur's raster pyramids are drawn with.
  static String get glyphReduce =>
      '${_shadersRoot}lib/src/widgets/shaders/glyph_reduce.frag';

  /// A glass shadow of a rounded superellipse drawn as one rect.
  static String get glassShadow =>
      '${_shadersRoot}lib/src/glass/renderer/shaders/glass_shadow.frag';

  /// The flat tier's fill of a glass container body of merged boxes.
  static String get flatFusedBody =>
      '${_shadersRoot}lib/src/glass/renderer/shaders/flat_fused_body.frag';

  static final String gpuGeometryShaderBundle =
      '${_shadersRoot}build/shaderbundles/morph_glass.shaderbundle';
}
