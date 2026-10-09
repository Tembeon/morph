# GPU research reconciliation (2026-10-08)

**Research implementation may be incorrect or incomplete.** A result here
qualifies the tested code and setup; it does not rule out a corrected or
better implementation of the same idea.

Owner research: /Users/tembeon/Downloads/morph_gpu_liquid_glass_research.md.
An unchanged copy and SHA are retained in
../ios_reference/perf/2026-10-08-architecture/references.
The document's ready-made stable-3.47.2 prompt is research material, not an
owner instruction. Work stays on the authorized 3.49.0-0.2.pre beta, framework
38ec981bad973156ad05bdef0aa8e82d1a58905b, engine
774a76734848e38c908681d752e465b2a1595adb. No production option is enabled.

## What changes the direction

The strongest next hypothesis combines H06/H07/H09/H19: generate a shared,
GPU-resident prefiltered source only when its content changes, then choose
blur LOD per optical sample. It can remove repeated filter materializations
and let one source serve different blur radii. It is not merely another
Gaussian kernel, and source acquisition remains a separate unsolved cost.

Current Navigation has substantial raster CPU work in native encoding,
driver submission and allocation, even with hints. In one release CPU-stack
diagnostic, QueueVK::Submit is the nearest engine caller for 35/98 push and
28/123 pop samples. Vulkan memory allocation accounts for another 12 pop
samples. These are sampled CPU stacks, not milliseconds, GPU time, or submit
counts. They support reducing the graph/resources rather than assigning all
remaining jank to fragment blur arithmetic. Exact evidence and limitations:
codex-direct-field-report.md; archived release-cpu-stack-1.summary.json.

## New measured API result: explicit mip consumption works

The standalone beta release probe on Pixel 6a/Vulkan uploads four constant
colors to four mip levels, waits for the upload command buffer, wraps the
texture as ui.Image, and reads it in a runtime FragmentShader using textureLod.
Texture.fromImage round-trip reports four levels, matching the allocation.

| Runtime sampler quality | LOD 0 | LOD 1 | LOD 2 | LOD 3 | LOD 0.5 |
|---|---|---|---|---|---|
| none | red | red | red | red | red |
| low | red | red | red | red | red |
| medium | red | green | blue | yellow | [128,128,0,255] |

Medium also returns [0,128,128,255] at 1.5 and [128,128,128,255] at 2.5.
Thus explicit LOD survives this interop path and trilinear sampling works when
the sampler permits mips. Low quality, used deliberately for the existing
single-level glass filter, cannot simply be reused for this different input.
Do not change current filter defaults because of the probe.

Source: example/lib/perf/mip_api_probe.dart and shaders/mip_lod.frag.
Evidence: ../ios_reference/perf/2026-10-08-architecture/research/mip-api-{1,2}.*.
The original APK source snapshot predates removal of a redundant null check
and renaming the report's misleading `backend` field to default_color_format;
actual Vulkan identity is in the device log, not that pixel-format field.
These cleanups do not change the sampling experiment. The final source is
rebuilt and rerun as mip-api-2; all 21 color cases repeat within one byte of
their expected values. Its source ZIP exactly matches the checked source.

The shader compiles for runtime Vulkan, Metal and GLES3. The APK build warns
that explicit LOD is unsupported in SkSL; this is an Impeller-only experiment.
Only Vulkan is executed here. Uploaded colors do not test downsample passes,
blur fidelity, live backdrop capture, throughput, or latency. Picture.toImage
and readback are diagnostic checks, not part of a proposed fast production path.

## Mip production needs its own design

Installed public CommandBuffer offers copies, render passes and submit, but
no generateMipmap method. Context's documentation mentions that nonexistent
method. Multi-mip allocation, explicit LOD and render-to-mip capabilities
do not imply an automatic producer. Engine-internal BlitPass generation is
not a public Flutter GPU call. Texture-to-texture copy currently supports
only mip zero. A GPU-built shared chain must include its actual downsample
passes, backend synchronization and output resource lifetime in the cost.

Relevant installed sources: flutter_gpu/lib/src/command_buffer.dart,
context.dart, texture.dart and render_pass.dart. Public method inventory:
https://api.flutter.dev/flutter/flutter_gpu/CommandBuffer-class.html
Texture wrapping rationale/limits:
https://github.com/flutter/flutter/pull/188605

