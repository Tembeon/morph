// The blur parameters are adapted from Flutter's Impeller
// (impeller/entity/contents/solid_rrect_like_blur_contents.cc and
// solid_rsuperellipse_blur_contents.cc, Flutter 3.49.0-0.2.pre):
//   Copyright 2013 The Flutter Authors. All rights reserved.
//   Use of this source code is governed by a BSD-style license that can be
//   found in third_party/flutter/LICENSE.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:morph/src/glass/renderer/internal/rounded_superellipse_parameters.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

/// Draws a glass shadow of a rounded superellipse as one rect with a
/// fragment shader: the Gaussian-blurred rounded superellipse Impeller draws
/// for `drawRSuperellipse` under a normal `MaskFilter.blur`, times the
/// coverage of the region outside the glass shape over one device pixel.
///
/// It replaces a clip path outside the glass and a mask-filtered shape per
/// shadow, so a shadow whose shape changes size builds no path. The shader
/// evaluates Impeller's own blur approximation, so it is drawn only where
/// Impeller draws (see [active]).
///
/// Off by default: `--dart-define=MORPH_SHADER_SHADOWS=true`, or
/// [debugEnabled] in tests. A glass shadow that attaches with the option on
/// loads the shader itself; while it has not loaded, shadows draw as
/// before.
@internal
abstract final class MorphGlassShadowShader {
  /// Whether the build enables the shader shadows.
  static const bool defined = bool.fromEnvironment('MORPH_SHADER_SHADOWS');

  /// Overrides [defined] when not null.
  @visibleForTesting
  static bool? debugEnabled;

  /// Whether glass shadows of rounded superellipses are drawn by the
  /// shader.
  static bool get enabled => debugEnabled ?? defined;

  static ui.FragmentProgram? _program;
  static ui.FragmentShader? _shader;
  static Future<void>? _loading;

  // The paint every draw shares: a draw copies the shader's uniforms.
  static final Paint _paint = Paint();

  /// Loads the shader; never fails (a shader that cannot load leaves every
  /// shadow on its clip path).
  static Future<void> precache() => _loading ??= ui.FragmentProgram.fromAsset(
    ShaderKeys.glassShadow,
  ).then((ui.FragmentProgram program) => _program = program, onError: _ignore);

  static void _ignore(Object error) {}

  /// Whether the shader has loaded.
  static bool get ready => _program != null;

  /// Whether shadows are drawn by the shader now: [enabled], on Impeller
  /// (whose blur the shader reproduces), and loaded.
  static bool get active =>
      enabled && ui.ImageFilter.isShaderFilterSupported && _program != null;

  /// The floats [blur] writes.
  static const int blurFloats = 36;

  /// The floats [coverage] writes.
  static const int coverageFloats = 20;

  /// The blur of a rounded superellipse at [rect] with corner [radius] by a
  /// Gaussian of [sigma] (a mask filter's sigma) in [color]: the shader's
  /// first [blurFloats] uniforms, Impeller's pass context for the shape.
  static Float32List blur(Rect rect, double radius, double sigma, Color color) {
    final out = Float32List(blurFloats);
    final a = color.a;
    out[0] = color.r * a;
    out[1] = color.g * a;
    out[2] = color.b * a;
    out[3] = a;

    const eps = 1e-3;
    final width = rect.width;
    final height = rect.height;
    // Rounding radii scale down to fit the sides; one uniform radius
    // becomes the smaller half side.
    final corner = math.min(radius, math.min(width, height) / 2);
    final r = math.min(
      corner.clamp(eps, width / 2),
      corner.clamp(eps, height / 2),
    );

    // SolidRRectLikeBlurContents::PopulateFragContext.
    final s = math.max(math.max(sigma, eps) * math.sqrt2, 1.0);
    final minEdge = math.min(width, height);
    final rMax = 0.5 * minEdge;
    final r0 = math.min(_hypot(r, s * 1.15), rMax);
    final r1 = math.min(_hypot(r, s * 2.0), rMax);
    final exponent = 2.0 * r1 / r0;
    final sInv = 1.0 / s;
    final ex = math.exp(-math.pow(width * sInv * 0.5, 2));
    final ey = math.exp(-math.pow(height * sInv * 0.5, 2));
    final delta = 1.25 * s * (ex - ey);
    final w = width + math.min(delta, 0.0);
    final h = height + math.max(delta, 0.0);
    final scale = 0.5 * _erf7(sInv * 0.5 * (math.max(w, h) - 0.5 * r));
    out[4] = rect.center.dx;
    out[5] = rect.center.dy;
    out[6] = w * 0.5 - r1;
    out[7] = h * 0.5 - r1;
    out[8] = r1;
    out[9] = exponent;
    out[10] = 1.0 / exponent;
    out[11] = sInv;
    out[12] = minEdge;
    out[13] = scale;

    // SolidRSuperellipseBlurContents::SetPassInfo.
    final halfWidth = width / 2;
    final halfHeight = height / 2;
    out[14] = halfWidth;
    out[15] = halfHeight;
    _octant(out, 16, halfWidth, corner);
    _octant(out, 20, halfHeight, corner);
    _poly(out, 24, halfWidth, corner);
    _poly(out, 28, halfHeight, corner);
    out[32] = math.max(corner, eps);
    return out;
  }

