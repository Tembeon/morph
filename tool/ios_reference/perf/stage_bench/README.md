# Standalone glass stage benchmark

The AOT entry point is `example/lib/perf/glass_stage_bench.dart`. It uses
the existing morph renderer and Flutter dependencies. There is no test
binding, gesture driver, gallery, per-frame logging, or
per-frame layer traversal. The background repaints through a listenable;
moving glass uses a retained child under a transform. JSON is written once,
after collection, with an atomic rename. Optional native PNG readbacks run
after all timing windows and never contribute to their frame/GPU statistics.

## Quick run

From the morph checkout:

```sh
python3 tool/ios_reference/perf/stage_bench/run_android.py build --apk /tmp/morph-stage/stage.apk
python3 tool/ios_reference/perf/stage_bench/run_android.py run --apk /tmp/morph-stage/stage.apk --out /tmp/morph-stage/results --trace gpu
python3 tool/ios_reference/perf/stage_bench/summarize.py /tmp/morph-stage/results/stage-1.json --out /tmp/morph-stage/results/summary
```

The default matrix takes about 70 seconds on a 60 Hz device: seven cases,
three shuffled repeats, 600 ms warmup before each measured window, and
2400 ms measured per window. Every selected case also runs once before
measurement to warm its pipelines. The seed and actual order are recorded.
Different seeds can be built for independent launches.

Use `build --flutter flutter-beta` to select the separately installed beta
SDK without changing the normal `flutter` command. Build records save
the framework, engine, Dart versions and selected executable. Use separate
checkouts for stable and beta: their package configuration, native build
hooks and shader bundles must not be shared across a timed comparison.

The runner takes the Pixel lock itself and refuses an occupied lock or
active kernel GPU recorder. It backs up the installed single gallery APK,
restores it and opens the gallery on success, failure, or interruption.
It stops only its own recorder, restores the previous trace clock and
buffer size, and releases only its own lock. Restoration failures preserve
a recovery APK next to the report. A split-APK installation is rejected.
It never clears application data. The app requests portrait orientation.
Only one of GPU tracing, energy tracing, or no tracing is active per launch.

The default serial is Pixel 6a `26221JEGR12737`. `--serial` selects another
Android device, still serialized by the Pixel lock. Kernel GPU tracing
requires device/driver access to the existing GPU work-period interface;
use `--trace none` when unavailable. The runner waits for VIRTUAL-SKIN below
37 C when that sensor exists, with a five-minute timeout. `--cool-c 0`
disables the wait. Thermal and battery states, app UID, backend log, APK
hash and the build's source hash are saved with the report.

## Cases and controls

| Mode | Operation |
|---|---|
| `bare` | Background only; not a Material or morph-flat comparison |
| `capture` | Clipped identity color backdrop filter, using morph's existing seed |
| `blur` | Clipped stock mirror Gaussian, using morph's half-resolution sigma policy |
| `optics` | Production LiquidGlassLayer/matte/appearance with frost zero |
| `glass` | The same production layer with requested frost |

The raw capture/blur proxies use rectangular clips. Production glass uses
its own geometry, coverage, pixel buckets and shader/filter composition.
They are deliberately separate paths; subtraction does not isolate a
single native engine operation. Capture has a nonzero native layer count
and GPU work on the verified Pixel run, but its precise engine graph still
requires a frame capture or instrumented engine. A zero-sigma no-op is not
used as a capture proxy.

Build flags (`--define NAME=value`, repeatable):

| Flag | Default | Options |
|---|---|---|
| `STAGE_LAYOUTS` | `single` | Comma list: `single,cluster,spread,large` |
| `STAGE_MOTIONS` | `background` | Comma list: `background,glass,both` |
| `STAGE_PLANS` | `independent` | Comma list: `independent,shared,merged` |
| `STAGE_SIGMAS` | `2,10` | Distinct positive logical-pixel sigmas |
| `STAGE_MODES` | All five | Comma list of modes |
| `STAGE_CONTENT` | `tiles` | `tiles` or prelaid-out `text` |
| `STAGE_RUNS` | `3` | Positive repeat count |
| `STAGE_WARM_MS` | `600` | At least 100 ms; short values are smoke checks |
| `STAGE_SAMPLE_MS` | `2400` | At least 100 ms; four timings/window required |
| `STAGE_SEED` | `20261007` | Shuffle seed |
| `STAGE_SHOTS` | `false` | Native PNGs at phases -1, 0, 1 after collection |

