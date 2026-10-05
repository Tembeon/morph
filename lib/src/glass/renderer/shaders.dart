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

  static String get fakeGlassSurface =>
      '${_runtimeRoot}fake_glass_surface.frag';

  static final String gpuGeometryShaderBundle =
      '${_shadersRoot}build/shaderbundles/morph_glass.shaderbundle';
}
