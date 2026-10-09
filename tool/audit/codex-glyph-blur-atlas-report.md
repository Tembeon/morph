# Retained foreground blur experiment (2026-10-08)

Work in progress. Production routing remains unchanged: the atlas is behind
MORPH_GLYPH_BLUR_ATLAS, false by default. Experiments 2-5 in
codex-rendering-architecture-research.md remain open. No general 60 FPS,
weak-device, energy or iOS claim follows from this first experiment.

## Protocol and source

Pixel 6a, Vulkan/Impeller, 1080x2400, DPR 2.625, 60 Hz. Flutter beta
3.49.0-0.2.pre / framework 38ec981bad / engine 774a767348. Actual Gallery
Navigation callbacks: enter, nested push/pop and toolbar item-set change,
flat and liquid. Three shuffled repeats per GPU launch, 500 ms post-mount
warmup, 800 ms collection, seed 2026100814. Action prewarm and five seconds
idle precede repeats. Every mount can miss the content cache: the measured
actions are not a permanently warm atlas-only benchmark.

Control source: HEAD 1325722; the owner's glass_phases_test.dart change is
not part of this entry point. SDK-pinned example lock resolution uses beta.
Candidate source snapshots and APK build records preserve inputs. Native
phase images follow collection and advance the scheduler in 16667 us steps.
Two control and two compact-atlas GPU launches are retained. Exploratory
unrestricted, handoff and dense variants each have one launch. Launch order:
control-1, atlas-1, handoff-1, packed-1, control-2, packed-2, dense-1.

The runner now supports --leave-installed, so it neither backs up nor
restores the gallery between these authorized experiments. It still releases
its Pixel lock and stops/restores owned recording resources on exit.

## What the prototype changes

The current renderer retains original glyph rasterization while sufficiently
blurred but still executes a live ImageFiltered blur. The prototype records
seven blur levels [0, .5, 1, 2, 4, 7, 10] per content revision, then samples
two levels in one shader with premultiplied opacity. Scale remains the actual
outer transform. Child repaint/DPR change invalidates; detach/dispose releases
the owned image. Animated sigma/opacity reuse its pixels.

The first variant also sampled clear content. Its glyph resampling introduced
up to 189/255 chrome differences. Restricting it to screen blur >= .5 logical
px preserves the existing live-glyph handoff and removes that error class.

The compact variant packs rows with their own blur padding, samples only the
logical source extent, and rasterizes levels >=2 at half device resolution.
The diffuse output is spatially reduced in the same frame, not captured from
the previously displayed frame. Each miss still incurs extra source and atlas
rasterization through toImageSync; that work is not described as borrowing
the existing framebuffer.

## Two-launch compact result

Values are each launch's median over three repeat windows. UI/raster stages
overlap, and GPU work is whole-app kernel activity per produced frame.

| Action/tier | Control UI p95 ms | Compact UI p95 ms | Control raster p95 ms | Compact raster p95 ms | Control GPU ms | Compact GPU ms |
|---|---|---|---|---|---|---|
| enter/flat | 8.65 / 8.22 | 10.27 / 10.87 | 12.92 / 12.31 | 7.71 / 9.01 | 2.761 / 2.768 | 2.718 / 2.671 |
| push/flat | 11.21 / 9.97 | 11.09 / 14.24 | 28.29 / 20.41 | 11.34 / 11.88 | 2.838 / 2.907 | 2.869 / 2.779 |
| pop/flat | 12.74 / 12.89 | 10.37 / 9.89 | 19.22 / 16.44 | 12.35 / 12.04 | 2.596 / 2.556 | 2.414 / 2.456 |
| toolbar/flat | 4.88 / 4.51 | 6.30 / 6.40 | 10.73 / 10.77 | 6.97 / 6.71 | 2.047 / 2.015 | 1.927 / 1.892 |
| enter/liquid | 14.42 / 15.02 | 14.23 / 11.11 | 12.94 / 15.55 | 11.89 / 9.09 | 5.031 / 5.070 | 5.047 / 4.960 |
| push/liquid | 23.77 / 23.60 | 26.14 / 20.16 | 32.84 / 24.39 | 14.16 / 14.85 | 6.222 / 6.192 | 6.522 / 6.580 |
| pop/liquid | 15.96 / 17.56 | 20.55 / 22.40 | 22.99 / 25.30 | 13.29 / 14.76 | 5.607 / 5.592 | 5.851 / 5.920 |
| toolbar/liquid | 8.08 / 8.61 | 8.29 / 8.71 | 12.43 / 13.31 | 8.89 / 10.37 | 4.451 / 4.407 | 4.385 / 4.401 |

