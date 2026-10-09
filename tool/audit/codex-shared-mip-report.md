# Shared prefilter producer experiment (2026-10-08)

**Research implementation may be incorrect or incomplete.** A result here
qualifies the tested code and setup; it does not rule out a corrected or
better implementation of the same idea.

Standalone release experiment on the authorized Flutter 3.49.0-0.2.pre beta,
Pixel 6a / Mali-G78 / Vulkan / 60 Hz. Source ownership is deliberately
controlled: this does not acquire the live Flutter compositor backdrop.
No production material, renderer option or quality default is enabled.

## Question and controlled implementation

Does producing one shared GPU pyramid pay off when multiple glass regions
consume it, including the producer's CPU recording, submissions and memory?
Does reuse beat grouped stock Gaussian, and how much of that win is simply
caching rather than a different blur kernel?

example/lib/perf/mip_stage_bench.dart owns a 1024x2048 RGBA8 texture. An opaque
checker, fine stripes and four distinct corner colors expose downsample phase
and orientation errors. The texture is displayed at one physical pixel per
texel. Rounded regions move horizontally; total visible area stays at 30%
for N=1,2,4,8,16. Region count changes without increasing visible area.

Modes:

- bare: source rendering/composition without blur.
- gaussian: N independent stock BackdropFilters, sigma 16 physical pixels.
- grouped: the same stock filters sharing one BackdropKey; regions do not
  overlap, so this is the relevant existing shared-filter control.
- box: five successive exact 2:1 bilinear downsample passes.
- tent: five passes using four bilinear taps per pixel, implementing separable
  [1,3,3,1]/8 weights at exact 2:1 sizes.
- cached: one stock Gaussian applied to the already owned source, then reused
  while the regions move. Available only for unchanged source content.

The fitted LODs are box 4.9526399109241535 and tent 4.688035443343443. These
are numerical PSF fits, not an approved appearance policy. The consumer mixes
the two corresponding separate textures with bilinear sampling. Separate
levels avoid attachment feedback and unsupported higher-mip texture copies.
This producer does not rely on an unavailable public generateMipmap method.

fresh changes the source and rebuilds the selected pyramid every frame.
reuse keeps content identical and moves the regions in the current frame;
there is no history frame delay in this fixture. It does not validate reuse
across scrolling, reveal, disocclusion or arbitrary animated widgets.

The cached control filters an owned texture once through Picture.toImage,
not a captured widget tree or a borrowed compositor frame. Its initial wait
is reported separately and excluded from warmed steady-state windows. It
cannot justify an every-frame toImage path for live production backdrops.

## Resource correction before measurement

The first diagnostic used GpuImageSurface plus Texture.fromImage wrappers
for successive levels. Retained pool bytes grew toward 1 GiB; fresh UI p95
was approximately 30-38 ms. Those results are rejected as an implementation
failure, not evidence against the blur algorithm. This does not establish a
general engine leak: native references, wrapper lifetimes and GC prevent
the intended reuse in this experimental usage.

The corrected producer allocates four fixed ordinary textures per extent,
retires them after three scene epochs and producer completion, and never
falls back to allocating extra targets. Source uniform buffers return only
after their submission completes. Epochs follow frame timestamps, not paint
call count. The same Vulkan GPU queue orders producer writes and Flutter
reads. This follows the existing renderer's retirement contract; other
backends and stressed scene backlogs remain unverified.

The baseline fixed texture floor is 53.3125 MiB, including the base ring and BOTH
kernel families for all cohorts. The cached Gaussian adds 8 MiB once ready.
These byte counts exclude alignment, allocator overhead, uniforms, native
filter intermediates and total process RSS. A production implementation
must crop sources and avoid retaining unused families; this fixture is not
a weak-phone memory budget.