  // The split angle, the retraction there, n and -1 / n of the octant
  // whose half extent is [axis].
  static void _octant(Float32List out, int at, double axis, double radius) {
    final n = roundedSuperellipseDegree(axis, radius);
    if (n < 1) {
      // A sharp corner: a split past every angle, no retraction.
      out[at] = math.pi / 2;
      out[at + 1] = 0;
      out[at + 2] = 1e10;
      out[at + 3] = -1e-10;
      return;
    }
    final split = math.atan2(axis - radius, axis);
    out[at] = split;
    out[at + 1] =
        (1 - math.pow(1 + math.pow(math.tan(split), n), -1 / n)) * axis;
    out[at + 2] = n;
    out[at + 3] = -1 / n;
  }

  // The cubic with f(0) = 1, f'(0) = v0, f(1) = 0 and f'(1) = 0 whose
  // initial slope shrinks as the octant's axis grows against the radius.
  static void _poly(Float32List out, int at, double axis, double radius) {
    final v0 = axis > 0 ? radius / axis * 3 : 0.0;
    out[at] = v0 + 2;
    out[at + 1] = -2 * v0 - 3;
    out[at + 2] = v0;
    out[at + 3] = 1;
  }

  /// The glass shape the shadow stays outside of, a rounded superellipse
  /// at [rect] with corner [radius]: the shader's [coverageFloats]
  /// uniforms after the blur's, the device pixel scale left for [paint].
  static Float32List coverage(Rect rect, double radius) {
    final out = Float32List(coverageFloats);
    final corner = math.min(radius, rect.shortestSide / 2);
    out[0] = rect.center.dx;
    out[1] = rect.center.dy;
    out[2] = rect.width / 2;
    out[3] = rect.height / 2;
    out[4] = corner;
    // out[5], the device pixels per local unit, is written by paint.
    final parameters = roundedSuperellipseParameters(rect.size, corner);
    // sdfSquircle tests each cap's angular span as 1 - cos(span).
    parameters[2] = 1 - math.cos(parameters[2]);
    parameters[3] = 1 - math.cos(parameters[3]);
    for (var i = 0; i < 12; i++) {
      out[8 + i] = parameters[i];
    }
    return out;
  }

  /// The extent past its rect the blur of [sigma] covers: Impeller draws
  /// a blurred rounded superellipse over its rect grown by this.
  static double reach(double sigma) {
    final s = math.max(sigma, 1e-3);
    return s * math.min(s / 47.6 + 2.5, 3.5);
  }

  /// Fills [rect] in [canvas]'s local coordinates with the shadow [blur]
  /// describes outside the glass shape [coverage] describes, with
  /// [screenScale] device pixels per local unit. Returns false, drawing
  /// nothing, while the shader has not loaded.
  static bool paint(
    Canvas canvas,
    Rect rect,
    Float32List blur,
    Float32List coverage,
    double screenScale,
  ) {
    final program = _program;
    if (program == null) return false;
    final shader = _shader ??= program.fragmentShader();
    for (var i = 0; i < blurFloats; i++) {
      shader.setFloat(i, blur[i]);
    }
    for (var i = 0; i < coverageFloats; i++) {
      shader.setFloat(blurFloats + i, coverage[i]);
    }
    shader.setFloat(blurFloats + 5, screenScale);
    _paint.shader = shader;
    canvas.drawRect(rect, _paint);
    return true;
  }

  static double _hypot(double a, double b) => math.sqrt(a * a + b * b);

  static double _erf7(double value) {
    var x = value * 2 / math.sqrt(math.pi);
    final xx = x * x;
    x = x + (0.24295 + (0.03395 + 0.0104 * xx) * xx) * (x * xx);
    return x / math.sqrt(1 + x * x);
  }
}
