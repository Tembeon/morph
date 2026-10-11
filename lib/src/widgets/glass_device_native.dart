import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_tier.dart';

/// Reads the device class: `MorphGlassDeviceClass.skia` at once on a
/// runtime without Impeller, else from the Flutter GPU context once the
/// liquid tier is available, and `MorphGlassDeviceClass.unknown` before
/// that.
///
/// The context is not read earlier: on Android reading it before the
/// engine has created it blocks the UI thread.
@internal
MorphGlassDeviceClass morphProbeGlassDeviceClass() {
  if (!ui.ImageFilter.isShaderFilterSupported) {
    return MorphGlassDeviceClass.skia;
  }
  if (!morphLiquidGlassCapability.value) return MorphGlassDeviceClass.unknown;
  try {
    final context = gpu.gpuContext;
    if (!context.doesSupportFramebufferRenderMipmap) {
      return MorphGlassDeviceClass.gles;
    }
    if (Platform.isIOS &&
        !context.supportsTextureCompression(
          gpu.TextureCompressionFamily.astcHdr,
        )) {
      return MorphGlassDeviceClass.appleBeforeA13;
    }
    return MorphGlassDeviceClass.capable;
  } on Object {
    return MorphGlassDeviceClass.unknown;
  }
}
