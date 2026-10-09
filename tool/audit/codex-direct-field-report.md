# Direct field and Android scheduling experiments (2026-10-08)

WIP, beta only, Pixel 6a Vulkan, actual dark Navigation, 60 Hz, arm64.
Profile and release evidence are labeled separately below.
All code paths are opt-in. No production adoption or weak-device guarantee.
Sources/evidence: ../ios_reference/perf/2026-10-08-architecture.

## Geometry experiments

MORPH_DIRECT_GEOMETRY evaluates one existing analytic primitive in the final
optical shader. It preserves the snapped matte coordinates, existing optical
equations and RGBA8 companding. The initial three-repeat launch gives liquid
push UI/raster p95 23.52/29.82 ms, GPU 6.104 ms versus control-2
23.60/24.39/6.192. Native chrome is identical; no robust timing win.
The archived binary predates a translation-uniform fix. Fused sampled fields
are not covered by this first path, so it does not address their CPU cost.

MORPH_DIRECT_FIELD wraps the existing RGBA32F node texture as a ui.Image and
reads it from the final runtime filter. This is Flutter GPU texture wrapping,
not a framebuffer capture or toImageSync replay. The same bilinear node
interpolation, optical equations, snapped pixels and byte companding are
retained. Uniform-appearance fields qualify; mixed materials retain the old
renderer. It removes the field-to-matte draw/target. Uploads still copy CPU
nodes on a command buffer and submit when samples change. CPU tracing and
field construction remain unchanged. There is no compute dispatch.

One three-repeat launch against control-2, medians in ms:

| Liquid action | Control UI p95 | Direct field UI p95 | Control raster p95 | Direct field raster p95 | Control GPU | Direct field GPU |
|---|---|---|---|---|---|---|
| enter | 15.02 | 11.74 | 15.55 | 14.28 | 5.070 | 5.086 |
| push | 23.60 | 18.33 | 24.39 | 27.34 | 6.192 | 6.261 |
| pop | 17.56 | 13.35 | 25.30 | 21.22 | 5.592 | 5.563 |
| toolbar | 8.61 | 7.85 | 13.31 | 14.74 | 4.407 | 4.414 |

Flat control also varies across launches, so repeat before assigning an exact
benefit. The direct-field counter advances during actual fused transitions;
settled bars have no field. Chrome max 2/255, whole-frame liquid max 10/255.

## Combined cache and direct field: presentation matters

A separate three-repeat FrameTimeline pair combines compact seven-row glyph
blur with direct-field shading. The unchanged control and combined candidate
are measured with the same trace mode. Each is one launch, not an ABBA pair.
Shader/geometry cache misses are included. GPU work is not collected here.

| Liquid action | Control UI / raster p95 ms | Combined UI / raster p95 ms | Control median missed slots | Combined median missed slots |
|---|---|---|---|---|
| enter | 13.93 / 18.30 | 12.33 / 10.77 | 11 | 13 |
| push | 22.18 / 34.17 | 23.48 / 13.17 | 16 | 21 |
| pop | 14.64 / 28.82 | 17.79 / 11.11 | 14 | 16 |
| toolbar | 7.77 / 12.69 | 10.25 / 12.21 | 8 | 8 |

Each window is 800 ms. Counts describe intervals between matched Impeller
buffer presentations, not FrameTiming's over-budget proxy. Longest combined
pop gaps reach 100-133 ms. A faster raster p95 has not improved presentation.
The glyph atlas creates extra offscreen source/blur work on misses and is
mounted only while sufficiently blurred. Investigate its creation/lifetime
and callback/submission costs; this trace does not yet prove an exclusive
cause. Combined chrome max is 7/255 on the frozen phase matrix.

## Opt-in Android performance hints

The benchmark-only client opens UI and raster Performance Hint sessions,
with a fixed 16,666,667 ns display target and actual FrameTiming durations.
It does not change affinity, clocks, game mode or engine code. Sessions and
temporary FFI memory are explicitly released; no hints run after collection.
The engine batches FrameTiming callbacks, so hints arrive late. Reports are
wall durations, not measured CPU running time or independently timed GPU work.
4297 frame reports are accepted with zero errors in the first launch.

Android's Performance Hint API lets the system choose clocks and core types
from target/actual duration. It also applies to demanding non-game apps:
https://source.android.com/docs/core/perf/performance-hint-api
https://developer.android.com/games/optimize/adpf

