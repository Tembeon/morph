# Gallery Navigation performance (Pixel 6a, 2026-10-07)

## Scope and result

The owner identified entering Gallery Navigation, opening nested pages,
and appbar/toolbar animations as the expensive interactions. The benchmark
now exercises GalleryApp and NavigationDemoPage itself, the real Message 0
and Filter callbacks, and the existing MorphNavigationStack shared chrome.
A permanent production benchmark and restoring runner target selection are
added. Experimental renderer behavior remains separate, with frozen source,
patches, hashes and native evidence under perf/2026-10-07-navigation.

The slowdown is confirmed. It is not primarily Gaussian blur inside these
bar capsules: their measured blurPassSigma is 0 with the gallery's default
frostControls=false. The scroll-edge effect has its own blur and identity
seed; route transitions also move page content, morph capsules, blur/scale
button glyphs, calculate fused fields and submit geometry passes.

No production performance win is claimed from these experiments. Two
candidates are tested: separate bar content to let the glass host push its
channel, and an exact two-box sampler that postpones normals until an
actual blend. Their single-action energy results are inconsistent. A
longer whole-navigation workflow is measured separately below.

## Native protocol

Pixel 6a, Android Vulkan/Impeller, 1080 x 2400, DPR 2.625, 60 Hz; profile
AOT, portrait, dark appearance, actual hard-edge Inbox and shared chrome.
All lab runs pin exp/same-frame-backdrop a34b9d0 plus the archived patch.
The owned source callback remains null: these cases use the stock backdrop
and complete optics. Production stock control uses 0858e99 plus the new
stand, not a substituted owned-source cache.

The frozen candidate stands include one extra RepaintBoundary around
Inbox to locate its scroll context and a root boundary for snapshots.
Flutter's ModalRoute already has page/transition repaint boundaries. The
permanent stand uses KeyedSubtree to locate Inbox without that extra page
boundary; the root snapshot boundary remains. Historical measurements are
from their pinned wrapper graph, not a claim of uninstrumented release cost.

The timed action matrix is enter, nested-push, nested-pop and toolbar,
three shuffled repeats, 500 ms post-mount warmup and 800 ms collection.
Actual actions are prewarmed once, followed by five seconds idle. First
liquid enter is recorded separately after shader precache, before action
warmup; this is not cold app launch. Framework phase collection is enabled
in the short candidate matrices and contributes observer overhead. The
long workflow and production control disable that observer. CPU profiling
is a separate diagnostic launch and is excluded from GPU/energy totals.

GPU work is exact app-UID kernel work-period activity prorated over each
CLOCK_MONOTONIC window, divided by produced FrameTiming frames. Power is
the sum of the available 14 ODPM rails per full measured window, not
isolated per-app power. Medians are calculated per launch over three
windows; all windows remain archived, including outliers. Raster wall time
includes engine waits and is not pure shader execution. UI, raster and
GPU durations overlap in a pipeline and must not be summed as frame cost.
An action can settle before its window ends; inferred empty vsync slots
are not measured Android presentation jank.

The initial smoke and ablation run had an Android system-triggered
Perfetto session active. After owner authorization it was stopped through
the profiling service's test-package-change path. The initially absent
DeviceConfig test key was deleted in cleanup. Verification found no
Perfetto recorders and kernel tracing/events disabled. Those early runs
are attribution only; subsequent runs have independent owned recorders.
Every runner exit restores the original installed release gallery.

## Baseline and first use

In the clean, action-prewarmed short matrices, stock liquid measured:

| Action | UI p95 range, ms | Raster p95 range, ms | GPU work/frame, ms |
|---|---:|---:|---:|
| Enter Navigation | 13.94-15.17 | 14.33-16.30 | 4.737-4.748 |
| Inbox -> Message 0 | 23.71-26.32 | 29.00-32.08 | 5.818-5.887 |
| Message 0 -> Inbox | 19.01-24.36 | 27.61-35.16 | 5.250-5.291 |
| Toolbar item-set change | 8.81-9.12 | 14.51-18.36 | 4.024-4.077 |

These are the two pair GPU launches' per-launch median percentiles, not
release-mode or SurfaceFlinger latency. A different clean baseline launch
had pop raster p95 38.87 ms. All three are preserved, not averaged into a
claim that the device always has one fixed cost.

The first enter in warm/gpu-1 had UI p95 13.365, raster p95 22.916,
p99 25.739/64.712 ms and four frames exceeding at least one 16.667 ms
stage budget. Pair/gpu-1's first enter had UI p99 39.835 and raster p99
32.115 ms, five over-budget frames. First-use work varies and survives
shader precache; a pipeline/font-atlas capture is needed before assigning
those spikes to one cause.

