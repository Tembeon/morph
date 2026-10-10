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

## Diagnosed, next

- Moto list scene is GPU-bound at the GPU's top clock (1047 MHz the whole
  window): 4.6 backdrop flips a frame, two of them the list cards'
  MorphGlassStage layers. Each Impeller flip ends the render pass and draws
  the whole previous frame back into the new one. Upper bound with the row
  glass buttons removed: raster p50 9.6 -> 3.5 ms, p95 13.8 -> 4.5, over
  budget 450-500 -> 2-3 (`lb-*`); stages off (one small filter per button)
  costs the same as stages on. In progress: a stage over a known opaque
  fill (a list card's cell color, nothing painted between) draws its glass
  as an ordinary shader paint with a solid backdrop, no flip.
- Moto sheet (raster p95 25 ms) and tab-bar (15 ms) are GPU-bound too:
  4.4 and 4.85 flips a frame (census `maud-census-all.json`).
- Redmi menu tail frames: Skia's multi-pass blur of the fading content
  (13 offscreen passes a frame) and the morphing flat silhouette, three
  software-rasterized paths a frame (5 - 8 ms each). A shader fill of the
  blurred-SDF silhouette needs its field on the GPU each frame - candidate,
  not started.