The installed beta engine source contains no ADPF integration. Flutter has
a separate draft opened Sep 10, 2026, not merged as of this check:
[API 35+ AWorkDuration draft](https://github.com/flutter/flutter/pull/192582).
It proposes reporting frame work directly from the engine and leaving target
headroom. Our Dart client uses an older duration API and delayed callbacks;
it is not that implementation. The 2024 exploratory issue was closed without
implementation: https://github.com/flutter/flutter/issues/155097.

One three-repeat launch, combined renderer without -> with hints:

| Liquid action | UI p95 ms | Raster p95 ms | Median missed slots |
|---|---|---|---|
| enter | 12.33 -> 5.54 | 10.77 -> 10.43 | 13 -> 4 |
| push | 23.48 -> 8.75 | 13.17 -> 11.80 | 21 -> 10 |
| pop | 17.79 -> 8.20 | 11.11 -> 12.85 | 16 -> 9 |
| toolbar | 10.25 -> 4.07 | 12.21 -> 9.30 | 8 -> 4 |

Longest pop gaps remain about 67 ms; push reaches 83-100 ms. This is a
substantial initial UI/cadence improvement, not uniform 60 FPS. The comparison
against live glyphs with hints is below; repeat presentation launches remain open.

## Live glyphs with hints

Direct field plus hints, without the glyph atlas, improves actual presentation
more than the combined atlas candidate in one three-repeat launch:

| Liquid action | UI / raster p95 ms | Median missed slots, live / atlas |
|---|---|---|
| enter | 6.01 / 9.40 | 1 / 4 |
| push | 8.32 / 18.07 | 3 / 10 |
| pop | 7.47 / 16.80 | 2 / 9 |
| toolbar | 3.71 / 8.96 | 1 / 4 |

Typical longest live-glyph push gaps are 50 ms, pop 33 ms; one repeat each
reaches 67 ms. Atlas push gaps reach 83-100 ms despite lower raster p95.
This is evidence against admitting the current atlas on raster duration alone.
The preferred candidate for the next probes uses live glyph blur. These are
callback-driven interactions; hardware touch boost is omitted.

## Sustained whole-phone power: control/candidate/candidate/control

Two launches per variant, three 20-second workflow repeats per launch, five
cycles per window (enter, nested push/pop, toolbar, exit). Same beta SDK,
liquid only, fixed seed, cooled starts and energy trace configuration. Candidate
uses direct field plus benchmark-only hints, with the atlas disabled.

| Variant | Power medians mW | UI p95 medians ms | Raster p95 medians ms | FrameTiming over-budget counts |
|---|---|---|---|---|
| control | 723.73 / 723.04 | 15.727 / 15.312 | 19.348 / 18.861 | 102 / 97 |
| field + hints | 820.54 / 829.54 | 9.492 / 8.776 | 14.276 / 14.493 | 41 / 41 |

Mean of launch medians: whole-phone power +14.1%, UI p95 -41.1%, raster p95
-24.7%. Energy per complete cycle is 2900 -> 3306 mJ, +14.0%. This tradeoff
fits the owner's smoothness-first research priority; it does not prove a
weak-device result, app-only energy, or uniformly smooth presentation.
Over-budget counts here are the FrameTiming proxy, not SurfaceFlinger misses.
Control was built before lightweight callback/capture timing instrumentation
was added to the candidate; the source difference is retained in snapshots.
Raw traces remain in /tmp/morph-architecture/results; archived JSON retains
rail/thread breakdowns and clock validation, and trace hashes identify inputs.

## Next experiment: coarse GPU optical field

MORPH_GPU_FUSION_FIELD is disabled by default. For owner-fused groups of at
most four circular rounded boxes it keeps the CPU silhouette trace and gives
the renderer a grid-relative analytic descriptor. A small RGBA32F render pass
computes the same four-point optical nodes without the full Dart optical loop
or node upload. Larger groups and other field owners retain sampled fields.
Both the direct final filter and the original matte path can consume it.

The shader explicitly ports liquid_field.dart's angular merge with carried
unit normals. It does not reuse sdf.glsl's different angular law. Gradients
remain central differences on the owner's 4-point grid; optical turn and
local thickness retain its separate polynomial contributor fold. A bounded
four-target ring waits three frames before overwrite and reuses descriptor
identity across translations. One extra GPU submission may offset CPU savings.
Initial native three-repeat pair, GPU-grid then CPU-grid, same source and
hints/direct-field configuration; only MORPH_GPU_FUSION_FIELD differs:

| Liquid action | CPU -> GPU grid UI p95 ms | Raster p95 ms | Whole-app active GPU ms/frame |
|---|---|---|---|
| enter | 5.28 -> 5.72 | 9.46 -> 9.68 | 5.087 -> 5.085 |
| push | 10.33 -> 10.24 | 21.66 -> 22.17 | 6.219 -> 6.310 |
| pop | 8.12 -> 7.76 | 16.39 -> 17.75 | 5.634 -> 5.609 |
| toolbar | 8.90 -> 3.26 | 8.50 -> 8.27 | 4.361 -> 4.377 |

Toolbar runs have zero GPU-field updates, so their UI difference is not this
path's effect. Actual fused transitions generate 19-40 coarse GPU fields per
window. Push includes mixed materials and uses the original matte after GPU
field generation; enter/pop also consume direct fields. No robust gain is
shown by this first pair. All liquid frozen phases differ by at most 2/255;
flat chrome is identical, with one isolated 55/255 body pixel in repeat noise.
Seven opt-in contour/translation tests, all 1407 default package tests and 21
gallery tests pass. Actual presentation repeats and admission remain open.

The next diagnostic records FrameTiming phase timestamps together with
sched_switch, sched_waking and native engine slices. It partitions each
build/raster interval into scheduled CPU time, ready-to-run delay, and other
non-running states; these cannot be inferred by subtracting active GPU work
from raster wall time. The probe adds tracing overhead and is kept separate
from clean performance runs.

## Frame CPU attribution

Exact FrameTiming build/raster timestamps are joined to Android sched_switch
and sched_waking through validated MONOTONIC/BOOTTIME clock snapshots. Each
phase has full thread-state coverage; native slice spans are inclusive.
Hints on/off use the same beta profile source with direct fields and live glyphs.
Median of three repeat p95 values, milliseconds:

| Liquid push | Hints off | Hints on |
|---|---|---|
| UI wall / scheduled CPU | 18.489 / 15.787 | 8.033 / 7.503 |
| Raster wall / scheduled CPU | 24.847 / 22.312 | 17.641 / 16.703 |
| Raster runnable delay | 0.615 | 0.436 |
| Raster not-runnable time | 2.216 | 1.436 |

These are marginal p95 statistics and cannot be summed. The slowest hints-on
push frame is 28.950 ms, including 26.979 ms scheduled CPU, 0.798 ms runnable
and 1.173 ms not-runnable time. This supports remaining raster CPU work as a
large bottleneck in this diagnostic, not a long GPU-fence wait. It does not
measure CPU cycles or certify instruction savings from hints.

Sustained rail traces also show changed placement/frequency. Control mid/big
average frequencies are about 618-641 / 544-547 MHz, hints 814-825 / 800-829.
Raster execution shifts from roughly 6.1 seconds on mid and 2.9 on big per
20-second control window to 2.6-2.8 on mid and 4.3-4.5 on big with hints.
These whole-window frequencies are not per-frame execution-weighted clocks.

The first traces reported systrace_parse_failure; scheduling-only summaries
exclude all native scopes. Raw-marker inspection of the app-only trace proves
all 2682 parse failures are C|pid|AllocatorVK|<fractional MB> counters. The
installed engine emits them in DebugTraceMemoryStatistics, enabled for profile
as well as debug. Perfetto's parser requires int64 counter values:
https://github.com/google/perfetto/blob/main/src/trace_processor/importers/systrace/systrace_parser.h
The --audit-float-counters reader permits scopes only when every error is
accounted for by this exact non-scope format; other errors still reject it.

App-only hints trace: slowest push frame 27.647 ms, SurfaceFrame::Encode
25.928 ms, including 23.467 ms scheduled CPU. LayerTree paint/preroll together
are under one millisecond in that frame. The slowest pop similarly has
20.385 ms in encode out of 21.635 ms. These nested spans must not be summed.
The uninstrumented portion of Impeller encoding needs deeper attribution.
Release evidence below is collected separately; profile durations above
are not assumed to be release cost.
The benchmark invokes actual gallery callbacks directly; it does not reproduce
the Android input boosts from physical touches. Also Pixel has big CPU cores:
these results cannot establish gains on a phone without comparable cores.

## Release feedback cadence and matching controls

Installed engine Shell batches FrameTiming callbacks over 100 ms in profile
and 1000 ms in release. The duration-only FFI hint client previously reported
all feedback through that delayed callback. NAV_HINTS_IMMEDIATE_UI records the
actual SchedulerBinding begin-to-draw/post-frame wall interval and reports UI
work immediately. Raster reports remain delayed; NAV_HINTS_UI_ONLY disables
the raster session. Fixed target remains 16,666,667 ns; no affinity/clocks or
headroom policy is changed. This is a benchmark-only path, not an engine ADPF
implementation or a measured CPU/GPU work duration split.

Two launches each, direct field and live glyphs on both sides; same source
apart from hint defines. Each cell is the median of three repeat p95 values,
or the median missed presentation slots over the 800 ms action windows.

| Action | Hints-off UI p95 ms, two launches | Immediate UI + delayed raster UI p95 | Hints-off raster p95 | Candidate raster p95 | Missed slots, off / candidate |
|---|---|---|---|---|---|
| enter | 12.893 / 12.376 | 5.080 / 5.502 | 14.052 / 13.179 | 11.988 / 13.449 | 8,9 / 4,3 |
| push | 27.335 / 27.154 | 9.508 / 9.378 | 28.990 / 25.935 | 18.779 / 21.992 | 17,16 / 4,8 |
| pop | 21.890 / 18.656 | 7.051 / 7.063 | 29.625 / 29.564 | 16.777 / 17.438 | 15,15 / 3,4 |
| toolbar | 8.900 / 8.512 | 3.719 / 3.916 | 14.796 / 13.532 | 14.763 / 14.661 | 8,8 / 3,3 |

This is repeated UI/presentation improvement; raster push still misses its
16.667 ms p95 target. One UI-only launch has push/pop raster 20.414/22.969 ms;
it does not isolate the raster session's causal benefit. Launch order was
candidate1, CPU-stack diagnostic, control1, candidate2, control2, not clean
ABBA. One candidate APK predates the benchmark release profileable manifest;
controls include it. Release power, real-touch boosts and weak-device tests
remain open. The earlier +14.1 percent whole-phone result applies to the
profile, batched-feedback candidate, not this new release variant.

## Release native CPU stack sampling

release-cpu-stack-1 uses direct field, immediate UI-only hints and live glyphs.
The gallery release manifest opts into profileable-by-shell sampling without
debuggable mode. Perfetto samples SW_CPU_CLOCK at 100 Hz; exact FrameTiming
raster intervals select samples. Official arm64-release engine symbols match
the installed APK's Build ID 95f51ced78a1b86bebc0a0c74e7e4e7907865db7.
Strict trace stats report no errors or data loss.

| Action | Selected raster CPU samples | QueueVK::Submit nearest engine caller | Other nearest caller counts |
|---|---|---|---|
| enter | 99 | 23 | RenderPassVK::Draw 11 |
| push | 98 | 35 | CreateRenderPass 5; CreateCommandBuffer 5 |
| pop | 123 | 28 | VmaAllocateVulkanMemory 12; CreateCommandBuffer 7 |
| toolbar | 84 | 20 | RenderPassVK::Draw 10 |

Push/pop unwind completely; enter and toolbar each have one invalid_elf
sample, retained in the summary. Counts do not measure exact milliseconds,
pass/submission counts, GPU waits or exclusively blur. Inclusive Gaussian
and RenderToTarget stacks are nested and must not be added. This diagnostic
supports reducing graph/materialization/resource work, while pass-level
attachment sizes and exclusive GPU timing remain open. Reader: cpu_stack.py.
Raw trace and official symbol ELF remain in /tmp with archived SHA identities.

## Admission and remaining scope

Beta analysis is clean. Existing focused glass/atlas tests pass (25), as do
18 Python reducer/numerical tests. Native phases exercise these shader paths; tester
uses the fake renderer and cannot certify Impeller behavior. Prior checks pass
1407 package tests, 21 gallery tests, seven opt-in contour tests, web Wasm,
macOS release and docs. New benchmark code has clean beta analysis. Energy is not inferred from
GPU time. No production flag is enabled.

Still open: full small-group fusion without CPU fields, real Navigation owned
backdrop/damage reuse, diffuse history with motion validation, bounded native
filter graph, cache-miss/first-use costs, sustained power/thermal behavior and
equivalent Material/weak-device comparisons. These probes do not complete the
architectural research objective.
