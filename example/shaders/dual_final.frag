#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 origin;
uniform vec2 extent;
uniform vec4 uvRect;
uniform vec2 halfOffset;
uniform sampler2D sourceTexture;
out vec4 fragColor;
void main() {
  vec2 uv = uvRect.xy + (FlutterFragCoord().xy - origin) / extent * uvRect.zw;
  vec2 h = halfOffset;
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
