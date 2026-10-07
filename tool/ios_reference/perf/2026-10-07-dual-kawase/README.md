# Bounded Dual Kawase experiments

Base: morph 620798e, Flutter 3.47.2, Pixel 6a Vulkan.
This is research evidence, not installed production renderer code.

Apply exactly one patch in an isolated checkout on exp/same-frame-backdrop:

- `direct-gpu.patch` reproduces the two corrected GPU/energy matrix launches.
  Its source hashes match both APK build records. The tracked example lock
  is included; use the calling checkout's pinned root pubspec.lock, whose
  hash is in the inputs manifest.
- `extended.patch` adds native-raster encoding and unchanged-source transform
  caching. It includes the final motion guard. Both patches are against the
  base checkout, not against each other.

Use the clone's restoring runner, which derives its root from its own path.
It acquires the Pixel lock and restores the original gallery on every exit.
Never acquire a second lock manually or use a device owned by another task.

Direct matrix build:

```sh
python3 tool/ios_reference/perf/stage_bench/run_android.py build --apk /tmp/dual.apk --define STAGE_MODES=gpu-bare,gpu-copy,gpu-gaussian,gpu-dual,gpu-dual3 --define STAGE_CONTENT=text --define STAGE_SHOTS=true --define STAGE_SHOT_PHASES=-1,0,0.0034013605,0.006802721,0.0102040816,0.01360544,1 --define STAGE_RUNS=3 --define STAGE_SEED=202610072 --define STAGE_WARM_MS=600 --define STAGE_SAMPLE_MS=2400
python3 tool/ios_reference/perf/stage_bench/run_android.py run --apk /tmp/dual.apk --out /tmp/dual-gpu --name text-1 --trace gpu --pull-artifacts
python3 tool/ios_reference/perf/stage_bench/run_android.py run --apk /tmp/dual.apk --out /tmp/dual-energy --name text-1 --trace energy
```

Repeat with seed 202610073, a separate APK and text-2. The defaults calibrate
small/large offsets at 0.75/0.756. `STAGE_FUSED_FINAL=false` restores the
extra full-resolution pass. `STAGE_IMAGE_SURFACE=true` exercises the SDK
surface-pool control; its native retained count is diagnostic, not a cap.
`STAGE_GPU_DIAGNOSTIC=true` records per-call wall-clock attribution outside
the report's collection-window boundary; keep it false for final trials.

The extended owned-source modes require single/large footprints, background
motion and the independent plan. The identity `gpu-copy` control separates
coordinate/sampling mistakes from kernel-shape differences. `gpu-dual3`
uses three levels at large sigma. `gpu-canvas` executes the same kernels
through native offscreen raster images; its source is never recaptured.
`gpu-retained` computes the reduced blur once for an immutable owned source,
then changes the final UV transform in the current frame. It is a cache-hit
workload, not a frequently-changing widget-backdrop benchmark.

Reduce reports with the standard stage summarizer and energy.py. The latter
needs Perfetto's existing Python dependency. Gzipped GPU traces are accepted
by summarize.py. Energy caches reproduce the summaries; raw system-wide Perfetto traces
are excluded from the repository, with original hashes and sizes recorded. pixels.py compares only case names and phases declared in
a report and needs numpy/Pillow; --edge adds the vertical edge response's
second moment. PNG hashes preserve native evidence identity; full native
captures are intentionally excluded from the compact bundle.

Directories `final-gpu` and `final-energy` are the corrected direct matrix.
`diagnostics` contains initial edge calibration, surface-pool and coordinate
checks. `canvas-smoke` is a diagnostic one-repeat comparison, not an energy
acceptance result. Invalid inverted-text and undersized-cache-guard runs
are excluded from the final acceptance tables.

See tool/audit/codex-dual-kawase-followup.md for all limitations and results.

Guarded cache reproduction: apply extended.patch, use the same build flags
with STAGE_MODES=gpu-bare,gpu-gaussian,gpu-retained and seeds 202610075/76.
Run GPU and energy separately as above. `retained-padded-gpu` and
`retained-padded-energy` contain the final two launches of each kind;
`retained-metrics.json` contains aggregate numbers. The motion guard is
included in these source hashes. No source content changes occur in this
cache-hit benchmark. See the report for energy variation and excluded costs.
