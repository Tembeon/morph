# Real Navigation on Pixel 6a, 2026-10-07

Start with `tool/audit/codex-navigation-report.md` for conclusions and
limits. The production entry point is
`example/lib/perf/navigation_stage_bench.dart`; the restoring runner's
`build --target` selects it. See `stage_bench/README.md` for stock usage.

The experiment source and patch in `pair/` are frozen before the pair
APK build. The later workflow adds only its longer driver; its full
entry-point source and build record are in `workflow/`. Reproduce them on exp/same-frame-backdrop a34b9d0, not by
mixing current production files with an old patch:

```sh
git clone --no-hardlinks /path/to/morph /tmp/morph-navigation-repro
cd /tmp/morph-navigation-repro
git checkout a34b9d0e356173cbd16322e59de5f60aa7ae3a56
# EVIDENCE is the absolute path to this archived evidence directory.
git apply "$EVIDENCE/pair/experiments.patch"
cp "$EVIDENCE/pair/navigation_stage_bench.dart.txt" example/lib/perf/navigation_stage_bench.dart
cp "$EVIDENCE/pair/navigation_content_host_test.dart.txt" example/test/navigation_content_host_test.dart
cp "$EVIDENCE/pair/liquid_pair_sampler_test.dart.txt" test/liquid_pair_sampler_test.dart
flutter pub get
python3 tool/ios_reference/perf/stage_bench/run_android.py build --target lib/perf/navigation_stage_bench.dart --apk /tmp/morph-nav/pair.apk --define NAV_MODES=liquid,pair-field --define NAV_MOTIONS=enter,nested-push,nested-pop,toolbar --define NAV_RUNS=3 --define NAV_WARM_MS=500 --define NAV_SAMPLE_MS=800 --define NAV_PHASES=true --define NAV_SHOTS=true --define NAV_REPEAT_REFERENCE=true
```

The underlying owned-source experiment stays dormant: its source callback
is null in every Navigation case, so the stock backdrop is used. The
patch adds three diagnostic switches, all default off: separate bar
content, a two-box field sampler, and scroll-edge blur omissions. The
stand selects them per case. Combined means bar content plus pair sampler;
only the host parity test tests that combination. The native pair matrix
uses pair-field alone. Visible edge/frost/flat ablations are attribution,
not fidelity-preserving candidates. Production exposes none of these
experimental switches.

`content/` contains the first three-repeat content-channel GPU and two
energy launches before action prewarm; `warm/` contains action-prewarmed
content-channel repeats. `pair/` contains the pair sampler experiment.
`parity/native-1` is a separate one-repeat CPU-profiler launch; do not
include it in GPU/power acceptance totals. `actions/` and `smoke/` ran
under the now-stopped Android system recording and are diagnostic only.
`content/gpu-2` failed during PNG capture and has no successful report;
its timing work is not reduced. The earlier `parity/pixels.json` had a
wrong capture clock and must not be used for fidelity acceptance.

Source/APK hashes and defines are in build records and source-hashes.
Large APKs, system-wide Perfetto traces and PNG files are not committed.
Their binary hashes, derived rail energy per exact window, image hashes,
comparison results, raw timing reports and compressed GPU/own-isolate CPU
records are retained. PNG comparisons require freshly collected images,
not stale app-data files. The runner restores the original gallery.

Use the existing stage reducer for each successful native report:

```sh
python3 tool/ios_reference/perf/stage_bench/summarize.py "$EVIDENCE/pair/gpu-1.json" "$EVIDENCE/pair/gpu-2.json" --out /tmp/morph-nav/summary
python3 "$EVIDENCE/reduce_cpu.py" "$EVIDENCE/parity/native-1.cpu.json.gz" "$EVIDENCE/parity/native-1.json" --out /tmp/morph-nav/cpu-windows.json
python3 "$EVIDENCE/compare_pixels.py" /tmp/morph-nav/gpu-1.artifacts --candidate pair-field --out /tmp/morph-nav/pixels.json
```

`reduce_energy.py BASE` reads a new BASE.pftrace + BASE.json using the
repository's existing energy reducer (pip install perfetto). Cached
BASE.energy.json records preserve every selected rail and repeat after
trace cleanup. The existing energy reducer's `thread_ms.ui` label names
the Android process main/platform thread, not the Flutter Dart UI thread;
those values are not used for UI attribution here. FrameTiming build
and the own-isolate CPU samples supply Flutter UI evidence.

The measured experimental energy config additionally requested
power/gpu_work_period; its source is archived as energy_android.cfg.txt.
GPU costs are calculated only from separate streamed kernel GPU launches.
The energy config did not provide usable raw GPU-work events through the
trace processor. All comparisons use equal config within their APK.

Native host parity needs real Impeller/Flutter GPU:

```sh
cd example
NAV_CONTENT_FRAMES_OUT=/tmp/morph-nav/host.json flutter test --enable-impeller --enable-flutter-gpu test/navigation_content_host_test.dart
```

The raw Pixel max channel error is reported alongside an A/A stock repeat.
Do not crop away or hide large errors to claim whole-frame byte identity.
At 60 Hz, action windows include a settled tail; inferred vsync gap slots
are not SurfaceFlinger jank measurements. Framework phase collection and
CPU profiling are explicit observers. Stock control smoke has phases off.

For the long energy protocol use workflow/navigation_stage_bench.dart.txt
with the same experiments.patch and build record. Select
NAV_MODES=liquid,content-channel,pair-field, NAV_MOTIONS=workflow,
NAV_WORKFLOW_CYCLES=5, NAV_SAMPLE_MS=800, NAV_RUNS=3,
NAV_PHASES=false and NAV_SHOTS=false. Actual twenty-second windows
and produced frames are preserved in each workflow report. The workflow
energy is an aggregate of its five action types and settled pauses.

`stock/gpu-final` is the final production stand's one-repeat native control,
with framework phase collection off and no extra Inbox repaint boundary.
`stock/gpu-1` used the previous page-boundary wrapper. Both frozen entry
sources are retained. The stock control validates the runnable callbacks,
not a three-repeat candidate acceptance estimate. Flutter ModalRoute
already wraps its page/transition subtrees in repaint boundaries.

`run_profile.py` is an optional diagnostic runner that enables the own
isolate profiler and saves CPU samples before APK restoration. It uses
the VM's getVMTimelineMicros for the sample query extent. The measured
older wrapper used host monotonic time for the upper bound; its complete
samples cover all reported phone windows, but the corrected portable
wrapper avoids relying on the host/phone clock ordering. Its frozen
source is run_profile-measured.py.txt. Never mix profiler-enabled launches
with unprofiled GPU/energy acceptance launches.

Dependency locks and pubspec files used by the lab are retained in inputs/.
Use the pinned Flutter 3.47.2/Dart 3.13.2 SDK and install those lockfiles
before pub get when reproducing the archived experiment.
