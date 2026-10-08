# Stable Navigation optimization, 2026-10-08

The owner now prioritizes smoothness on weak Android devices and accepts
a modest energy increase for a meaningful frame-time improvement. This
supersedes the earlier energy-first rejection rule; appearance remains a
gate. This change uses Flutter 3.47.2 stable without an SDK update.

## What changes

- Flat fused bodies prepare the exact silhouette alone. Block-corner
  distance minima select near blocks; the original normal-aware sampler,
  marching squares and spline still determine the contour. Optical
  distances, half-minors, turns and their field conversion are omitted.
  Silhouettes and optical outlines have separate four-entry caches.
  Fake and liquid still receive their full fields. Custom renderer
  subclasses retain the previous full-parts contract.
- On Android, app-bar and toolbar button content uses one retained
  device-resolution raster while its existing screen-space content blur
  is at least 0.5 logical pixels. Existing blur, opacity, transforms,
  hit targets, semantics and motion remain. The content widget is retained
  per button identity, activation uses immutable listenables, and the
  render object owns the image. Child repaints invalidate the source;
  deactivation, removal and disposal release it.
  iOS and web retain live bar glyphs until independently measured.
- Fractional logical dimensions select the corresponding source extent
  rather than stretching the rounded image dimensions. Existing menu
  raster call sites retain their original sampling policy.

The button raster is a small additional `OffsetLayer.toImageSync`
render, paid when needed or invalidated. It does not expose an already
rendered framebuffer. Neither change substitutes a previous-frame
backdrop or adds one frame of latency.

## Native experiment and attribution

Pixel 6a, Mali-G78 Vulkan, 60 Hz, DPR 2.625, profile APKs; shuffled
same-binary cases, cooled starts, 500 ms warm-up, 800 ms action windows.
The actual gallery Navigation callbacks drive enter, nested push/pop and
toolbar changes. GPU-work and energy are separate launches. No phase
collector, CPU profiler or image readback runs inside these windows.
Actions are prewarmed; entry windows are not cold-install startup tests.

The initial matrix has five repeats per action and two launches with
different shuffle seeds. Its `stock-flat` means a same-binary full-field,
live-glyph control, `flat` the sparse silhouette with live glyphs, and
`glyph` the combined prototype. The prototype had a small StatefulWidget
wrapper per button; final production retains the content in the
existing button-content cache and uses immutable activation values.
A later native matrix validates that port on flat and liquid.
The JSON's old `diagnostic_ablation` flag is
generic tier metadata, not an indication that effects were removed here.

Median per-run raster p95, ms, initial launch 1 / launch 2:

| Action | Full-field live control | Sparse silhouette | Sparse + retained glyphs |
|---|---:|---:|---:|
| Enter | 14.805 / 15.405 | 12.374 / 12.896 | 14.031 / 13.142 |
| Nested push | 24.545 / 28.192 | 26.636 / 30.669 | 19.916 / 21.350 |
| Nested pop | 24.870 / 27.003 | 26.248 / 25.999 | 24.417 / 21.668 |
| Toolbar | 14.283 / 15.793 | 14.125 / 14.529 | 14.788 / 13.916 |

Push improves about 19-24 percent against the full-field control and
25-30 percent against the sparse live-glyph variant. GPU active work
per frame rises from 2.527 / 2.483 to 2.574 / 2.625 ms against the
full-field control, approximately 2-6 percent. Other actions are mixed;
there is no uniform frame-time win. Sparse silhouettes improve entry
and reduce some CPU preparation, but do not fix the push raster tail
alone. These results still exceed the 16.667 ms budget on nested
transitions and do not establish consistent 60 FPS.

The final immutable-activation port has five repeats in its own shuffled
launch. Live and retained glyphs use the same silhouette/optics:

| Tier / action | UI p95 live -> retained | Raster p95 live -> retained | GPU ms/frame live -> retained |
|---|---:|---:|---:|
| Flat enter | 10.717 -> 10.517 | 14.373 -> 12.641 | 2.493 -> 2.506 |
| Flat push | 15.200 -> 14.374 | 27.672 -> 21.620 | 2.513 -> 2.498 |
| Flat pop | 12.900 -> 12.730 | 26.679 -> 19.739 | 2.168 -> 2.224 |
| Flat toolbar | 5.416 -> 6.913 | 13.463 -> 14.205 | 1.698 -> 1.729 |
| Liquid enter | 14.761 -> 13.689 | 14.884 -> 16.057 | 4.790 -> 4.790 |
| Liquid push | 26.690 -> 21.612 | 33.843 -> 25.341 | 5.807 -> 5.950 |
| Liquid pop | 23.375 -> 24.631 | 32.829 -> 26.671 | 5.147 -> 5.303 |
| Liquid toolbar | 11.353 -> 8.361 | 16.596 -> 15.400 | 4.033 -> 4.089 |

