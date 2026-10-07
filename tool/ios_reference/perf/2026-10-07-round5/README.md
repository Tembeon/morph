# Round 5 optimization evidence

Source base: c80a905, Pixel 6a, Impeller Vulkan, portrait, 60 Hz.
See tool/audit/codex-round5-optimization.md for verdicts and limits.
Each launch used stage_bench/run_android.py, with its Pixel lock, cooled
start, single recorder and original gallery restoration. Energy tracing
was separate from GPU tracing. Native readbacks followed all timed windows.

## Reductions

GPU reports preserve exact monotonic windows, UID and native work events.
Compressed traces keep app GPU 0 work overlapping the measured envelope,
all frequency transitions within it, and the last preceding frequency.
Every retained reduction was checked equal to the original unfiltered
trace window by window. evidence.json records original trace hashes.
Stage reports retain every frame, including cheap frames. Legacy field
reports use the existing audit's active-frame denominator; do not compare
it numerically with the standalone denominator.

Recompute standalone metrics from the repository root:

    python3 tool/ios_reference/perf/stage_bench/summarize.py \
      tool/ios_reference/perf/2026-10-07-round5/grouping/gpu/groups-1.json \
      tool/ios_reference/perf/2026-10-07-round5/grouping/gpu/groups-2.json \
      --out /tmp/morph-r5-grouping

field/reduce_field.py recomputes the field audit's frame/GPU metrics.
energy.py can reprint the saved rail/scheduler caches with its existing
Perfetto dependency. Raw APKs and large Perfetto traces are omitted;
original SHA-256 values and build flags are retained. Re-extracting
scheduler or rail counters independently requires a new native trace.

## Prototype reproduction

Experimental sources are patches against c80a905; they do not add a
production dependency or a new public backdrop API. Apply each in its own
checkout. The replay patch belongs to exp/same-frame-backdrop.
Download Haze 0.5.0's official archive into a sibling haze directory and
preserve its included BSD-3-Clause license. Copy baseline lockfiles before
resolving its local dependency. Build flags are in each .build.json.
Use AUDIT_OUT=/sdcard/Android/data/dev.tembeon.morph_example/files/stage-bench
for the restoring runner. Do not use snapshots from an unrelated case:
the runner preserves app data, so old PNGs may remain in that directory.

Parity summaries compare decoded RGBA pixels and retain PNG hashes.
They cover explicit fixed phases; they are not full presentation-latency,
glass-over-glass, texture, platform-view, or weak-phone acceptance tests.
RGBA8 pool capacities exclude driver padding, field textures, engine
captures, retained scenes and garbage-collector finalization delay.

The replay patch's matrix modes consume the existing native backdrop and
use a one-time 1x1 sampler placeholder before timing. They never capture
the widget scene per frame. matrix-probe encodes actual input width/1080
and height/2400 into red/green, subject to 8-bit rounding. Decode the
last downsample input, not the final framebuffer dimensions. Matrix
resamples and kernel passes are separate; this is not an optimal fused
pyramid. Original image-pyramid smoke runs used nearest sampler defaults
and unmatched blur widths; retain them as diagnostics, not valid kernel
performance or fidelity comparisons. The current patch explicitly uses
bilinear sampling. Tentative sigma scale controls are laboratory values
only; the corresponding calibrated image APK was not launched.

reduce_pixels.py compares native PNGs supplied from a new run (the saved
reports contain hashes, not the PNG payloads). calibrate_edge.py reads a
Pixel 6a horizontal edge profile at y=1104 and x=320:760, and reports
centroid and second moment of its nonnegative derivative. It is an edge
width diagnostic, not a perceptual-equivalence or temporal-motion judge.
