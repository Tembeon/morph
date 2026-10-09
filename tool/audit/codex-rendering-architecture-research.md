# Architectural performance research (2026-10-08)

**Research implementation may be incorrect or incomplete.** A result here
qualifies the tested code and setup; it does not rule out a corrected or
better implementation of the same idea.

Research and proposed experiments, not new device measurements or landed
renderer changes. Use beta only. Do not restore release APKs between active
experiments. Smoothness on weak Android is the priority; energy remains a
secondary measured constraint. Similar cheaper effects are research options,
not silently approved production replacements.

## Diagnosis from existing evidence

- Beta liquid nested push: UI p95 21.641/19.984 ms, raster p95
  29.419/26.456 ms, app GPU work 6.228/6.202 ms per produced frame.
  These are different statistics and overlapping pipeline stages. They
  cannot be subtracted to calculate driver overhead or added as frame cost.
  The evidence motivates investigating CPU work, submissions and waits as
  well as fragment work; it does not establish one exclusive root cause.
- Flat navigation has zero backdrop filters but still exceeds its raster
  budget. Earlier live-glyph ablations implicated foreground blur and paint.
  Some original glyph rasterization is now retained, so repeat attribution
  against the current beta renderer before assigning current percentages.
- Default gallery capsules have blurPassSigma=0. Scroll-edge effects and
  glyph blurs remain separate. Optimizing a large Gaussian kernel cannot
  explain or cure all Navigation stalls.
- The two-runtime-filter blur experiment exposes a 1082x2402 second input
  for a small region on a 1080x2400 display. Existing-display screencap
  confirms it. This is an oversized intermediate in this graph, not proof
  that every stock filter shades every screen pixel.
- The owned-source experiment already reduced whole-app GPU work from
  4.073 to 1.900 ms/frame for unchanged-source translation with full optics
  and max error 3/255 on its fixture. It has not proved general navigation
  source ownership or performance when everything changes every frame.

Evidence: codex-beta-sdk-report.md, codex-navigation-report.md,
codex-navigation-flat-report.md, codex-navigation-stable-report.md,
codex-combined-source-report.md, codex-backdrop-input-review.md.

## Experiment 1: remove live glyph filters, retain blur results

Current bar_items.dart retains original glyph rasterization on Android but
still wraps it in ImageFiltered, then opacity and scale. Retaining the
original input is not retaining the blurred output.

Prototype a small, bounded atlas per immutable content revision with a few
preblurred levels. Animate by blending two neighboring levels in one shader,
including opacity and the existing scale transform. Align sampling and blur
sigma to the current transform and preserve premultiplied alpha/padding.
Generate levels only for used content and account for misses and memory.
Keep live content for rapidly changing labels or unsupported paint.

This removes repeated glyph filter passes and may reduce raster/submit work
even in flat mode. Interpolation between blur levels is approximate; a
cross-fade is not an exact Gaussian at the intermediate sigma. Test thin
strokes, small text, subpixel motion, changing colors and the clear/blurred
handoff. Capture first-use costs instead of measuring only a warm atlas.

Alternative: SDF glyph rendering can make edge softness, shadow and opacity
cheap. SDF softness is not Gaussian convolution of arbitrary glyph coverage;
small text, corners and intersecting strokes make this a higher-risk option.
Start with preblurred images, not a replacement text engine.

## Experiment 2: fuse small-group geometry into final shading

Morph already uses analytic GPU shape distance functions. The new proposal
is to remove intermediate representations for small capsule groups, rather
than merely introduce SDF rendering again.

Today fused groups can calculate a CPU grid/outline, upload a field, encode
geometry with Flutter GPU, and sample the resulting matte in final optics.
Try a specialized final runtime filter for one/two/few capsules: send shape
parameters, evaluate the existing normal-dependent merge law directly, then
derive coverage, normals, displacement and tint in the optical shader.
Use bounded rectangular clips and shader coverage where composition allows
it. Hit testing/semantics still need correct geometry, but need not imply a
full marching-squares path every animation tick. Shadows need their own
solution; do not discard the one-mass/one-shadow rule.

This trades additional fragment arithmetic for fewer CPU sampling/upload
steps, GPU submissions and intermediate targets. It can lose for many shapes,
large areas or iterative superellipse solvers. Specialize small groups; retain
the general renderer for complex cases. Match the actual Apple merge law,
not a generic smooth-min. A precise analytic field also differs from the
current sampled/packed matte, so exact parity cannot be assumed.

## Experiment 3: own a damage-tracked backdrop source

Promote the existing owned-source fixture into real Navigation chrome.
Represent source pictures/images with revisions and known transforms. Cache
only visible source tiles plus blur/refraction reach and a scroll guard.
Reuse unchanged tiles; update newly exposed or modified regions.

Blur commutes with uniform translation, enabling same-frame reuse of an
unchanged blurred source. Scaling changes effective sigma; overlapping
layers, reveal regions and non-rigid changes need invalidation. Independent
glass surfaces can share a source only when they read the same paint-order
background. Nested glass and platform views/textures need separate handling.

This is more than an arbitrary screenshot cache. Picture replay and
toImageSync still rasterize extra work on misses. Public Flutter GPU does not
provide the current compositor backdrop as a Dart texture. Any claim of
rendering the source once for both display and glass needs an explicit
composition design or engine integration. Include animated-list worst cases
and cache misses in the result, not just static scroll throughput.

## Experiment 4: separate crisp geometry from diffuse appearance