Nested raster tails improve in both launches, including flat with zero
backdrop filters. Liquid UI remains over budget and pop UI regresses. Liquid
push GPU work increases about 5-6 percent. Do not infer energy from GPU work
or call this a complete smoothness fix. The direction supports attacking
foreground filter organization separately from background Gaussian kernels.

## Memory, first use and parity

Owned atlas estimates peak at 19,509,868 bytes in the first equal-sized-row
variant and 3,942,564 bytes in the compact version, about 80 percent less.
These count owned image dimensions times four; they exclude source images,
transient filters, in-flight references, allocator retention and process RSS.

The compact launch's first enter after shader precache, before action prewarm,
has UI/raster p99 24.72/23.64 ms. It is not cold app startup. First-use spikes
remain; accepting only warm p95 would conceal them.

Compact against control-1: chrome max 7/255, whole-frame max 56/10 on
flat/liquid. Against control-2 in the second launch: chrome max 7/255,
whole-frame max 8/10. The control/control repeat reaches whole-frame 56/255
with chrome 0/2, so isolated whole-frame errors are retained alongside repeat
noise rather than hidden. Blur-level interpolation is approximate; the
tested default dark Navigation scenes do not establish all-theme/RTL parity.

Thirteen levels cost 7,246,716 owned bytes and do not improve the chrome
maximum beyond 7. One launch gives liquid push GPU 7.098 ms and raster p95
10.44 ms. More levels are not selected from this result.

## Presentation and verification

A short, separate FrameTimeline control probe confirms actual Impeller
buffer records (Is Buffer? = Yes), not just surface transactions. The reader
maps MONOTONIC action windows to BOOTTIME through recorded clock snapshots
and links buffer tokens to SurfaceFlinger display frames. Jank flags and
observed presentation gaps are reported separately; the control shows gaps
up to 50-67 ms despite mostly on-time transaction flags. The compact candidate
has longest gaps 66.69/83.38/83.37/66.61 ms for toolbar/pop/push/enter,
versus control 33.45/66.73/50.09/50.04. Missed slots are 6/18/16/17 versus
6/18/8/7. This is one separate launch each, not a repeat-controlled result:
it does not establish improved presentation and motivates investigating the
remaining UI/cache-miss cost. These diagnostic launches are separate from
GPU measurements.

Beta analysis passes with no issues. A render test checks cache reuse during
sigma/opacity motion, updated child pixels, premultiplied opacity and owned
image release; it passes at full and reduced atlas resolutions. Seven Python
tests pass, including unique-presentation deduplication and missing display
mapping. Full package/gallery gates have not yet run for this experiment.

## Remaining work

- Repeat presentation when a candidate resolves UI cost; measure sustained
  workflow energy before production admission. The first pair is mixed/worse.
- Validate first-use/UI cost, theme/RTL/custom button content, scale and blur
  ranges before enabling any production route. Keep fallback for unsupported
  or rapidly changing content, and do not silently clamp custom blur requests.
- Investigate small-group geometry/CPU submission work next; the foreground
  cache does not eliminate those costs.
- Continue real Navigation backdrop source ownership, diffuse-history reuse
  and bounded native filter graph experiments. None is completed by this
  foreground cache result.

Evidence: ../ios_reference/perf/2026-10-08-architecture. Frozen sources,
native timing/GPU traces, SDK/build records and phase hashes are retained.
