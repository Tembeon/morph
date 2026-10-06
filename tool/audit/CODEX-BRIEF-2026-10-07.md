# Codex brief: morph performance, round 3 (2026-10-07)

You work alone on this repository until the owner returns. Read this
whole file first, then the files it points to. ASCII only in everything
you write.

## 1. What morph is and what "better" means

morph (this repo, branch `wip/measured-liquid-glass`) is a Flutter
package that copies iOS 27 Liquid Glass 1:1: measured UIKit physics and a
real refraction glass renderer (vendored, `lib/src/glass/renderer`).
The look is the product. Performance work must keep it.

The goal of this round: find out how much further performance can go,
and take every win that keeps the native look.

- FIDELITY: a change is either IDENTICAL (byte-identical frames) or NEAR
  (a stated max channel error, practically invisible: a few steps on rim
  pixels). VISIBLE changes are NOT made; write them down as proposals for
  the owner.
- ENERGY IS A PRIMARY METRIC (owner, 2026-10-06): an app using morph must
  not run hotter or drain more battery. A change that wins frames by
  spending more energy is rejected (example: ADPF was rejected, +9 percent
  energy on the menu, branch `exp/adpf`).
- Measure GPU time and energy, not only frame timings: at 60 Hz the Pixel
  hides GPU waste (the 2 pt edge effect blur cost 7.6 ms GPU a frame and
  never missed a frame).

## 2. Read first

1. `CLAUDE.md` - architecture, the glass seam (surfaces channel, BACKDROP
   GROUPS, GLASS CONTAINER, tiers), invariants, rules, the Performance
   passport (all current device numbers).
2. `tool/audit/PLAN.md`, section "Status 2026-10-06 evening - HANDOFF".
3. `tool/ios_reference/spec/glass-renderer.md`, all performance sections
   (surfaces channel, Glass container, Backdrop filter attribution, Small
   blurs, Energy, The Mali offline compiler batch, Menu fusion ahead,
   First use, Startup and queue bounds). Every rejected lever with numbers
   is there - do not redo them.
4. `tool/audit/g1455-review.md` - the comparison with PlugFox/g1455 and
   Material (one-binary bench) and the idea table.
5. `tool/audit/round2-fable.md`, `round2-astra.md`, `shader-audit-*.md`,
   `flutter-tricks-*.md` - earlier reviews.

## 3. Hard rules

- Dart: no cascades (`..`) in new code, no `dynamic` (use `Object?`), no
  comments that explain what code does, never SingleChildScrollView,
  `package:material_ui/material_ui.dart` (never flutter/material.dart).
- Every public member has a dartdoc (lint is on). Measured values carry
  their measurement in dartdoc; nothing invented.
- Replay tests (fixtures under test/fixtures) are the fidelity judge for
  motion: a red replay means revert.
- Gates before every commit, serially:
  `dart format lib test example/lib example/test`, `flutter analyze` (0
  issues), `flutter test`, `(cd example && flutter test)`,
  `dart doc --dry-run` (0 warnings).
- Commit small, one change per commit, with `git commit --only <paths>`
  (never `git add -A`). One CHANGELOG.md 0.7.0 bullet per landed change,
  in its own commit; read CHANGELOG.md before editing it. Do NOT push.
  This branch was never released: no deprecation or BREAKING notes.
- Update the passport (`glass-renderer.md`) and CLAUDE.md's Performance
  passport with every measured change.
- Devices are shared and use locks: `mkdir /tmp/morph-native/pixel.lock`
  (Pixel 6a, adb serial 26221JEGR12737) or `/tmp/morph-native/device.lock`
  (iPhone 16 Pro, UDID 00008140-001039D01442801C) plus an `owner` file;
  never run on a device if mkdir failed; release after; never delete a
  lock you did not create. If a lock says OWNER, the owner has the
  device: do not use it. Keep the Pixel in portrait. Leave the release
  gallery installed (`cd example && flutter build apk --release`, adb
  install) when done.
