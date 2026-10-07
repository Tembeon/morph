# Standalone glass stage benchmark (2026-10-07)

The requested lightweight R&D stand is implemented. This is measurement
tooling, not a rendering optimization. Production library code, dependencies,
glass appearance and tier policy are unchanged.

## Implementation

`example/lib/perf/glass_stage_bench.dart` is a standalone profile/release
entry point using the current production renderer. It has no integration
test binding, gallery, gesture driver, per-frame log, image readback or
per-frame layer census. A painter listenable moves the background; a
retained child under a transform moves the glass. Text is laid out before
measurement. Layer snapshots run outside the measured windows. The report
is serialized once and atomically renamed after timings have drained.

Five paths compare background only, identity backdrop seed, stock Gaussian,
production optics without frost, and full production glass. Layouts include
one strip, a large surface, and four equal-area surfaces either clustered
or spread. Independent filters, shared capture keys, and merged production
geometry can be compared. Background-only, glass-only and simultaneous
motion plus tiles/text establish workloads for later same-frame/cache work.
No new cache or alternative blur is implemented here.

The default is seven cases with three shuffled repeats, warmed once per
case and again before each measured window. A default launch takes about
70 seconds at 60 Hz. Matrix flags avoid rebuilding a gallery or running a
large Cartesian product for each question. Usage and calculations:
`tool/ios_reference/perf/stage_bench/README.md`.

The Python runner/reducer use only the standard library. GPU attribution
uses the existing kernel work-period interface and exact application UID.
Frequency transitions inside a period are integrated; unknown frequency
coverage produces null cycles. All rendered timings count, including very
cheap frames. Missing traces produce null GPU cost. Lost events, invalid
periods, missing UID and windows without app GPU work reject the trace.
Within-repeat stage differences preserve negative values.

Android launches take the device lock, back up and restore the installed
gallery APK without clearing data, and restore owned tracing settings on
success, failure or interruption. Active GPU recorders are rejected. Every
cleanup action is attempted even if an earlier one fails; failed restoration
preserves a recovery APK beside the result. Energy uses a separate Perfetto
launch and the existing energy.py reducer.

## Pixel smoke evidence

Base source HEAD: `bdab3cb9a47e58c68b46b9046d0d3d9781aae764`.
The first default/matrix builds identify the entry point by SHA-256:
`b573665f08a2280da66f97bb422e8495d5f91acc39d17a5454404272a9a400d8`.
Pixel 6a, serial 26221JEGR12737, Impeller Vulkan verified in the app PID's
log, profile arm64 APK, portrait, 1080x2400, DPR 2.625, reported 60 Hz.
Thermal/battery notes are retained with each launch. These are functional
smoke launches, not cooled multi-launch optimization acceptance.

Default launch: 600 ms warm / 2400 ms sample, three repeats, seed 20261007,
single surface, moving tiled background, independent capture. Every case
has native liquid available and 143-144 timings per window. Median counts
are 144; every case has median over-budget count and inferred vsync gaps 0.

| Path | UI p95 ms | Raster p95 ms | GPU active ms/frame | Mcycles/frame |
|---|---:|---:|---:|---:|
| bare background | 4.32 | 7.39 | 0.829 | 0.360 |
| identity capture proxy | 4.75 | 8.95 | 1.733 | 0.752 |
| raw blur, requested sigma 2 | 6.80 | 9.40 | 2.121 | 0.921 |
| raw blur, sigma 10 | 4.52 | 9.35 | 2.140 | 0.929 |
| production optics, frost 0 | 4.46 | 8.84 | 2.179 | 0.946 |
| production glass, requested frost 2 | 6.46 | 9.81 | 3.570 | 1.550 |
| production glass, frost 10 | 4.68 | 9.77 | 3.123 | 1.355 |

Medians are computed per metric over repeats. They are not additive.
Paired GPU differences: capture minus bare 0.881 ms; raw blur minus capture
0.426/0.407 ms for sigma 2/10; optics minus capture 0.444 ms; full glass
minus optics 1.393/0.947 ms. The raw-blur difference is smaller than blur
added to the production path, demonstrating why one cannot substitute it
for the production composition cost. The current half-resolution policy
raises production frost 2 to actual pass sigma 2.1731692520167614 here;
frost 10 remains 10. The no-frost path records pass sigma 0.

The final source also averages the two middle values for even repeat counts
in energy.py-compatible median fields. Three-repeat results above are
unaffected. Each build retains its own source hash.

