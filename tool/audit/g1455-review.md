# g1455 review: his benches, a fair Material comparison, ideas for morph (2026-10-06)

Owner question: "compare with Material, not only our own flat tier - is that
a fair comparison? PlugFox's g1455 compares and optimizes differently. Study
his benches, try them, is there room left (his glass is not real glass)?"

Sources: https://github.com/PlugFox/g1455 at 33eb89e (0.1.4, cloned to
/tmp/g1455, read only). Our side: morph 294a754 (HEAD after the list-stage
work), Pixel 6a (Vulkan, Mali-G78, 60 Hz), profile. Results:
tool/ios_reference/perf/2026-10-06-g1455-compare/ (reports, summaries,
the bench app's source; no traces or images).

## TL;DR

- His harness is not public (only 32 result digests in provenance/), so his
  benches cannot be re-run. I rebuilt his methodology instead - ONE binary,
  every variant in a seeded shuffled order, same layout, GPU cycles per
  frame - and ran Material, morph flat / fake / liquid and g1455 full / cheap
  through it on the Pixel 6a, two launches x 5 runs, plus our FrameTiming
  columns.
- Fair? Material is a fair EXTERNAL floor ("what an ordinary app pays")
  only with the same layout and content, the same binary, and both metrics:
  GPU work AND UI / raster thread time. Our flat tier is NOT a no-glass
  floor: its scroll edge effect is a backdrop blur.
- The comparison found the biggest lever on the Pixel, and it is not glass:
  the hard scroll edge effect's sigma-2 blur costs 7.6 ms of GPU a frame
  (8.48 vs 0.88 ms without it, Material 0.77). Impeller blurs a sigma of
  <= 4 device px at full resolution (CalculateScale) and the Pixel's 2.625
  dpr puts 2 pt at 5.25 px -> scale 1.0: a sigma-2 backdrop blur of the
  same strip costs 8.8 ms GPU, a sigma-10 one 3.2 ms. The bars' 2 pt frost
  sits in the same regime (liquid without the edge effect still 9.15 ms
  GPU vs flat 0.88).
- Scroll under bars, GPU ms a frame (busy share at 60 Hz): plain 0.69,
  Material 0.77 (4 %), g1455 full 2.74 (15 %), morph flat 8.48 (50 %),
  morph liquid 11.15 (67 %). Raster p50: Material 5.30, g1455 3.75, flat
  7.60, liquid 9.36 ms. Controls: GPU Material 1.14, morph flat 1.03,
  liquid 3.22, g1455 1.32 ms; UI build p50 Material 1.03, flat 1.95,
  liquid 5.18, g1455 1.89 ms. Frames over the 16.6 ms budget: 0 - 2 per run
  everywhere (Material controls 5).
- Room left: yes. Ranked: (1) small-sigma blurs (edge effect, bar frost):
  ~5 - 8 ms GPU a scrolling frame on the Pixel, pixel-equal if done as a
  shader kernel; (2) the cheap tier's edge effect without a blur; (3) the
  liquid controls' UI thread (+3.2 ms build p50 over flat); (4) fewer pass
  breaks by drawing known content twice instead of reading the backdrop
  (his capture idea done in the same frame); (5) macOS: shader / gradient
  paints with isAntiAlias false. His one-frame-late capture itself is NOT
  applicable (fidelity).

## 1. What g1455 is

A Liquid-Glass-styled package (23.4 k lines in lib/, widgets layer only, no
Material dependency) built "cost first". The render model is the opposite
of ours:

- ONE CAPTURE PER SCREEN, NO BACKDROP FILTER. `GlassHost` (above the
  navigator) re-paints the part of the tree under all glass surfaces into
  one picture with its own PaintingContext walk (lib/src/proxy/proxy_walk.dart,
  proxy_recorder.dart:98-121) and rasterizes it with
  `OffsetLayer.toImageSync` at a reduced pixel ratio into one atlas, one slot
  per surface (proxy_atlas.dart:1-30). Every surface is then a plain
  `drawRect` with a FragmentShader that samples its slot
  (shaders/glass_surface.frag:21-27, 41-60): refraction is a radial
  displacement profile `(1 - (u/t)^0.6)^1.9` sampled with ONE texture fetch
  (no dispersion), tint, an additive rim. No BackdropFilterLayer, so no
  render-pass break in the frame.
- CAPTURE ONLY ON CHANGE. A post-frame callback (glass_host.dart:1092-1110)
  asks an oracle; the oracle walks the composited layer tree and compares
  a flat signature of every layer (picture identity, offsets, opacity,
  filters; a whitelist - unknown layer types count as changed every frame)
  (proxy_layer_watch.dart:1-40, proxy_retake.dart:436-465). A still screen,
  and glass moving over still content inside a declared `GlassTravel`
  region (glass_travel.dart:98), take no capture.
- ONE FRAME LATE BY CONSTRUCTION. The capture reads the frame just painted
  and the glass shows it on the next one (glass_host.dart:9-14: "The
  one-frame delay is structural"); the first frame of a screen has no
  proxy. While content scrolls under a bar, the bar refracts the previous
  frame. His own ladder prices one frame of staleness at more than a
  quarter-resolution capture for every finish but frosted
  (proxy_retake.dart:9-20).
- BLUR = DOWNSCALE. The capture is taken at 1/N of the device pixel ratio;
  he measured the downscale + bilinear upscale as ~0.30 logical px of
  Gaussian sigma per unit of divisor, composing in quadrature, and blurs
  only the residual sigma (proxy_resolution.dart:50-66, 574;
  proxy_pipeline.dart:867).
- Capture hygiene: shadows are dropped from the capture (a filtering
  canvas drops drawShadow and mask-filter blurs, shadow_filter.dart:1-50),
  opaque covers stop the walk (occlusion.dart:1-60), `GlassProxy` roles let
  the app stand in for video / platform views.
- Glass on glass costs one capture per level (`GlassAbove`,
  glass_above.dart:66); `GlassButtonGroup` is one surface for N items
  (glass_toolbar.dart:92); groups fuse by an SDF in a second shader binary,
  split into tiles (glass_group.dart, debugGlassFusedSplit).
- Separate shader binaries per mode, because "a path a program carries and
  does not take reprices the modes that do not take it by 52-62%" (his B5,
  glass_surface.frag:79-80, glass_group.frag:4-6).
- Shader draws with `isAntiAlias = false` plus a primer draw
  (glass_surface.dart:71-128, D200): on an Impeller backend with SDFs on
  (macOS always, iOS only with FLTEnableSDFs, Android never) an
  anti-aliased paint with a color source is drawn as a white SDF mask and
  the shader joined by `MakeBlend(kSrcIn)` through offscreen snapshots
  (engine canvas.cc:2185-2209, confirmed in our 3.47.2 SDK source).
- Tiers full / cheap (translucent fill, no capture) / opaque, chosen by the
  app (`GlassTierPolicy`), never switched at runtime; a thermal policy may
  hold a stale capture for 1-2 frames under serious / critical thermal state
  (performance.md "Hardware and thermals").

So "not real glass" is fair in two concrete ways: it refracts a picture of
the previous frame, and the material is a calibrated single-sample
displacement + tint + rim, not UIKit's measured lens (no dispersion, no
depth-below-rim shrink, no lifted lens magnification law).

