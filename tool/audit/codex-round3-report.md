# Codex round 3: flat tier and liquid controls (2026-10-06)

Requested scope: the flat tier's remaining backdrop blur (brief T1), and
liquid controls on the UI thread (brief T2). The flat change lands;
the controls coordinate trial is rejected. The profiling harness and
measurement evidence are retained.

## Method and provenance

Base: 84997e1, wip/measured-liquid-glass. Landed code: 36fa94e (flat
edge), 60719c3 (controls profiler). Pixel 6a, serial
26221JEGR12737, Impeller Vulkan, 60 Hz, portrait, profile builds. The
Pixel lock was acquired with mkdir before device work. No iPhone work.
Builds of the baseline used a git archive of the pinned commit; the
candidate APKs were copied before the next build. APK hashes are retained
with the evidence. Every energy launch starts below 37 C VIRTUAL-SKIN;
power is ODPM rails over the audit's monotonic scene windows. The phone
was on AC at 100 percent; battery status changed from charging to full.
The harness includes its continuous live-test frame loop on both sides.

An existing uncommitted PHASES_ONLY change in glass_phases_test.dart was
left untouched. There were no production changes in the initial tree.

## T1: no backdrop reads on flat

MorphScrollEdgeEffect now resolves the installed renderer's effective
tier through MorphAdaptiveGlass.tierOf. Flat keeps the same fade and
hard-style hairline, but allocates no blur, color-matrix backdrop filter
or seed copy. Unknown/custom painters retain their ordinary edge effect.
The render object also handles tier changes and driven opacity without
retaining filters from the previous tier.

The complete flat device census has zero backdrop filters at every
sampled frame in all seven scenes: home-scroll, segmented, tab-bar,
controls, menu, sheet and list. Before, only the edge effect owned the
remaining filters (up to two).

Energy A/B/B/A, two launches per variant, five runs per scene. Median of
launch medians; raster is p95 in ms, power is all-phone ODPM mW, GPU rail
is energy over the scene window in mJ. A = 84997e1, B = flat fade only.

| Scene | raster p95 A -> B | power A -> B | GPU rail A -> B |
|---|---:|---:|---:|
| home-scroll | 10.88 -> 9.19 | 590 -> 465 (-21%) | 3653 -> 1231 |
| segmented | 7.03 -> 6.73 | 425 -> 420 | 875 -> 911 |
| tab-bar | 10.93 -> 8.47 | 661 -> 519 (-21%) | 5385 -> 1893 |
| controls | 7.08 -> 6.82 | 419 -> 421 | 778 -> 831 |
| menu | 10.09 -> 10.20 | 481 -> 487 | 773 -> 742 |
| sheet | 8.17 -> 7.77 | 426 -> 431 | 936 -> 966 |
| list | 10.98 -> 8.45 | 553 -> 447 (-19%) | 3977 -> 1369 |

The three changed scenes reduce GPU-rail energy by 65-66 percent;
CPU and memory rails also fall. Scenes without an active edge show no
repeatable energy improvement. Evidence: perf/2026-10-06-round3-flat-energy,
including cached Perfetto rail and scheduler reductions, thermal metadata,
the original frame reports and before/after frame hashes.

Separate kernel GPU-work launches, five runs per scene, weighted GPU
time per active frame at 434 MHz. home-scroll 4.110 -> 2.009 ms
(1.784 -> 0.872 Mcycles), tab-bar 5.113 -> 2.413 (2.219 -> 1.047),
list 4.525 -> 2.159 (1.964 -> 0.937): -51 to -53 percent. Other scenes
change by less than 0.01 ms. This pair is A/B; the independent frame and
energy comparisons above use A/B/B/A. Evidence:
perf/2026-10-06-round3-flat-gpu. Its frame reports confirm every changed
scene has zero over-budget frames at the median run, against 2 / 0 / 2
before (home / tab / list). The audit APKs used for flat have screenshots
disabled; deterministic hashes cover the approved appearance change.

