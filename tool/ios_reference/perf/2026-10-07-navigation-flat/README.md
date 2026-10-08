# Navigation without glass: attribution, 2026-10-07

Read `tool/audit/codex-navigation-flat-report.md` for the conclusions.
All APKs use 7170939, Flutter 3.47.2 / Dart 3.13.2, Pixel 6a,
1080 x 2400, DPR 2.625, 60 Hz, Vulkan/Impeller, profile AOT and dark
appearance. Flat mode preserves the actual gallery, route callbacks,
bar motion and glyph effects. Every case's at-rest census is zero
BackdropFilter layers. These are visible diagnostic ablations, never
production improvements or approved fidelity changes.

Two cooled launches of each diagnostic binary, three shuffled repeats
per action, action prewarm, 500 ms post-mount warmup, 800 ms collection.
Phase collection, screenshots and CPU profiler are off in GPU launches.
The stand retains its production root snapshot boundary and uses a
KeyedSubtree page locator, not an additional Inbox repaint boundary.
GPU work is attributed by the exact application UID and monotonic windows,
then divided by produced frames. UI/raster/GPU overlap and are not summed.
Settled tails and inferred vsync gaps are not SurfaceFlinger jank.
The separate liquid cold_enter record produced by enter cases is not used
for flat attribution; all reported action windows are action-prewarmed.
No power or fidelity acceptance is claimed for deliberately changed images.

Variants:

- `flat`: unchanged production baseline.
- `no-glyphs`: zero opacity around button content, before its original
  blur/scale/presence wrappers; dimensions, motion and layout are retained.
  The inline title, page text and capsule shapes remain.
- `no-fusion`: the plain union of the same capsule rectangles replaces
  the fused contour; it skips field calculation and changes the neck.
- `no-body`: zero opacity around the shared scaffold body; page layout,
  scroll controllers and route motion remain.
- `still-body`: zero route translation; callbacks and animations keep
  advancing. The underlying page is more occluded, so this is not a pure
  translate-instruction microbenchmark.
- `no-blur`: only button ImageFiltered wrappers are omitted.
- `no-scale`: only the button content scale is set to 1.
- `no-opacity`: button presence opacity is set to 1. It also draws
  zero-presence glyphs, so it cannot isolate the cost of Opacity itself.

`ablations.patch` reconstructs the first diagnostic binary; its original
entrypoint hash is verified against ablations.build.json. `diagnostics.patch`
and `sources/` preserve the later glyph diagnostic build. APK hashes and
exact defines are in build records. Large binaries and raw PNGs are not
committed. Lockfiles and manifests in `inputs/` pin package versions.

Example reproduction, on a disposable checkout:

```sh
git clone --no-hardlinks /path/to/morph /tmp/morph-flat-repro
cd /tmp/morph-flat-repro
git checkout 7170939
# EVIDENCE is this directory's absolute path.
cp "$EVIDENCE/inputs/pubspec.lock" pubspec.lock
cp "$EVIDENCE/inputs/example/pubspec.lock" example/pubspec.lock
flutter pub get
git apply "$EVIDENCE/ablations.patch"
python3 tool/ios_reference/perf/stage_bench/run_android.py build --target lib/perf/navigation_stage_bench.dart --apk /tmp/morph-flat.apk --define NAV_MODES=flat,no-glyphs,no-fusion,no-body,still-body --define NAV_MOTIONS=enter,nested-push,nested-pop,toolbar --define NAV_RUNS=3 --define NAV_WARM_MS=500 --define NAV_SAMPLE_MS=800
python3 tool/ios_reference/perf/stage_bench/run_android.py run --apk /tmp/morph-flat.apk --out /tmp/morph-flat-results --name gpu-1 --trace gpu
```

For the glyph matrix use diagnostics.patch on a fresh checkout and the
exact defines in glyphs.build.json. The runner owns the Pixel lock and
restores the previously installed release gallery on every exit. Inspect
the lock before using other phone tools; never remove another owner's lock.

`cpu-flat` is a separate three-repeat diagnostic launch from unmodified
main. The own-isolate CPU sample period is 1 ms; all twelve action windows
have samples. `cpu-windows.json` comes from the previous evidence's
reduce_cpu.py. The end-of-run VM timeline ring covers only the last
push/pop windows: `timeline-windows.json` explicitly counts coverage and
must not be extrapolated to all repeats. Named durations are inclusive.
The initial wrapper's setVMTimelineFlags request was rejected for quoting
its list values, after CPU profiling had been enabled. Existing streams
Dart/Embedder/GC/Microtask remained enabled, and later timeline/CPU reads
succeeded. The error is preserved; this run is excluded from GPU acceptance.
`profile-measured.py.txt` preserves that exact diagnostic wrapper with
its original host path. Change the path when reproducing; omit the failed
flags call or use `[Dart,Embedder,GC]` rather than a JSON-quoted list.

Reduce successful reports with the existing stage_bench/summarize.py.
It emits per-launch medians plus every repeat's UI/raster p50/p95/p99,
mean, over-budget counts, inferred gaps and GPU work. The aggregate
cases.csv and summary.json in this archive are generated from all four
clean GPU launches. Their report paths refer to the temporary collection
workspace, not files required at those paths.

```sh
python3 tool/ios_reference/perf/stage_bench/summarize.py "$EVIDENCE/gpu-ablate-1.json" "$EVIDENCE/gpu-ablate-2.json" "$EVIDENCE/gpu-glyph-1.json" "$EVIDENCE/gpu-glyph-2.json" --out /tmp/morph-flat-summary
python3 "$EVIDENCE/reduce_timeline.py" "$EVIDENCE/cpu-flat.timeline.json.gz" "$EVIDENCE/cpu-flat.json" --out /tmp/morph-flat-timeline.json
```