## 2. His benchmark methodology vs ours

His harness is NOT in the repository (no bench/, integration_test/ or
driver; the shader comments cite `bench/shaders/*.frag` and spikes that are
not published). What is published are 32 digests in provenance/digest/
(cells only). From them:

| | g1455 | morph |
|---|---|---|
| metric | GPU cycles a frame (Adreno kgsl busy x freq, 30 s windows x 3); GPU ms (iPad, engine GPUTracer, 4 s x 3); raster ms p50 (macOS) | FrameTiming build / raster p50 / p95 / p99 / over budget over active frames (UI and raster THREAD time), 5 runs median; GPU active ms and cycles from the kernel's gpu_work_period (Pixel, `AUDIT_GPUWORK=1`); energy from ODPM rails |
| scenes | synthetic: bank_home, many_cluster, over_photo, over_text, scroll_under_bar, area_n*_c*; driven by fixed scroll steps (2 px a frame) | the real gallery pages with synthetic touches (segmented, tab bar, controls, menu, sheet, home scroll) |
| variants | plain, material, flatTranslucent, fake, backdrop, pubGlass (liquid_glass_renderer, our renderer's upstream), glass at divisors, tiers | tiers liquid / fake / flat of the same app, per APK |
| binary | one binary, all variants, shuffled order (seed), warmup 3 s, cooldown 5 s | one APK per tier, ABBA across launches, cooled starts |
| devices | S25 Ultra (Adreno 830, 120 Hz), iPad Pro M2, S22 Ultra (Xclipse, cross-check), M3 Max | Pixel 6a (Mali-G78, 60 Hz), iPhone 16 Pro, macOS |
| fidelity gate | Delta-E ladder against Apple materials on stills | replay of device recordings + shot diffs, pixel parity harness |

The decisive difference is the metric. GPU cycles see the GPU work only:
they do not see the UI-thread capture walk or the raster thread's encode
and pass breaks, which is where our liquid tier pays on the Pixel (a
backdrop filter is ~0.75 ms of raster CPU there, glass-renderer.md
"Backdrop filter attribution"). FrameTiming raster time is the opposite:
it ends at submit, so a GPU saving shows only where the GPU is the
bottleneck, and it moves with CPU DVFS. Neither alone answers "what does
the glass cost"; the bench below reports both.

What his digests say (ratios computed from s938-tier-a/b, ipad-tier-a/b,
mac-drawcost-a):

| platform, metric | Material / plain | g1455 glass / Material | glass / plain |
|---|---|---|---|
| Adreno 830, GPU cycles | 1.17 - 1.34 | 0.93 - 1.20 | 1.20 - 1.42 |
| iPad M2, GPU ms | 1.02 - 1.09 | 1.80 - 2.69 | 1.86 - 2.74 |
| M3 Max, raster ms p50 | 1.06 - 1.10 | 5.67 - 6.09 | 6.25 - 6.45 |

His headline "glass at x0.99 - 1.08 of stock Material" is the Adreno
GPU-cycles number, where Material is itself 17 - 34 percent over plain
(elevation shadows and tonal surfaces on a tiler); the digests give 0.93 -
1.20 across all five scenes. On Metal the same glass is ~2x Material, and on
the Mac's raster thread ~6x. Material is not a fixed floor: it is cheap
on Apple GPUs and dear on Adreno.

## 3. Is "against Material" a fair comparison?

A fair comparison has to fix four things, and our numbers so far fixed one:

1. Same layout and content. Each library draws its own idiom of the same
   screen: a list of 60 colored tiles under a top bar (title + two
   actions) and a 4-tab bar; and a panel of two switches, a slider, a
   3-segment control and three buttons over a still tile wall. Material:
   AppBar + NavigationBar (opaque, the list does not run under them),
   Switch / Slider / SegmentedButton / FilledButton.tonal. morph:
   MorphNavigationScaffold (hard edge effect, a trailing capsule group) +
   MorphTabBar, MorphSwitch / MorphSlider / MorphSegmentedControl /
   MorphGlassButton in a MorphGlassContainer, under MorphAdaptiveGlass at a
   pinned tier with BackdropGroup + MorphScope. g1455: GlassHost above the
   navigator, GlassScrollEdge + GlassBar + GlassTabBar, GlassSwitch /
   GlassSlider / GlassSegmentedControl / GlassButton. `plain` = the list
   alone. Shots of every variant were checked (the first build showed the
   no-Material red text in the g1455 and plain variants; every scene now
   sits under a transparent Material).
2. Same driving: the scroll scene animates the controller 0 -> 2400 -> 0
   px linearly over 6 s (800 px/s); the controls scene drags the slider
   across and back, taps both switches, drags across the segments and back
   and taps a button, with stamped synthetic pointers (glass_audit's
   finger()).
3. Same binary and order: one APK, 13 (scene, variant) pairs, one untimed
   warm-up pass, then 5 runs in a seeded shuffle (seed 20261007 and
   20261008 for the two launches), each pair mounted fresh with runApp.
4. Both metrics: FrameTiming over active frames as in glass_audit (build,
   raster p50 / p95, over budget) and the kernel's gpu_work_period of the
   app's uid per scene window (GPU active ms and Mcycles per frame).

Results (Pixel 6a, 60 Hz, profile, morph 294a754, skin 33 - 35 C, thermal
status 0; median of 10 runs over two launches; the launches agree within
0.03 ms GPU per cell and within 0.5 ms raster p50, except liquid scroll
(11.37 / 8.97, and 10.87 in the ablation launch); summary-compare.txt):

| scene | variant | build p50 | raster p50 | raster p95 | GPU ms / frame | Mcyc / frame | GPU busy | over budget / run |
|---|---|---|---|---|---|---|---|---|
| scroll | plain | 1.23 | 4.57 | 5.69 | 0.69 | 0.30 | 3.9 % | 0 |
| scroll | Material | 1.83 | 5.30 | 6.37 | 0.77 | 0.34 | 4.4 % | 0 |
| scroll | g1455 cheap | 1.35 | 5.71 | 6.75 | 1.50 | 0.65 | 8.5 % | 0 |
| scroll | g1455 full | 2.01 | 3.75 | 5.32 | 2.74 | 1.19 | 15.5 % | 0 |
| scroll | morph flat | 1.79 | 7.60 | 9.06 | 8.48 | 3.68 | 50.1 % | 1 |
| scroll | morph fake | 1.90 | 9.74 | 12.15 | 11.15 | 6.72 | 65.9 % | 2 |
| scroll | morph liquid | 2.05 | 9.36 | 11.70 | 11.15 | 6.71 | 67.3 % | 1 |
| controls | Material | 1.03 | 6.06 | 8.26 | 1.14 | 0.50 | 5.9 % | 5 |
| controls | g1455 cheap | 1.32 | 6.32 | 8.01 | 1.05 | 0.46 | 5.6 % | 0 |
| controls | g1455 full | 1.89 | 5.90 | 7.45 | 1.32 | 0.57 | 7.0 % | 0 |
| controls | morph flat | 1.95 | 5.55 | 7.27 | 1.03 | 0.45 | 6.1 % | 0 |
| controls | morph fake | 3.59 | 9.29 | 12.49 | 3.35 | 1.46 | 19.9 % | 5 |
| controls | morph liquid | 5.18 | 7.81 | 10.79 | 3.22 | 1.40 | 19.2 % | 1 |

Ablation and probes (one launch each, scroll only; ablate1, probe1,
probe2; every repeated cell within 0.1 ms GPU of the table above):

| variant | GPU ms / frame | raster p50 |
|---|---|---|
| morph flat, no edge effect | 0.88 | 4.97 |
| morph flat, no edge effect, no tab bar | 0.71 | 4.50 |
| morph liquid, no edge effect | 9.15 | 7.89 |
| plain + a 1-pt-shift matrix backdrop filter over the top strip | 2.43 | 5.33 |
| plain + backdrop blur sigma 10 over the strip | 3.19 | 5.96 |
| plain + backdrop blur sigma 2 over the strip | 8.81 | 5.96 |
| plain + the edge effect's own filter (color matrix over blur 2) | 8.82 | 6.05 |
| plain + MorphScrollEdgeEffect (hard) | 7.98 | 6.14 |
| plain + the strip's content drawn a second time under ImageFiltered blur 10 (no backdrop read) | 1.36 | 6.58 |

Reading:

- Against Material, morph flat is at par where it draws no blur (controls
  0.90x Material's cycles, raster p50 0.92x; scroll without the edge effect
  1.12x GPU, 1.02x raster, ablate1) and 11x Material's GPU where the hard edge
  effect runs. Liquid is 2.8x Material's cycles on the controls and 20x on
  the scroll (14.4x in GPU ms; the clock rises from 434 to 602 MHz).
  g1455 full is 1.15x on the controls and 3.5x on the scroll - his own
  Adreno claim (~1x) does not carry to Mali, where Material is only 1.12x
  plain.
- The flat tier is therefore not a no-glass floor; the honest floors are
  `plain` (content alone) and Material (an ordinary app), and the flat
  column minus the edge effect.
- The pass break itself is cheap-ish on Mali: a trivial backdrop filter
  adds 1.7 ms GPU. The edge effect's 7.6 ms is the BLUR: sigma 2 pt is the
  most expensive sigma Impeller has on this phone (no downsample below 4
  device px, engine gaussian_blur_filter_contents.cc CalculateScale), 2.8x
  a sigma-10 blur of the same strip. The edge effect's color matrix and
  fade cost nothing measurable on top (8.82 / 7.98 vs 8.81).
- Liquid without the edge effect still spends 8.3 ms GPU more than flat
  on two bars; the bars' frost is 2 pt (glass_settings: "the bars frost by
  the renderer's 2 pt"), 5.25 device px, above the in-shader softening
  limit `shaderSofteningMaxDeviceSigma` = 1.25 (liquid_glass_layer.dart:754):
  the same full-resolution blur. Inference from the numbers, not yet
  ablated (frost 0 / 2 / 4 pt on the bars).
- None of this shows as missed frames at 60 Hz (the GPU is not the
  bottleneck of a 60 Hz Pixel frame, the raster thread is), which is why
  the FrameTiming audit never surfaced it; it shows as GPU busy 50 - 67
  percent against Material's 4 percent, i.e. as energy and heat (the
  energy-first rule), and it would show as frames on a 90 / 120 Hz Mali
  phone.
