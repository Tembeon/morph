# Flutter / Impeller / Flutter GPU / Dart VM levers for weak devices - 2026-10-05

Read-only research, no code changed. Question (owner): which mechanisms of
Flutter 3.47.2 (framework d3b14c8769, engine a804b26164, Dart 3.13.2) can
morph exploit for maximum performance on WEAK devices (old iPhones,
mid/low Android on Impeller Vulkan or the GLES fallback) while keeping the
native look. Everything counts: UI thread, raster/GPU, first-use jank,
idle battery.

This file does not repeat the per-file waste map of
perf-research-2026-10-05.md (G1-G14, C1-C23, M1-M24, X1-X8), Fable's
perf-opinion (A1-A11) or the two unified-canvas opinions. Items from them
that are DONE by now (repaint boundary per control 003e112, spinner doze
027dbe4, menu sleeps under a resting finger 79f6ccc, plain unions exact
f9293cd, clipped glass shadows b0f79b1, lazy uniforms / field upload reuse /
outline translation memo in the identical batch, governor ladder
flat + liquid 6f8a325, chrome backdrop key per screen) are taken as the
baseline. Here: ENGINE MECHANISMS, verified in source.

Sources: the framework and pub packages of the installed SDK
(`/opt/homebrew/Caskroom/flutter/3.19.1/flutter`, version file says
3.47.2; paths below abbreviated `SDK/`), a shallow checkout of
flutter/flutter at d3b14c8769 in /tmp/flutter-src (engine paths below are
relative to `engine/src/flutter/`), the SDK's own `impellerc`
(`SDK/bin/cache/artifacts/engine/darwin-x64/impellerc`) run on probe
shaders, and `strings` of the iOS release `gen_snapshot_arm64`. Line
numbers are the checkout's. Codex (gpt-6-astra, high) ran independently
on the same question; its list is merged in section 4
(tool/audit/flutter-tricks-astra.md holds its full text).

Tags as in perf-research: IDENTICAL (same pixels and motion; a diff is a
bug) / VERIFY (plausibly invisible, shot diff on the phone first) /
CHANGES LOOK (a deliberate trade, only for a weak-device tier).
Gain classes on a weak device: H = removes a full-screen pass or > 0.5 ms
of a frame / a first-use hitch of tens of ms; M = 0.1-0.5 ms or a bounded
pass; L = small. Effort S / M / L.

## 0. Five facts that set the cost model on weak devices

F1. NO PARTIAL REPAINT ON ANY MOBILE TARGET IN PRACTICE.
- Android: Impeller Vulkan never sets `supports_partial_repaint`
  (shell/gpu/gpu_surface_vulkan_impeller.cc:277 builds
  `FramebufferInfo{.supports_readback = true}` only); Impeller GLES says
  false explicitly (shell/platform/android/android_surface_gl_impeller.cc:212-216).
- iOS: the Metal Impeller surface advertises it (shell/gpu/
  gpu_surface_metal_impeller.mm:209-218, opt-out key `FLTDisablePartialRepaint`
  :34-39), BUT the rasterizer forces a full repaint whenever an external
  view embedder exists and there is no merged thread merger
  (shell/common/rasterizer.cc:785-797: `force_full_repaint =
  external_view_embedder_ && (!raster_thread_merger_ ||
  raster_thread_merger_->IsMerged())`, and with it the previous layer tree
  is never set, so FrameDamage marks the whole frame dirty,
  flow/compositor_context.cc:27-31). The shell always installs the iOS
  embedder (shell/common/shell.cc:878-879,
  shell/platform/darwin/ios/platform_view_ios.mm:131-133) and iOS never
  creates a merger (`SupportsDynamicThreadMerging` returns false,
  shell/platform/darwin/ios/ios_external_view_embedder.mm:100-102;
  rasterizer.cc:93-102). So every iOS frame repaints the whole surface.
- Even where it ran, Impeller only takes a damage rect under 70 percent of
  an axis (flow/compositor_context.cc:199-227, kImpellerRepaintRatio 0.7),
  and a BackdropFilterLayer adds its whole cull rect plus its filter's
  input region as readback damage (flow/layers/backdrop_filter_layer.cc:
  25-36) and dirties itself whenever its filter object is not equal
  (:20-22) - every new `ImageFilter.shader` is.
- Consequence: do not design anything around damage regions. Every frame
  that anything renders, every visible glass layer is re-shaded. Idle
  discipline (render no frame) is the only "cache".

F2. A BACKDROP FLIP IS A FULL-SCREEN OPERATION; THE FILTER IS CLIP-SIZED.
- `Canvas::FlipBackdrop` ends the current render pass and then draws the
  WHOLE previous texture into the new pass ("MSAA backdrop",
  impeller/display_list/canvas.cc:2415-2510; `size_rect` is the full
  input texture, :2495). On Metal the flip reads the resolve texture in
  place (impeller/entity/entity_pass_target.cc:32-38); Vulkan and GLES do
  not support read-from-resolve (impeller/renderer/backend/vulkan/
  capabilities_vk.cc:755-757, backend/gles/capabilities_gles.cc:282-284)
  and ping-pong a lazily allocated second full-screen MSAA target
  (entity_pass_target.cc:40-60). So on Android a flip is a full-screen
  resolve + a full-screen redraw at 4 B/px, on a wide-gamut iPhone at
  8 B/px (F5).