Fidelity: removing the flat blur and saturation/brightness is the
owner-approved visible change. The 63 deterministic scene/tier frame
hash sets differ only in nav-scroll/flat; every fake and liquid frame
hash remains identical. The edge test also checks the fade's actual
pixels across opacity changes, top/bottom, hard/soft, and fake-to-flat-to-
fake transitions. No numeric max-channel bound is claimed for the
approved flat appearance change.
The hash suite runs in flutter_test, where liquid paints its fallback;
it is not a device Impeller pixel-identity claim. T1 leaves the liquid
edge path unchanged. The separate true-Impeller comparison below covers
the rejected coordinate trial.

One-binary scroll bench, five randomized interleaved repeats, seed
20261016, Material / morphFlat / morphFlatNoEdge. All variants share
the content and gestures; the flat render path is the final one.

| Variant | build p50 / p95 ms | raster p50 / p95 ms | GPU ms / Mcycles per frame |
|---|---:|---:|---:|
| Material | 1.34 / 3.82 | 4.79 / 5.85 | 0.743 / 0.322 |
| morph flat | 1.25 / 3.18 | 5.15 / 6.40 | 0.957 / 0.415 |
| morph flat, no edge | 1.23 / 3.02 | 4.92 / 6.01 | 0.871 / 0.378 |

The remaining fade costs about 0.086 ms GPU; flat's raster is 8-9
percent above Material and GPU cycles 29 percent above it. The target
is approached, not exactly reached. Material and no-edge morph still
have a small content/chrome cost difference. All variants have zero
over-budget frames at the median run. Evidence:
perf/2026-10-06-round3-flat-bench. Rebuild from the existing comparison
bench scaffold described in g1455-review.md, with BENCH_RUNS=5,
BENCH_SEED=20261016, BENCH_VARIANTS=material+morphFlat+morphFlatNoEdge,
BENCH_SCENES=scroll and BENCH_SHOTS=true.

## T2: liquid controls UI anatomy

The existing menu_frames_test profiler now also accepts
FRAMES_SCENE=controls. It runs the audit's switch/slider gesture sequence,
collects framework blocks, VM events, FrameTimings, per-frame Dart CPU
samples, and touch marks. The default menu scenario is preserved.
Evidence: perf/2026-10-06-round3-controls-profile. Three timed runs per
tier, CPU samples at 250 us, no per-widget instrumentation. These figures
include profiler overhead; candidate timing/energy uses the ordinary
glass_audit_test instead.

| Metric, ms | flat | liquid |
|---|---:|---:|
| FrameTiming build p50 | 1.681 | 5.134 |
| FrameTiming build p95 | 9.637 | 12.975 |
| FrameTiming build p99 | 13.961 | 15.892 |
| Raster p50 | 5.180 | 7.601 |
| Raster p95 | 6.524 | 11.067 |
| Raster p99 | 7.341 | 13.762 |
| Frames over 16.67 ms, median/run | 1 | 2 |
| BUILD, mean per active frame | 1.027 | 1.067 |
| LAYOUT, mean per active frame | 0.531 | 0.564 |
| PAINT, mean per active frame | 0.558 | 1.937 |
| COMPOSITING, mean per active frame | 0.710 | 2.411 |

The phase rows are means, then medians across runs; they do not add to
the FrameTiming p50. Liquid's extra work is paint and compositing, not
widget construction or layout. CPU samples in heavy UI frames place
CommandBuffer.submit at 9.2-9.8 percent of self samples. RenderPass.draw,
RenderPass.begin and Texture.asImage together account for another
5.4-5.8 percent; RenderObject.getTransformTo about 2.0-2.2 percent. The
geometry renderer and deferred-submit flush are the main package paths
into that native work. Those are sample shares, not per-frame durations.

A separate baseline native atrace run (TraceSystrace=true, two ordinary
audit repeats, no CPU sampler) covers 800 UI / 801 raster frames over
13.543 seconds. Means over every frame in the scene windows:

