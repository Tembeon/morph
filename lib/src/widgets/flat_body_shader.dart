import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/liquid_field.dart'
    show LiquidField, liquidMinMergeWidth;

/// Fills the flat tier's glass container bodies of merged rounded boxes
/// with a fragment shader that evaluates the container's merge law per
/// pixel, instead of a silhouette the package traces on the CPU.
///
/// The shader folds the boxes by the law [LiquidField] samples (the same
/// GLSL the liquid tier's analytic final pass merges with), in list order,
/// and covers each pixel by the signed distance over one device pixel; an
/// optional rim strokes the edge centered on it, as a stroked path does.
/// It runs on Skia and on Impeller.
///
/// On by default: `--dart-define=MORPH_FLAT_SHADER_BODIES=false` fills the
/// traced outline instead, or [debugEnabled] in tests. While the shader has not loaded, a body fills
/// its traced outline as before.
@internal
abstract final class MorphFlatBodyShader {
  /// Whether the build enables the shader bodies.
  static const bool defined = bool.fromEnvironment(
    'MORPH_FLAT_SHADER_BODIES',
    defaultValue: true,
  );

  /// Overrides [defined] when not null.
  @visibleForTesting
  static bool? debugEnabled;

  /// Whether flat glass container bodies of at most [maxBoxes] boxes are
  /// filled by the shader.
  static bool get enabled => debugEnabled ?? defined;

  /// The most boxes the shader merges (its FUSED_MAX_BOXES).
  static const int maxBoxes = 4;

  static ui.FragmentProgram? _program;
  static ui.FragmentShader? _shader;
  static Future<void>? _loading;

  /// Loads the shader; never fails (a shader that cannot load leaves every
  /// body on its traced outline).
  static Future<void> precache() => _loading ??= ui.FragmentProgram.fromAsset(
    ShaderKeys.flatFusedBody,
  ).then((ui.FragmentProgram program) => _program = program, onError: _ignore);

  static void _ignore(Object error) {}

  /// Whether the shader has loaded.
  static bool get ready => _program != null;

  /// Fills the body [boxes] merge into with [spacing], in [canvas]'s local
  /// coordinates, with [fill], and strokes its edge [rimWidth] wide with
  /// [rim] when that is not clear; [screenScale] is the device pixels per
  /// local unit. Returns false, drawing nothing, while the shader has not
  /// loaded.
  static bool paint(
    Canvas canvas,
    List<RRect> boxes,
    double spacing,
    double screenScale, {
    required Color fill,
    Color rim = const Color(0x00000000),
    double rimWidth = 0,
  }) {
    final program = _program;
    if (program == null) return false;
    assert(
      boxes.isNotEmpty && boxes.length <= maxBoxes,
      'The shader merges 1 to $maxBoxes boxes.',
    );
    final shader = _shader ??= program.fragmentShader();
    var bounds = boxes.first.outerRect;
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final hx = box.width / 2;
      final hy = box.height / 2;
      shader.setFloat(i * 8, box.center.dx);
      shader.setFloat(i * 8 + 1, box.center.dy);
      shader.setFloat(i * 8 + 2, hx);
      shader.setFloat(i * 8 + 3, hy);
      shader.setFloat(i * 8 + 4, math.min(box.tlRadiusX, math.min(hx, hy)));
      bounds = bounds.expandToInclude(box.outerRect);
    }
    const law = maxBoxes * 8;
    shader.setFloat(law, boxes.length.toDouble());
    shader.setFloat(law + 1, spacing);
    shader.setFloat(law + 2, liquidMinMergeWidth);
    shader.setFloat(law + 3, screenScale);
    _setColor(shader, law + 4, fill);
    _setColor(shader, law + 8, rim);
    shader.setFloat(law + 12, rimWidth);
    final paint = Paint();
    paint.shader = shader;
    // Each merge reaches at most a quarter of the spacing past the boxes.
    canvas.drawRect(
      bounds.inflate(
        (boxes.length - 1) * spacing / 4 + rimWidth + 2 / screenScale,
      ),
      paint,
    );
    return true;
  }

  static void _setColor(ui.FragmentShader shader, int at, Color color) {
    shader.setFloat(at, color.r);
    shader.setFloat(at + 1, color.g);
    shader.setFloat(at + 2, color.b);
    shader.setFloat(at + 3, color.a);
  }
}