- The filter itself renders into a saveLayer subpass sized to the clip
  coverage (`GetLocalCoverageLimit` -> `ComputeSaveLayerCoverage` ->
  `subpass_size`, canvas.cc:1722-1790), an MSAA offscreen target with a
  stencil attachment (canvas.cc:140, 158-172).
- Shared keys skip the flip for later members (canvas.cc:1801-1846), which
  is why the backdrop-group work paid off. On weak bandwidth-bound GPUs
  (Mali, older Adreno, A12) the number of flips per frame is the dominant
  raster term; shader ALU is second.

F3. THE FROSTED CHAIN IS FIVE PASSES, AND THE BLUR IS ALREADY LOW-RES.
- Impeller's Gaussian downsamples by `CalculateScale` (impeller/entity/
  contents/filters/gaussian_blur_filter_contents.cc:751-775): no
  downsample at sigma <= 4 device px, else the nearest power of two of
  4 / sigma, floor 1/16. chromeFrost 14 pt at DPR 3 = 42 device px ->
  1/8; the small-lens frost 6 pt -> 1/4. Blur passes are cheap.
- `ImageFilter.compose(inner: blur, outer: shader)` hands the runtime
  effect a SCALED snapshot (the blur's output transform carries
  `1 / effective_scalar`, :969-973), and `ShouldRasterizeForRuntimeEffects`
  is true for any translate+scale transform (impeller/renderer/
  snapshot.h:51-57), so the runtime-effect filter re-rasterizes the
  blurred input into the full-resolution coverage first
  (runtime_effect_filter_contents.cc:70-126). Frosted liquid layer =
  downsample + blur Y + blur X + full-res re-rasterize + shader. The
  renderer's "about four command buffers" note
  (lib/src/glass/renderer/rendering/liquid_glass_layer.dart:602-604) is
  this chain.
- A SHARED group whose filters are all equal (dl_dispatcher.cc:1001-1017)
  renders the filter ONCE over the whole backdrop with no input hint
  (canvas.cc:1858-1868, `TODO(157110): compute minimum input hint`) and
  every member samples that snapshot. That is the frosted tier's body
  path (`_FrostedSurface` with `_frostKey`, lib/src/widgets/
  glass_renderer.dart:519, 535-560): N same-sigma frosted surfaces in one
  group = ONE full-screen 1/8-res blur, not N bounded ones. Never true
  for liquid layers (each `ImageFilter.shader` carries its own uniforms).

F4. NO RASTER CACHE UNDER IMPELLER.
`EnableRasterCache()` returns false on the Metal, Vulkan and GLES Impeller
surfaces (shell/gpu/gpu_surface_metal_impeller.mm:372-374,
gpu_surface_vulkan_impeller.cc:311-313, gpu_surface_gl_impeller.cc:170).
Retained EngineLayers (`addRetained`, SDK/packages/flutter/lib/src/
rendering/layer.dart:700-711) only save Dart-side scene building and
picture re-recording; the engine re-executes every display list and every
filter of every rendered frame.

F5. WIDE GAMUT IS ON BY DEFAULT ON iOS AND DOUBLES EVERY BYTE.
`FLTEnableWideGamut` defaults to YES on capable hardware
(shell/platform/darwin/ios/framework/Source/FlutterDartProject.mm:178-181);
the surface is `MTLPixelFormatBGRA10_XR` (64 bpp,
impeller/renderer/backend/metal/formats_mtl.h:50-51) and the context's
default color format follows it (backend/metal/context_mtl.mm:72-80), so
every flip, every saveLayer subpass and every filter intermediate is
8 B/px. This is an APP decision (Info.plist), not the package's - but it
is the single largest bandwidth knob on an iPhone.

## 1. The levers, one by one

### L1. Warm the pipelines that precache does not warm (first-use jank)

Available: yes. Gain: H once per install / per session on weak devices
(the passport already caught ~45 ms of one-time work in the first outline
case; pipeline compiles on Vulkan/GLES are of the same order). Fidelity:
IDENTICAL (nothing visible is drawn). Effort: S-M.

Evidence:
- Flutter GPU: `createRenderPipeline` only records the two shaders and
  the vertex layout (engine lib/gpu/render_pipeline.cc:24-52). The real
  pipeline is fetched at the first DRAW from the full PipelineDescriptor
  (attachment formats, sample count, blend, stencil), synchronously on the
  UI thread with `.Get()`; on GLES the UI thread even blocks on a task
  posted to the raster thread (lib/gpu/render_pass.cc:146-180, the
  comment says "could hang the UI thread long enough to miss a frame").
- morph's precache builds the GPU renderer and disposes it without a
  draw (lib/src/widgets/glass_liquid_native.dart:20-35), so the geometry,
  field, material-gradient and tint-gradient pipelines
  (lib/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.
  dart:1065-1100) compile on the first glass frame, on the UI thread.