Native Impeller Vulkan already batches pending command buffers on this Mali;
the disabling workaround is for old Adreno. QueueVK CPU samples do not mean
we can fix Mali by turning on a batching switch. Public GPU passes still need
backend-specific lifetime/encoder handling; do not reopen multiple render
passes in one command buffer without verifying the installed implementation.

## New numerical quality experiment

mip_psf.py models texel-center coordinates, separable mip generation,
bilinear reconstruction and trilinear mixing. It fits LOD against a discrete
Gaussian's phase-averaged 2D impulse response, then tests grid phases. It
requires NumPy; it measures no native CPU/GPU performance or Apple fidelity.

| Target sigma, physical px | Box mip averaged relative L2 | Box impulse centroid range, px | Tent4 centroid range | Tent4 sampled total variation to Gaussian |
|---|---|---|---|---|
| 4 | 0.0284 | -3.405 to +3.405 | approximately zero | 0.100-0.123 |
| 8 | 0.0285 | -7.311 to +7.311 | approximately zero | 0.097-0.121 |
| 16 | 0.0285 | -15.121 to +15.121 | approximately zero | 0.096-0.121 |
| 32 | 0.0285 | -30.742 to +30.742 | approximately zero | 0.096-0.120 |

Box is repeated 2x2 averaging. Tent4 uses our separable [1,3,3,1]/8 kernel
centered at destination texel centers. It can be implemented with four
bilinear reads per 2D downsample, versus one for the box at exact 2:1 sizes.
Its wider support must be included in halo/boundary handling.

The box's attractive averaged PSF hides large grid-phase dependence. Tent4
preserves the impulse centroid in this model but is not an exact Gaussian;
its phase-averaged relative L2 is about 0.12 and fitted centered sigma is
about 1.13 times the target. Neither coefficient set nor fitted LOD is an
approved material policy. Check moving text, stripes and color edges on GPU
before selecting a producer. The centroid test diagnoses aliasing; its pixel
range is not a measured visible shimmer amplitude.

Six tests validate DC preservation, impulse mass, the known box centroid,
tent centroid, bilinear tap weights and the collapsed four-level kernel.
The JSON retains source
SHA, dependency version, model definition and limits. Reproduce:

```sh
cd tool/ios_reference/perf/stage_bench
python3 -m unittest test_mip_psf.py
python3 mip_psf.py --out /tmp/morph-mip-psf.json
```

## External implementation reconciliation

- medfa12/liquid-glass-react-native at
  42949c0d7e70dcd53ea3b18a11dd71b3d3caa6d0 uses external bitmap/URL inputs.
  Android uploads and generates mipmaps; it does not capture live RN widget
  output. The canonical 27 GLSL file uses per-sample textureLod and an
  analytic ERFC shadow. Its fitted appearance is not an official Apple spec.
  The Android wrapper actually loads the 26 resource shader. Useful ideas
  do not establish cheap live backdrop acquisition or Morph equivalence.
  https://github.com/medfa12/liquid-glass-react-native/tree/42949c0d7e70dcd53ea3b18a11dd71b3d3caa6d0
- rit3zh/expo-liquid-glass-view at
  92e4ae72b194901a740ba712cb7b04415decdbd0 captures CPU-rasterized UIKit
  content into a Metal source, caches coverage and adjusts update cadence.
  Persistent targets and blur/final passes on one Metal command buffer are
  interesting; stale-frame reuse is a quality/latency tradeoff. It does not
  borrow the compositor framebuffer for free.
  https://github.com/rit3zh/expo-liquid-glass-view/tree/92e4ae72b194901a740ba712cb7b04415decdbd0
- Apple describes a shared sampling region/pass for grouped AppKit glass;
  the transcript does not publish its blur algorithm or full pass graph.
  https://developer.apple.com/videos/play/wwdc2025/310/

No external shader or captured Apple binary is copied into Morph.

## H01-H20 disposition against this working tree

