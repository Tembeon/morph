# Foreground cohort evidence, 2026-10-09

Read ../../../audit/codex-glyph-cohort-report.md. Both variants fail visual
admission. MORPH_BAR_GLYPH_BATCH stays false by default. No candidate
presentation, energy, memory, weak-device or production FPS win is claimed.

Pixel 6a, 1080 x 2400, DPR 2.625, 60 Hz, Impeller Vulkan, release arm64,
Flutter beta 3.49.0-0.2.pre, framework 38ec981bad, engine 774a767348.
Both sides use direct field, live Gaussian glyphs and benchmark performance
hints. Build records preserve all defines and binary identity. APKs remain
at the absolute paths in apk-identity.json, not inside this archive.

Source snapshots:

- cohort-inputs-v1.sources.tar.gz/json: unrestricted coalescing, rejected
  phase-4 live-text witness max 222/255.
- cohort-inputs.sources.tar.gz/json: Android raster-eligible known glyph
  content only, rejected phase-5 witness max 37/255. Control-v2 and
  cohort-raster were built from these same inputs.

The snapshots include dirty source/dependency/shader/hook inputs relative
to HEAD 1325722; extract into an isolated Morph checkout, preserving the
Android scaffold. Source manifests and target SHA records are separate
from the APK hashes. The revised new target supports NAV_SHOT_FRAMES;
defaults retain the old seven frames, while the final pair also captures
5, 6 and 8. Readback is after all measured windows.

Launch order: control-gpu-1, cohort-gpu-1, preliminary control-present-1,
control-v2-gpu-1, cohort-raster-gpu-1. Final candidate FrameTimeline ABBA
was not run after image admission failed. The preliminary control contains
matched real Impeller buffers but has no candidate comparator.

Reproduce with the archived protocol placed at the main
tool/ios_reference/perf/stage_bench path:

1. run_android.py build --flutter flutter-beta --mode release --target
   lib/perf/navigation_stage_bench.dart --apk ABSOLUTE_APK, with each
   --define from the corresponding results/*.build.json.
2. run_android.py run --schema stage --leave-installed --trace gpu
   --pull-artifacts, or the independent --trace presentation.
3. summarize.py REPORTS --out DIRECTORY reads the archived .gpuwork.txt.gz.
4. compare_bounds.py LEFT_REPORT RIGHT_REPORT --out JSON uses Pillow/NumPy
   and matching .artifacts folders. Compare the first pair and revised pair
   separately. It selects only shot_graphs-owned files, not stale PNGs.
5. presentation.py TRACE REPORT --out JSON requires perfetto Python and
   its trace processor. Its preliminary control is diagnostic only.

There are 136 owned native framework-root PNGs: 28 per initial side, 40 per
revised side. They are not SurfaceFlinger screen grabs. The fixed halo in
glyph-witness comparison is not actual native attachment coverage. Large
isolated contour/page errors and systematic glyph differences both remain
in the raw statistics; global p95 zero is not an exact-quality certificate.

Verification: 1419 package tests, 21 example tests, twelve targeted tests,
zero analysis/doc warnings, macOS release, Wasm and default-flag Metal
AUTODEMO. The latter is baseline integration, not candidate Metal admission.
Check SHA256SUMS with shasum -a 256 -c SHA256SUMS from this directory.
