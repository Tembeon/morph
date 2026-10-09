// Draws a raster of glyphs blurred by a Gaussian and faded, in one pass
// without an offscreen layer (MorphGlyphBlur in glyph_scale.dart).
//
// The value at a point is the Gaussian-weighted sum of the texel centers
// around it, normalized: the continuous Gaussian convolved with the
// texels. The kernel is separable, so each bilinear tap reads a 2 x 2
// block of texels with their exact weights for this point: up to 7 x 7
// taps cover the 14 x 14 texels around it, enough for a sigma of 2
// texels; smaller sigmas read only the central 5 x 5 or 3 x 3. A weight
// at offset i from the base texel is exp(-i^2 / 2s^2) (uniform, given)
// times q^i with q = exp(f / s^2) for the point's fraction f past the
// base (the factor common to all weights cancels in the normalization).
// Each raster sits in a slot of a shared atlas with a clear border wider
// than the taps reach, so outside the raster reads as clear, like a decal
// blur.
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

// Raster texels per local unit, then the texel of the local origin.
uniform vec3 uMap;
// The atlas's size in texels.
uniform vec2 uRasterSize;
// 1 / s^2 for the kernel's sigma s in texels, the opacity, and the pairs
// of taps per axis: 3, 5 or 7.
uniform vec3 uKernel;
// exp(-i^2 / 2s^2) for i = 0..7.
uniform vec4 uGaussA;
uniform vec4 uGaussB;

uniform sampler2D uRaster;

out vec4 fragColor;

// The bilinear tap of the texel pair with weights [a] and [b] starting
// [i] texels from the base: its offset and total weight.
vec2 pair(float i, float a, float b) {
  float w = a + b;
  return vec2(i + b / max(w, 1e-30), w);
}

vec4 tap(vec2 base, float ox, float oy) {
  return texture(uRaster, (base + vec2(ox, oy)) / uRasterSize);
}

// The pairs of one axis at fraction [f]: offsets and weights of the pairs
// starting at -6, -4, -2 (in a) and 0, 2, 4, 6 (in b).
void pairs(float f, out vec3 oa, out vec3 wa, out vec4 ob, out vec4 wb) {
  float q = exp(f * uKernel.x);
  float r = 1.0 / q;
  float r2 = r * r;
  float r4 = r2 * r2;
  float q2 = q * q;
  float q4 = q2 * q2;
  vec2 p6 = pair(-6.0, uGaussB.z * r4 * r2, uGaussB.y * r4 * r);
  vec2 p4 = pair(-4.0, uGaussB.x * r4, uGaussA.w * r2 * r);
  vec2 p2 = pair(-2.0, uGaussA.z * r2, uGaussA.y * r);
  vec2 n0 = pair(0.0, uGaussA.x, uGaussA.y * q);
  vec2 n2 = pair(2.0, uGaussA.z * q2, uGaussA.w * q2 * q);
  vec2 n4 = pair(4.0, uGaussB.x * q4, uGaussB.y * q4 * q);
  vec2 n6 = pair(6.0, uGaussB.z * q4 * q2, uGaussB.w * q4 * q2 * q);
  oa = vec3(p6.x, p4.x, p2.x);
  wa = vec3(p6.y, p4.y, p2.y);
  ob = vec4(n0.x, n2.x, n4.x, n6.x);
  wb = vec4(n0.y, n2.y, n4.y, n6.y);
}

// One row: the taps at vertical offset [oy], weighted along x.
vec4 row(vec2 base, float oy, vec3 oa, vec3 wa, vec4 ob, vec4 wb) {
  vec4 sum = tap(base, oa.z, oy) * wa.z + tap(base, ob.x, oy) * wb.x +
      tap(base, ob.y, oy) * wb.y;
  if (uKernel.z > 3.5) {
    sum += tap(base, oa.y, oy) * wa.y + tap(base, ob.z, oy) * wb.z;
  }
  if (uKernel.z > 5.5) {
    sum += tap(base, oa.x, oy) * wa.x + tap(base, ob.w, oy) * wb.w;
  }
  return sum;
}

void main() {
  vec2 texel = FlutterFragCoord().xy * uMap.x + uMap.yz;
  vec2 base = floor(texel - 0.5) + 0.5;
  vec2 f = texel - base;
  vec3 xoa;
  vec3 xwa;
  vec4 xob;
  vec4 xwb;
  pairs(f.x, xoa, xwa, xob, xwb);
  vec3 yoa;
  vec3 ywa;
  vec4 yob;
  vec4 ywb;
  pairs(f.y, yoa, ywa, yob, ywb);
  vec4 sum = row(base, yoa.z, xoa, xwa, xob, xwb) * ywa.z +
      row(base, yob.x, xoa, xwa, xob, xwb) * ywb.x +
      row(base, yob.y, xoa, xwa, xob, xwb) * ywb.y;
  float wx = xwa.z + xwb.x + xwb.y;
  float wy = ywa.z + ywb.x + ywb.y;
  if (uKernel.z > 3.5) {
    sum += row(base, yoa.y, xoa, xwa, xob, xwb) * ywa.y +
        row(base, yob.z, xoa, xwa, xob, xwb) * ywb.z;
    wx += xwa.y + xwb.z;
    wy += ywa.y + ywb.z;
  }
  if (uKernel.z > 5.5) {
    sum += row(base, yoa.x, xoa, xwa, xob, xwb) * ywa.x +
        row(base, yob.w, xoa, xwa, xob, xwb) * ywb.w;
    wx += xwa.x + xwb.w;
    wy += ywa.x + ywb.w;
  }
  fragColor = sum * (uKernel.y / (wx * wy));
}
