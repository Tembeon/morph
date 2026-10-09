// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// Shapes that differ only by tint, the direct color model,
// the shapes evaluated in this pass instead of read from a geometry matte.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 1
#define DIRECT_MODEL 1
#define IOS27_MODELS 0
#define ANALYTIC_GEOMETRY 1

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