Use low-resolution/less frequently refreshed diffuse color while keeping
contours, foreground glyphs, glints and transforms current at full resolution.
Reuse known motion to reproject diffuse data rather than leaving it stationary.
Current detailed refraction should use an appropriate current source if its
sharp features would expose stale history. This is a component-wise design,
not reducing the entire interface resolution or freezing its interaction.

Updating diffuse history at 30 Hz while chrome moves at 60 Hz is a research
starting point, not a selected policy. Fast scrolling, newly exposed content,
video and theme changes can reveal lag/ghosting and require refresh/history
rejection. Compare motion recordings, not just still-frame channel error.
Spatial downsampling within the same frame does not itself add a frame of
latency; reusing a previous frame or scheduling capture for later does.

## Experiment 5: bounded native filter graph, then alternate kernels

For arbitrary Flutter backdrop content, investigate an Impeller experiment
that receives the native FilterInput, crops to the actual region plus halo,
downsamples once and shares reduced outputs across compatible effects. Keep
targets/pass encoding together on the raster side. First measure allocation
extent, actual draw/scissor extent, pass/submit count and waits. The runtime
compose probe alone does not establish which of these dominates.

Single-dispatch shared-memory Gaussian is a real alternative to writing a
full horizontal intermediate: AMD FidelityFX Blur demonstrates it. The beta
Flutter GPU API exposes vertex/fragment stages, not a public compute dispatch;
using this algorithm needs engine work or a separately owned native pipeline.
A plugin with another GPU context does not automatically obtain Impeller's
backdrop, synchronization or zero-copy interoperability. AMD's desktop
implementation is not a measured Mali win.

Dual Kawase remains a candidate for large blur after source/bounds/pass costs
are controlled. Arm reports limited gains over already downsampled Gaussian
in a real mobile case. Pixel-local storage/input attachments do not solve
neighbor sampling: ordinary accesses are pixel-local, whereas blur crosses
pixels and tiles. They can help suitable local composition, not make spatial
blur free.

## Other cheap approximations

- Scheduling is a separate hypothesis. Revisit the existing Android ADPF
  experiment under the owner's later smoothness-first policy. A fixed-target
  Performance Hint session can affect CPU placement/DVFS without changing
  the rendering math; it cannot remove work or guarantee gains on small-core
  phones. Measure actual presentation and sustained energy, and distinguish
  direct callback benchmarks from real Android touch/input boosts.

- Analytic rectangle shadows avoid blur textures entirely; rounded rectangles
  admit a small fixed sampling approximation. Fused shapes and Apple's fitted
  material require additional validation. A simple distance-to-edge softness
  is not the exact blur of a fused mask.
- For a known solid/gradient/image backdrop, derive or precompute its diffuse
  source instead of blurring arbitrary widget output. Preserve live details
  where needed. This is a source-specific fast path, not universal fake glass.
- Prebake finite transition states only when their parameter space stays
  bounded. Unbounded label/shape combinations would turn this into cache
  churn and memory growth.

## Order and success criteria

1. Re-attribute current beta Navigation: glyph filters and geometry submissions
   independently, including first entry, push/pop and toolbar changes.
2. Compare the glyph atlas and fused small-group final shader independently
   and together. These attack two bottlenecks without solving backdrop access.
3. Carry source/damage reuse into actual Navigation, including misses/reveals.
4. Explore diffuse temporal reuse only with explicit motion-quality evidence.
5. Use a bounded native Impeller prototype if public composition imposes the
   remaining floor; choose the blur kernel inside the corrected graph.

Engineering target, not a new measured promise: each UI/raster stage p95
below 16.667 ms at 60 Hz, preferably about 12 ms to retain headroom. Verify
actual presentation misses with Android FrameTimeline where available;
average FPS/GPU work alone cannot establish smoothness. Compare equivalent
interactions to Material, not unrelated control scenes. Pixel 6a is a useful
diagnostic device, not proof of low-end support: validate on weaker hardware
and include cache memory and sustained thermal behavior.

## Primary sources

- Arm, mobile post-processing and alternatives (2018):
  https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/post-processing-effects-on-mobile-optimization-and-alternatives
- AMD, FidelityFX Blur single-dispatch shared-memory implementation:
  https://gpuopen.com/manuals/fidelityfx_sdk/techniques/blur/
- Khronos, render-pass/input-attachment locality:
  https://docs.vulkan.org/spec/latest/chapters/renderpass.html
- Valve, distance-field vector textures and effects (SIGGRAPH 2007):
  https://cdn.akamai.steamstatic.com/apps/valve/2007/SIGGRAPH2007_AlphaTestedMagnification.pdf
- Evan Wallace, analytic/fixed-sample rectangle shadows (CC0 examples):
  https://madebyevan.com/shaders/fast-rounded-rectangle-shadows/
- Ragan-Kelley et al., decoupled visibility/shading sampling (2011):
  https://research.nvidia.com/publication/decoupled-sampling-graphics-pipelines
- AMD, temporal reuse and history rejection/disocclusion (GDC 2023):
  https://gpuopen.com/download/GDC-2023-Temporal-Upscaling.pdf
- Flutter GPU public shader stages, checked against installed beta source:
  https://api.flutter.dev/flutter/flutter_gpu/ShaderStage.html
- Android Performance Hint target/actual durations and CPU resource selection:
  https://source.android.com/docs/core/perf/performance-hint-api

The proposed glyph atlas, capsule fusion and diffuse-history policies are
our inferences/design hypotheses. These sources establish the underlying
techniques and limitations, not their performance in Morph.
