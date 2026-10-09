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

  /// Whether liquid layers evaluate their geometry in the final shader
  /// instead of rendering a geometry matte: up to eight separate shapes,
  /// and a glass container's fused body of up to four boxes (merged by the
  /// container's law, never fused on the CPU). Set at compile time with
  /// `--dart-define=MORPH_ANALYTIC_GEOMETRY=true`; off by default.
  static const bool analyticGeometry = bool.fromEnvironment(
    'MORPH_ANALYTIC_GEOMETRY',
  );

  /// When liquid layers shade analytically, with [analyticGeometry] on:
  /// `always`, every frame (the default), or `changes`, only frames whose
  /// geometry changed - a layer at rest encodes a matte once and shades
  /// from it until its geometry changes again. Set at compile time with
  /// `--dart-define=MORPH_ANALYTIC_MODE=changes`.
  static const String analyticMode = String.fromEnvironment(
    'MORPH_ANALYTIC_MODE',
    defaultValue: 'always',
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

  static String get liquidGlassAnalyticRender =>
      '${_runtimeRoot}liquid_glass_final_render_analytic.frag';

  static String get liquidGlassAnalyticIos27Render =>
      '${_runtimeRoot}liquid_glass_final_render_analytic_ios27.frag';

  static String get liquidGlassAnalyticTintRender =>
      '${_runtimeRoot}liquid_glass_final_render_analytic_tint.frag';

  static String get liquidGlassAnalyticTintIos27Render =>
      '${_runtimeRoot}liquid_glass_final_render_analytic_tint_ios27.frag';

  static String get liquidGlassAnalyticFusedRender =>
      '${_runtimeRoot}liquid_glass_final_render_analytic_fused.frag';

  static String get liquidGlassAnalyticFusedIos27Render =>
      '${_runtimeRoot}liquid_glass_final_render_analytic_fused_ios27.frag';

  static String get liquidGlassAnalyticFusedTintRender =>
      '${_runtimeRoot}liquid_glass_final_render_analytic_fused_tint.frag';

  static String get liquidGlassAnalyticFusedTintIos27Render =>
      '${_runtimeRoot}liquid_glass_final_render_analytic_fused_tint_ios27.frag';

  /// The final shaders that merge a fused body of boxes analytically, in
  /// the order of [liquidGlassAnalyticRenders]; only a layer whose field
  /// is a `GlassBoxField` draws with them, so the separate-shape variants
  /// carry none of the merge law.
  static List<String> get liquidGlassAnalyticFusedRenders => [
    liquidGlassAnalyticFusedRender,
    liquidGlassAnalyticFusedIos27Render,
    liquidGlassAnalyticFusedTintRender,
    liquidGlassAnalyticFusedTintIos27Render,
  ];

  /// The final shaders that evaluate their shapes analytically: one
  /// appearance with the direct and with an iOS 27 color model, shapes that
  /// differ only by tint with the direct and with an iOS 27 color model.
  ///
  /// Not part of [liquidGlassRenders]: they load only while analytic
  /// geometry is enabled, and a copy of the runtime shaders under
  /// [debugRuntimeRoot] without them leaves its layers on the matte path.
  static List<String> get liquidGlassAnalyticRenders => [
    liquidGlassAnalyticRender,
    liquidGlassAnalyticIos27Render,
    liquidGlassAnalyticTintRender,
    liquidGlassAnalyticTintIos27Render,
  ];

  /// The final liquid glass shaders in the order a layer binds them: one
  /// appearance with the direct and with an iOS 27 color model, shapes with
  /// their own appearances, shapes that differ only by tint with the direct
  /// and with an iOS 27 color model.
  static List<String> get liquidGlassRenders => [
    liquidGlassRender,
    liquidGlassIos27Render,
    liquidGlassMaterialRender,
    liquidGlassTintRender,
    liquidGlassTintIos27Render,
  ];

  static String get fakeGlassSurface =>
      '${_runtimeRoot}fake_glass_surface.frag';

  /// The single-pass Gaussian the bar glyphs blur with.
  static String get glyphBlur =>
      '${_shadersRoot}lib/src/widgets/shaders/glyph_blur.frag';

  /// The box reduction the glyph blur's raster pyramids are drawn with.
  static String get glyphReduce =>
      '${_shadersRoot}lib/src/widgets/shaders/glyph_reduce.frag';

  /// The flat tier's fill of a glass container body of merged boxes.
  static String get flatFusedBody =>
      '${_shadersRoot}lib/src/widgets/shaders/flat_fused_body.frag';

  static final String gpuGeometryShaderBundle =
      '${_shadersRoot}build/shaderbundles/morph_glass.shaderbundle';
}