- Clean your own /tmp worktrees and build outputs when done (the disk ran
  down to 5 GB once).
- If you cannot reach a device or run flutter test from your sandbox
  (an earlier sandbox could not open sockets: run the test binary through
  flutter_tester directly, or leave the step for the owner), say so
  explicitly in the report; never claim a measurement you did not take.

## 4. Harnesses (all exist)

- Device frame cost: `tool/ios_reference/perf/audit.sh` (iPhone) and
  `audit_android.sh` (Pixel): profile builds of
  `example/integration_test/glass_audit_test.dart` from a pinned git
  worktree; `AUDIT_RUNS=5`; `summarize.py <dir> [<dir>]`; `shotdiff.py`.
  Options: AUDIT_SCENES, AUDIT_SHOTS, AUDIT_CENSUS(_OWNERS), AUDIT_GPUWORK,
  AUDIT_ATLAS, AUDIT_IDLE_S, AUDIT_STAGES_OFF, AUDIT_LEGACY_BLURS.
- GPU per frame on the Pixel: `AUDIT_GPUWORK=1` + `gpu_work.py` /
  `gpu_scenes.py` (kernel GPU work periods; GPU cycles ignore clock
  scaling). Energy: `energy_android.sh` + `energy.py` (ODPM power rails via
  Perfetto; needs the `perfetto` pip module in a temporary venv). Traces:
  `trace_android.sh`, `atrace_slices.py --scenes`.
- One-binary comparison bench (Material / plain / morph flat / liquid /
  g1455): source in `tool/ios_reference/perf/2026-10-06-g1455-compare/bench/`,
  how to rebuild in g1455-review.md section 5.
- Deterministic: `test/perf_counts_test.dart` (ceilings in
  `test/fixtures/perf/counts.json`, `PERF_COUNTS_UPDATE=true` after a
  change that lowers a count), `test/glass_frames_test.dart` (pixel
  identity per scene and tier; `GLASS_FRAMES_OUT=` writes hashes to compare
  commits), `example/test/*host_test.dart` (host Impeller parity).
- Shaders: `example/integration_test/shader_parity_test.dart` +
  `tool/audit/shader/run_pixel.sh` / `run_iphone.sh` / `offline.py`
  (malioc for Mali-G78 is installed:
  `/Applications/Arm Performance Studio 2026.5/mali_offline_compiler/malioc`,
  also on PATH).
- Menu: `example/integration_test/menu_frames_test.dart` +
  `tool/ios_reference/perf/menu_frames.py`; fusion probe
  `example/integration_test/fusion_probe.dart`.
- Debug: `MorphGlassInspector` (public) shows glass layers per frame,
  owners and container hints.

## 5. Tasks, in order

Each task: measure before, change, measure after on the same device and
harness (interleave launches A/B/B/A, cooled starts), state the max pixel
difference, the frame / GPU / energy deltas, and keep or revert.

### T1. The flat tier draws no backdrop blur
Owner decision (2026-10-06): flat = no backdrop reads at all. Today
`MorphScrollEdgeEffect` (lib/src/widgets/scroll_edge_effect.dart) still
blurs on flat. On flat, draw only its fade and hairline (no
BackdropFilterLayer, no seed copy). Find the tier through the installed
painter / MorphAdaptiveGlass the same way other surfaces do. Also check
that nothing else reads the backdrop on flat (census on every audit scene
on flat must show 0 backdrop filters). Target: flat scroll GPU at
Material's level (bench: Material 0.77 ms, flat today ~3.7 ms after the
small-blur fix, 0.88 ms without the edge effect). This IS a visible change
on the flat tier only: approved by the owner.

### T2. Liquid controls: UI thread
Pixel 6a: liquid controls build p50 5.18 ms vs flat 1.95 (same widgets,
tier only; g1455 controls 1.89, Material 1.03). Profile what the liquid
tier does on the UI thread per frame while a knob / thumb / lens is
lifted (glass_phases_test PAINT/COMPOSITING, timeline, CPU samples): host
structure changes, Flutter GPU encode/submit on the UI thread, field
uploads, channel pushes, content snapshots. Cut it IDENTICAL
(glass_frames_test hashes). Report the frame anatomy even if nothing
lands.