The preceding three-repeat port used owner-state notifiers; gallery
regression tests exposed a disposed-notifier reparenting error, corrected
by immutable activation. Its native pop raster p95 improves from 33.833
to 26.729 ms, but push reverses direction: 22.782 -> 28.551 ms. Those
reports and the separate `port-v1.patch` are retained, not described as
final source. Liquid pop improvement repeats across both ports; liquid
push has substantial launch variation. UI is still over budget in nested
liquid actions, and median frames over budget are 10/10 for final push
and 9/9 for final pop. Faster raster work is not equivalent to a measured
presentation-FPS gain. Do not advertise uniformly smoother glass or
stable 60 FPS from these data.

## Energy tradeoff

Separate three-repeat workflows run four cycles of enter, push, pop,
toolbar, exit: 16 seconds per measured window. Median selected ODPM
rail power, mW:

| Launch | Full-field live control | Sparse silhouette | Sparse + retained glyphs |
|---|---:|---:|---:|
| 1 | 556.4 | 571.6 | 541.9 |
| 2 | 534 | 537 | 547 |

The combined prototype gives about -2.6 / +2.4 percent against the
control: no repeatable power saving. This modest measured cost is
acceptable under the owner's updated smoothness priority. These rails
include the screen and other processes; they are not app-exclusive
power. Liquid power has not been established by this flat workflow.

One sparse window reaches 727.6 mW. It is retained in the evidence.
Its app scheduled CPU time is lower, while system_server/SystemUI and
CPU frequencies rise. This suggests a system/core-placement contribution,
but does not prove the entire outlier external. No sample was removed
to manufacture a power result.

## Fidelity and verification

The silhouette-only change has identical hashes for all 63 host
scene/tier collections, compared with the actual original source.
Seeded random two-to-four-box tests compare path bounds, lengths and
tangents and check translated caches and field isolation. They also
check that fake/liquid still receive fields.

Native phase readbacks follow timing collection: four actions times
frames 0, 1, 4, 10, 20, 34, 48. The initial sparse silhouette comparison
changes seven pixels total over 28 frames, with isolated body errors
up to 64 also seen in repeated references. The final production glyph
comparison gives a chrome maximum of 8/255 on flat and liquid; 99/25
chrome pixels exceed six steps across 28 pairs. Whole-frame maxima are
64/11 on isolated body pixels, while a liquid same-variant repeat reaches
63 with only 12 changed pixels and chrome maximum 1. The preceding port
has whole-frame maxima 64/56 and same-variant 64; both sets are retained.
Thus native frames
are NEAR, not byte-identical; full-frame raw errors are not concealed by
reporting only the bars. A render test also checks source refresh after
child changes and release on deactivation and unmount at fractional DPR.

Final gates pass serially: formatting, analysis with zero issues,
1404 package tests, 21 example tests and documentation with zero warnings
or errors. The full gallery regression includes appearance/page changes
that exposed the intermediate port's ownership error. The updated
release gallery is built from the main source; its installed hash,
portrait state and tracing cleanup are recorded in `device-final.json`.

FrameTiming raster duration is CPU/raster-thread duration, not GPU
execution or Android presentation latency. GPU kernel work periods are
prorated across the windows; scheduling gaps are not presentation-jank
measurements. No low-end-device guarantee follows from one Pixel model.

Evidence and reproduction are in
`tool/ios_reference/perf/2026-10-08-navigation-stable`. Final production
matrix results and commit gates are recorded there alongside the initial
raw reports, source patches, input locks and native pixel statistics.

## Next bottlenecks

Retained glyphs still pass through the original ImageFiltered blur and
scaling composition. Nested transitions also retain the full optical
field, native pass submission and glass backdrop work. The next useful
experiments are reducing repeated filter/pass preparation and sharing
compatible glass work, with native timing and fidelity controls.

Downsampling can execute reduction, blur and composition in the current
frame. Its resolution does not itself imply a one-frame delay; using a
previous-frame source does. Stable explicit texture samplers already
support filter quality, but obtaining a correct generic current backdrop
is still the source problem. The newer implicit shader-input sampling
API is not required for these changes. Revisit beta only for an
identified engine/API limitation, not before exhausting these paths.
