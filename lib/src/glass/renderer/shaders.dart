// ignore_for_file: public_member_api_docs

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

@internal
bool isLocalTest = false;

final String _shadersRoot = !kIsWeb && isLocalTest ? '' : 'packages/morph/';

@internal
abstract class ShaderKeys {
  const ShaderKeys._();

  /// The asset folder the runtime-effect shaders load from instead of the
  /// package's own, for a harness that renders a second copy of them in
  /// the same app; null loads the package's.
  @visibleForTesting
  static String? debugRuntimeRoot;

  static String get _runtimeRoot =>
      debugRuntimeRoot ?? '${_shadersRoot}lib/src/glass/renderer/shaders/';

  static String get liquidGlassRender =>
      '${_runtimeRoot}liquid_glass_final_render.frag';

  static String get liquidGlassMaterialRender =>
      '${_runtimeRoot}liquid_glass_final_render_material.frag';

  static String get liquidGlassTintRender =>
      '${_runtimeRoot}liquid_glass_final_render_tint.frag';

  static String get liquidGlassIos27Render =>
      '${_runtimeRoot}liquid_glass_final_render_ios27.frag';

  static String get liquidGlassTintIos27Render =>
      '${_runtimeRoot}liquid_glass_final_render_tint_ios27.frag';

  /// Whether layers whose shapes are separate evaluate them in the final
  /// shader instead of rendering a geometry matte; set at compile time with
  /// `--dart-define=MORPH_ANALYTIC_GEOMETRY=true`.
  static const bool analyticGeometry = bool.fromEnvironment(
    'MORPH_ANALYTIC_GEOMETRY',
  );

  // The analytic variants always load from the package: a frozen copy of
  // the runtime shaders (debugRuntimeRoot) may predate them.
  static String get _analyticRoot =>
      '${_shadersRoot}lib/src/glass/renderer/shaders/';

  static String get liquidGlassAnalyticRender =>
      '${_analyticRoot}liquid_glass_final_render_analytic.frag';

  static String get liquidGlassAnalyticIos27Render =>
      '${_analyticRoot}liquid_glass_final_render_analytic_ios27.frag';

  static String get liquidGlassAnalyticTintRender =>
      '${_analyticRoot}liquid_glass_final_render_analytic_tint.frag';

  static String get liquidGlassAnalyticTintIos27Render =>
      '${_analyticRoot}liquid_glass_final_render_analytic_tint_ios27.frag';

  /// The final shaders that evaluate their shapes analytically, in the
  /// order of [liquidGlassRenders]' tail: one appearance with the direct and
  /// with an iOS 27 color model, shapes that differ only by tint with the
  /// direct and with an iOS 27 color model.
  static List<String> get liquidGlassAnalyticRenders => [
    liquidGlassAnalyticRender,
    liquidGlassAnalyticIos27Render,
    liquidGlassAnalyticTintRender,
    liquidGlassAnalyticTintIos27Render,
  ];

  /// The final liquid glass shaders in the order a layer binds them: one
  /// appearance with the direct and with an iOS 27 color model, shapes with
  /// their own appearances, shapes that differ only by tint with the direct
  /// and with an iOS 27 color model, then [liquidGlassAnalyticRenders].
  static List<String> get liquidGlassRenders => [
    liquidGlassRender,
    liquidGlassIos27Render,
    liquidGlassMaterialRender,
    liquidGlassTintRender,
    liquidGlassTintIos27Render,
    ...liquidGlassAnalyticRenders,
  ];

  static String get fakeGlassSurface =>
      '${_runtimeRoot}fake_glass_surface.frag';

  /// The single-pass Gaussian the bar glyphs blur with.
  static String get glyphBlur =>
      '${_shadersRoot}lib/src/widgets/shaders/glyph_blur.frag';

  /// The box reduction the glyph blur's raster pyramids are drawn with.
  static String get glyphReduce =>
      '${_shadersRoot}lib/src/widgets/shaders/glyph_reduce.frag';

  static final String gpuGeometryShaderBundle =
      '${_shadersRoot}build/shaderbundles/morph_glass.shaderbundle';
}
