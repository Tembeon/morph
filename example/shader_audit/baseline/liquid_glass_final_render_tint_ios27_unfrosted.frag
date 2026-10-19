// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core
#define WITH_SHAPE_TINT
#define WITH_IOS27_MODELS

// The liquid glass final pass. hook/build.dart compiles it once per
// LiquidShaderVariant (lib/src/glass/renderer/liquid_shader_variants.dart),
// defining WITH_<switch> for each switch the variant turns on: impellerc's
// --define takes a name without a value, so its presence sets the switch
// to 1 here.
#ifdef WITH_SHAPE_APPEARANCE
#define SHAPE_APPEARANCE 1
#else
#define SHAPE_APPEARANCE 0
#endif
#ifdef WITH_SHAPE_TINT
#define SHAPE_TINT 1
#else
#define SHAPE_TINT 0
#endif
#ifdef WITH_DIRECT_MODEL
#define DIRECT_MODEL 1
#else
#define DIRECT_MODEL 0
#endif
#ifdef WITH_IOS27_MODELS
#define IOS27_MODELS 1
#else
#define IOS27_MODELS 0
#endif
#ifdef WITH_ANALYTIC_GEOMETRY
#define ANALYTIC_GEOMETRY 1
#else
#define ANALYTIC_GEOMETRY 0
#endif
#ifdef WITH_ANALYTIC_FUSED
#define ANALYTIC_FUSED 1
#else
#define ANALYTIC_FUSED 0
#endif
#ifdef WITH_FROST
#define FROST 1
#else
#define FROST 0
#endif
#if !DIRECT_MODEL && !IOS27_MODELS
#error "no color model: compile through hook/build.dart"
#endif

// The Skia stage is an empty stub: SkSL cannot express the core's texture
// sampling, and only the host tests' flutter_tester (Skia) loads it; no
// Skia renderer draws liquid glass.
#ifdef SKIA_GRAPHICS_BACKEND
#include <flutter/runtime_effect.glsl>
out vec4 fragColor;
void main() {
    fragColor = vec4(0.0);
}
#else
#include "liquid_glass_final_render_core.glsl"
#endif
