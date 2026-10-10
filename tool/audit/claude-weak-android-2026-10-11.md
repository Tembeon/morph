# Weak Android, beyond navigation (night of 2026-10-11)

Devices: Redmi 6A (4 x A53, PowerVR GE8320, Skia, 60 Hz, flat tier) and
Moto g86 power (8 cores, Mali, Impeller Vulkan, forced 120 Hz, fixed
performance mode, liquid tier). Harness: the glass audit
(example/integration_test/glass_audit_test.dart, 3 timed runs per scene,
synthetic input) and the navigation bench, run through
tool/ios_reference/perf/nav_quick/run.py; every comparison is A B B A from
one tree per variant. Raw reports: tool/ios_reference/perf/2026-10-11-night/
(prefixes below).

## Device hygiene

- The Moto had system-wide atrace categories enabled
  (`debug.atrace.tags.enableflags=0x1404e`, left by an earlier tracing
  session): every app emitted trace markers and kernel GPU traces grew to
  1.5 GB a run. Cleared (`setprop debug.atrace.tags.enableflags 0`). Runs
  with tracing load also landed on higher CPU clocks (push build p95 about
  2 ms instead of 4): never compare traced and untraced runs.
- Night light was on (scheduled) on the Moto; switching it on and off
  changes nothing measurable (`nl-*`: push / pop identical), its color
  matrix runs in the display hardware. Left off. The Redmi had none.

## Landed (pushed to wip/measured-liquid-glass)

| change | commit | Redmi 6A flat | Moto g86 liquid |
|---|---|---|---|
| MorphListSection paints in its own repaint boundary | 18a569b | home-scroll raster p95 19.4 -> 6.2-6.5 ms, over budget 131-142 -> 0-1; list build p95 5 -> 2.4 (`rb-*`) | neutral (`mrb-*`) |
| tab bar labels snap their glyph scale while the bar swells (MorphGlyphSnap; bar items off Android too) | 52b84ac, a823499, 0387422 | tab-bar raster p95 14.0-15.7 -> 11.9-12.1, over budget 4-10 -> 0-1 (`gs-*`) | neutral (`mgs-*`) |
| menu fusion workers only on >= 6 cores | 3715416 | menu raster p95 34-39 -> 28.5-29.4, p99 57-76 -> 44-49 (`fp-*`) | prefetch neutral either way (`mfp-*`) |
| the flat menu fuses its silhouette's edge only (no shading field), contour bit-identical | 6cb91df | menu UI build p95 15.0-15.3 -> 11.0-11.2 ms, over budget 30-33 -> 27-28, warm cache (`fm-*`) | - (liquid keeps the field) |
| the gallery asks Skia for a 128 MB GPU resource cache (app setting) | (this commit) | menu raster p95 23.3-23.6 -> 21.5-21.6, over budget 33 -> 27; texture creations in menu windows 419 -> 25 (`sc-*`, warm cache) | - (Impeller ignores it) |
| list section cards shade their glass over the card's own color: one shader paint, no backdrop filter | e872d85, 30df6d8 | - (flat tier) | list raster p50 8.9-9.4 -> 4.4-4.8 ms, p95 13.7 -> 5.4, over budget 387-454 -> 5 (`sb-*`); device shots within base-vs-base noise; tab-bar / home-scroll / segmented unchanged by the new uniform (`su-*`) |

Tonight's start (ab5b970) against the head (3715416), Redmi flat, all
scenes (`rall-*`): home-scroll raster p95 19.3 -> 6.0-6.4 ms and over budget
130-135 -> 0; tab-bar raster p95 15.2-15.5 -> 11.9-12.1, over budget 9-14
-> 1; list build p95 5.1-5.2 -> 2.3-2.4; segmented, controls, sheet
unchanged; menu within its (large) run spread.

Why the scroll fix works: the gallery's sections sit under a
SliverToBoxAdapter, so every scroll frame repainted every row, card and
separator; on Skia each rounded superellipse is a fresh path that the
software path renderer rasterizes again (Skia caches a path mask only for
the same scale and sub-pixel translation, which a scrolling list never
repeats). Behind a boundary the picture is replayed and Flutter's raster
cache serves it.

## Measured, not landed

- Moto, scroll edge blur off (fade only; option on branch exp/edge-effect,
  visible change, owner decision): tab-bar raster p50 11.2 -> 9.0 ms, list
  9.0 -> 7.4, over budget about -100 to -170 (`ne-*`).
- Moto, the edge effect's seed copy confirmed: the legacy unbounded blur is
  worse in every scene (home-scroll raster p95 4.2-4.4 -> 7.5-7.8; `eb-*`).
- Moto, shader glass shadows (MORPH_SHADER_SHADOWS) from real input:
  neutral to slightly positive (push raster p95 3.4 against 3.6-7.2,
  missed 0 both; `shd-a3/a4/b3/b4`); stays an option.
- Redmi menu content blur through the one-pass glyph shader: worse (raster
  p50 +1.7 ms, over budget 35 -> 55; `mb*-*`). The pyramid pays for small
  glyphs, not a large content layer. Rejected.