- Raster thread time is confounded by DVFS: g1455 full's raster p50 (3.75)
  is below plain's (4.57) because its capture walk keeps the CPU clocked
  up; read raster ms across libraries only next to the GPU and build
  columns.
- macOS: a profile run of the same bench was frame-starved (the window was
  occluded, ~7 fps), so its numbers are discarded; macOS was then off limits
  (owner using the Mac).

## 4. Ideas: what he does that we do not

Ranked by expected gain for morph. "Applies" = whether it works for real
refraction glass at our fidelity bar.

| # | technique (his file:line) | what morph does now (file:line) | applies | expected gain | fidelity risk |
|---|---|---|---|---|---|
| 1 | Blur as a cheap downscale (proxy_resolution.dart:50-66, 574): he never pays a full-resolution Gaussian | edge effect hard blur 2 pt through ImageFilter.blur (scroll_edge_effect.dart:417-431); bar frost 2 pt through the blur pass above shaderSofteningMaxDeviceSigma 1.25 (liquid_glass_layer.dart:754-760, 1466-1471) - both land in Impeller's no-downsample regime at dpr 2.625 | yes, as a KERNEL, not as his downscale: fold sigmas up to ~6 device px into a shader pass (ImageFilter.shader over the backdrop for the edge effect; extend the final pass's softening kernel for the frost) | edge effect 7.6 -> ~2 ms GPU a scrolling frame on the Pixel (probe: pass break 1.7 + a small kernel); bars plausibly similar (8.3 ms liquid-over-flat, to ablate); iPhone at 3x already downsamples by 2 there (6 px), smaller gain - measure | low if the kernel is a true Gaussian (gate: shader parity harness, max channel step); a downscaled blur (his way) is a visible change at sigma 2 |
| 2 | Cheap tier = no capture at all (glass_tier.dart, `GlassTier.cheap` reads nothing) | flat tier still runs the edge effect's backdrop blur (8.48 vs 0.88 ms GPU) | yes, cheap tier only: draw the edge effect as its fade + hairline without the blur on flat | flat scroll GPU 8.5 -> 0.9 ms; the GLES devices that get flat are exactly the ones this protects | a visible change, but only on the cheap tier (owner call) |
| 3 | UI-thread frugality: one host, controls cost ~ Material on the UI thread (build p50 1.89 vs 1.03) | liquid controls build p50 5.18 vs flat 1.95 (same widgets, tier only): ~3.2 ms of UI work per frame for the lifted glass | partial: find what the liquid tier builds per frame while a knob / thumb / lens is lifted (structure changes, field uploads, channel pushes) | up to ~3 ms UI per active frame on the Pixel; fewer DVFS boosts | none if it stays pixel-identical (glass_frames_test) |
| 4 | No backdrop read: one capture of the content, every glass a plain shader draw (proxy_recorder.dart:98-121, glass_draw_layer.dart:158-209) | every floating glass and the edge effect read the backdrop through a BackdropFilterLayer (pass break: +1.7 ms GPU on Mali per frame for the first one, ~0.75 ms raster CPU each, glass-renderer.md "Backdrop filter attribution") | partial: NOT his post-frame capture (one frame late, glass_host.dart:9-14), but the same-frame variant - re-add the known content's pictures under a clip + ImageFilter (or the final shader as a layer filter) instead of reading the backdrop. Probe: 1.36 vs 3.19 ms GPU for a blurred strip, but +0.6 ms raster with a naive second ListView | 1.5 - 2 ms GPU and ~0.75 ms raster per removed filter; largest for bars over a scroll view | medium-high: platform views / textures cannot be mirrored, glass over glass needs levels (his GlassAbove), content must be re-added unchanged; a research spike, not a patch |
| 5 | Shader paints with isAntiAlias false + a primer draw (glass_surface.dart:71-128, D200) | fake-tier surfaces draw `Paint()..shader` anti-aliased (paint_fake_glass_surface.dart:161); gradients in scroll_edge_effect.dart:480, menu.dart:2453, glass_glow.dart:85 | yes on macOS only (Impeller SDFs: always on desktop, iOS only with FLTEnableSDFs, Android never; engine canvas.cc:2185-2209) | he measured 1.355 -> 0.522 ms GPU for 12 surfaces on an M3 Max; also removes an offscreen that shifts the interior on fractional layouts | low; the shader writes its own coverage. Not measured here (Mac off limits) |
| 6 | One binary per shader mode (glass_surface.frag:79-80: unused paths reprice 52-62 %) | already: per color-model-family final shaders (F7, glass-renderer.md "The Mali offline compiler batch") | done | - | - |
| 7 | N items, one surface (GlassButtonGroup, glass_toolbar.dart:92) | MorphGlassContainer, bar capsules, list stages | done | - | - |
| 8 | Capture only on change (proxy_layer_watch.dart, proxy_retake.dart) | a BackdropFilter re-reads every frame something repaints; a still screen draws no frames at all | no: without his capture there is nothing to hold, and the still case is already free | - | - |
| 9 | Stale capture under thermal pressure (GlassThermalPolicy) | none | no (a stale backdrop is a fidelity regression; tiers never switch) | - | high |
| 10 | Drop shadows / occluded subtrees from the capture (shadow_filter.dart, occlusion.dart) | n/a (the backdrop is whatever the engine drew) | only together with 4 | - | - |
| 11 | Methodology: one binary, shuffled variants incl. Material and plain, GPU cycles per frame | per-tier APKs, FrameTiming first | yes, adopted here (bench/), cheap to keep: it is what found 1 and 2 | - | - |