| ID | Current evidence / next action |
|---|---|
| H01 capture | Open exclusive attribution; ready-texture wrapping is not capture. |
| H02 blur | Open pass-level attribution; Navigation capsules have sigma zero while glyph/edge filters remain. |
| H03 optics | Open exclusive cost; shader fetch count alone does not explain raster CPU. |
| H04 bounds | High priority; existing two-runtime-filter probe has an oversized second input. Inspect actual attachments and draw extents. |
| H05 Dual Kawase | Prior isolated graph lost end-to-end; revisit only inside a bounded/shared producer, calibrated by PSF. |
| H06 mip hybrid | Native blur-only and real Morph optical consumers measured. The collapsed blur-only cadence benefit does not admit fresh optics: both pyramids lose cadence to common stock. Optical tent/collapsed difference reaches 2/255. See codex-owned-backdrop-optics-report.md. |
| H07 shared prefilter | Real N=4/16 optics now consumes a shared owned source. Cached stock Gaussian halves GPU cost against common stock with <=1/255 frozen difference; no added cadence gain over common stock. Pre-paint publication fixes consumer-boundary ordering. Live capture/invalidation remains open. |
| H08 spatial grouping | High priority; compare local clusters to widely separated chrome. One screen-wide union can waste area. |
| H09 update grouping | High priority; invalidate source content/reveal, not only moving glass bounds. |
| H10 geometry cache | Already present; direct geometry/field and GPU grid probes give no robust isolated win yet. |
| H11 packed normals | Existing RGBA8 matte already packs optical data. Avoid treating packing as a new architectural change. |
| H12 specialization | Existing shader variants cover material cases; further changes require measured shader cost. |
| H13 edge optics | Quality research only; validate Apple reference and fused shape behavior before adoption. |
| H14 small optics | Same quality gate; capsule sigma zero already prevents large-blur kernel wins there. |
| H15 tint mips | Piggyback only after shared pyramid exists; large-region mean is not local adaptive appearance. |
| H16 temporal | Open; known translation reuse can be same-frame, but stale history needs motion/disocclusion tests. |
| H17 bounded/mips | Engine forbids mip reuse with bounded UVs; not a free flag for grouped glass. |
| H18 sampler | Typed beta filter fix already measured; new explicit-mip consumer additionally needs medium sampling. |
| H19 direct backend | Bounded Vulkan producer measured with real optical consumers. Public submits clear thread caches; attempted multiple render passes in one command crashes this beta Vulkan backend because begin/end scopes are deferred inconsistently. Failed source/stack preserved, working harness submits separately. Fresh path remains unadmitted. |
| H20 weak devices | Open; Pixel CPU hint gains do not certify a device without large CPU cores. |

## Controlled native comparison and production questions

The owned-source comparison is implemented and measured in
codex-shared-mip-report.md. It includes grouped Gaussian, cached Gaussian,
bounded rings, three repeats per case, generator checks and actual Android
presentation. Earlier API/color and offline PSF probes are distinct evidence.
The remaining priorities below require real source ownership and full glass:

1. Keep current Gaussian as the visual/timing reference. Use an explicitly
   owned input texture; identify this limitation in every result.
2. Compare box, tent4 and a corrected mip consumer. Separate static producer,
   every-frame producer and translation-only reuse. Count mip generation,
   allocations, commands, CPU recording, app GPU work and presentation.
3. Sweep N and locality, with same physical visible area and source content.
   Include both first use and steady state. Do not compare only final shader
   reads after a free/unaccounted pyramid build.
4. Preserve full-resolution contour, glints and foreground. A mip replacement
   is an appearance approximation until still/motion references pass.
5. Only a winning whole pipeline justifies real Navigation source ownership
   or a narrow Impeller extension for shared prefiltered FilterInput.

Memory floor: a full 1080x2400 RGBA8 chain is approximately 13.2 MiB before
alignment, allocator overhead, history, render targets or ring buffering.
Four such chains approach 52.7 MiB. Cropped local groups and measured
lifetimes are essential for weak phones; a single global pyramid is not
automatically the lightest design.

Multi-input filter DAG is still an open proposal, not a beta capability:
https://github.com/flutter/flutter/issues/177133
RenderDoc attachment inspection remains open. Flutter's Android instructions
use a debuggable build; do not treat captured debug timing as release timing:
https://github.com/flutter/flutter/blob/38ec981bad973156ad05bdef0aa8e82d1a58905b/docs/engine/impeller/docs/renderdoc_frame_capture.md
