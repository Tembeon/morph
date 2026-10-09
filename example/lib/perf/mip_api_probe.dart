import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Checks explicit mip sampling through a Flutter GPU image on the native GPU.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final out = Directory(
    const String.fromEnvironment('AUDIT_OUT', defaultValue: '/tmp/morph-mip'),
  );
  out.createSync(recursive: true);
  try {
    final report = await _probe();
    final temporary = File('${out.path}/report.tmp');
    temporary.writeAsStringSync(jsonEncode(report));
    temporary.renameSync('${out.path}/report.json');
  } on Object catch (error, stack) {
    File(
      '${out.path}/error.json',
    ).writeAsStringSync(jsonEncode({'error': '$error', 'stack': '$stack'}));
  }
}

Future<Map<String, Object>> _probe() async {
  final context = gpu.gpuContext;
  final texture = context.createTexture(
    gpu.StorageMode.devicePrivate,
    64,
    64,
    format: gpu.PixelFormat.r8g8b8a8UNormInt,
    mipLevelCount: 4,
    enableRenderTargetUsage: false,
  );
  const colors = [
    [255, 0, 0, 255],
    [0, 255, 0, 255],
    [0, 0, 255, 255],
    [255, 255, 0, 255],
  ];
  final command = context.createCommandBuffer();
  for (var level = 0; level < 4; level++) {
    final bytes = Uint8List(texture.getMipLevelSizeInBytes(level));
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = colors[level][i % 4];
    }
    final buffer = context.createDeviceBufferWithCopy(
      ByteData.sublistView(bytes),
    );
    command.copyBufferToTexture(
      gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: bytes.length),
      gpu.TextureRegion(texture, mipLevel: level),
    );
  }
  final completed = Completer<bool>();
  command.submit(completionCallback: completed.complete);
  if (!await completed.future.timeout(const Duration(seconds: 20))) {
    throw StateError('Mip upload failed');
  }
  final program = await ui.FragmentProgram.fromAsset(
    'lib/perf/shaders/mip_lod.frag',
  );
  final image = texture.asImage();
  final rows = <Map<String, Object>>[];
  var wrappedMipCount = 0;
  try {
    wrappedMipCount = gpu.Texture.fromImage(context, image).mipLevelCount;
    for (final quality in [
      ui.FilterQuality.none,
      ui.FilterQuality.low,
      ui.FilterQuality.medium,
    ]) {
      for (final lod in [0.0, .5, 1.0, 1.5, 2.0, 2.5, 3.0]) {
        final shader = program.fragmentShader();
        shader.setFloat(0, 64);
        shader.setFloat(1, 64);
        shader.setFloat(2, lod);
        shader.setImageSampler(0, image, filterQuality: quality);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final paint = ui.Paint();
        paint.shader = shader;
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 64, 64), paint);
        final picture = recorder.endRecording();
        ui.Image? result;
        try {
          result = await picture.toImage(64, 64);
          final bytes = await result.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (bytes == null) throw StateError('Missing sample bytes');
          final center = (32 * 64 + 32) * 4;
          rows.add({
            'quality': quality.name,
            'lod': lod,
            'center_rgba': [
              for (var c = 0; c < 4; c++) bytes.getUint8(center + c),
            ],
          });
        } finally {
          result?.dispose();
          picture.dispose();
          shader.dispose();
        }
      }
    }
  } finally {
    image.dispose();
  }
  return {
    'schema': 'morph-mip-api-probe-v1',
    'default_color_format': '${context.defaultColorFormat}',
    'manually_mipped_textures': context.doesSupportManuallyMippedTextures,
    'render_to_mip': context.doesSupportFramebufferRenderMipmap,
    'allocated_mips': texture.mipLevelCount,
    'wrapped_mips': wrappedMipCount,
    'source_colors_rgba': colors,
    'rows': rows,
    'limitations': [
      'Explicitly uploaded colors test API interoperability, not backdrop acquisition.',
      'Picture rasterization and readback are diagnostic only; no performance claim.',
    ],
  };
}