- Moto menu, content blur off (timing proxy): no change (raster p95
  18.5-18.7 -> 18.4-18.5, `mnb-*`); Impeller's menu cost is elsewhere.
- Redmi menu, the flat body filled as a plain rect instead of its traced
  path (timing proxy): no change in cold-cache runs (`rf-b*` against
  `rf-a*`, buried under shader compiles), but warm: raster p95 19.7 / 20.0
  -> 17.7 / 18.6, over budget 29 / 32 -> 16 / 16 (`rw-*`). Skia rasterizes
  that concave, per-frame path in software and uploads its mask every
  frame. A GPU fill from the fusion's own field (a vertex mesh, alpha from
  the distance) is in progress.
- Redmi menu, content blur off (timing proxy): raster p95 25-36 -> 18-21,
  p99 41-152 -> 23-35 (`rf-c*`). Blurring the content at a half or quarter
  resolution layer instead (render scaled down, blur, scale up, as Skia does
  internally): no change on either phone (`rf-d*`, `mlow-*`): the cost is
  the blur's passes and render-target switches, not its pixels. Rejected.
- App glass containers over a known opaque page color
  (`MorphGlassContainer(solidBackdrop:)`, opt-in, in review): Moto sheet
  raster p50 10.5-11.8 -> 7.9-8.9, over budget 235-247 -> 158-176; menu
  raster p95 19.3-19.8 -> 17.3, over budget 136-147 -> 118; controls over
  budget 18-22 -> 14-18 (`sp-*`). Shots within noise except 51 rim pixels
  up to 24 steps on the controls page (the glass no longer sees its own
  drop shadow under the rim).

- Navigation bar painted inside its scroll edge effect's seed offscreen
  (branch edge-hosts-bar, e17ad0b + an unpushed guard fix): the bar's
  backdrop filter and frost then cover the band-sized offscreen instead of
  the whole screen. Host pixels within 2 steps. On the Moto it engages
  (traced) and saves nothing: tab-bar raster p50 11.5 / 11.6 -> 11.7 / 11.8
  (`eh-*`). For comparison the whole edge effect costs 2.2 ms there
  (tab-bar raster p50 11.3 / 11.6 -> 9.2 / 9.3 without it, `ab-*`): its own
  copy and blur, not the bar's filter after it. Not merged.
- The list sections' repaint boundary (18a569b) trades on the Redmi's
  navigation: nested push raster p95 11.8-12.3 without it, 13.1-14.5 with
  it, pop 13.2-13.9 / 13.4-16.7; enter 10.4-13.3 / 8.9-10.0 (warm cache,
  real input, `nr-*`). Skia's raster cache serves the sections' pictures
  while scrolling (home-scroll 19.4 -> 6.5) and has to create those
  entries while a page slides in. Kept: the scroll win is far larger.
- Navigation tonight, start ab5b970 -> head f8fe93b, real input, two
  launches each: Moto unchanged or slightly better (nested push raster p95
  7.7-8.9 -> 7.5-7.9, missed slots 6-11 -> 6-9; `nm-*`); Redmi enter raster
  p95 11.7-12.8 -> 9.8-10.0, nested push / pop about +1 ms raster p95 (the
  boundary above; `nr-*`).

## First use on Skia

The Redmi's 200 - 1150 ms single frames in the menu scene are Skia
compiling GL programs mid-animation (58 compiles a run, PowerVR driver
compiles of 200 - 780 ms each); Skia keys its Gaussian blur program by the
kernel radius, so every new content blur radius compiles. The engine keeps
compiled programs in code_cache, which Android wipes on every install or
update: a relaunch of the same build has none (menu raster worst 41 - 53
ms, p99 32 - 34, `rf-t3`). Users meet them once per app update, on the
first menu opens. Every run.py run reinstalls, so Redmi tails in earlier
reports carry these spikes; steady-state Redmi numbers now come from a
warm-up launch followed by a launch without installing. Open: fewer
distinct radii (quantized blur) or a deferred warm-up, both visible or
risky; not attempted.

## Diagnosed, next

- Moto list scene (done above): it was GPU-bound at the GPU's top clock
  with 4.6 backdrop flips a frame, two of them the list cards' stages; each
  Impeller flip ends the render pass and draws the whole previous frame
  back into the new one (upper bound with the row buttons removed: raster
  p95 13.8 -> 4.5, `lb-*`; the solid stages reach 5.4).
- Moto tab-bar is now its worst scene: raster p50 11.4 ms, about 640
  frames over budget a run, 4.85 flips (edge effect seed + blur, nav bar,
  tab bar, lifted lens), all over live content.
- Moto sheet (raster p95 25 ms) and tab-bar (15 ms) are GPU-bound too:
  4.4 and 4.85 flips a frame (census `maud-census-all.json`).
- Redmi menu tail frames: Skia's multi-pass blur of the fading content
  (13 offscreen passes a frame) and the morphing flat silhouette, three
  software-rasterized paths a frame (5 - 8 ms each). A shader fill of the
  blurred-SDF silhouette needs its field on the GPU each frame - candidate,
  not started.