Expanded functional launch: cluster/spread x glass/both motion x
independent/shared/merged x capture/blur/glass, text backdrop, sigma 2,
one repeat, 300 ms warm / 600 ms sample. All 36 cases report 36-37 timings
and valid GPU coverage. All three modes have the expected native layer/key
counts: independent 4/4, shared 4/1, merged 1/1. These short windows verify
the controls and accounting; they do not select a grouping optimization.

Final-source large-layout smoke: all five modes, glass-only motion over
a static tiled backdrop, two repeats, 200 ms warm / 600 ms sample, tracing
disabled. Each window has 36 frames; even-count median fields were checked
against the average of the middle values. Reduction correctly reports
GPU unavailable. Build and timing evidence is in `large/`.

Evidence: `tool/ios_reference/perf/2026-10-07-stage-bench/`. JSON reports,
raw timings, build/thermal/backend notes, CSVs, per-repeat summaries and
compressed GPU events are retained. GPU events are filtered to app work
overlapping the measured envelope plus every relevant frequency transition
and the preceding frequency; reduction was checked identical to the full
trace. Full/filtered hashes and selection are in `evidence.json`. Both
compressed traces together occupy about 1.2 MB; APKs are not committed.

Energy collector smoke: a separate default-APK launch completed with
Perfetto. The existing energy.py processed 21 windows with 14 ODPM rails,
monotonic-to-trace clock conversion and two aggregated raster threads.
Its per-window cache, FrameTiming report, launch summary and device/build
notes are in the evidence directory's `energy/`. The 24 MB trace is not
committed; its SHA-256 and reducer SHA are retained. The cached reduction
can be reprinted, but recomputing counters requires a fresh trace. Whole-
phone power varies enough that this one launch must not rank the modes.
This verifies collection/schema compatibility, not an energy saving.

The first energy attempt failed with configuration supplied by a file path.
The runner now pipes it through stdin, as the existing
energy runner does; the repeat succeeded. Cleanup after the failed attempt
restored the gallery and released the lock. Cooldown now prefers the final
HAL VIRTUAL-SKIN reading over a stale earlier cached reading, and writes
skin values in the existing energy reducer's format on future launches.

After the final launch, adb SHA-256 of the installed gallery APK matches
the original `46067271b0547de0bc092c52052f1986b1391d36412c350fc1e6c63ede3bd3c3`.
GPU events/tracing are off, the previous boot trace clock and 7 KB buffer
were restored, no owned Perfetto PID remains, the Pixel lock is gone and
the gallery is foreground. Observed restoration is in `restoration.json`.

## Interpretation and next experiments

Differences are comparative proxies: the paths change clip geometry and
native composition. Capture is an identity color seed, not an engine-
verified isolated copy pass. Optics includes matte generation, coverage,
shader filtering and composition. GPU active work is not presentation
latency; raster duration is not GPU time. Inferred vsync slots do not
replace Android presentation-jank measurements.

Filter output bounds, visible area and distinct capture keys are recorded,
but do not measure capture input dimensions, pass count, bandwidth,
transient GPU allocation or total process RAM. Exact pass attribution
still needs an instrumented engine or native frame capture. No pixel
equivalence between the synthetic proxy paths is claimed. Grouping needs
fidelity checks with actual intervening content and glass-over-glass.

Use this stand first to narrow shared versus merged capture by surface
spacing, then to evaluate bounded same-frame replay or correctly invalidated
static-backdrop reuse. Add alternatives behind explicit benchmark modes,
compare the same production optics, interleave cooled launches and measure
energy separately. Accept changes only with production-scene fidelity,
power and frame/GPU verification; a Pixel smoke run does not prove weak
Android support or proximity to Material's cost.

## Verification

- `dart format lib test example/lib example/test`: 307 files, no changes.
- `flutter analyze`: zero issues.
- `flutter test`: 1398 passed.
- `cd example && flutter test`: 21 passed, including three stand tests.
- Python unittest: six passed (frequency transitions, absent initial
  frequency, exact UID/compressed trace, missing GPU/negative differences,
  frame-window validation, HAL temperature selection and cleanup continuation).
- `dart doc --dry-run`: zero warnings and zero errors.
- Pixel profile builds and default GPU / expanded GPU / energy launches
  completed, with original gallery APK restoration and no owned recorder
  remaining. The large-layout launch also completed and restored the gallery.