`cluster` and `spread` have four equal-sized non-overlapping shapes and
the same total visible area. Their bounding rectangles differ. `shared`
keeps separate filters with one key; `merged` uses one production geometry
layer, or one union rectangle for the raw proxies. No intervening content
is present. These are R&D comparisons, not proof that grouping arbitrary
app surfaces preserves their image. Real glass-over-glass remains a
different backdrop dependency and is not represented by this first matrix.

An economical grouping experiment:

```sh
python3 tool/ios_reference/perf/stage_bench/run_android.py build --apk /tmp/morph-stage/grouping.apk --define STAGE_LAYOUTS=cluster,spread --define STAGE_PLANS=independent,shared,merged --define STAGE_MODES=bare,capture,optics,glass --define STAGE_SIGMAS=2
```

Run motion/content experiments separately rather than taking the entire
Cartesian product at once. `glass` motion leaves the backdrop static;
`both` moves both. These establish workloads for a future cache prototype;
this benchmark does not implement a new backdrop cache or renderer.

With `STAGE_SHOTS=true`, pass `--pull-artifacts` to keep the phase PNGs
next to the report. Compare filenames from that report's case list: the
runner preserves app data, so the device directory may also contain older
artifacts. Snapshot phases are recorded in `shot_phases`.

The same restoring runner can launch existing native audit APKs with
`--schema native`. Build them with `AUDIT_OUT` set to the stage directory
(`/sdcard/Android/data/dev.tembeon.morph_example/files/stage-bench`). Native
mode requires `liquid_available`, but each audit's own fidelity assertions
and completeness must also be checked. The stage reducer intentionally
requires the standalone schema and cannot reduce legacy audit timings.

## Output and calculations

