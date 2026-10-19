# Performance

morph is meant for mass use by developers who should not have to
optimize anything themselves: the measured controls and the glass must
be fast by default. The reference weak device is the Pixel 6a (Mali-G78,
Vulkan, 60 Hz, 16.67 ms budget): the gallery must hold 60+ fps
everywhere on it, ideally with headroom toward 120 fps so weaker devices
still hold 60. Fidelity may be traded for performance where the eye does
not notice, and every trade is stated as IDENTICAL, NEAR or an
approximation. Both renderers - liquid glass and flat - stay supported.

## 1. Targets and admission policy

- Smoothness on weak Android devices is the primary objective. Modest
  measured energy increases are acceptable for meaningful frame-time
  improvements; energy is still measured on every candidate.
- Fidelity stays IDENTICAL or stated NEAR. A visible quality reduction
  needs an owner decision.
- A change is admitted on frame time AND energy measured on the device,
  never on CPU or raster timing alone. Also verify: the path actually
  activates, native pixels (device readback, not only Flutter toImage),
  real presentation (missed slots, not only profile windows) and
  sustained resource use (RSS, retained textures).
- Working runs: one `tool/bench/bench.py` run of the candidate against
  `tool/bench/baseline.json` (frame anatomy and power per scene, one
  launch per tier, 3 repeats per scene). ABBA over separate cooled
  launches only when a delta is within the noise and the decision hangs
  on it; then use `--fixed` (steady clocks) or `energy_android.sh`.
- Current SDK for optimization work: `flutter-beta` / `dart-beta`
  (3.49.0-0.2.pre); normal commands stay on 3.47.2 stable. The native
  shader-filter factory requests low quality when its typed signature
  exposes filterQuality (fixes beta's nearest-sampling regression; liquid
  chrome max error 27 -> 1/255 against stable).
- Experimental paths live on branches off `wip/measured-liquid-glass`
  (section 5b). Every prototype there may be wrong or incomplete: a
  measured failure rejects that implementation, not the idea.

## 2. Harnesses

- Pixel bench, the default for every Android check: `tool/bench/bench.py`
  (`--help`). Builds the working tree or `--rev` once per suite (the
  glass audit and the navigation bench; tier, scenes and repeats are
  launch settings, not builds), takes the Pixel lock, waits for Thermal
  Status 0, runs every launch under one Perfetto trace
  (`tool/bench/trace.cfg`: Flutter/Dart events via the profile manifest's
  TraceSystrace, sched, CPU/GPU clocks, GPU work periods, ODPM rails) and
  prints per scene: UI / raster / GPU p50 and p95, frames over budget with
  the first limiter of each (gpu, raster-wait, raster-sched, raster-cpu,
  ui-sched, ui-<phase>), the UI phases and the raster thread's self time
  by slice, dropped vsync slots, clocks and power; deltas against
  `tool/bench/baseline.json` (`--save-baseline` replaces it once a change
  is admitted). `tool/bench/analyze.py <trace>` reads any trace whose
  bench marks `scene:<name>:<run>:begin|end`. Results:
  `tool/ios_reference/perf/<date>-bench-<label>/` (traces stay in
  /tmp/morph-perf/bench). The scripts below remain for what bench.py does
  not cover (iPhone, shader parity, layer census, Skia devices).
- Device frame cost (iPhone): `tool/ios_reference/perf/audit.sh` builds
  example/integration_test/glass_audit_test.dart as a profile app per
  tier (`AUDIT_SOURCE=` a git worktree at a fixed commit, `AUDIT_RUNS=5`),
  takes the phone lock, writes `tool/ios_reference/perf/<date>-<label>/<tier>.json`;
  `summarize.py <dir> [<dir>]` prints medians of percentiles over active
  frames (build or raster > 0.3 ms) and the delta; `shotdiff.py` diffs
  screenshots.
- Device frame cost (Android): `audit_android.sh` with the glass_phases
  collection (dirs pixel6a-cpu-*, -gpu-*, -retain-*).
- Navigation quick runs: `tool/ios_reference/perf/nav_quick`.
- Real gallery navigation: navigation_stage_bench (actual
  GalleryApp/Inbox/detail callbacks: first enter, nested push/pop,
  toolbar morph, scrolling, a repeated five-action workflow).
