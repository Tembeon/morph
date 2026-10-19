import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The touch glow the final pass applies to the glass of one lit shape of
/// a layer, in the layer's coordinates.
///
/// A wash that adds [wash] to every color channel and a spot that
/// multiplies the channels by `1 + gain * exp(-0.5 * (r / radius)^2)` at
/// `r` from [center], clamped at white, both inside [clip], over everything
/// the glass shows and under the content painted after the layer
/// (shaders/glass_glow.glsl). A layer whose shapes mix appearances beyond
/// tint draws no glow (its final shader variant leaves the glow out to
/// stay within its registers).
@immutable
class LiquidGlassGlow {
  /// Creates a glow.
  const LiquidGlassGlow({
    required this.clip,
    required this.center,
    required this.radius,
    required this.gain,
    required this.wash,
  });

  /// The lit shape's outline: the glow stays inside it. Its top-left
  /// corner radius rounds every corner.
  final RRect clip;

  /// The center of the spot.
  final Offset center;

  /// The standard deviation of the spot's falloff.
  final double radius;

  /// How much the spot brightens its center: there the channels are
  /// multiplied by `1 + gain`.
  final double gain;

  /// How much every color channel rises inside [clip], in `[0, 1]` units.
  final double wash;

  /// How many floats [uniformsOf] writes: three vec4 after uSolidBackdrop.
  static const int floatCount = 12;

  /// The floats of uGlowSpot, uGlowBox and uGlowShape for [glow] in a
  /// layer whose matte has [devicePixelRatio] device pixels per unit; all
  /// zero, which draws no glow, for none.
  ///
  /// The spot's radius goes in as its falloff `log2(e) / (2 sigma^2)` per
  /// squared device pixel, so the shader's Gaussian is one exp2 with no
  /// divide.
  static List<double> uniformsOf(
    LiquidGlassGlow? glow,
    double devicePixelRatio,
  ) {
    if (glow == null || (glow.wash <= 0 && glow.gain <= 0)) {
      return List<double>.filled(floatCount, 0);
    }
    final scale = devicePixelRatio;
    final clip = glow.clip;
    final spot = glow.radius > 0 && glow.gain > 0;
    final sigma = glow.radius * scale;
    final corner = math.min(
      math.max(clip.tlRadiusX, 0.0),
      clip.shortestSide / 2,
    );
    return [
      glow.center.dx * scale,
      glow.center.dy * scale,
      spot ? math.log2e / (2 * sigma * sigma) : 0,
      spot ? glow.gain : 0,
      clip.center.dx * scale,
      clip.center.dy * scale,
      clip.width / 2 * scale,
      clip.height / 2 * scale,
      corner * scale,
      math.max(glow.wash, 0.0),
      0,
      0,
    ];
  }

  /// The color the final pass gives the glass color [rgb] at [point], in
  /// matte device pixels, under the glow [uniforms] (from [uniformsOf]):
  /// the CPU reference of shaders/glass_glow.glsl and of the branch that
  /// skips it.
  static (double, double, double) shade(
    List<double> uniforms,
    Offset point,
    (double, double, double) rgb,
  ) {
    final gain = uniforms[3];
    final wash = uniforms[9];
    if (gain <= 0 && wash <= 0) return rgb;
    final qx = (point.dx - uniforms[4]).abs() - uniforms[6] + uniforms[8];
    final qy = (point.dy - uniforms[5]).abs() - uniforms[7] + uniforms[8];
    final ox = math.max(qx, 0.0);
    final oy = math.max(qy, 0.0);
    final d =
        math.sqrt(ox * ox + oy * oy) +
        math.min(math.max(qx, qy), 0.0) -
        uniforms[8];
    final cover = (0.5 - d).clamp(0.0, 1.0);
    final rx = point.dx - uniforms[0];
    final ry = point.dy - uniforms[1];
    final factor =
        1 + gain * math.exp(-uniforms[2] * (rx * rx + ry * ry) * math.ln2);
    double channel(double c) {
      final lit = math.min((c + wash) * factor, 1.0);
      return c + (lit - c) * cover;
    }

    return (channel(rgb.$1), channel(rgb.$2), channel(rgb.$3));
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassGlow &&
      other.clip == clip &&
      other.center == center &&
      other.radius == radius &&
      other.gain == gain &&
      other.wash == wash;

  @override
  int get hashCode => Object.hash(clip, center, radius, gain, wash);
}
