// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// One appearance for the layer, the direct color model,
// a fused body of merged boxes evaluated in this pass instead of read from
// a geometry matte.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 0
#define DIRECT_MODEL 1
#define IOS27_MODELS 0
#define ANALYTIC_GEOMETRY 1
#define ANALYTIC_FUSED 1

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
