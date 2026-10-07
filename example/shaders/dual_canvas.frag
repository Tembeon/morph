#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 extent;
uniform vec4 uvRect;
uniform vec2 halfOffset;
uniform float kind;
uniform sampler2D sourceTexture;
out vec4 fragColor;
void main() {
  vec2 uv = uvRect.xy + FlutterFragCoord().xy / extent * uvRect.zw;
  vec2 h = halfOffset;
  if (kind < 0.5) {
    vec4 sum = texture(sourceTexture, uv) * 4.0;
    sum += texture(sourceTexture, uv + h);
    sum += texture(sourceTexture, uv - h);
    sum += texture(sourceTexture, uv + vec2(h.x, -h.y));
    sum += texture(sourceTexture, uv + vec2(-h.x, h.y));
    fragColor = sum * 0.125;
    return;
  }
  vec4 sum = texture(sourceTexture, uv + vec2(-2.0 * h.x, 0.0));
  sum += texture(sourceTexture, uv + vec2(-h.x, h.y)) * 2.0;
  sum += texture(sourceTexture, uv + vec2(0.0, 2.0 * h.y));
  sum += texture(sourceTexture, uv + h) * 2.0;
  sum += texture(sourceTexture, uv + vec2(2.0 * h.x, 0.0));
  sum += texture(sourceTexture, uv + vec2(h.x, -h.y)) * 2.0;
  sum += texture(sourceTexture, uv + vec2(0.0, -2.0 * h.y));
  sum += texture(sourceTexture, uv - h) * 2.0;
  fragColor = sum / 12.0;
}