At-rest snapshots: two bar optical filters with one shared capture key,
plus top edge blur/seed when the edge is active (four filters, three keys).
Removing only bottom-edge blur does nothing on this page: it has no
bottom scroll-edge effect. Disabling bar frost alone also does not remove
a blur that was already zero. Top and bottom glass filter rectangles are
roughly 414 x 73 and 366 x 98 logical pixels, including their shadow reach.
These snapshots are not an in-flight topology census.

The final production stand control (stock/gpu-final, one repeat, phases
off, KeyedSubtree page locator) validates every real callback including
workflow. Liquid nested push is UI p95 20.26, raster 28.91, GPU 5.884 ms;
flat is 13.03/19.56/2.564. Liquid pop is 12.38/22.85/5.340, flat
15.52/22.36/2.138. Even flat can exceed the raster stage budget during
page transitions. One repeat is a functional/control check, not a new
stable acceptance estimate. The older stock/gpu-1 retained the redundant
page boundary; both source versions and all raw reports are preserved.

## CPU anatomy

The own-isolate VM CPU sample period is 1 ms. Filtering to each action's
exact window gives 228-383 stock samples, not a profile of screenshot
readbacks or the entire benchmark run. Percentages are estimates from
those samples, not independent additive stage timings.

| Action | GPU submit, exclusive | Fused outline, inclusive | Geometry preparation, inclusive |
|---|---:|---:|---:|
| Enter | 17.4% | 12.8% | 11.0% |
| Nested push | 19.8% | 11.7% | 12.3% |
| Nested pop | 19.7% | 15.9% | 11.9% |
| Toolbar | 22.4% | below top set | 10.1% |

Submit is CommandBuffer.__submit on the Flutter UI isolate, reached
through the deferred geometry submission flush during composition.
This identifies a costly native boundary; it does not establish whether
all its cost is CPU encoding or driver/GPU waiting. Outline sampling is
still material during nested transitions. Separate content alone cannot
remove the outline or native submit.

Short framework phase aggregates also show work spread across the
pipeline. In warm/gpu-1, nested push averages per composited frame are
BUILD 3.20, root LAYOUT 3.31, root PAINT 3.79 and COMPOSITING 3.30 ms;
pop is 3.65/3.78/3.37/3.31 ms. They are aggregate means, not p95 stage
costs. LayoutBuilder builds can occur inside layout, so these are not disjoint
stages to sum. Root and nested aggregates are not added together. The existing
energy reducer's thread_ms.ui labels the Android process main/platform
thread, so it is not used to explain the Flutter Dart UI time.

## Candidate 1: separate bar content

The old bar builds a new content Stack every tick. MorphGlassHost._push
requires identical content, so it falls through to build. The candidate
keeps the joined/apart glass hosts without their changing content and
places that content above them in the same paint order. It leaves the
optical shaders, blur, field law and motion unchanged.

Warm GPU launch: push UI/raster p95 21.70/30.15 -> 17.79/25.69 ms,
but enter UI 14.40 -> 19.03 and toolbar 9.04 -> 9.95. GPU remains about
4.0-5.9 ms. The first energy launch had power enter 663/665, push
730/702, pop 754/690, toolbar 658/676 mW (stock/candidate). The second
had 602/692, 748/704, 708/744, 659/641 mW. Earlier unprewarmed power
also flipped between launches. It is not accepted on these short windows.
Custom painters and unrelated bar interactions are not certified by this
stock-gallery content separation experiment.

## Candidate 2: exact pair sampler

For exactly two boxes and no bridges, evaluate the same signed distances
first. If one wins by at least k, return that winner before computing any
normal. Otherwise compute the same two normals and call the existing
merge unchanged. Other fields retain the old evaluator. Twenty thousand
seeded finite probes produce exactly the old sampler doubles and agree
with the independent LiquidField evaluator within 1e-10.

First GPU launch: push UI p95 26.32 -> 22.46, pop 24.36 -> 19.66 ms.
Second: push 23.71 -> 25.18, pop 19.01 -> 17.95 ms. GPU remains within
about 0.1 ms/frame; it is a CPU hypothesis, not a blur improvement.
Short energy launch 1, stock/candidate: enter 690/683, push 740/718,
pop 722/721, toolbar 642/668 mW. Launch 2: 655/681, 720/768,
696/743, 646/656 mW. These results do not support unconditional admission.
Some faster windows produce more frames, and whole-phone CPU rails have
large outliers; those are observations, not a proven cause of the flips.