## 5. Reproduce

Everything is in tool/ios_reference/perf/2026-10-06-g1455-compare/:
head1/head2 (the comparison, seeds 20261007 / 20261008), ablate1 (edge
effect and tab bar ablations), probe1 / probe2 (backdrop probes), each
`<name>.json` (the report, glass_audit's format plus `g1455_captures`) and
`<name>.device.txt` (thermal, uid, logcat); `summary-*.txt` are the
printed tables (the GPU columns need the 30 - 90 MB gpuwork traces, kept
in /tmp/g1455-bench-out, not committed). bench/ holds the app's source as
text (main.dart.txt, compare_test.dart.txt, pubspec.yaml.txt, the manifest)
and the two scripts:

```bash
# app: flutter create --org dev.tembeon --project-name g1455_bench --platforms android
# + bench/*.txt, morph and g1455 as path dependencies, MainActivity calling
# getExternalFilesDir(null), EnableImpeller + EnableFlutterGPU in the manifest
flutter build apk --profile --target-platform android-arm64 \
  -t integration_test/compare_test.dart --dart-define=BENCH_RUNS=5 \
  --dart-define=BENCH_SEED=20261007 \
  --dart-define=AUDIT_OUT=/sdcard/Android/data/dev.tembeon.g1455_bench/files/compare
# BENCH_VARIANTS=a+b+c and BENCH_SCENES=scroll narrow it ('+', since
# flutter splits dart-define values on commas); BENCH_SHOTS=true screenshots
# every pair once in the warm-up pass
bench/run_pixel.sh app-profile.apk <out dir> <name>   # holds no lock itself
bench/summarize_bench.py <out dir>/<name>.json [...]
```

Follow-up (same day): idea 1 landed - the edge effect blurs a copy of its
band, a frost just below half resolution is raised to it; scroll GPU flat
8.47 -> 3.71, liquid 11.15 -> 6.28 ms, energy and pixels in
glass-renderer.md "Small blurs" (the cause was also the whole-pass blur
of a band along the screen edge, not only the full resolution).

Not done: energy rails for these variants (perfetto's Python module is not
installed on this Mac; GPU busy is the proxy here); the bars' frost ablation
(idea 1's second half); macOS and iPhone runs of the bench.
