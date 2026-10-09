// Reuses Morph optics; the source is explicitly owned by the benchmark.
#version 460 core
#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 0
#define DIRECT_MODEL 0
#define IOS27_MODELS 1
#define OWNED_BACKGROUND 1
#ifdef SKIA_GRAPHICS_BACKEND
#include <flutter/runtime_effect.glsl>
out vec4 fragColor;
void main() { fragColor = vec4(0.0); }
#else
#include "../../../../lib/src/glass/renderer/shaders/gpu/displacement_encoding.glsl"
#include "../../../../lib/src/glass/renderer/shaders/render.glsl"
#include "../../../../lib/src/glass/renderer/shaders/liquid_glass_final_render_core.glsl"
#endif