Each producer pass uses a separate public GPU command buffer. The installed
lib/gpu/command_buffer.cc submits directly to the native queue and calls
DisposeThreadLocalCachedResources after submission; Vulkan clears its cached
descriptor pool and command-pool recycler there. Impeller's separate pending
command-buffer batching does not automatically batch these public calls.
The benchmark counts public submit calls, not measured native driver calls.
It does not try multiple open render encoders in one buffer: that requires
backend-specific validation and an explicit encoder-lifetime design.

## Measurement protocol

Full sweep: three shuffled repeats, seed 20261008, 300 ms warm-up and 1200 ms
sample per case. All modes/counts/update patterns are prewarmed first.
FrameTiming callbacks drain after timing. Frozen phase-zero PNGs are read
only afterwards and are never used to infer presentation.

GPU work is kernel gpu_work_period activity attributed to the exact app UID.
The reducer includes per-repeat GPU frequency-weighted cycles where coverage
exists. UI time, raster time and GPU activity overlap; they are not additive.
Actual Android buffer presentation is measured in a separate FrameTimeline
run with three repeats for N=4 and N=16, independent/grouped Gaussian, tent
and cached Gaussian. The same release sources are used; defines select the
subset and disable shots. Kernel GPU tracing and FrameTimeline are separate
launches, not simultaneous paired samples.

## Baseline repeated results

One release GPU launch, three shuffled repeats per case. Values below are
medians of the per-repeat active GPU ms per measured Flutter frame. The two
presentation launches are independently repeated three times per case.

| Regions | Fresh independent Gaussian | Fresh grouped Gaussian | Fresh tent | Reuse grouped Gaussian | Reuse tent | Reuse cached Gaussian |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 3.377 | 3.381 | 2.817 | 2.931 | 1.413 | 1.453 |
| 2 | 4.284 | 3.136 | 2.809 | 2.723 | 1.436 | 1.430 |
| 4 | 5.810 | 3.162 | 2.829 | 2.686 | 1.458 | 1.453 |
| 8 | 8.919 | 3.170 | 2.848 | 2.790 | 1.493 | 1.518 |
| 16 | 13.588 | 3.232 | 2.879 | 2.752 | 1.505 | 1.580 |

Tent reduces total app GPU activity versus grouped Gaussian by 10-17% fresh
and 45-52% unchanged. Frequency-weighted cycle ratios agree. The independent
Gaussian scaling is not the relevant final admission test: grouping already
removes most of that count-dependent cost.

Fresh tent UI p95 is 10.1-11.8 ms, versus grouped Gaussian 3.8-4.7 ms.
Fresh tent's producer recording averages approximately 6.0-6.5 ms/frame;
six public submissions include one source and five downsample passes.
Reuse records about 0.007-0.008 ms/frame and submits no producer passes in
the sample windows. Source uniform allocations are zero in those warmed
windows. No extra texture targets are allocated; the pool remains
61.3125 MiB including the shared cached-Gaussian control.

Caching stock Gaussian costs essentially the same as reusing tent here.
Its initial asynchronous filter wait is 11.463 ms in this launch. This is
one warmed-library creation, not a complete cold entry/first-frame metric.
Initial pool allocation and pipeline warm-up remain outside steady-state
windows. This experiment does not prove that cold Navigation entry is faster.

Actual missed display presentation slots, summed across each launch's three
1200 ms windows (roughly 216 possible presentations; boundary gaps excluded):

| Regions/update | Independent Gaussian, launches 1/2 | Grouped Gaussian, launches 1/2 | Tent, launches 1/2 |
|---|---:|---:|---:|
| 4/fresh | 9 / 24 | 0 / 1 | 5 / 5 |
| 16/fresh | 70 / 60 | 1 / 0 | 6 / 15 |
| 4/reuse | 5 / 3 | 0 / 0 | 0 / 0 |
| 16/reuse | 54 / 47 | 0 / 0 | 0 / 0 |

