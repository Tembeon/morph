#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uMix;
uniform sampler2D uLower;
uniform sampler2D uUpper;
out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  fragColor = mix(texture(uLower, uv), texture(uUpper, uv), uMix);
}