### T3. GPU sweep of every scene
Before the g1455 bench nobody measured GPU per scene. Run
`AUDIT_GPUWORK=1` on every audit scene and tier on the Pixel and attribute
GPU time to layers (ablation switches, census owners). Look for more
full-pass or full-resolution blurs (Impeller blurs at full resolution for
sigma <= ~4 device px, and a blur whose clip grown by its kernel leaves
the pass blurs the whole pass - glass-renderer.md "Small blurs"),
unbounded filter inputs, offscreen layers, oversized clips. Fix what can
be fixed IDENTICAL or NEAR; the tab bar (9.3 ms GPU, 905 mW) and the sheet
are the first suspects.

### T4. Anti-aliased shader paints on SDF backends
On Impeller with SDFs (macOS always, iOS with FLTEnableSDFs), a paint with
a shader and isAntiAlias true is drawn as an SDF mask plus an offscreen
blend (engine canvas.cc ~2185-2209; g1455 measured 1.36 -> 0.52 ms GPU for
12 surfaces on an M3 Max with `isAntiAlias = false` + a primer draw,
g1455 glass_surface.dart:71-128). Our candidates: fake-tier surfaces
(paint_fake_glass_surface.dart:161), gradients in scroll_edge_effect.dart,
menu.dart, glass_glow.dart. Apply only where the shader writes its own
coverage or the shape edge is clipped anyway; prove pixels (macOS host
and shotdiff) and measure macOS GPU (Metal System Trace or frame timings).
Note: the owner may be gaming on the Mac - if a lock file
/tmp/morph-native/mac.gaming exists, do not open GUI windows.

### T5. Research spike: same-frame content instead of a backdrop read
g1455 is cheap because it has NO BackdropFilter: one capture per screen,
each glass a plain shader draw. We reject its one-frame-late capture
(fidelity). The same-frame variant: for package-owned chrome over a known
scroll view (navigation bar / toolbar over MorphNavigationScaffold's
body), re-add the content's already-recorded pictures (retained layers)
under a clip + the glass filter instead of reading the backdrop. Probe in
g1455-review.md: 1.36 vs 3.19 ms GPU for a blurred strip, +0.6 ms raster
with a naive second ListView. Build the prototype on a branch
`exp/same-frame-backdrop` only. Questions to answer with numbers: raster
CPU and GPU per removed filter, identity vs the backdrop path (glass over
glass, platform views, textures - list what breaks), energy. Do not merge;
report.

### T6. iOS verification (only if the iPhone lock is free and not OWNER)
The 2026-10-06 work was measured on the Pixel only: small blurs, list
stages, MorphGlassInspector, F7 shader families, fusion workers. Run
audit.sh + shotdiff vs the last iPhone baseline (perf/2026-10-05-apple-
verify) and shader parity (run_iphone.sh). Report deltas; fix Apple-only
regressions.

### Do NOT change
- Fusion workers 3 frames ahead vs 2 (owner decision pending; you may
  measure 2 ahead and report).
- Tiers: liquid / fake / flat, chosen once; never add frosted or a
  runtime governor.
- Anything listed as rejected in glass-renderer.md (ADPF, edge effects in
  the bars' group, one container for nav bar + toolbar, frost inside the
  final shader, F1 uniforms, R1 shadow clip, copying the backdrop for
  every frosted layer).

## 6. Report

Write `tool/audit/codex-round3-report.md` (commit it) with, per task:
what you measured (device, commit, harness, runs), before/after tables
(frame p50/p95/p99, frames over budget, GPU ms/frame, energy mW), max
pixel difference, verdict, commit IDs, and what is left. End with "how
far can it go": the remaining cost per scene split into Flutter/Impeller
floor (flat / Material) vs morph's own, and the levers still open.
