# Compatible foreground filter cohorts

2026-10-09, WIP, Pixel 6a, release arm64, Impeller Vulkan, Flutter beta
3.49.0-0.2.pre, framework 38ec981bad, engine 774a767348. Default flag off:
`MORPH_BAR_GLYPH_BATCH`. Sources/results:
../ios_reference/perf/2026-10-09-glyph-cohorts.

## Mechanism

The prototype replaces a glyph's separate filter, transform and opacity
widgets with one render proxy. The positioned item, semantics and pointer
listener remain outside it. A RenderStack subclass can paint compatible
adjacent items through one Gaussian, one scale and one opacity layer.
There is no new kernel, new backdrop, extra widget snapshot or public
Flutter GPU command-buffer change. Existing Android glyph rasters remain.

Cohorts require exact local sigma and scale, equal quantized 8-bit alpha,
and disjoint transformed item boxes grown by 4 screen sigmas plus one
device pixel. A union larger than twice the summed grown areas is rejected.
Only contiguous siblings are combined, preserving their paint order.
An inverse common-scale placement preserves the original item centers.
Singletons retain individual filters. Layer handles are reused and released
when no longer needed; children paint through their normal wrapper chain
so repaint bookkeeping still works. A child-only repaint is tested.

The revised prototype additionally requires the existing 0.5 pt screen-blur
glyph-raster threshold. Actual bars batch only on Android, only labels and
standard unshadowed Icon widgets. Custom icon content, other platforms,
the bounded-source experiment and the prefiltered atlas retain independent
paths. Arbitrary overflow, fonts/emoji, 200% text scale and native gesture
retarget fidelity still need qualification before any production adoption.

## First attempt: rejected image quality

The unrestricted first attempt reduced early nested push filters 10 -> 9
and pop 10 -> 8, but not phase 10's ten filters. Whole-layer opacity counts
also declined, including singleton full-alpha passthroughs.

Phase-4 glyph-witness maximum was 222/255 push and 197/255 pop, with 173
and 698 changed witness pixels. Phase 10 and enter/toolbar glyph witnesses
were identical. The affected outgoing glyphs had screen sigma 0.2729 pt,
below raster activation; the shared source therefore rasterized live text
in a different filtering surface. Source-grid/AA differences are the
working explanation, not a proven exclusive native attribution.

One three-repeat GPU pair was essentially unchanged: push 6.230 -> 6.209,
pop 5.463 -> 5.472 ms/frame. Raster push 14.50 -> 12.77 ms did not establish
a pacing win; UI push/pop worsened in that pair. The rejected binary,
source snapshot and all owned original images are retained, not silently
replaced by the revised variant.

## Revised experiment

The revised native image matrix adds frames 5, 6 and 8 between the original
4 and 10, capturing the interval when a retained raster can qualify before
its blur halo or deformation makes neighbors incompatible. Captures occur
after all measured windows. Graph inventory distinguishes source sprites
from retained filter layers; neither is a native GPU pass/allocation count.

Both sides use direct field, live glyph Gaussian and benchmark performance
hints plus immediate UI feedback. Three shuffled repeats, seed 2026100911,
warm 500 ms, sample 800 ms, real Gallery Navigation callbacks, action
prewarm on, no hardware touch boost. Build JSON identifies each APK/define.
The old preliminary presentation control has a shorter post-timing shot
list; it is retained as diagnostic evidence separately from the final cohort.

### Revised image result: still not admitted

Forty native framework-root captures per side, frames 0, 1, 4, 5, 6, 8,
10, 20, 34, 48. Phase 4 is now identical in push and <=2/255 at one pixel
in pop. Only phase 5 coalesces filters in this sampled matrix: push
10 -> 9, pop 10 -> 8. Phase-5 glyph witnesses still differ by max 37/255
push (708 changed pixels) and 7/255 pop (2094 changed pixels). Enter and
toolbar active glyph witnesses are identical; later nested phases are
identical or have <=2/255 isolated noise. The added phases prevented an
incorrect exact-fidelity conclusion from the original sparse capture set.

Gaussian sigma is unchanged mathematically, but a common intermediate
surface does not preserve all native sampling/coverage decisions. A
source-grid explanation remains an inference. Current halo/transform
compatibility checks alone do not establish native pixel equivalence.
Full-frame isolated page/contour outliers up to 64/255 are retained in the
raw comparisons separately from the systematic phase-5 glyph difference.
This is framework-root `toImage` readback after timing, not a direct
SurfaceFlinger screen capture or temporal-quality certification.

### Revised GPU-traced pair

Median of three repeats per action, one launch per side:

| Action | UI p95 control / candidate ms | Raster p95 control / candidate ms | GPU active control / candidate ms/frame |
|---|---:|---:|---:|
| Enter | 5.16 / 5.50 | 13.14 / 11.88 | 5.093 / 5.099 |
| Nested push | 8.87 / 9.63 | 18.64 / 19.63 | 6.252 / 6.236 |
| Nested pop | 7.78 / 8.25 | 19.05 / 15.04 | 5.589 / 5.677 |
| Toolbar | 7.19 / 6.25 | 15.50 / 12.74 | 4.375 / 4.454 |

GPU work is essentially unchanged; tails are mixed. UI/raster/GPU stages
overlap and must not be summed. These results do not establish an FPS or
presentation win. The planned final ABBA FrameTimeline cohort was not run
after the revised candidate failed the visual gate. Only a preliminary
control FrameTimeline launch was collected, with no candidate comparison;
it cannot establish candidate cadence. No missing metrics are inferred.

### Verification and next work

1419 package tests, 21 example tests, twelve targeted glyph tests, zero
analysis/dartdoc warnings, format/diff checks, macOS release, Wasm and
Metal AUTODEMO pass. Desktop AUTODEMO uses default experiment flags; it is
not a candidate Metal fidelity/performance qualification. No measured
physics, shader kernel or production default changed. The flag remains
false, and Pixel retains the revised candidate benchmark for further work.

This experiment shows why a blanket common foreground filter is unsuitable
for current Navigation: the real sigma/scale/opacity/overlap combination
permits little coalescing, and native sampling still changes in that narrow
interval. It is not evidence that every form of batching is impossible.

The next larger experiment is a compatible optical material pass across
disconnected local components. The owned-background lab already measured
a strong grouping benefit, but real Navigation must preserve per-field
coordinate grids, sparse coverage, appearance, apart/dissolve behavior and
overlap order. Another foreground attempt should preserve each source's
native sampling grid and include every newly batched phase. Proxy-only
render-object consolidation can be measured separately if pursued; the
current pair does not isolate its effect from coalescing.