- Stage stand: example/lib/perf/glass_stage_bench.dart compares
  bare/capture/blur/optics/glass with shuffled windows and separate
  GPU/energy launches; usage in tool/ios_reference/perf/stage_bench/README.md.
- Work per frame (deterministic, every `flutter test`):
  test/perf_counts_test.dart counts rebuilds, paints, re-recorded
  pictures, backdrop captures, offscreen layers, traced outlines,
  snapshot fallbacks and idle frames for eleven scenes x two tiers,
  pinned as ceilings in test/fixtures/perf/counts.json
  (`PERF_COUNTS_UPDATE=true` rewrites it after a change that lowers a
  count). flutter_test has no Impeller: liquid builds its real tree but
  its layers paint their content without glass, so liquid counts no
  glass captures there.
- Pixel identity across frames: test/glass_frames_test.dart hashes.
- Skin / flight (AOT): `cd example && flutter build macos --release
  --dart-define=MORPH_BENCH=true`, run the binary, grep BENCH.
- Tracing microbenchmarks: `flutter test benchmark/liquid_benchmark_test.dart`
  (JIT, relative only).
- Energy (Pixel 6a ODPM rails): `perf/energy_android.sh` + `energy.py`
  (ABBA, cooled starts). energy.py sums duplicate raster threads; the
  runner cleans its recorder on failure.

## 3. What ships, and its switches

| optimization | what it does | switch / fidelity |
|---|---|---|
| Analytic geometry | eligible liquid layer (<= 8 shapes, uniform or tint-only; container body <= 4 uniform-radius boxes) evaluated in the final shader: no matte, material pass, field upload or CPU fusion | on; `MORPH_ANALYTIC_GEOMETRY=false` restores the matte, mode `changes` = analytic only while geometry changes; host oracles pin the shader to liquid_field.dart (mean < 0.75/channel); body shadow NEAR |
| Flat shader bodies | flat fused body of <= 4 boxes filled by the merge law in flat_fused_body.frag; path traced only if read | on; `MORPH_FLAT_SHADER_BODIES=false` restores the traced path |
| Flat sparse silhouette | flat fused bodies trace their exact silhouette without unused optical fields (liquid keeps full fields) | IDENTICAL (silhouette hashes match all 63 collections) |
| Menu fusion workers | `MorphFusionWorker`: fuse the next three predicted frames on up to four isolates, served within 0.02 pt per input | profile/release only; IDENTICAL law |
| Menu fusion core | plain-union field from box distances, grids kept across calls, menu face built once | IDENTICAL |
| Field uploads | fewer per-frame field uploads (07bb27d) | IDENTICAL |
| Retained glass layers | `MorphGlassChannel` builds once per structure, pushes values (e2f9c4e) | IDENTICAL |
| Glyph policy | `MorphGlyphPolicy` + `MorphGlyphs` (glyph_scale.dart): text under an animated transform decides per frame from its observed scale velocity, cover blur and content stability: live at rest, snapped to a 64/32/16-per-octave grid while slow (or when its content re-records every frame: the lens copy), one batched raster (mipmapped, at the device pixel ratio up to 1.09x) while fast or under a blur >= 0.5 pt; `morphVeiledGlyphs` blurs and fades through the pyramid shader on Android. Wraps tab bar labels, bar items, inline title, menu glyph, every `MorphControlCapsule` child; the menu rows (never snap: a snap about the rows' center shook the far rows against the card in the open's tail), the alert's and the date picker overlay's content are cards (`MorphGlyphs.faded`: own fade, never snap, raster at any scale motion; host atlas replay strike frames alert 67 -> 3, date picker 124 -> 2); the lens copy uses the same tracker. Pixel 6a liquid tab bar: strike frames 6.5 -> 2.9 percent, atlas 0.33 -> 0.22 ms/frame (3.8 -> 0.9 in frames over budget); menu 9.7 -> 4.4 percent; sheet 3.0 -> 0.2; over budget within run spread; power without display liquid +2.1 / flat -1.6 / nav -1.8 percent (glass-renderer.md "One glyph policy") | exact at rest; snapped NEAR (<= 0.54 / 1.1 / 2.2 percent); raster NEAR (resampled); shader NEAR (within a channel step of mean error) |
| Small-blur rules | scroll edge blurs a copy of its band (`morphBackdropSeed` under a clip grown by `morphBlurReach`); a frost or edge blur just below half resolution is raised to it by <= 12 percent (`morphHalfResolutionSigma`; edge: hard 2 -> 2.17 pt at 2.625, `MORPH_EDGE_HALF_RESOLUTION=false` turns it off); a fading hard edge folds its presence into its saturation matrix (`MORPH_EDGE_FOLDED_FADE=false`) | NEAR (frost 1 - 6 steps on real content; edge median 4, max 19 on sharp host edges); fold within 1 step |
| Inline title layer | the navigation bar's inline title paints in its own layer; its spring repaints 1 object a frame instead of the bar and the overlay (`MORPH_TITLE_LAYER=false` turns it off) | IDENTICAL |
| Flat edge effect | flat scroll edge = fade/hairline only, zero backdrop filters on flat | approved visible change on flat only |
| Glass container | `MorphGlassContainer` shades resting glass of joined hosts in one layer; list cards and the search toolbar are stages | IDENTICAL within 1 - 3 channel steps |
| Pipeline warm-up | `MorphGlassRenderer.precache` | first-frame worst UI/raster: Pixel liquid 102/74 -> 5/11 ms, iPhone 69/362 -> 2/42; costs 0.33 - 0.85 s precache |
| Skin eval budget | `MorphSkin.defaultEvalBudget` coarsens the grid by the overshoot factor | 64-piece worst case 1.9 ms (8.2 unbounded) |
| Backdrop cache | glass over an opaque route below it (sheet, alert, action sheet, popover, date picker) paints over a frosted copy of that route, re-copied when what it samples changes, never an older frame (`GlassBackdropCache`); menus excluded | on; `MORPH_BACKDROP_CACHE=false` reads every frame; NEAR (host max 45 - 55 on < 200 px while opening, 0 - 1 at rest); Pixel sheet GPU 515 -> 393 ms/s, 1119 -> 833 mW; iPhone sheet raster p50/p99 -0.23/-0.82 ms |
| Shader frost | a frost up to 8 device px without dispersion is blurred by the final pass (24 Gaussian taps), no blur pass | on; `MORPH_SHADER_FROST=false` restores the blur pass; NEAR (host tab bar max 29 along the rim); Pixel tab bar GPU 560 -> 514 ms/s, 904 -> 798 mW; iPhone tab bar raster p50/p95 -0.31/-0.35 ms |

