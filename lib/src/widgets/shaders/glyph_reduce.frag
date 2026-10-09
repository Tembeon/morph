// Draws one level of a glyph raster's pyramid: each texel the mean of the
// [uFactor] x [uFactor] raster texels it covers (MorphGlyphBlur in
// glyph_scale.dart). Every level of every raster draws in one pass, with
// no mipmaps: each bilinear tap reads the exact mean of a 2 x 2 block.
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

// The raster's size in texels, then the reduction factor (a power of two
// up to 32).
uniform vec3 uRaster;
// The level's origin in the pyramid, then the raster's origin it maps
// from, both in texels.
uniform vec4 uMap;

uniform sampler2D uSource;

out vec4 fragColor;

void main() {
  vec2 at = (FlutterFragCoord().xy - uMap.xy) * uRaster.z + uMap.zw;
  float factor = uRaster.z;
  // The block's corner, then one tap at the shared corner of each 2 x 2
  // block in it; a level of factor 1 reads its own texel's center.
  vec2 corner = at - 0.5 * factor;
  float taps = max(0.5 * factor, 1.0);
  vec2 step = factor < 1.5 ? vec2(0.0) : vec2(1.0);
  vec4 sum = vec4(0.0);
  for (int y = 0; y < 16; y++) {
    if (float(y) < taps) {
      for (int x = 0; x < 16; x++) {
        if (float(x) < taps) {
          vec2 tap = factor < 1.5
              ? at
              : corner + vec2(2.0 * float(x), 2.0 * float(y)) + step;
          sum += texture(uSource, tap / uRaster.xy);
        }
      }
    }
  }
  fragColor = sum / (taps * taps);
}
