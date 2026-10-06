# Resource study: current Android capture, matte and GC costs

2026-10-06. Requested scope: investigate per-layer costs and matte/cache/
allocation waste; assess whether same-frame content replay requires a
visual downgrade. No production renderer or widget change is landed.
Two measurement-tool bugs are fixed. The evidence supports narrower
experiments, not a claim that full liquid is already near Material cost.

## Method and limits

Source: 8cfcd219f494c349362cb6dda98d3f4d2e93ff15, archived into separate
baseline and diagnostic trees. Pixel 6a, 60 Hz, portrait, Impeller Vulkan.
The existing user PHASES_ONLY edit remains untouched. The Pixel lock was
acquired with mkdir; the iPhone lock was not used.

Baseline APKs: ordinary glass_audit_test, AUDIT_RUNS=3,
AUDIT_SCENES=tab-bar,controls,menu,sheet, screenshots off, census and
owners on. Energy order liquid / flat / flat / liquid, two launches
per tier, starts below 37 C VIRTUAL-SKIN, thermal status 0 throughout,
AC at 100 percent. Separate GPU-work launches have three runs per tier.
These are exploratory baselines, not a candidate acceptance experiment.

A failed initial energy launch left an owned Perfetto recorder alive.
It also ran during the four energy launches, and was stopped afterward.
All four scene sets have complete trace coverage, but the additional
collector and the fullyLive test harness contribute CPU work. The
all-phone rail totals below are measured audit costs, not production
app-only power. Flat sheet launches range from 455 to 688 mW because of
CPU/memory-rail variation. Do not use their median as a Material power
floor. Future candidate energy gates need a clean interleaved run.

Stopping that recorder interrupted the first liquid GPU trace. Its
trace stopped before the timed windows, so its zero results are rejected.
Liquid GPU was rerun after diagnostics; both retained GPU traces cover
all timed windows and have nonzero app work. The rejected trace's hash
and metadata are retained, not its invalid numerical results as a baseline.

Counter APK: MORPH_RESOURCE_STUDY=true, three repeats. Counts compare
actual packed analytic uniform bytes and mode flags, not just revisions.
Field passes are excluded from the identical-input check. Separate VM
heap-probe APKs have MORPH_RESOURCE_STUDY=false and MORPH_ALLOC_STUDY=true,
two repeats. Native atrace has counters off, allocation probing off,
TraceSystrace=true and two repeats. Diagnostic timings are not accepted
as ordinary performance measurements.

Evidence directories under tool/ios_reference/perf/2026-10-06-round4-:
energy (rail/scheduler reductions and independent SQL checks),
baseline-gpu (reports, weighted work and coverage check), matte-study
(counter reports), alloc-study (heap-probe reductions), resource-study
(native reductions, diagnostic patch, helpers, hashes and validation).
Raw traces and APKs are temporary. The full VM reports were reduced
rather than adding 66 MB of redundant class metadata to the repository;
their original SHA-256 hashes are retained. reduce_study.py expects the
original diagnostic report before that reduction.

## 1. Capture and filter costs

Ordinary energy launches, median of launch medians. Times are ms. CPU
running time is actual scheduled app UI/raster time over scene windows,
divided by the report's active frame count; it includes test work outside
BeginFrame. It is not the same metric as a native phase duration.

| Scene | flat UI / raster p95 | liquid UI / raster p95 | liquid UI / raster running ms per active frame |
|---|---:|---:|---:|
| tab-bar | 3.98 / 8.50 | 9.11 / 13.90 | 7.44 / 9.88 |
| controls | 8.16 / 6.70 | 12.83 / 11.85 | 7.45 / 8.08 |
| menu | 11.30 / 10.01 | 13.40 / 14.35 | 7.90 / 8.86 |
| sheet | 4.57 / 7.65 | 6.60 / 13.85 | 4.99 / 9.05 |

Separate kernel GPU work, weighted per active frame. These are one
launch per tier, not an interleaved repeated candidate comparison.
Cycles account for clock variation; liquid sheet runs at a higher clock.

| Scene | flat GPU ms / Mcycles | liquid GPU ms / Mcycles | liquid / flat cycles |
|---|---:|---:|---:|
| tab-bar | 2.420 / 1.050 | 9.282 / 4.142 | 3.9x |
| controls | 0.999 / 0.434 | 4.961 / 2.153 | 5.0x |
| menu | 1.582 / 0.687 | 7.510 / 3.289 | 4.8x |
| sheet | 2.237 / 0.971 | 9.854 / 6.002 | 6.2x |

Whole-phone audit power, with the limitations above: flat/liquid
535/1014 mW tab, 439/646 controls, 498/835 menu, 572/1189 sheet.
GPU rail alone is 52/306, 23/157, 35/237, 43/666 mW respectively.
This ranks sheet and tab as useful energy targets; it proves no new win.