| Native trace measure | value |
|---|---:|
| UI BUILD self ms/frame | 0.892 |
| UI LAYOUT self ms/frame | 0.285 |
| UI PAINT self ms/frame | 1.615 |
| UI COMPOSITING self ms/frame | 1.284 |
| UI QueueSubmit calls/frame | 0.887 |
| UI QueueSubmit inclusive ms/frame | 0.915 |
| Animator::BeginFrame inclusive ms/frame | 6.013 |
| Raster QueueSubmit calls/frame | 1.998 |
| Raster QueueSubmit inclusive ms/frame | 2.155 |
| Raster Canvas::saveLayer calls/frame | 6.206 |
| Raster Canvas::saveLayer self ms/frame | 1.153 |
| Raster SurfaceFrame::Encode self ms/frame | 2.837 |
| GPURasterizer::Draw inclusive ms/frame | 8.037 |

Native self times exclude traced children; inclusive times include them.
Do not add nested values or compare these means directly to p95. In
particular native submit contributes about 0.9 ms per UI frame, while
paint and composition still consume additional time. Evidence:
perf/2026-10-06-round3-controls-native (scene/thread reductions, audit
report, temporary manifest patch and raw trace SHA-256). The manifest
in the production example is unchanged.

The trial avoids rewriting unchanged coordinate uniforms (tracking the
shader instance so a program switch still receives them), and uses the
translation inverse instead of a general 4x4 inverse for translation-only
passes. General transforms retain the inverse path. The patch is saved
with the evidence; production rendering was restored to the original.

Ordinary audit A/B/B/A, two launches per variant, five controls runs per
launch. These are median-of-launch medians, with no CPU sampler. A =
original renderer; B = coordinate trial.

| Metric | A | B |
|---|---:|---:|
| build p50, ms | 4.96 | 4.84 |
| build p95, ms | 12.32 | 12.27 |
| raster p50, ms | 8.41 | 8.94 |
| raster p95, ms | 11.64 | 12.49 |
| total power, mW | 666 | 645 |
| GPU rail, mJ | 5106 | 5220 |

The build improvement is within the baseline's launch spread (p50
4.85-5.07; p95 12.11-12.54). Raster gets worse on both trial launches.
The power delta is only -3 percent and GPU-rail energy rises 2 percent.
This is insufficient evidence for a performance change: REJECTED.
Evidence: perf/2026-10-06-round3-controls-energy.

Separate GPU-work launches, five runs each: original / trial 5.014 /
4.993 ms per active frame, 2.176 / 2.167 Mcycles per frame at 434 MHz.
Build p50 5.08 -> 5.12 ms, p95 12.25 -> 12.10. Neither metric repeats
an improvement beyond noise. Evidence: perf/2026-10-06-round3-controls-gpu.

Real Impeller host before/after captures: max channel difference 0 for
regular-dark, lens-lifted, tint-pair, mixed-models and menu-frosted (both
runtime-shader variants). This compares the original and trial renderer,
not only two shaders through the same renderer.
Device controls-resting is also identical (max 0). Held switch max 15,
held slider max 233 on 0.0343 percent of pixels above 15. Those gesture
captures are not synchronized to the same motion frame; no device-wide
IDENTICAL or NEAR claim is made for the rejected trial.

## Verification

Package tests: 1398 passed (including motion replays, channel/rebuild
frame identity and work ceilings). Example tests: 18 passed. Analyzer:
zero issues. dart doc --dry-run: zero warnings and errors. Formatting and
git diff --check passed. The candidate's true-liquid host captures passed
on Impeller, maximum before/after difference 0.

## Remaining cost and next levers

Controls: the flat renderer is the current framework/content floor.
Most of the liquid UI premium is matte encoding and native submission,
plus the layer composition/filter path. The source already defers
submissions to the scene build; sharing render passes on one command
buffer remains unsafe on the current engine. Any larger package change
needs fewer actual matte encodes with byte-identical GPU inputs, or less
layer work without changing paint/backdrop dependencies. An engine-side
change to Flutter GPU encode/submit is a separate lever.

Flat scroll is now below 1 ms GPU in the comparison bench, with a small
remaining fade and content/chrome premium. No change to motion laws,
fusion workers or liquid appearance is part of this scope.

The ordinary release gallery was rebuilt, installed and launched on the
Pixel after all measurements. Portrait orientation 0 was verified. The
owned Pixel lock was released. Temporary work trees, APKs, traces and
shots were removed. No push was made. The initial PHASES_ONLY edit remains
uncommitted and unchanged. Validation and release APK hash are retained
in the controls-profile evidence directory.
