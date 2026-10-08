# Stable Navigation evidence

Base: `114e827ac5c116cbaa8e667d3a325986d2538397`. Device: Pixel 6a,
serial 26221JEGR12737; Flutter 3.47.2 / Dart 3.13.2, engine
`a804b261645ef8c13eb3d5c44a5c2fb0340c5539`. No beta or SDK changes.
Interpretation: `tool/audit/codex-navigation-stable-report.md`.

`prototype.patch` reproduces the initial matrix from the base commit.
`prototype-source` stores the measured source as `.dart.txt` so that
research copies are not analyzed as library code. `source-hashes.json`
identifies those files. The production patch and production lab patch
preserve the final implementation and the later same-binary controls.
`port-v1.patch`, `gpu/production-1` and the first `pixels/production`
capture document an intermediate notifier-owning port. It exposed a
gallery reparenting lifetime error and is superseded by immutable
activation in the final source. `gpu/production-2` measures the final
five-repeat port, with the same rendering law. Do not apply port-v1 as a
production change.
`pixels/final-production` and `pixels/final-production-pixels.json`
capture the final immutable-activation source, including repeated liquid
references. `verification` records passed final gates and tested source
hashes; `device-final.json` identifies the updated installed release.
The installed example lock in `inputs/example/pubspec.lock.txt` governs APK
dependencies; the root lock documents host-test dependencies.

Initial cases: `stock-flat` = full optical preparation/live glyphs,
`flat` = sparse silhouette/live glyphs, `glyph` = sparse/retained glyphs.
Final cases: `flat` and `glyph` select live/retained glyphs with the same
sparse silhouette; `liquid-live` and `liquid` select live/retained glyphs
with the same full optical renderer. Effects and timing are retained.

Build and run from a disposable checkout patched with the selected lab
patch. Individual `.build.json` files contain exact defines and APK
hashes. Use `tool/ios_reference/perf/stage_bench/run_android.py`; it owns
the Pixel lock and restores the previously installed APK on all exits.
Native phase images are collected after timing windows. Repeated liquid
phase references are captured by `NAV_REPEAT_REFERENCE=true`.

GPU reducers accept archived compressed work-period streams:

```
python3 tool/ios_reference/perf/stage_bench/summarize.py \
  tool/ios_reference/perf/2026-10-08-navigation-stable/gpu/matrix-1.json \
  tool/ios_reference/perf/2026-10-08-navigation-stable/gpu/matrix-2.json \
  --out /tmp/morph-navigation-summary
```

Energy reports retain per-window rail integration, CPU/frequency metadata
and the anomalous launch-1 process accounting. APKs and large Perfetto
traces are identified by hash/size rather than committed. Re-record them
with the archived definitions and the standard energy runner; the existing
`perf/2026-10-07-navigation/reduce_energy.py` produces `.energy.json`.
The raw energy totals include other processes and display rails.

`compare_pixels.py` compares all 28 selected phases per pair, including
whole frames and top/bottom 230-pixel chrome bands on the native Pixel
1080x2400 captures. PNG hashes and metrics are archived; regenerate PNGs
with the shot APK definitions, then pass `--pair baseline,candidate`.
Unrelated pre-existing device artifacts pulled by the generic runner are
excluded. Host hashes apply to silhouette-only parity, not to the admitted
NEAR raster resampling. No screenshot readback enters a measured window.