Liquid census, representative ordinary launch:

| Scene | mean / max backdrop filters | max independent captures | max offscreen engine layers |
|---|---:|---:|---:|
| tab-bar | 4.87 / 5 | 5 | 6 |
| controls | 3.11 / 4 | 4 | 5 |
| menu | 2.89 / 3 | 3 | 5 |
| sheet | 5.15 / 7 | 4 | 7 |

The historical menu count of about 8.8 is not the current renderer.
Sheet grouping already shares several button captures. Tab has two edge
filters, bar body, navigation body and a lifted lens. Controls have the
body container/navigation glass plus moving switch/slider lenses.

Native trace means over all scene-window frames:

| Scene | saveLayer calls/frame | saveLayer self ms/frame | raster submit incl ms/frame | Encode self ms/frame |
|---|---:|---:|---:|---:|
| tab-bar | 9.70 | 2.37 | 2.93 | 2.76 |
| controls | 6.21 | 1.32 | 2.22 | 3.24 |
| menu | 6.22 | 1.44 | 2.52 | 3.73 |
| sheet | 9.17 | 1.93 | 2.72 | 3.09 |

These are nested wall-clock slices; do not sum them or call every submit
millisecond running CPU. saveLayers inside pictures are absent from the
census, so the native count is larger. Cached matte does not remove this
per-frame engine encoding, backdrop capture and filter work.

Counter peaks show bounded output coverage: moving tab lens up to
384x256 physical pixels, switch/slider around 256x192, menu body
704x1536, sheet face 1152x1408. A sparse page container reaches
1088x2112 because its grouped shapes span the page. These are shader
output rectangles, not measurements of captured input, GPU bandwidth
or actual transient texture allocation. There is no demonstrated
accidental full-screen lens output here.

Pinned engine source, Canvas::FlipBackdrop in impeller/display_list/
canvas.cc:2415-2515, ends the parent pass, reads its texture and restores
its full size. A tighter output clip alone does not bound that operation.
Preserve blur/refraction sampling support and the mirror domain when
changing coverage; reducing bucket size is not automatically identical.

## 2. Matte reuse, retained resources and allocation limits

Median counts per complete diagnostic run:

| Scene | native matte encodes | active paints | clean matte reuses | field encodes | identical analytic encodes |
|---|---:|---:|---:|---:|---:|
| tab-bar | 513 | 513 | 0 | 0 | 0 |
| controls | 360 | 360 | 0 | 0 | 0 |
| menu | 216 | 380 | 166 | 98 | 0 |
| sheet | 16 | 67 | 51 | 0 | 0 |

Static retained layers can bypass paint completely; they are not missing
cache hits just because they do not appear in this table. Tab encodes
are the moving lens. In menu run 2 the page container paints 169 times,
reusing its matte 167 times, while the menu body changes geometry. Sheet
has very few matte encodes despite hundreds of composited frames.
No translated-reuse or successful retained-encode event occurs in these
windows; retained.refresh counts are attempts, not successful renders.
No identical analytic encoding was found in any of the three runs.
The field exclusion means this does not rule out redundant field work.

Measured per-layer peak RGBA8 ring storage during encoded activity:
0.84 MiB tab lens, 0.19 MiB each switch/slider, 16.22 MiB animated menu,
16.50 MiB the broad menu-page container, 9.50 MiB the sheet-page container,
5.58 MiB sheet face. Shared uniform arena: 595968 bytes, about 0.57 MiB,
stable through all scenes. The ring figures include current and spare
matte/material targets for that renderer. They exclude released global
textures, field textures, driver padding, retained scene references and
engine offscreens; per-layer peaks must not be summed as measured RSS.

Source already reuses shape/RSE/bounds arrays, ByteData, pipelines and
texture rings. Spare trimming and the released pool are bounded by frame
age/count. A count limit is not a byte budget: up to four large released
textures can still consume substantial RAM on a weak phone. Measure that
pool and long-loop release RSS before choosing a tighter byte budget.
The large sparse container is also a memory/coverage target, with a
tradeoff against the additional filters caused by splitting it.

The VM probe returned accumulatedSize == bytesCurrent and
instancesAccumulated == instancesCurrent for every class in every sample.
Even startup Code/InstructionsSection objects remain in those values
after reset. Treat this output as heap census, not allocated bytes per
frame. The probe also retains its own reports. Its heap growth cannot
establish a renderer leak or identify allocation call sites. Liquid/flat
end-of-sheet heap use is similar, about 64-66 MiB in this diagnostic run;
that is not a production memory budget. Do not pool objects based on the
large generic List/String counts in these reports.

