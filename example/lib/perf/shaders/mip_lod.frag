#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uLod;
uniform sampler2D uInput;
out vec4 fragColor;

// Interoperability probe; its synthetic input does not capture a backdrop.
void main() {
#ifdef SKIA_GRAPHICS_BACKEND
  // Explicit GPU mip sampling is a native-only probe. SkSL rejects textureLod.
  fragColor = vec4(0.0);
#else
  fragColor = textureLod(uInput, FlutterFragCoord().xy / uSize, uLod);
#endif
}
