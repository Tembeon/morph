// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// The shared core snapshots coordinate mappings and output opacity.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 1

// The web (SkSL) cannot compile the core's texture sampling; the web never
// draws liquid glass, so there the shader is an empty stub.
#ifdef SKIA_GRAPHICS_BACKEND
#include <flutter/runtime_effect.glsl>
out vec4 fragColor;
void main() {
    fragColor = vec4(0.0);
}
#else
#include "liquid_glass_final_render_core.glsl"
#endif