## 4. Standing lessons

- Backdrop filters are the raster cost. Each glass layer is one
  BackdropFilterLayer (liquid menu 10 saveLayers vs flat 1); full liquid
  costs 3.9 - 6.2x flat GPU cycles. The levers left change pixels.
- What a glass surface costs is the filter machinery, not the read or the
  shader (Pixel, `MORPH_GLASS_PROBE`): the glass shader as a plain paint is
  11 - 36 percent of what liquid adds; a frame with any live read pays
  0.4 - 1.1 ms GPU once (frame rendered offscreen and copied out); each
  separate surface two MSAA passes and a composite; the frost and shader
  inside the filter 0.4 - 2.0 ms on the big frosted surfaces. One shared
  read per frame saves only 0.2 - 0.5 ms (tool/audit/2026-10-12-glass-composition.md).
- Every layer-tree saveLayer appears twice as `Canvas::saveLayer` in a
  trace (flow records it, Impeller executes it); count the ones inside
  SurfaceFrame::Encode. An encode saveLayer without a flow twin is an
  OpacityLayer whose children took the opacity (Impeller still calls
  saveLayer for the picture) or a saveLayer inside a picture: compare
  with m/empty/frames before blaming a control.
- A blur whose kernel-grown clip leaves the pass makes Impeller blur the
  WHOLE pass, and below 5.66 device px of sigma at full resolution.
  Keep blur clips inside the pass.