- Runtime effects: `FragmentProgram.fromAsset` caches the runtime stage
  and bootstraps ONE pipeline with default `ContentContextOptions`
  (lib/ui/painting/fragment_program.cc:215 ->
  shell/common/snapshot_controller_impeller.cc:245-257 ->
  impeller/entity/contents/runtime_effect_contents.cc:149-159: default
  color format, default options = single-sampled, no stencil). The glass
  filter renders into an MSAA subpass with a stencil attachment (F2), a
  different variant, compiled on the raster thread at first use. The
  Gaussian downsample/blur and texture pipelines for the frosted chain are
  engine built-ins created on demand the same way.
- Vulkan persists its VkPipelineCache to disk every 50 frames when dirty
  (impeller/renderer/backend/vulkan/pipeline_library_vk.cc:280-297), so on
  Android the hitch is mostly first launch after install/update; Metal
  compiles runtime-stage MSL source at load.

What to do (glass_liquid_native.dart `_capability.load`, renderer
`FlutterGpuGeometryRenderer`):
1. Flutter GPU: after creating the shared resources, encode ONE 1 x 1
   draw per pipeline into a texture of the exact format, sample count and
   blend state the real passes use (matte RGBA8 devicePrivate; field
   pipeline with a 2 x 2 RGBA32F field; both material pipelines), submit,
   keep the textures in the ring. Same descriptors -> same cached
   pipelines (lib/gpu/render_pass.cc:155 `HasPipeline`).
2. Runtime effects + blur: build a throwaway `SceneBuilder` scene of a
   4 x 4 clip with `pushBackdropFilter` for each final shader (plain and
   `compose(blur, shader)` at the chrome and lens sigmas) and
   `scene.toImage(4, 4)`. `DisplayListToTexture` renders through the same
   Canvas, so a backdrop filter inside it lands in a `CreateRenderTarget`
   subpass with the same MSAA + stencil config (impeller/display_list/
   dl_dispatcher.cc:1228-1260; canvas.cc:158-172). VERIFY on the device:
   a timeline of the first glass frame must show no pipeline creation
   (and the second launch on Android none at all).
3. Run it from `morphPrecacheLiquidGlass()` (the app calls it behind its
   splash), not from the first build.

### L2. Half precision in the final shader, per backend (raster ALU)

Available: partial - Metal yes, Vulkan through mediump, GLES no.
Gain: M-H on A12-A14 iPhones (the 938-line final shader runs over every
glass pixel every frame; half doubles ALU throughput and halves register
pressure on Apple GPUs), M on Vulkan Mali/Adreno, none on GLES.
Fidelity: VERIFY (colour math in half is ~1/2048 at 1.0, under one step
of an 8-bit or 10-bit XR surface; coordinates must stay float). Effort: M.

Evidence (probe shaders compiled with the SDK's impellerc, outputs read
from the .iplr):
- `mediump` locals in a runtime-effect .frag compile to `float` in MSL
  and to explicit `highp` in the GLES 300 es output; the SPIR-V for the
  Metal and GLES runtime stages carries ZERO RelaxedPrecision decorations
  (glslang runs those stages in the OpenGL 4.5 environment,
  impeller/compiler/compiler.cc:477-495, where precision qualifiers have
  no semantics). The Vulkan runtime stage (Vulkan environment, relaxed
  rules, :465-475) DOES keep RelaxedPrecision (1 decoration for 1
  mediump local in the probe) - the driver may run it in FP16.
- Explicit `float16_t` / `f16vec4` with
  `GL_EXT_shader_explicit_arithmetic_types_float16` compile to MSL
  `half` / `half4` on the Metal runtime stage. The GLES output then
  demands `GL_AMD_gpu_shader_half_float` or `GL_NV_gpu_shader5` and
  otherwise `#error No extension available for FP16.` - i.e. it breaks on
  practically every Android GLES driver. The SkSL target rejects it (the
  existing `SKIA_GRAPHICS_BACKEND` stub in the three .frag files already
  keeps the web out).
- The stages are distinguishable by macro: `VULKAN` is predefined only
  for the Vulkan runtime stage (probe: a `#ifdef VULKAN` branch survived
  only there), `IMPELLER_TARGET_OPENGLES` only for the GLES stages
  (compiler.cc:487-494), neither for Metal.
- Today the core declares `precision highp float` globally on purpose
  (lib/src/glass/renderer/shaders/liquid_glass_final_render_core.glsl:
  7-10: mediump coordinate math shimmered on GLES). Given the probe, that
  line is a no-op on Metal and GLES; only Vulkan would have honoured
  mediump.
- Flutter GPU shader bundles get `IMPELLER_TARGET_METAL_IOS` /
  `_VULKAN` / `_OPENGLES` defines (impeller/compiler/shader_bundle.cc:
  89-110), and Impeller's own `impeller/types.glsl` maps `f16vec4` to
  real half only on Metal iOS and to `vec4` elsewhere
  (impeller/compiler/shader_lib/impeller/types.glsl) - the ready-made
  pattern for the geometry/material passes.

What to do: one header in the core, e.g.
`#if defined(VULKAN) -> #define mfloat mediump float` (and vec types),
`#elif !defined(IMPELLER_TARGET_OPENGLES) -> float16_t / f16vecN`,
`#else -> float`; convert ONLY the colour/lighting section (tint, mixed
appearance, highlight, contour, saturation/gamma, the final composite -
roughly liquid_glass_final_render_core.glsl:544-680 and the lighting after
:790) and keep every UV, displacement, distance and the affine mapping in
float. Gate: glass_audit shots within the resting noise floor on the iPhone
16 Pro AND one A12-A14 device; a Mali Vulkan device for the mediump path.
Do not touch the geometry/field passes (12-bit matte codes and SDF
distances need float; they also run only when shapes change).

