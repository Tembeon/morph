// ignore_for_file: public_member_api_docs

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

@internal
bool isLocalTest = false;

final String _shadersRoot = !kIsWeb && isLocalTest ? '' : 'packages/morph/';

@internal
abstract class ShaderKeys {
  const ShaderKeys._();

  static final liquidGlassRender =
      '${_shadersRoot}lib/src/glass/renderer/shaders/liquid_glass_final_render.frag';

  static final liquidGlassMaterialRender =
      '${_shadersRoot}lib/src/glass/renderer/shaders/liquid_glass_final_render_material.frag';

  static final liquidGlassTintRender =
      '${_shadersRoot}lib/src/glass/renderer/shaders/liquid_glass_final_render_tint.frag';

  static final fakeGlassSurface =
      '${_shadersRoot}lib/src/glass/renderer/shaders/fake_glass_surface.frag';

  static final String gpuGeometryShaderBundle =
      'packages/morph/flutter_gpu_shaders/shaderbundles/morph_glass.shaderbundle';
}
