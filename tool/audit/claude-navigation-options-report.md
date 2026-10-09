# Navigation transitions on weak Android: options and measurements (2026-10-10)

Branch `wip/measured-liquid-glass`, beta SDK (3.49.0-0.2.pre). Devices:
Redmi 6A (Helio A22 / PowerVR GE8320, Android 9, Skia, 32-bit, 60 Hz,
flat tier only) and Moto g86 power (Dimensity 7300 / Mali, Android 16,
Impeller Vulkan, forced 120 Hz, fixed performance mode). Bench:
`example/lib/perf/navigation_stage_bench.dart` (real gallery callbacks,
three repeats per case per launch), runner `tool/ios_reference/perf/nav_quick`
(`run.py`, `compare.py`, `gpu.py`). Raw reports:
`tool/ios_reference/perf/2026-10-10-nav-options/`.

Synthetic actions get no touch boost and the clocks a launch lands on
dominate 120 Hz results; every comparison below is A B (B) A from one
source tree per variant, and ranges are the two launches.

## Headline: handover base -> now -> now with the recommended options

`base` = 37abe0e (the handover), `now` = 40a76ec (production defaults),
`opt` = 40a76ec with the recommended option for the device's tier
(Redmi: `MORPH_FLAT_SHADER_BODIES=true`; Moto:
`MORPH_ANALYTIC_GEOMETRY=true`, mode `changes`). Same bench source on all
three (the base got the current bench file with its glyph counter
stubbed). Missed = vsync slots missed inside the 1.5 s window; worst =
the worst single frame (build or raster).

Redmi 6A, flat, 60 Hz (16.5 ms budget):

| case | metric | base | now | opt |
|---|---|---|---|---|
| nested push | missed | 21 - 23 | 3 | 3 |
| nested push | worst ms | 139 | 23 - 26 | 20 - 26 |
| nested push | build p95 ms | 15.4 - 15.8 | 12.7 - 12.9 | 8.0 - 8.4 |
| nested pop | missed | 21 | 4 - 5 | 2 |
| nested pop | worst ms | 127 - 130 | 22 | 21 - 24 |
| nested pop | build p95 ms | 14.2 - 15.2 | 14.4 - 14.9 | 7.6 - 8.2 |
| enter | missed | 11 - 12 | 3 | 3 - 4 |
| enter | worst ms | 69 - 71 | 20 | 20 - 22 |
| toolbar | missed | 11 - 12 | 0 | 0 - 2 |
| toolbar | worst ms | 69 - 72 | 17 - 18 | 17 - 18 |
| steady scroll | missed | 0 | 0 | 0 |

Moto g86, liquid, 120 Hz (8.3 ms budget):

| case | metric | base | now | opt |
|---|---|---|---|---|
| nested push | missed | 26 | 18 - 38 | 10 |
| nested push | raster p95 ms | 13.0 - 15.3 | 6.4 - 7.7 | 7.6 - 7.8 |
| nested push | build p95 ms | 6.6 - 6.7 | 7.8 - 8.3 | 4.8 |
| nested push | worst ms | 29 - 31 | 19 - 24 | 13 - 20 |
| nested pop | missed | 17 - 24 | 16 - 21 | 5 - 6 |
| nested pop | raster p95 ms | 14.7 - 16.1 | 7.4 - 7.8 | 7.4 - 7.7 |
| nested pop | build p95 ms | 4.9 - 5.7 | 7.5 - 7.6 | 4.3 - 4.6 |
| enter | missed | 9 | 6 - 10 | 4 - 6 |
| toolbar | missed | 2 - 5 | 2 | 1 - 2 |
| steady scroll | missed | 0 | 0 | 0 |

Reading: on the Redmi the production defaults already remove the
transition jank (missed slots per window 21 -> 3 - 5); the flat shader
bodies halve the remaining UI time. On the Moto the defaults halve the
raster time but move work to the UI thread (glyph pyramids and their
shader draws), so missed slots only drop with analytic geometry, which
takes the per-frame matte encode off the UI thread while the glass
moves and rests on the matte otherwise.

## The same, started from real input

Synthetic callbacks get no input boost: on the Moto the GPU then ran
anywhere from 265 to 1047 MHz window to window, even in fixed
performance mode, and most remaining misses fell on frames whose UI and
raster times were both well under budget. With `NAV_REAL_INPUT` the
bench asks the runner (`run.py --real`) to inject a real tap on the
message row (push) or the back key (pop), so the action gets the boost a
user's touch gets (GPU 775 - 1047 MHz in those windows); the window
starts at the input. Same three builds, two launches each:

| device | case | metric | base | now | opt |
|---|---|---|---|---|---|
| Redmi flat | push | missed | 25 | 10 - 12 | 3 - 5 |
| Redmi flat | push | worst ms | 149 - 153 | 25 - 33 | 25 - 27 |
| Redmi flat | push | build p95 ms | 19.9 - 21.4 | 16.7 - 18.5 | 8.5 - 8.7 |
| Redmi flat | pop | missed | 19 - 24 | 6 - 7 | 2 - 3 |
| Redmi flat | pop | worst ms | 142 - 152 | 20 - 23 | 23 - 25 |
| Moto liquid | push | missed | 57 | 19 - 22 | 3 - 5 |
| Moto liquid | push | worst ms | 27 - 29 | 13 - 14 | 11 - 12 |
| Moto liquid | pop | missed | 18 - 23 | 4 - 7 | 4 - 5 |
| Moto liquid | pop | worst ms | 25 - 28 | 12 - 13 | 10 - 11 |