Cached Gaussian also misses zero slots in all measured reuse windows.
Fresh tent therefore fails the current smoothness admission against grouped
Gaussian despite using less GPU. Reuse offers GPU headroom; both grouped
Gaussian and cached paths already saturate this fixture's 60 Hz display.
There is no measured FPS increase beyond that cap and no Navigation result.

## Quality checks

Frozen phase-zero generator checks match box and tent within 2/255 in the
rectangular interiors. Outside expanded region bounds the difference from
the bare source is exactly zero. The four distinct corners also validate
orientation. This establishes the implemented generator, not Gaussian parity.

Against the independent native Gaussian reference, tent interior p95 error
is 9-10/255 and maximum 25/255; box p95 is 13-15 and maximum 54. Grouped
Gaussian differs by maximum 7. Cached stock Gaussian differs by maximum 15
and p95 7: filtering a full owned texture has different bounds/coordinate
materialization from individual BackdropFilters. A stock kernel alone does
not guarantee identical output under a different graph.

Quality statistics exclude rounded AA boundaries with a 16-pixel interior
inset, and exclude expanded whole-region bounds for background checks.
They do not cover motion shimmer, disocclusion, refraction, glints, text,
overlapping lenses, transparent sources, Apple-reference fidelity or real
production backdrop capture. Approximate box blur is not admitted.

## Second optimization: fewer producer passes

The first four tent levels can be expressed as one separable 46-source-texel
kernel. Two passes (horizontal into 64x2048, vertical into 64x128) produce
level four; one ordinary tent pass produces level five at 32x64. Each wide
axis uses 23 paired bilinear taps. The fitted LOD and consumer stay the same.
Before RGBA8 rounding, the interior kernel matches the original four-level
cascade; a numerical random-signal test verifies this independently.

This `wide` mode uses three downsample submissions instead of five, while
preserving separate encoders and texture retirement. It specializes to the
fixed sigma-16 experiment's requested levels four/five; it is not a complete
arbitrary-radius mip-chain generator. Earlier repeated evidence predates
this mode. Its separate matched cohort includes original tent and grouped
Gaussian controls, with the same source, count, area and update patterns.

Matched GPU cohort, three repeats, medians of per-repeat metrics:

| Regions | Mode | Producer CPU mean, ms | UI p95, ms | Raster p95, ms | App GPU active, ms |
|---|---|---:|---:|---:|---:|
| 4 | grouped | 2.008 | 4.165 | 4.826 | 3.153 |
| 4 | tent | 5.836 | 9.686 | 2.854 | 2.806 |
| 4 | wide | 5.450 | 10.679 | 2.915 | 2.929 |
| 16 | grouped | 1.931 | 4.590 | 6.037 | 3.183 |
| 16 | tent | 6.205 | 11.354 | 3.656 | 2.868 |
| 16 | wide | 4.793 | 10.001 | 3.919 | 3.010 |

Wide reduces producer CPU about 23% at N=16; N=4 has a smaller/noisy effect.
It increases GPU activity 4-5% versus tent, remaining 5-7% below grouped
Gaussian. These results do not make submission count alone an exclusive
CPU attribution; pass extents, shader work and driver behavior also change.

Two separate release presentation launches, three repeats per case:

| Regions/update | Grouped missed slots, launches 1/2 | Tent missed slots, launches 1/2 | Wide missed slots, launches 1/2 |
|---|---:|---:|---:|
| 4/fresh | 1 / 0 | 11 / 12 | 1 / 4 |
| 16/fresh | 0 / 0 | 9 / 5 | 0 / 2 |
| 4/reuse | 1 / 0 | 0 / 0 | 1 / 0 |
| 16/reuse | 0 / 0 | 0 / 0 | 0 / 0 |

Wide improves actual fresh cadence versus the original five-pass tent in
both launches, but does not beat grouped Gaussian. It is a better owned-source
prototype for this fixed-radius case, not a production replacement.

Wide native output matches its independent collapsed/rounded CPU model within
1/255. The original tent output also differs by maximum 1/255 in tested
interiors. Against Gaussian it remains approximate: p95 9-11, max 25/255.
Motion, transparent edges and other backends remain open.