### L3. Pick the starting tier from the device class, not only from timings

Available: yes, without a plugin. Gain: H for the first seconds on a weak
device (the governor otherwise spends its first 30-frame windows, plus a
first-use hitch, on a tier the device cannot hold; and it climbs back up
every 5-80 s, MorphGlassTierPolicy, lib/src/widgets/glass_tier.dart:23-90).
Fidelity: none (policy). Effort: S for the GPU probes, M for FFI.

Probes verified in 3.47.2:
- Impeller at all: `ImageFilter.isShaderFilterSupported`
  (SDK/bin/cache/pkg/sky_engine/lib/ui/painting.dart:4488, `=
  _impellerEnabled`).
- Android GLES fallback (Vulkan absent or blocklisted - the device class
  Impeller itself distrusts, shell/platform/android/
  android_context_dynamic_impeller.cc:81-110, impeller/renderer/backend/
  vulkan/driver_info_vk.cc:377-405): Flutter GPU's
  `gpuContext.doesSupportFramebufferRenderMipmap` is false only on GLES
  (impeller/renderer/backend/gles/capabilities_gles.cc:227; exposed by
  lib/gpu/context.cc:143-147). Android + false => GLES => start flat.
- Apple GPU generation: `gpuContext.supportsTextureCompression(
  TextureCompressionFamily.astcHdr)` is true exactly on
  `MTLGPUFamilyApple6` = A13 and later (impeller/renderer/backend/metal/
  context_mtl.mm:66-69). False on iOS => A12 or older (iPhone XS/XR and
  before): start flat or liquid-without-dispersion (L9).
- Tiler with implicit MSAA resolve (EXT_multisampled_render_to_single_
  sampled, typical Mali/Adreno): `doesSupportOffscreenMSAA` reports
  "normal" MSAA only (lib/gpu/context.cc:21-25).
- Refresh class: `display.refreshRate` 60 on a non-ProMotion phone (but
  see L6: it reads 120 on a ProMotion phone even when the app is held at
  60).
- Unusual but legal: `dart:ffi` without a plugin - `sysctlbyname
  ("hw.machine")` on iOS (model id, e.g. iPhone13,2) and
  `__system_property_get("ro.soc.model" / "ro.hardware.vulkan")` from
  libc on Android give a model table key. Not verified on device here.
Where: an optional `MorphGlassTierPolicy.initialCeiling` (or a pure
`morphDeviceGlassClass()` the app feeds into `MorphAdaptiveGlass.tier`),
glass_tier.dart. Keep the governor as the safety net.

### L4. Consumer configuration that the package should document and check

Available: yes. Gain: H (each item). Fidelity: none / app decision.
Effort: S (docs + a debug-mode check).
- `FLTEnableFlutterGPU` (example/ios/Runner/Info.plist:27) and the
  Android manifest equivalent: without Flutter GPU the ceiling is frosted
  (glass-renderer.md "Adaptive policy"), and frosted costs MORE raster
  than liquid on the control scenes. A debug-mode warning when
  `morphLiquidGlassUnavailableReason` says the GPU context is missing.
- `CADisableMinimumFrameDurationOnPhone` (DisplayLinkManager.swift:
  26-40 in shell/platform/darwin/ios/framework/Source): without it a
  ProMotion iPhone presents at 60 (fine for battery, see L6 for the
  fidelity side).
- `FLTEnableWideGamut = false` (F5) halves flip, subpass and filter
  traffic on iPhones. The package cannot set it; a weak-device section in
  the README should name it with the measured delta (run the audit once
  with and without, phone lock protocol).

### L5. Tighter filter clips (subpass area)

