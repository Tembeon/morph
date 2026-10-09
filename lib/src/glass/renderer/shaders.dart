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

  /// Enables the experimental single-primitive final shading path.
  static const bool directGeometry = bool.fromEnvironment(
    'MORPH_DIRECT_GEOMETRY',
  );

  /// Enables experimental sampled-field shading without a geometry matte.
  static const bool directField = bool.fromEnvironment('MORPH_DIRECT_FIELD');

  /// Direct appearance reading the owner's floating-point field.
  static String get liquidGlassDirectField =>
      '${_runtimeRoot}liquid_glass_direct_field.frag';

  /// Fitted appearance reading the owner's floating-point field.
  static String get liquidGlassDirectFieldIos27 =>
      '${_runtimeRoot}liquid_glass_direct_field_ios27.frag';

  /// One direct appearance with geometry evaluated by the final filter.
  static String get liquidGlassDirectGeometry =>
      '${_runtimeRoot}liquid_glass_direct_geometry.frag';

  /// One fitted appearance with geometry evaluated by the final filter.
  static String get liquidGlassDirectGeometryIos27 =>
      '${_runtimeRoot}liquid_glass_direct_geometry_ios27.frag';

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
    if (directGeometry) liquidGlassDirectGeometry,
    if (directGeometry) liquidGlassDirectGeometryIos27,
    if (directField) liquidGlassDirectField,
    if (directField) liquidGlassDirectFieldIos27,
  ];

  static String get fakeGlassSurface =>
      '${_runtimeRoot}fake_glass_surface.frag';

  static final String gpuGeometryShaderBundle =
      '${_shadersRoot}build/shaderbundles/morph_glass.shaderbundle';
}