`summary.json` keeps each repeat, median metrics, and paired within-repeat
stage differences. Negative differences remain visible. `cases.csv` is a
small plotting input. The source report stores raw frame timestamps and
durations, exact monotonic windows, case inputs, and a layer snapshot taken
outside each window (the last repeat's snapshot appears in metadata).

- Every rendered frame counts, including sub-0.3 ms frames. Percentiles use
  nearest rank. Frame selection uses vsync timestamps within the window,
  not the time a delayed batch of timings was delivered.
- UI/raster p50/p95/p99, means, and over-budget count are in milliseconds.
  A frame is over budget if either stage exceeds the display's reported
  period; the two durations are not summed. Vsync-gap slots are estimates
  of missing scheduled slots, not Android presentation-jank measurements.
- GPU active ms and Mcycles per rendered frame use the existing kernel
  work-period format. Only the exact app UID is included. Activity is
  prorated uniformly within an event; frequency is integrated across every
  transition. Missing frequency coverage makes cycles unavailable, not
  zero or a value extrapolated from a future frequency.
  The reducer accepts `.gpuwork.txt` and compressed `.gpuwork.txt.gz`.
- An absent GPU trace produces null GPU metrics. A present trace with
  missing app UID, lost events, invalid periods, or an uncovered window is
  rejected. Raster time is never substituted for GPU time.
- Visible area, union/visible ratio, native filter output area, actual
  production blur-pass sigmas and distinct capture keys are retained.
  Filter bounds and key counts are not captured-input dimensions, native
  pass counts, transient allocation bytes, bandwidth, or total app RAM.
- `capture - bare`, `blur - capture`, `optics - capture`, and
  `glass - optics` are topology-sensitive estimates. In particular,
  `optics - capture` includes matte and production-composition differences.
  Small-sigma shader softening also means not every frost has a Gaussian
  pass. The report records the actual production pass sigma.

## Energy and scheduled CPU time

Run a separate launch, reusing the same APK:

```sh
python3 tool/ios_reference/perf/stage_bench/run_android.py run --apk /tmp/morph-stage/stage.apk --out /tmp/morph-stage/energy --name stage-1 --trace energy
python3 tool/ios_reference/perf/energy.py /tmp/morph-stage/energy --json /tmp/morph-stage/energy/summary.json
```

This uses the existing Perfetto configuration and reducer (the latter
requires its existing `perfetto` Python dependency). Report windows and
scene median keys match the audit schema. ODPM measures whole-phone audit
power; scheduled CPU time is distinct from FrameTiming duration. Do not
equate GPU cycles with energy. Use repeated cooled launches and independent
seeds before selecting an optimization. The default smoke result is not a
production-scene acceptance benchmark.

## Verification

```sh
python3 -m unittest discover -s tool/ios_reference/perf/stage_bench -p 'test_*.py'
cd example
flutter test test/glass_stage_bench_test.dart
```

Tests protect the cheap-frame denominator, the separate-stage frame budget,
equal-area geometry, UID attribution, frequency transitions, incomplete
windows, negative differences, current HAL temperature selection, and
restoration after cleanup failure.
See `tool/audit/codex-stage-bench-report.md` for device smoke evidence.

## Real gallery Navigation

`example/lib/perf/navigation_stage_bench.dart` exercises the actual
GalleryApp, NavigationDemoPage, detail-page callbacks and shared chrome.
This is a separate fixture from the glass-only stage matrix above.

```sh
python3 tool/ios_reference/perf/stage_bench/run_android.py build --target lib/perf/navigation_stage_bench.dart --apk /tmp/morph-nav/nav.apk --define NAV_MODES=liquid,flat --define NAV_MOTIONS=enter,nested-push,nested-pop,toolbar --define NAV_RUNS=3 --define NAV_WARM_MS=500 --define NAV_SAMPLE_MS=800
python3 tool/ios_reference/perf/stage_bench/run_android.py run --apk /tmp/morph-nav/nav.apk --out /tmp/morph-nav/results --name gpu-1 --trace gpu
python3 tool/ios_reference/perf/stage_bench/summarize.py /tmp/morph-nav/results/gpu-1.json --out /tmp/morph-nav/results/summary
```

NAV_MODES selects liquid/flat. Flat changes appearance and is an attribution
baseline, not a candidate preserving the liquid image. NAV_MOTIONS selects
enter, nested-push, nested-pop, toolbar, steady, title and workflow. Actions invoke
the real callbacks once per window; scroll workloads use ScrollPosition's
animateTo, retaining normal scroll activity notifications. NAV_PAGES defaults
to navigation; home is intended for the two scroll workloads only.

NAV_WARM_ACTIONS defaults to true: every selected action runs once before
shuffled measured repeats, followed by a five-second pause. The first
liquid enter is recorded separately as cold_enter, after shader precache
and before action warmup. It is not a cold app-launch measurement. The
stand uses dark appearance and resets each case through a new GalleryApp.
Report windows use CLOCK_MONOTONIC; UI/raster statistics include every
produced frame. A settled action can stop producing frames before its
800 ms window ends. Inferred vsync gaps in that idle tail are not Android
presentation jank. GPU active work is divided by produced frames; power
includes the whole fixed window and device/background work.

NAV_PHASES optionally collects framework BUILD, LAYOUT, PAINT and
COMPOSITING aggregates per repeat. Default false avoids that observer's
cost. Root/nested aggregates and builds nested inside LayoutBuilder layout
are not disjoint timings to sum. A
layer census and liquid bounds/sigma snapshot run before each window,
not on every frame; they do not describe all in-flight route topology.

NAV_SHOTS defaults to false. When enabled, native snapshots follow all
timing collection. Action frames are 0, 1, 4, 10, 20, 34 and 48 at
16667 us increments; the binding supplies frozen raw handleBeginFrame
timestamps, including Ticker callbacks. NAV_REPEAT_REFERENCE adds a
second stock capture for render-repeatability checks. Scroll snapshots
use NAV_SHOT_OFFSETS, default 0,40,160,420,640. Use --pull-artifacts and
only the report's filenames; older files may remain in app data.

Navigation research and preserved experimental variants are documented in
`tool/audit/codex-navigation-report.md` and
`tool/ios_reference/perf/2026-10-07-navigation/`. A diagnostic CPU profiler
run is separate from unprofiled GPU/energy acceptance launches.

For more stable power attribution, workflow repeats five real actions:
enter Inbox, open Message 0, pop to Inbox, swap the toolbar, pop to home.
NAV_WORKFLOW_CYCLES defaults to five. NAV_SAMPLE_MS is the pause per
action, so five cycles at 800 ms give a roughly 20-second measured window.
The JSON includes actual windows and cycle counts. Workflow is opt-in,
requires NAV_PAGES=navigation and NAV_SHOTS=false, and its action mix
must not be labeled the energy of one isolated push/pop.

```sh
python3 tool/ios_reference/perf/stage_bench/run_android.py build --target lib/perf/navigation_stage_bench.dart --apk /tmp/morph-nav/workflow.apk --define NAV_MODES=liquid,flat --define NAV_MOTIONS=workflow --define NAV_RUNS=3 --define NAV_SAMPLE_MS=800 --define NAV_SHOTS=false
```
