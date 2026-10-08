import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

typedef _SamplingShaderFactory =
    ui.ImageFilter Function(
      ui.FragmentShader shader, {
      ui.FilterQuality filterQuality,
    });

final Object _shaderFactory = ui.ImageFilter.shader;

/// Retains bilinear backdrop sampling across native shader-filter SDKs.
///
/// Flutter 3.47.2 keeps sampling from the bound first shader sampler.
/// Flutter 3.49 beta replaces it with the factory's sampling argument;
/// its default nearest sampling changes the measured glass appearance.
/// Callers still bind the first sampler with low quality for older SDKs.
@internal
ui.ImageFilter morphGlassShaderFilter(ui.FragmentShader shader) {
  final factory = _shaderFactory;
  if (factory is _SamplingShaderFactory) {
    return factory(shader, filterQuality: ui.FilterQuality.low);
  }
  return ui.ImageFilter.shader(shader);
}