Real input is the closer model of a user's tap and the one to judge
options by; it makes both recommended options decisive (Redmi push
missed 10 - 12 -> 3 - 5, Moto push 19 - 22 -> 3 - 5).

Branch `exp/navigation-defaults` (bc429dc, on top of this report) turns
both recommended options on by default, with the docs and one test pinned
to the traced path; package (1439), example (32) and host suites pass,
the macOS autodemo ends clean and the web build compiles. Merging it is
the owner's call.

## Options in the harness (compile-time defines)

| define | default | what it does | evidence | recommendation |
|---|---|---|---|---|
| `MORPH_ANALYTIC_GEOMETRY` | false | eligible liquid layers (<= 8 shapes, <= 4 fused boxes, uniform or tint-only) shade their shapes in the final shader: no matte, no material pass, no CPU fusion | Moto push missed 26 -> 10, pop 17 - 24 -> 5 - 6, build p95 -30 to -40 percent | turn on for liquid |
| `MORPH_ANALYTIC_MODE` | `changes` | `changes`: analytic only on frames whose geometry changed, one matte encoded at rest (rest pixels are the matte's); `always`: analytic every frame | `always` loses 15 - 30 frames per window at 120 Hz (per-pixel shape cost every frame); `changes` keeps every frame | keep `changes` |
| `MORPH_ANALYTIC_CAPSULE` | false | analytic frames shade a full-radius rounded superellipse as a stadium | Flutter's superellipse lies up to 1.2 device px (0.39 pt) inside the stadium; with `changes` the cap edge would jump by that at rest; not measured on device | keep off unless a measurement shows the bisection cost matters |
| `MORPH_FLAT_SHADER_BODIES` | false | flat fused glass bodies of <= 4 boxes filled by the merge law in a shader instead of a CPU-traced path (no CPU fusion, no software path mask on Skia) | per-pixel within 1 channel step of the law (the traced path is up to 130 off at thin necks); Redmi push / pop build p95 12.7 - 14.9 -> 7.6 - 8.4 ms; Moto build p95 -1 ms | turn on for flat |
| `MORPH_EDGE_EFFECT_BLUR` (branch `exp/edge-effect`) | true | false draws the flat fade-only scroll edge on glass tiers | Moto steady scroll GPU 6.6 -> 5.8 ms a frame, raster p95 5.7 -> 5.0; transitions unchanged | visible change: owner decision |

Shipped as defaults during this work (no option): one-pass glyph blur
with mip pyramids on Android bars, decided-block fusion, glass shadow
paths kept across frames (pixel-identical on Impeller), fading glyphs
drawn through the blur shader (removes Skia's per-item layer cache
passes: Redmi worst push / pop frame 22 - 43 -> 13 - 25 ms).

## Analytic frames on the device

The bench's frozen-clock shots (`NAV_SHOTS`, frames 0 - 48 of each
action) on the Moto, analytic (`changes`) against the matte, with a
second matte run as the noise floor (28 frames): pixels over 8 channel
steps 0 - 0.27 percent (repeat: 0), mean difference under 0.23 steps.
Most frames stay under 0.15 percent with a largest step of about 60
along glass rims. The largest steps (252 - 253, push frames 10 and 20)
are the blue and grey toolbar capsules fusing: the matte draws their tint
boundary inside the neck as a staircase (its material map is sampled at
1/8 resolution), the analytic pass draws the same nearest-shape rule per
pixel as a smooth curve (`tool/ios_reference/perf/2026-10-10-nav-options/
analytic-vs-matte-push-f10-bar.png`: matte, analytic, difference x3). At
rest the `changes` mode shows the matte itself.

The same shots on the Redmi, flat shader bodies against the traced
silhouette (28 frames, repeat noise max 8 and 0 pixels over 8 steps):
pixels over 8 steps 0 - 0.021 percent, largest step 48 along a neck
edge, mean under 0.005 steps; toolbar frames identical.

## Frame-rate policy (measured, not an option in the package)

Moto g86, liquid, production defaults (40a76ec), A B B A: forced 120 Hz
against the app asking for the 60 Hz display mode (`run.py --60`,
MainActivity picks the closest mode; a surface frame-rate vote alone
was ignored). Frames presented in the first 0.5 s of each action and
the longest gap between two frames:

| case | 120 Hz fps / longest gap | 60 Hz fps / longest gap |
|---|---|---|
| nested push | 78 / 25 ms | 58 - 60 / 17 - 33 ms |
| nested pop | 80 - 106 / 25 ms | 60 / 33 ms |
| enter | 110 - 112 / 17 ms | 58 - 60 / 33 ms |
| toolbar | 118 - 120 / 17 ms | 60 - 62 / 17 ms |

At 120 Hz a push drops about a third of its frames (uneven cadence); at
60 Hz almost none, with an occasional 33 ms gap. Choosing a rate per
screen or per transition is an app decision (Flutter has no frame-rate
API; it takes a platform call like the gallery's MainActivity).

## Tried and rejected

- Reduce-shader early-out (identical output): no Redmi change; reverted.
- Keeping glyph pyramids after a fade settles, and taking invisible
  blurred items' pyramids in the same batch: instrumentation shows the
  pyramids are dropped by child repaints between transitions and the
  second batch is the outgoing items, which start sharp; no hits.
- Analytic `always`: loses frames at 120 Hz (see above).

## Open

- The Moto's remaining push UI cost: geometry encode at the first
  frames, glass shadows of resizing bar buttons (path rebuilt per size),
  container fusion when analytic is off.
- Redmi: the route's first build frame (14 - 26 ms) and pop's first
  frames (detail page disposal, ~10 percent of UI).
