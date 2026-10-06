import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart';
import 'package:morph/src/glass/renderer/internal/glass_warm_up.dart';
import 'package:morph/src/glass/renderer/internal/liquid_capability.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_tier.dart';

export 'package:morph/src/widgets/glass_liquid_draw.dart';

final List<String> _finalShaders = ShaderKeys.liquidGlassRenders;

final LiquidCapability _capability = LiquidCapability(
  load: () async {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      throw UnsupportedError('Impeller shader filters are unavailable.');
    }
    final geometry = await FlutterGpuGeometryRenderer.fromAsset(
      ShaderKeys.gpuGeometryShaderBundle,
    );
    geometry.dispose();
    await MultiShaderBuilder.precacheShaders(_finalShaders);
  },
);

Future<void>? _warmUp;

/// Warms the liquid pipelines, then the fake glass ones, on a GPU the
/// automatic choice draws liquid on.
///
/// Nothing is warmed on any other device class: the cheap tier draws no
/// backdrop pipelines, and on Impeller's OpenGL ES backend an offscreen
/// snapshot before the first frame crashes the raster thread (Flutter
/// 3.47.2, Pixel 6a forced to GLES: a null dereference in
/// `BlitCopyBufferToTextureCommandGLES::Encode` under
/// `Rasterizer::MakeImpellerSnapshot`).
Future<void> _warmPipelines() async {
  if (MorphAdaptiveGlass.deviceClass != MorphGlassDeviceClass.capable) {
    return;
  }
  final liquid = _capability.value;
  final geometry = liquid
      ? FlutterGpuGeometryRenderer.tryCreateCached(
          ShaderKeys.gpuGeometryShaderBundle,
        )
      : null;
  if (geometry != null) {
    try {
      await morphWarmLiquidPipelines(geometry, _finalShaders);
    } finally {
      geometry.dispose();
    }
  }
  await morphWarmFakePipelines();
}

/// Whether the GPU context and all liquid shaders are ready.
@internal
bool get morphLiquidGlassAvailable {
  if (isLocalTest) return true;
  unawaited(_capability.precache());
  return _capability.value;
}

/// The cached runtime initialization failure, or null before failure.
@internal
String? get morphLiquidGlassUnavailableReason =>
    isLocalTest ? null : _capability.unavailableReason;

/// Notifies when runtime shader initialization completes successfully.
@internal
ValueListenable<bool> get morphLiquidGlassCapability => _capability;

/// The longest [morphPrecacheLiquidGlass] holds a launch.
///
/// The warm-up measured 0.35 to 0.45 s on a Pixel 6a; past this budget the
/// launch goes on and the warm-up finishes in the background.
@internal
const Duration morphPrecacheBudget = Duration(seconds: 1);

/// Resolves runtime availability without throwing on unsupported devices,
/// and warms the pipelines the first glass frame needs, waiting at most
/// [morphPrecacheBudget].
@internal
Future<void> morphPrecacheLiquidGlass() {
  if (isLocalTest) return _capability.precache();
  return morphWithinBudget(_precacheAndWarm(), morphPrecacheBudget);
}

Future<void> _precacheAndWarm() async {
  await _capability.precache();
  await (_warmUp ??= _warmPipelines());
}