Available: yes. Gain: M with many small glass controls on screen (each
filter's subpass is cleared, shaded and composited at clip size, F2).
Fidelity: IDENTICAL for unfrosted layers if the clip still contains the
material bounds; VERIFY for frosted layers. Effort: S.

The renderer snaps its filter clip OUT to 64-device-px buckets
(lib/src/glass/renderer/internal/snap_rect_to_pixels.dart:20-28, applied at
liquid_glass_layer.dart:1184-1188). For a 44 pt button at DPR 3 (132 px)
the clip can grow to 192-256 px per side: up to ~3.7x the shaded area.
The bucket buys reuse: Impeller's render target cache matches the exact
size (impeller/entity/render_target_cache.cc:70-82), so a clip that
changes per frame would allocate per frame. Try 16 or 32 px buckets and
measure raster p95 on the controls scene. Unfrosted layers read the whole
flipped backdrop as filter input (canvas.cc:1848-1850 wraps the full
texture; runtime_effect_filter_contents.cc:144-145 passes the full input
size), so the clip does not limit refraction reach; frosted layers
re-rasterize the blurred input INTO the coverage (F3), so their clip must
keep a margin of the maximum displacement - keep 64 there or add
`maxDisplacement` to the material bounds before bucketing.

### L6. Frame cadence: measure it, do not read it (fidelity on 60/90 Hz)

Available: partial. Gain: none for speed; fixes a fidelity hazard that
shows up exactly on the devices this file is about. Effort: S.
- iOS reports `UIScreen.maximumFramesPerSecond` as the display refresh
  rate whether or not ProMotion is unlocked (DisplayLinkManager.swift:
  55-77; the engine's own TODO says the code is incorrect).
- Android reports `Display.getRefreshRate()` (shell/platform/android/io/
  flutter/view/VsyncWaiter.java:37-74) and never requests a frame rate;
  90 Hz panels are common in the mid range.
- `MorphClock.motionFrameRate` (lib/src/widgets/clock.dart:116) is "60 when
  the display reports 60 Hz, 120 otherwise", so a 60 Hz-held ProMotion
  phone or a 90 Hz Android steps the flex sub-clock at the wrong rate
  (alpha 0.3 per RENDERED frame is measured). Choose the sub-clock rate
  from the observed frame interval (median of the last N ticker deltas
  or FrameTiming vsync starts), with 60 / 90 / 120 buckets.
- Battery lever for weak devices (app-level): cap at 60 Hz (iOS: no
  plist key; Android: the host Activity's preferred display mode). Halves
  GPU work during animation; correct only once the sub-clock follows the
  measured cadence.

### L7. Dart VM pragmas on the CPU fusion hot loops (UI thread)

Available: yes - `vm:prefer-inline`, `vm:unsafe:no-bounds-checks`,
`vm:align-loops`, `vm:unsafe:no-interrupts` are present in the iOS release
`gen_snapshot_arm64` (strings). None is used in lib/ (grep `pragma(`:
no hits). Gain: M while fusing (the outline traces cost 0.12-0.71 ms on
the iPhone 16 Pro, several times that on an A12 or a Cortex-A55 phone;
bounds checks and non-inlined calls in typed-array loops are a typical
5-20 percent). Fidelity: IDENTICAL (same arithmetic). Effort: S.
Targets: `morphBoxDistance` (lib/src/widgets/glass_outline.dart:179,
called per node), `_fuseContainer` (:772), the `_BlurredUnion` loops
(lib/src/widgets/menu_fusion.dart:222-400), the skin's `_FieldSampler`
(lib/src/liquid_field.dart:377). Safety: no-bounds-checks turns an index
bug into memory corruption; keep the fuzz/golden tests (liquid_fuzz_test,
liquid_geometry_golden_test, the outline goldens) green and measure in
the AOT release bench and the device outline timings
(`AUDIT_OUTLINES_ONLY`), since the JIT microbenchmark does not track the
device here (passport).

### L8. Composited layer properties without repaint (UI thread)

Available: yes. Gain: M UI on weak CPUs for press/scale/opacity channels.
Fidelity: VERIFY (hit testing, semantics). Effort: M-L.
`RenderObject.updateCompositedLayer` + `markNeedsCompositedLayerUpdate`
(SDK/packages/flutter/lib/src/rendering/object.dart:3107-3131, 3398-3420)
lets a repaint boundary change its OWN layer without repainting children;
the layer must be an `OffsetLayer` subtype: `TransformLayer`
(layer.dart:2038), `OpacityLayer` (:2138), `ImageFilterLayer` (:1993) are;
`BackdropFilterLayer` is a plain ContainerLayer (:2325) and cannot be a
boundary's own layer (the renderer already mutates its filter in place
from compositor hooks, liquid_glass_layer.dart:1195-1198, 1255-1263 - the
right pattern). This is the concrete mechanism for perf-research X8 /
Codex B5: a `_MorphTransformChannel` render object (repaint boundary,
TransformLayer, listens to the motion and calls
markNeedsCompositedLayerUpdate) under glass_button.dart, bar_items.dart,
tab_bar.dart content; labels are never re-recorded per tick. It does NOT
make the glass itself cheaper under a scale: the renderer only reuses a
matte under uniform translation, a scale still re-renders the matte.

### L9. A "lite liquid" shader variant for weak tiers (raster ALU)

Available: yes (one more `.frag` with defines, like the three existing
variants). Gain: M-H on A12 / Mali-G5x class (dispersion = 3 backdrop
taps instead of 1, liquid_glass_final_render_core.glsl:760-790; the
softening taps :743-756). Fidelity: CHANGES LOOK - only as a policy tier
below liquid (the measured spec has no reference on hardware that cannot
run iOS 26; iOS 26 needs A13 or later - external fact, not verified
here). Effort: M (variant + tier + precache).
Note: dispersion already early-outs below a quarter-pixel
(:717-719), so the gain is only where lenses lift; measure before building.

### L10. Field texture format (small)

Available: yes (`PixelFormat.r16g16b16a16Float`, SDK/bin/cache/pkg/
flutter_gpu/lib/src/formats.dart:97-99; `supportsTextureFormat`,
context.dart:107; `CommandBuffer.copyBufferToTexture` for a devicePrivate
upload, command_buffer.dart:134-150). Today: hostVisible RGBA32F
(flutter_gpu_geometry_renderer_native.dart:1046-1050) with a manual 4-tap
bilinear (shaders/gpu/geometry_field_fragment.glsl:38-51) because RGBA32F
is not filterable on most mobile GPUs. RGBA16F is filterable everywhere:
1 hardware-filtered fetch instead of 4 and half the upload. Gain: L (the
field pass runs only for fused bodies while they change). Fidelity:
VERIFY (half distances: ~0.06 pt steps at 64-128 pt depth; filter weight
precision is 8 bits on some GPUs). Effort: S-M. Low priority.

## 2. Mechanisms checked and rejected (with the reason)

- Caching the glass output while the backdrop is unchanged: NOT
  FEASIBLE. No raster cache (F4), no damage tracking on mobile (F1), and
  Dart cannot know that what lies under a glass did not change (the
  passport already found pictures carry no drawn bounds). The only form
  that exists is not rendering frames: tickers sleep, idle frames = 0
  (test/fixtures/perf/counts.json). Keep the idle check in every phase.
- Rendering the glass at reduced resolution: NOT AVAILABLE for the final
  pass (a runtime effect re-rasterizes any scaled input to full
  resolution, F3; the filter output is the clip subpass at device res).
  The matte packs 12-bit displacement codes (shaders/gpu/
  displacement_encoding.glsl) that bilinear downsampling would corrupt;
  the material map is already 8x down. The blur is already 1/8.
- Partial repaint / damage regions: see F1. `FLTDisablePartialRepaint`
  changes nothing measurable on iOS.
- Moving the CPU SDF tracing to the GPU: Flutter GPU has render passes
  but no compute pass in the 3.47.2 package (SDK/bin/cache/pkg/
  flutter_gpu/lib/src has no compute API) and no synchronous readback
  (only `Texture.asImage`, texture.dart:248, then an async toByteData).
  The CPU outline Path is still needed for clips, shadows, the flat and
  frosted tiers and hit shapes, and field-only work is 10-16 percent of a
  fusion (passport) - a GPU field would save only that slice. Reject.
- Isolates for fusion: the result is needed in the same frame; message
  latency and copies exceed a 0.1-0.7 ms job. Reject (keep for one-off
  work only, e.g. nothing today).
- `alwaysNeedsAddToScene` on the transform-tracking layer
  (lib/src/glass/renderer/internal/transform_tracking_repaint_boundary_
  mixin.dart:137) forces the ancestor chain to re-add every frame
  (layer.dart:485-498). Composition callbacks cannot replace it: they fire
  after `addToScene` and must not mutate layers (layer.dart:200-227,
  1118-1123), and the mixin's comment explains why the effect must be
  updated before retained rendering is selected. Under F4 the re-add only
  costs Dart-side scene building. Keep; Fable A6 (skip the polls when no
  transform changed) is the real saving.
- Flutter GPU instancing / stencil / MSAA / render-pass reuse: all present
  (render_pass.dart:577-627, 648-690; texture.dart:49-50 sample count 1 or
  4), none useful today - every pass is one quad (Fable unified-canvas G),
  the passes are single-sampled with AA in the shader (keep it that way:
  MSAA 4x on a geometry pass would quadruple its bandwidth), and separate
  command buffers are deliberate (astra unified-canvas).
- `GpuContext.createImageSurface` / `GpuSurface` (new in 3.47.2,
  flutter_gpu/lib/src/surface.dart, context.dart:255): a presentable image
  surface; the renderer's own texture ring already does the same job with
  frame-counted reuse. No gain.
- Opacity at full alpha: free (no save layer at alpha 255; Impeller also
  distributes opacity into simple saveLayers, canvas.cc:1728-1734) -
  already in the passport.
- Glass shadows: the 3.47.2 Impeller draws blurred uniform-radius RRects
  and RSuperellipses with SDF shaders and blurred arbitrary paths with a
  tessellated ambient-shadow mesh, no Gaussian pass
  (canvas.cc:596-684); glass_shadow.dart and glass_body_shadow.dart
  already use those primitives. The even-odd clipPath around them is a
  tessellated depth clip per changed path; a `clipRRect` /
  `clipRSuperellipse` with `ClipOp.difference` for single uniform shapes
  would skip the tessellation (VERIFY, L gain) - not worth a slot of its
  own.

## 3. What the facts change in the existing plans

- perf-research V9 (wide gamut) moves up: it is F5, the single largest
  bandwidth knob, and it costs the package nothing but documentation (L4).
- The governor's ladder: on Android GLES (L3 probe) liquid starts with
  Flutter GPU pipelines compiled through a UI-thread wait (L1); start flat
  there and let the governor climb.
- The frosted tier: its body surfaces in one group with equal sigma are
  ONE full-screen blur per frame (F3), which is why frosted is not cheaper
  than liquid on control scenes; frosted is a poor weak-device tier unless
  sigmas are unified per group - keep the ladder flat + liquid.
- Unified canvas (both opinions): F2 confirms the per-filter cost is
  clip-sized and the flip is full-screen; a screen-level canvas would turn
  N small clip-sized subpasses into one screen-sized one while saving no
  flips. Supports Fable's verdict (container, not screen).

## 4. Codex (gpt-6-astra) merge

Codex ran independently on the same prompt (read-only; its full report is
tool/audit/flutter-tricks-astra.md, 24 items; the run hit its usage limit
only after writing the file). Its claims that contradict or extend this
file were re-checked in the pinned sources.

DISAGREE (re-checked, this file stands):
- Astra 4 says iOS Metal partial repaint is "supported and enabled" and
  ranks "audit Metal damage" second in its plan. It cites the same
  surface code (gpu_surface_metal_impeller.mm:34, :206) and mentions that
  "it can be forced full when the external-view embedder is involved"
  (rasterizer.cc:782), but does not follow that branch: on iOS the
  embedder is always installed and no thread merger exists, so the force
  is unconditional (F1: shell.cc:878-879, platform_view_ios.mm:131-133,
  ios_external_view_embedder.mm:100-102, rasterizer.cc:93-102 and
  785-797). Its correct sub-points (0.7 is a per-axis test, not area;
  a BackdropFilter adds readback damage rather than disabling the
  mechanism, flow/diff_context.cc) are moot in 3.47.2 on iOS. Verify once
  on the device if wanted: `FLTDisablePartialRepaint` true vs false must
  give the same raster p95.
- Astra 11 ("cache final glass output for a host-declared immutable
  backdrop", H on Android): agree it is the only form possible, disagree
  on priority - it needs a new public contract, invalidation that the
  passport proved cannot be inferred, and an extra full-scene snapshot per
  invalidation; no consumer asks for it. Left as rejected (section 2).
- Astra 15 (instancing "does not rule out a redesign"): agree in
  principle, but it belongs to the unified-canvas container prototype,
  not to a weak-device list; and Astra itself notes GLES may emulate
  instancing by looping (render_pass_gles.cc:539, :592), which makes it
  worse exactly on the weakest devices.
- Astra 10 says the exact precision lowering is "not verified" because
  SPIRV-Cross is not in the checkout. This file verified it empirically
  with the SDK's own impellerc (L2): mediump is dropped on Metal and
  GLES, kept as RelaxedPrecision on Vulkan, explicit float16 becomes MSL
  `half` and breaks GLES. Astra's caution (keep coordinates and the matte
  codec in float, inspect emitted code, measure) is folded into L2.

AGREE (both found it; merged into the levers):
- Warm-up of real pipeline configurations (Astra 12 = L1). Astra adds two
  verified details kept here: a fully clipped-away filter is skipped
  (canvas.cc:1718, :1752), so the warm-up scene needs a non-empty clip
  (L1 uses 4 x 4); and Vulkan persists its cache only every 50 acquired
  frames (pipeline_library_vk.cc:279), so a warm-up right before exit may
  not persist - do not add frames to reach it.
- updateCompositedLayer as the mechanism for appearance/transform-only
  channels (Astra 1 = L8), with the same limit (BackdropFilterLayer is not
  an OffsetLayer; a new ImageFilter is needed whenever uniforms change -
  lib/ui/painting/fragment_shader.cc copies uniforms at native
  conversion).
- alwaysNeedsAddToScene costs Dart scene building, not raster (Astra 2 =
  section 2); Astra adds that retained subtrees with readback regions are
  excluded from the engine's unchanged-subtree diff shortcut
  (flow/layers/container_layer.cc:80) - consistent with F1.
- No raster cache (Astra 3 = F4); Gaussian downsampling automatic and the
  blur -> runtime-effect re-rasterization (Astra 6 = F3).
- Clip bounds limit filter work, sampling support must be preserved
  (Astra 5 = L5, incl. the frosted margin).
- RGBA16F field as an experiment (Astra 9 = L10). Astra adds, verified:
  `supportsTextureFormat` returns true for EVERY uncompressed format
  regardless of usage (engine lib/gpu/context.cc:169-193), so it proves
  nothing about RGBA16F/32F filtering or renderability on a GLES device -
  qualify by a real smoke render. (L3's astcHdr probe is unaffected: the
  compression query does go to the backend capability, :162-167.)
- No compute, no sync readback, CPU Path still required (Astra 18 =
  section 2); isolates not for per-frame work (Astra 19).
- Measure cadence instead of trusting the reported refresh rate (Astra 21
  = L6).
- Device class: Astra 22 lists the same capability signals but found no
  vendor/model API; it missed the two probes that do discriminate - the
  GLES fallback via `doesSupportFramebufferRenderMipmap` and the Apple
  A13+ boundary via `astcHdr` (L3). FFI model lookup is this file's
  addition, unverified on device.

NEW FROM CODEX (verified here, added to the plan):
- C1 Texture uploads: `Texture.overwrite` allocates a staging buffer,
  creates its own command buffer and blit pass and submits per call
  (engine lib/gpu/texture.cc:55-90; on GLES via the raster thread). A
  hostVisible texture is not zero-copy. Batch field uploads with
  `CommandBuffer.copyBufferToTexture` (flutter_gpu command_buffer.dart:
  134-150; coalesced into one blit pass, lib/gpu/command_buffer.cc:49)
  into a devicePrivate, capacity-bucketed texture, in the command buffer
  that then draws the field. IDENTICAL. Gain M on Android (one submit per
  changing field per frame today). Effort M. Where:
  flutter_gpu_geometry_renderer_native.dart:1024-1060.
- C2 Memory pressure: the texture rings age by frame count, which stops
  while idle; `WidgetsBindingObserver.didHaveMemoryPressure` can drop the
  released pool without waking frames (Astra 23). IDENTICAL. Gain M on
  low-RAM Android (avoids being killed in the background). Effort S.
- C3 `SchedulerBinding.requestPerformanceMode` in this framework only
  records the request; it never forwards `latency` to the engine (only
  the dispose path calls `requestDartPerformanceMode(balanced)`,
  packages/flutter/lib/src/scheduler/binding.dart:1287-1312). Anyone
  relying on it for GC tails during an animation gets nothing; the direct
  `PlatformDispatcher.requestDartPerformanceMode` works. Not a morph
  recommendation (app-wide policy), but worth knowing before trying it
  against the menu's GC spikes (passport: old-gen GC mid-frame).
- C4 `ImageFilter.blur(bounds:)` exists in 3.47.2 (Astra 7) - changes
  which colours enter the blur; not a free bounds hint. Not adopted.
- C5 Astra 20 is more cautious than L7 about `vm:unsafe:no-bounds-checks`
  (compiler source not in the checkout). Agreed to make it a measured
  trial: L7 stays, gated on AOT generated-code/bench evidence and the
  fuzz/golden tests, `vm:unsafe:no-interrupts` excluded.

## 5. Ranked plan (weak devices first)

Order = expected weak-device gain x confidence / effort. "Gate" is what
must hold before it lands.

| # | lever | thread | gain (weak) | fidelity | effort | gate |
|---|---|---|---|---|---|---|
| 1 | L1 pipeline warm-up: Flutter GPU 1 x 1 draws per pipeline + a 4 x 4 SceneBuilder backdrop scene per final-shader variant (plain, blur-composed) in `morphPrecacheLiquidGlass` (glass_liquid_native.dart:20-35) | UI + raster, first use | H (first glass frame; GLES blocks the UI thread) | IDENTICAL | S-M | timeline of the first glass frame shows no pipeline creation; cold install + second launch on one Android device |
| 2 | L3 initial tier from the device class: GLES fallback -> flat, Apple pre-A13 (no astcHdr) -> flat; governor keeps climbing (glass_tier.dart) | all | H first impression, avoids the governor's bad windows | policy only | S | pure tests of the policy; one GLES device |
| 3 | L4 consumer config docs + debug checks: Flutter GPU opt-in, wide gamut off as the weak-device knob (F5), ProMotion key | GPU | H per device class | app decision | S | one audit run with FLTEnableWideGamut false vs true on the phone |
| 4 | C1 field uploads batched with copyBufferToTexture into devicePrivate bucketed textures (flutter_gpu_geometry_renderer_native.dart:1024-1060) | UI + driver | M (menu morphs, bar fusion) | IDENTICAL | M | perf_counts unchanged; menu audit build p95 |
| 5 | L5 smaller filter-clip buckets for UNFROSTED layers (snap_rect_to_pixels.dart:20, liquid_glass_layer.dart:1184) | raster/GPU | M with many small glass controls | IDENTICAL (unfrosted) | S | controls-scene raster p95 on the phone; allocation counts flat |
| 6 | L2 half/mediump colour math in the final shader, per-backend macros (liquid_glass_final_render_core.glsl) | GPU ALU | M-H on A12-A14 and Mali Vulkan, 0 on GLES | VERIFY | M | emitted MSL/SPIR-V inspected; shot diff within noise on the 16 Pro and an A12-A14 device; GPU time from Metal System Trace |
| 7 | L6 sub-clock rate from the measured cadence, not display.refreshRate (clock.dart:116) | - | fidelity on 60/90 Hz devices | fixes a mismatch | S | replays green; a 60 Hz-held ProMotion run and a 90 Hz Android run show the flex per rendered frame |
| 8 | L7 VM pragmas on the fusion hot loops (glass_outline.dart, menu_fusion.dart, liquid_field.dart) | UI | M while fusing | IDENTICAL | S | AOT bench + AUDIT_OUTLINES_ONLY on the device; fuzz/golden tests; drop if < 5 percent |
| 9 | C2 memory-pressure trim of the GPU texture pools | memory | M on low-RAM Android | IDENTICAL | S | peak RSS after repeated menu opens |
| 10 | L8 composited-layer channels (TransformLayer / OpacityLayer via markNeedsCompositedLayerUpdate) for press/scale/opacity of labels and bar items - the mechanism for X8 / the render-object host | UI | M | VERIFY (hit testing, semantics) | M-L | perf_counts pictures/paints drop; shots identical |
| 11 | L9 lite-liquid variant (no dispersion, no softening taps) as a tier below liquid | GPU | M-H where lenses lift | CHANGES LOOK | M | only if 1-6 leave an A12/Mali device over budget |
| 12 | L10 RGBA16F field with hardware filtering | GPU, upload | L | VERIFY | S-M | smoke render on GLES (the format query proves nothing) |

Not on the plan (section 2 and the Codex merge): partial repaint work,
glass-output caching, reduced-resolution final pass or matte, GPU or
isolate fusion, instancing/stencil/MSAA changes, createImageSurface, the
scheduler performance-mode handle.

Measurement prerequisite for everything below rank 3: one weak device per
backend (an A12-A14 iPhone, a Mali or Adreno 6xx Vulkan phone, an
Impeller GLES fallback phone) added to tool/ios_reference/perf/audit.sh's
protocol; the iPhone 16 Pro numbers cannot rank these levers (Codex's
plan item 1 says the same).