- Impeller keys glyphs by screen scale (1/200): text under a sweeping
  scale re-rasterizes glyphs nearly every frame. Wrap it in `MorphGlyphs`
  (the policy chooses); a raster pays an offscreen pass every time,
  while a repeated sweep's strikes are partly cached, so rasters win only
  for fast sweeps of still content. The atlas also keys the x position in
  quarter device pixels: a label that moves sideways while it scales (the
  tab bar's, under the swell and in the lens copy) takes
  `MorphGlyphs(aligned: true)`, which snaps down to the drift and puts
  the snapped origin on a whole device pixel.
- On the Pixel the nested-navigation raster tail is the bar button
  glyphs and their blur, not page painting or glass (hiding glyphs cut
  nested raster p95 24-33 -> 7-8 ms in ablation).
- The CPU fusion's 4 - 12x device-over-loop gap is core placement and
  DVFS (paced calls land on A55/A76), not the algorithm.
- A lighter load can raise p50 (the CPU clocks down); read p50 rises
  next to an unchanged workload as DVFS, not cost.
- First use is pipeline compilation; the Vulkan disk cache does not help
  second launches.
- Reference bytes alone do not bound native memory (a texture cap halved
  retained capacity but raised RSS).
- Old-generation GC mid-frame came from reallocated grids: keep grids
  across calls.
- Never compare an old nearest/duplicate-source/full-viewport graph with
  a fused calibrated kernel when judging an algorithm.
- Profile windows with framework phase collection are not presentation
  latency; isolated body-pixel errors up to 64/255 also occur in
  same-variant repeats, so compare against a stock/stock repeat.
- Flutter GPU `Texture.fromImage` wraps a ready ui.Image without copying
  but cannot see the private current backdrop.

## 5. Rejected and inconclusive experiments

| experiment | result | evidence |
|---|---|---|
| ADPF hint sessions | menu over-budget 16 -> 4 but +9 percent energy menu, +3 sheet; rejected (branch exp/adpf) | perf/2026-10-06-pixel6a-energy |
| Fusion one frame ahead | costs nothing, gains nothing (three ahead kept) | perf/2026-10-06-fusion-ab |
| Coordinate-uniform / translation-inverse renderer | raster p95 11.64 -> 12.49, GPU within noise; rejected | tool/audit/codex-round3-report.md |
| Field-only preparation | identical pixels, GPU unchanged, no repeatable power gain; reverted | tool/audit/codex-round5-optimization.md |
| Released-texture 16 MiB cap | retained 24.375 -> 12.188 MiB but RSS 387.45 -> 467.04 MiB; reverted | tool/audit/codex-round5-optimization.md |
| Haze 0.5.0 blur | GPU 11.05/24.26 ms vs stock 2.13/2.16; ClipRect changes pixels | perf/2026-10-07-round5 |
| Full-DPR cached image input | visibly incorrect native pixels; rejected | tool/audit/codex-round5-optimization.md |
| Same-frame known picture replay | saves capture GPU; moving-coordinate fidelity unresolved | tool/audit/codex-round5-optimization.md |
| Matrix/runtime-effect native backdrop chain | GPU 4.007/4.541 vs stock 2.555/2.596, error 50/35, sigma 10 power 718 -> 873 mW | tool/audit/codex-backdrop-input-review.md |
| Merged cluster surfaces (synthetic) | GPU 9.716 -> 4.057, power 1155 -> 841 mW, raster p95 +1.8 ms; synthetic, not gallery-wide | perf/2026-10-07-round5 |
| Dual Kawase direct | sigma 2 GPU 2.030 -> 1.492 but UI p95 1.685 -> 8.569, power flat; sigma 10 power up | tool/audit/codex-dual-kawase-followup.md, perf/2026-10-07-dual-kawase |
| Dual Kawase translation cache | GPU halves, power 573 -> 500 / 611 -> 518 mW, but immutable fixture only; source invalidation not built | tool/audit/codex-dual-kawase-followup.md |
| Combined current-frame source (exp/same-frame-backdrop a34b9d0) | static GPU 4.073 -> 1.900 but periodic power +3.8 percent; fixture only | tool/audit/codex-combined-source-report.md, perf/2026-10-07-combined-source |
| Paired runtime Gaussian | graph 3.1 - 3.5x stock, 20/255 off; research only | tool/audit/codex-beta-sdk-report.md, perf/2026-10-08-beta-sdk |
| Content-channel and exact two-box sampler (navigation) | power 704 - 712 mW all variants; no repeatable win, unmerged | tool/audit/codex-navigation-report.md, perf/2026-10-07-navigation |
| Plain contour / glyph ablations (flat navigation) | diagnostic only, visible changes | tool/audit/codex-navigation-flat-report.md, perf/2026-10-07-navigation-flat |
| Navigation snapshots (Redmi) | no gain, capture spike | commit ab5b970 |
| Redmi menu content blur through the one-pass glyph shader | raster p50 +1.7 ms; the pyramid pays only for small glyphs | claude-weak-android-2026-10-11.md |
| Moto sheet frost seeded from its own region | p50 better, p95 unchanged, p99 worse, rim off up to 57 steps | same |
| Analytic blurred union for the menu (Clark) | exact only up to 6 pt radius; most fused frames are 10 pt+ (branch menu-blur-analytic-oracle) | same |
| Optical batch (one filter for disconnected chrome) | pilot never activated in 40 frames: no evidence | codex-optical-batch-report.md |
| Dependent GPU pass batching | crashes both tested SDKs; keep separate command buffers | codex-gpu-pass-lifecycle-report.md |
| Backdrop region (one read per bar band for the edge blur and the bar's glass, e6ce856) | GPU within +-2 percent in every audit scene, power and raster in launch spread: a saved full-screen read is worth about what the region's own pass costs; removed | tool/audit/2026-10-12-glass-composition.md, perf/2026-10-12-bench-gr-* |
| Analytic containers under a closed gate (3611bf0, reverted) | a scaled sheet's glass container keeps its members analytically: host backdrop filters per frame 9.84 -> 6.13, Pixel sheet saveLayers 3.5 -> 2.4 but GPU 8.04 -> 8.24 ms/frame, raster and power within launch noise: the one layer over the members' union costs what their passes did | perf/2026-10-13-bench-plane-gate, -plane-off |
| Flat sparse field + Android glyph raster | push raster p95 improves, power 556/534 -> 542/547 mW (no saving), other actions mixed; shipped for frame time | tool/audit/codex-navigation-stable-report.md, perf/2026-10-08-navigation-stable |

Open owner decisions (pixel-changing levers with device numbers): Redmi
menu content blur, large glass surfaces at reduced interior resolution
(Moto sheet / menu), scroll edge blur off on Impeller (branch
exp/edge-effect); details in tool/audit/claude-weak-android-2026-10-11.md.

Research notes: tool/audit/codex-round4-resource-study.md
(perf/2026-10-06-round4-*), tool/audit/codex-stage-bench-report.md,
tool/audit/perf-research-2026-10-05.md, glass-renderer.md.

## 5b. Experiment branches

Default-off prototypes, each with an `EXPERIMENT.md` (intent, activation,
result, report locations). Compare an experiment only with its parent,
same SDK, flags, warm-up and action protocol; never merge the integration
snapshot as a shortcut.

The remote experiment branches are archived under tags
`archive/2026-10-14/<branch>`; the names below remain as local branches.
Origin carries only `main` and `wip/measured-liquid-glass`. Each archive
tag points to the experiment's original tip, preserving its full history.

| branch | parent | state |
|---|---|---|
| `codex/exp-glyph-atlas` | baseline | retained foreground blur atlas; cadence not admitted |
| `codex/exp-glyph-cohorts` | glyph atlas | foreground filter grouping; not admitted |
| `codex/exp-direct-field` | baseline | direct primitive and sampled-field optics |
| `codex/exp-gpu-optical-grid` | direct field | GPU optical nodes; no robust native win |
| `codex/exp-owned-mip` | GPU optical grid | owned source / pyramid; source acquisition unresolved |
| `codex/exp-dependent-pass-batching` | owned mip | archived; known Vulkan crash |
| `codex/exp-direct-field-material` | owned mip | tint/mixed-field consumer; no repeatable win |
| `codex/exp-optical-batch` | direct field material | pilot inactive |
| `codex/optimization-evidence` | baseline | raw evidence, no renderer changes |
| `codex/optimization-integration` | baseline | every experiment together, defaults off |
| `exp/adpf`, `exp/fake-tier`, `exp/glass-container`, `exp/same-frame-backdrop`, `codex/exp-dual-kawase`, `codex/exp-same-frame-source` | older | checkpoints without the beta SDK fixes |

Compile-time flags on those branches (default false): `MORPH_GLYPH_BLUR_ATLAS`,
`MORPH_GLYPH_ATLAS_REDUCED`, `MORPH_GLYPH_ATLAS_DENSE`, `MORPH_BAR_GLYPH_BATCH`,
`MORPH_BAR_GLYPH_BOUNDS`, `MORPH_DIRECT_GEOMETRY`, `MORPH_DIRECT_FIELD`,
`MORPH_GPU_FUSION_FIELD`, `MORPH_DIRECT_FIELD_MATERIAL`, `MORPH_OPTICAL_BATCH`.
Architecture background: tool/audit/codex-rendering-architecture-research.md,
codex-gpu-research-reconciliation.md, codex-navigation-transition-report.md.
Where to aim next: encoding, submission, allocation and foreground work; do
not swap blur kernels without counting acquisition, producer and consumer
costs.

## 6. Latest known device figures

Profile builds, ms unless stated; most recent measurement per scene.

| device / tier / scene | figure | source |
|---|---|---|
| Pixel 6a liquid nested push / pop / enter | raster p95 10.8 / 10.5 / 11.1, UI p95 9.8 / 10.0 / 8.0; over budget 1.2 - 1.3 percent, each a page's first layout (10 - 16 ms UI) | perf/2026-10-13-bench-nav-tip |
| Pixel 6a flat nested push / pop / enter | raster p95 7.3 / 7.0 / 8.2, UI p95 6.1 / 6.2 / 5.4; same layout spikes | perf/2026-10-13-bench-nav-tip |
| Pixel 6a liquid steady navigation | raster p95 14.5 (waitForBufferRelease 4.9 ms a bad frame) | perf/2026-10-13-bench-nav-tip |
| Pixel 6a flat home-scroll / tab bar / list | raster p95 9.19 / 8.47 / 8.45; power 465 / 519 / 447 mW | perf/2026-10-06-round3-* |
| Pixel 6a liquid tab bar | raster p95 17.32 | perf/2026-10-06-*-glyph-after |
| Pixel 6a liquid / flat menu | build p95 13.4 / 11.1; raster p95 16.69 / 9.70 | perf/2026-10-06-fusion-ab, -glyph-after |
| Pixel 6a GPU Mcycles/frame flat/liquid | tab 1.050/4.142, controls 0.434/2.153, menu 0.687/3.289, sheet 0.971/6.002 | perf/2026-10-06-round4-* |
| Pixel 6a 16 resting liquid buttons | COMPOSITING 1.24 (flat 0.49); build p50/p95 1.48/3.28 | pixel6a-retain-* |
| Pixel 6a idle home | 286 mW whole phone (display 133) | perf/2026-10-06-pixel6a-energy |
| Moto g86 liquid push / pop | raster p95 9.4 / 10.6 | glass-renderer.md "Navigation glyph blur in one pass" |
| Redmi 6A flat push / pop | missed slots per window 2-4 / 3 | same |
| iPhone 16 Pro liquid segmented / tab bar / controls | build p95 1.32 / 1.56 / 2.56; raster p95 1.68 / 2.82 / 2.25 | perf/2026-10-05-apple-verify |
| iPhone 16 Pro liquid menu / home scroll / sheet | build p95 2.12 / 1.39 / 1.33; raster p95 3.05 / 2.32 / 2.76 | perf/2026-10-05-apple-verify |
| iPhone 16 Pro flat menu | build p95 1.55 (fusion ahead); raster p95 1.76 | perf/2026-10-06-fusion-ab, 2026-10-05-apple-verify |
| iPhone 16 Pro liquid buttons, raster p50 | 16: 2.50 -> 1.19 in a container; 32: 3.53 -> 1.46 | perf/2026-10-05-apple-verify |
| macOS AOT release bench | oneMoving/cached 57 us/op, manyPieces 436, megaCluster64 1 939 (8 239 unbounded); glacial flight raster p95 1.33 | release bench |

All iPhone scenes fit the 8.3 ms (120 Hz) budget at p95 on every tier.
On the Pixel every audit and navigation scene fits 16.67 ms at p95; the
frames over budget left in navigation are a new page's first layout.