The wide generator's own four-target surfaces use 2.15625 MiB, versus
10.65625 MiB for the original five-level family. This saves intermediates by
producing only the requested levels. The whole matched fixture holds all
three families at 55.46875 MiB; it excludes cached Gaussian. The current
default fixture with the cached control therefore holds 63.46875 MiB.
Do not interpret these all-cohort pools as a production-required footprint.
Producer-only scratch lifetimes and cropped groups are the next memory work.

## Interpretation and next production questions

The largest reusable win is avoiding regeneration for unchanged content;
it does not require a different kernel. First test source ownership,
invalidation, reveal/damage and small spatial groups on real Navigation.
Keep exact contour/foreground/optics resolution. An owned blur result needs
an optical consumer; Flutter's composed single-input filter chain cannot
automatically accept an unrelated shared texture as its second input.

Current Navigation capsule blur sigma is zero, and earlier release CPU
stacks implicate native submission/allocation as well as remaining glyph/edge
filters. The blur-only fixture cannot explain all current jank. Reducing
native graph work, avoiding repeated capture/materialization and measuring
cold entry remain production priorities. A local engine extension is only
justified after the controlled owned-source graph beats the existing path
in full scene presentation and quality.

Evidence: ../ios_reference/perf/2026-10-08-architecture/shared-mip. Exact
build/SDK/APK hashes, complete report-owned shots, generator statistics,
source archives, kernel trace and both presentation traces are retained.
The final asset path is perf_assets/mip.shaderbundle, surviving flutter clean;
the baseline binaries used build/perf-shaders or the identical moved bundle.
The final source changes only the report's pool-description string after the
wide measurements; the measured source snapshots preserve the original text.
Release builds and native runs succeed, final analysis is clean, and all
20 Python reducer/numerical tests pass. There are no package-library edits
in this experiment. Explicit-LOD's known SkSL build warning belongs to the
separate Impeller-only API probe; native Vulkan shaders load successfully.

## Reproduce

From the Morph repository, compile the example-only bundle first. The command
below runs the current complete fixture, including wide. Exact measured
baseline/wide selections and sources are retained in their build records:

```sh
python3 tool/ios_reference/perf/stage_bench/compile_mip_bundle.py \
  --sdk /Users/tembeon/.local/share/flutter-beta
python3 tool/ios_reference/perf/stage_bench/run_android.py build \
  --flutter flutter-beta --mode release --target lib/perf/mip_stage_bench.dart \
  --apk /tmp/morph-mip.apk \
  --define MIP_RUNS=3 --define MIP_COUNTS=1,2,4,8,16 \
  --define MIP_MODES=bare,gaussian,grouped,box,tent,wide,cached \
  --define MIP_UPDATES=fresh,reuse --define MIP_SAMPLE_MS=1200 \
  --define MIP_WARM_MS=300 --define MIP_SHOTS=true
python3 tool/ios_reference/perf/stage_bench/run_android.py run \
  --apk /tmp/morph-mip.apk --out /tmp/morph-mip-results --name mip-1 \
  --trace gpu --pull-artifacts --leave-installed
python3 tool/ios_reference/perf/stage_bench/summarize.py \
  /tmp/morph-mip-results/mip-1.json --out /tmp/morph-mip-summary
python3 tool/ios_reference/perf/stage_bench/mip_quality.py \
  /tmp/morph-mip-results/mip-1.json /tmp/morph-mip-results/mip-1.artifacts \
  --out /tmp/morph-mip-quality.json
```

For presentation, rebuild with counts 4,16; modes gaussian,grouped,tent,cached;
shots false. Run with --trace presentation and reduce using presentation.py
with the perfetto Python package. Preserve exact APK/build/source hashes and
selected report-owned PNGs; pulled directories can contain unrelated older
fixtures. All native runs leave the benchmark installed, per owner workflow.