## Fidelity and capture corrections

Native host Impeller/Flutter GPU, all three tiers, all four actions,
seven phases: content separation alone 84/84 byte-identical raw frames;
content separation plus pair sampler another 84/84 byte-identical frames.
The mathematical sampler test is separate from the visual test.

The first Pixel capture binding froze timestamp getters, but Ticker
callbacks still received the real handleBeginFrame timestamp. Its
misaligned max-255 comparison is invalid. The corrected binding feeds
frozen raw handleBeginFrame timestamps, advances by 16667 us, and takes
PNG readbacks after all timed windows. The failed earlier getter access
outside a frame is also retained as a failed run, not used as evidence.

Corrected content-channel Pixel comparison: 25/28 exact pairs; three pop
frames differ at one body pixel each, raw max 64/255. Pair Pixel comparison:
raw max 64, 12 changed pixels across 28 frames. A separate stock/stock
repeat itself has raw max 64 and 143 changed pixels across 28 frames;
three phase-0 glass pixels with max 10 occur identically in both comparisons.
The large errors are single body pixels, and most other changes are 1-2
steps. This quantifies native capture/repeat variation; it is not a claim
of whole-frame byte identity on Pixel. No errors were hidden by cropping.
The preserved comparison script includes all declared phases and hashes.

## Longer energy workflow

Workflow repeats enter, nested push, nested pop, toolbar change and pop
to GalleryHome five times, with 800 ms per action: approximately 20 s per
measured window, three shuffled repeats. Every workflow is prewarmed.
Framework phase collection, CPU profiler and snapshots are disabled.
The energy is that whole action mix, not one isolated route transition.
Both launches, stock/content-channel/pair-field median selected power:
706.08/705.19/705.54 mW, then 703.85/699.04/711.89 mW. UI p95 is
17.649/16.555/16.599 ms, then 17.211/17.086/17.570 ms. Raster p95 is
21.386/20.404/21.365, then 20.670/20.471/21.849 ms. The second run's
mean UI and raster both increase for each candidate.

The long windows substantially reduce the extreme short-window swings.
Content separation has only a 0.125 ms UI p95 improvement in the second
launch; pair specialization is slower and uses about 1.1 percent more
power there. Neither produces a repeatable, material navigation win.
Both remain experiments; no library optimization is merged. The stand,
measurement corrections and the quantified bottlenecks are the result.

## Next work and acceptance

1. Keep first-enter, nested push/pop and toolbar as distinct regressions;
   also retain the long workflow for energy. Capture SurfaceFlinger frame
   timelines before equating over-budget stage counts with visible jank.
2. Investigate scaled/blurred bar glyphs and whole-page repaint/layout
   during transitions. The existing menu glyph raster cache is a candidate,
   but its extra snapshots, resampling fidelity and power must be tested
   here before reuse. Do not reduce text blur or motion quality by fiat.
3. Investigate one bounded geometry atlas/pass shared by the chrome,
   retaining each bar's optical filter and coordinate grid. It could
   reduce native submit frequency; combining backdrop filters into a
   screen-spanning layer repeats an already rejected approach. Public
   Flutter GPU pass/command-buffer constraints must be respected.
4. Specialize/cull field sampling only where the exact merge law allows
   it. A CPU microbenchmark alone is insufficient: include all short
   actions, long energy workflow, motion replay and native frames.

Minimum responsiveness target is both UI and raster p95 below 16.667 ms
at 60 Hz; 8 ms each is useful headroom, not a measured current result.
GPU cost and total power must improve or remain within repeat variation,
with no visible fidelity degradation. A Pixel win does not certify a
low-end Android phone or cost parity with Material on another fixture.

## Verification and artifacts

Stock stand format/analyze, 1402 package tests, 21 example tests and
dartdoc dry run passed. Pair arithmetic test and both native host parity
runs passed. Final stock stand verification after the workflow/page-locator changes
passed all the same gates; six stage-reducer tests also pass.
No changes to the owner's glass_phases_test.dart are staged. No push.
Raw successful reports, exact windows, build defines, own-isolate CPU,
streamed GPU work, derived rail energy, source patches and image hashes:
`tool/ios_reference/perf/2026-10-07-navigation/`. Large APKs/PNGs and
system-wide traces are represented by hashes and cleaned from our temporary
workspace after preservation. See its README for reproduction and caveats.
