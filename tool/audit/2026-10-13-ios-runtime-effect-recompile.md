# iOS: analytic final shaders recompiled on every frame (2026-10-13)

## Symptom

iPhone 16 Pro, iOS 27.0.1, Impeller Metal, profile gallery, liquid tier:
opening and closing the Navigation and Menu pages ran raster p95 ~58 ms,
worst ~95 ms, ~38 frames over budget per open+back pair, on every open.
`MORPH_ANALYTIC_GEOMETRY=false` made it 2.6 ms. Pixel 6a (Vulkan) was
fine. Each slow frame was `Canvas::saveLayer` blocked in
`RuntimeEffectContents::RegisterShader` on its `std::future`, i.e. in
`ShaderLibraryMTL::RegisterFunction` -> `newLibraryWithSource`.

## Root cause

Not a new RuntimeStage per frame and not a dirty-flag ping-pong: the MSL of
six of the eight analytic final shaders does not compile on Metal.

impellerc (SPIRV-Cross) gives every non-sampler uniform declaration its own
`[[buffer(N)]]`, N = the declaration's ordinal over all declared uniforms
(unused ones keep their number and leave a hole). Metal has buffer slots
0 to 30. The core declares 24 uniforms, the analytic include 7 to 9 more:

| variant | declarations | highest slot | Metal |
|---|---|---|---|
| analytic, analytic_ios27 | 31 | 30 | compiles |
| analytic_tint(_ios27) | 32 | 31 | `'buffer' attribute parameter is out of bounds: must be between 0 and 30` |
| analytic_fused(_ios27) | 32 | 31 | same |
| analytic_fused_tint(_ios27) | 33 | 32 | same |

Reproduced off-device: the MSL extracted from the built `.frag` bundles
fails `MTLDevice.makeLibrary(source:)` with exactly that error, the other
final shaders compile.

Impeller does not remember the failure. `RuntimeEffectContents::
RegisterShader` looks the function up, finds none (the registration
failed), and calls `ShaderLibrary::RegisterFunction` again, waiting
synchronously for `newLibraryWithSource`, which fails again after the full
compile (55-90 ms on the A18 Pro, ~150 ms on an M-series Mac). That repeats
for every draw of the shader on every frame, and the draw itself is
dropped (`RegisterShader` returns false), so those glass shapes were also
missing on iOS while analytic. The only trace is a validation log line per
frame ("Could not register dynamic stage library ...", "Failed to build
runtime effect"). Vulkan puts all uniforms in one UBO, so Android never
hit the limit.

Why page open: the opening page brings tinted and fused glass (menu
sources, bar groups), and `MORPH_ANALYTIC_MODE=changes` shades analytic
exactly while geometry moves. `always` was as slow because the same
shaders were in use. A stubbed `analyticGeometry()` still failed because
the declarations, not the math, overflow.

## Fix in morph (2e4687b)

`analytic_geometry.glsl` declares fewer uniforms with the same float
layout: `uAnalyticOptics` and `uAnalyticRanges` are macros onto
`uniform vec4 uAnalyticHeader[2]`, and the cull factors are the tail of
`uShapeBounds[MAX_SHAPES * 5 / 4]` (`shapeCull(i)`). Dart float indices
and the Vulkan std140 layout do not move. Highest slot is now 28 to 30.
`test/analytic_geometry_test.dart` counts each variant's declarations
against the 31 slots. The fused tint variants sit at 30: the next uniform
there needs another merge (for example `uBlurFade` + `uSoften` into a
vec2 in the core).

iPhone 16 Pro page-open (3 runs, profile, liquid, analytic default
`changes`): raster p95 2.73 ms (runs 2.73 / 3.19 / 2.72), worst 8.9 ms,
1 frame over budget, against 58.5 ms / 99.8 ms / 38 before and 2.6 ms
with analytic geometry off.

## Engine issues to file upstream (flutter/flutter, engine a804b26)

1. A runtime effect whose registration fails is retried on every draw.
   `impeller/entity/contents/runtime_effect_contents.cc`
   `RegisterShader`: when `RegisterFunction` reports failure, nothing is
   recorded on the `RuntimeStage`, so the next `Render` sees `!function`
   and recompiles, synchronously on the raster thread. With Metal that is
   a full `newLibraryWithSource` per draw per frame (tens of ms). Expected:
   remember the failure per stage (or per scoped name in the shader
   library) and fail fast, logging once.
2. impellerc emits MSL that cannot compile on any Apple GPU without
   failing the build. A fragment program with more than 31 non-sampler
   uniform declarations (counting unused ones, whose indices are kept)
   gets `[[buffer(31)]]` or higher. The same `.frag` compiles for Vulkan,
   GLES and SkSL. Expected: an impellerc error at build time (or packing
   loose uniforms into one argument buffer / struct on Metal, as Vulkan
   does).
3. Minor, seen while reading: `ShaderLibraryMTL::UnregisterFunction`
   fallback loop `for (size_t i = [libraries_ count] - 1; i >= 0; i--)`
   never terminates by its condition (size_t), and underflows when the
   list is empty.

Repro for 1 and 2: a `.frag` with 32 `uniform float uN;` used in `main`,
loaded with `FragmentProgram.fromAsset` and drawn each frame on iOS or
macOS Impeller: raster time grows by the MSL compile time per frame and
nothing is drawn.