Ordinary native trace: young GC 29/13/17/8 collections in tab/controls/
menu/sheet, totaling 97.9/77.6/110.3/57.6 ms over two repeats. Longest
collection 4.8/9.1/12.1/10.5 ms. The join finds no overlap between these
collections and UI Animator::BeginFrame intervals, including its frames
above 16.667 ms. They may delay later callbacks, but this trace does not
prove GC caused the observed slow BeginFrame events. Targeted allocation
stack profiling is still needed; global pooling is not an established win.

## 3. Same-frame replay and CPU/GPU balance

Same-frame replay need not change quality. Reuse the current source's
recorded pictures/display lists, with the same paint order, transforms,
clips, alpha/color space, sampling support and glass inputs, then filter
only the required region. The ordinary content remains mounted once.
There is no requirement to use a previous frame or lower resolution.
Pixel equivalence remains a test obligation, not a theoretical guarantee.

The existing GlassContentSnapshot already replays pictures for lens
content. It is not a complete page-backdrop provider: unsupported layers
fall back to toImageSync. Reusing that fallback blindly could restore the
GPU capture cost and add synchronization. Glass over glass, platform/
texture views and intervening content require explicit dependency rules.

Earlier narrow strip prototype, g1455-review.md: backdrop sigma-10 blur
GPU 3.19 ms, raster p50 5.96; a second content draw under ImageFiltered
GPU 1.36, raster 6.58. This is an existence proof of a trade, not a usable
implementation or a fidelity/energy acceptance result.

Balance means minimizing the limiting stage and total resource cost,
not equal CPU/GPU utilization. Current raster already runs about 8-10 ms
per active liquid frame on this phone. Spending more raster CPU can hurt
weak CPUs despite a GPU saving. First remove unnecessary preparation and
pass encoding; then test retained same-frame replay in one package-owned
scene. Accept a transfer only with repeated p95/p99/over-budget checks,
lower or unchanged energy, bounded memory and current-frame fidelity.
A net energy win may remain useful without an FPS win, but is not an FPS
improvement. Do not generalize one Pixel/Mali result to low-end Adreno.

## Ranked next experiments

1. Field-only preparation: menu body has about 95 field encodes/run and
   no material pass. Avoid unused analytic array packing/arena placement;
   reserve the field block's actual size. _packFieldUniformData copies
   offset, texture size and optical/contour values, not the analytic shape
   arrays. Keep the fallback/material branches correct. Measure UI phase,
   copies/allocations, ordinary energy and pixel parity; the size of the
   win is unknown.
2. Resource retention: instrument the global released pool and all held
   rings, then test a byte cap and shorter idle retention over repeated
   menu/sheet open-close loops. Compare release RSS and re-open tails.
   Reducing retained RAM by increasing allocation/power is not sufficient.
3. One-scene retained same-frame replay, starting with package-owned
   bar content and a known backdrop prefix. Compare full-color current
   frames through motion/reversal and a moving background. This is the
   larger GPU/bandwidth opportunity, with real composition dependencies.
4. Raster preparation/submit work: reduce the engine operations required
   by the scene or investigate reusable encoding. An engine fork is a
   separate delivery constraint for a package intended to run on stock
   Flutter; do not count hypothetical SDK changes as package wins.

Flat already approaches Material in the controlled round-3 scroll bench:
GPU 0.957 vs 0.743 ms, raster p95 6.40 vs 5.85. Full liquid still has a
substantial capture/filter premium. No reduction in blur, resolution,
motion cadence or optics is adopted here. A low-end Android device is
still needed before claiming the owner's target is achieved.

## Tool fixes and validation

energy.py previously overwrote the raster thread ID when two app threads
were named 1.raster. It now sums both. Direct scene-window SQL matches
all four corrected reports: for liquid launch 1, controls raster time is
9658.5 ms, versus 109.3 ms when only the last thread was counted. Rails,
GPU work and FrameTiming values are unchanged. Old caches are recomputed
when raw traces exist; otherwise a legacy CPU-cache warning is printed.

energy_android.sh now terminates its own recorder on early failure or
interrupt. A fault-injection run with mock adb/sleep confirms a failed
am start exits 1 and terminates only PID 4321 exactly once. Syntax checks
pass. This prevents the orphan encountered in this study.

Required gates, run serially: format 305 files, zero changed; analyze
zero issues; 1398 package tests; 18 example tests; dartdoc zero warnings
and errors. The diagnostic clone also analyzes with zero issues, and its
patch passes git apply --check --unidiff-zero against the baseline. The release gallery
was restored in portrait; owned traces, temporary clones and Pixel lock
are cleaned after evidence reduction. No push.
