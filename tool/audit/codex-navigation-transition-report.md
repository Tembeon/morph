# Navigation research and bounded foreground filters

**Research implementation may be incorrect or incomplete.** A result here
qualifies the tested code and setup; it does not rule out a corrected or
better implementation of the same idea.

2026-10-09, WIP. The bounded-source candidate is not admitted as a production
optimization. It reduces Flutter source-box area, but does not establish a
general Navigation presentation improvement and introduces small foreground
image differences. The flag remains off by default.

Audit: ../../docs/research/navigation-transition-audit.md.
Pinned external reference notes:
../../docs/research/navigation-transition-reference-notes.md.
Raw evidence: ../ios_reference/perf/2026-10-09-navigation-transition.

## Experiment and control

Pixel 6a, Mali-G78, Impeller Vulkan, release arm64, 1080 x 2400, DPR 2.625,
60 Hz. Flutter beta 3.49.0-0.2.pre, framework `38ec981bad`, engine
`774a767348`. Same source, APKs differ only by
`MORPH_BAR_GLYPH_BOUNDS=false/true`. Complete build metadata and source
snapshot are archived; HEAD alone does not describe the dirty WIP source.

Both sides use the current research control: direct field enabled, live
glyph raster plus stock Gaussian, benchmark UI/raster hints and immediate
UI reports. This is not the production-default gallery or a comparison
against stable. No new backdrop algorithm, physics or shader is introduced.
Each launch shuffles the same four actions with seed 2026100911, three
repeats, warm 500 ms and sample 800 ms; actions are prewarmed. No hardware
touch boost is simulated. Frozen framework-root image readback follows all
timed windows and is never charged as transition work.

The candidate centers a smaller filtered glyph source within the unchanged
item and hit box. Back labels retain full horizontal fitting and crop only
vertically. Text, icon, semantics and edge-of-item tap placement are covered
by new LTR/RTL widget tests. There is no added clipping or frame delay.

## Release graph observations

The bench now records the retained Layer tree and attached visible liquid
render objects, plus enabled foreground source boxes. Collection occurs at
mount metadata or after timing, not on every timed frame. In the frozen
nested-push/pop phases 4 and 10 there are ten foreground `ImageFilterLayer`s,
two or three liquid layers and one shared capture key. This is a graph
inventory, not a count of native submissions, captures or texture allocations.
The old assert-only inspector is empty in release and is not used as proof.

Liquid `blurPassSigma` is zero in all 28 sampled control phases. Source
confirms the separate backdrop Gaussian is omitted in those states; the
optical shader/capture still runs and may include its own small softening.
This observation is specific to this fixture's sampled phases, not all
frames, all blur, or other frosted widgets. Foreground Gaussian filtering
is still present. The expensive transition cannot simply be attributed to
a separate Gaussian pass behind these glass bars.

| Action, active glyph phase | Control source area, logical px squared | Candidate | Reduction |
|---|---:|---:|---:|
| Enter | 7724 | 3759 | 51% |
| Nested push/pop | 16143 | 6171 / 6170 | 62% |
| Toolbar | 6871 | 2504 | 64% |

The filter count is unchanged. These widget source sizes are not GPU
attachment sizes. Impeller may already crop painted coverage; the current
measurements do not demonstrate a native allocation reduction.

## GPU-traced pair

One launch per variant, median of three action repeats:

| Action | UI p95 control / candidate ms | Raster p95 control / candidate ms | GPU active control / candidate ms/frame |
|---|---:|---:|---:|
| Enter | 5.85 / 5.65 | 12.52 / 11.65 | 5.108 / 5.111 |
| Nested push | 9.40 / 7.52 | 19.84 / 19.18 | 6.299 / 6.228 |
| Nested pop | 7.80 / 8.49 | 17.00 / 14.36 | 5.563 / 5.628 |
| Toolbar | 3.51 / 7.44 | 13.89 / 11.58 | 4.389 / 4.423 |

GPU cost is essentially unchanged in this pair. FrameTiming tails vary
substantially within each launch; all individual repeats are retained.
This is not a statistically established GPU or raster win. GPU work-period
activity is UID-attributed and prorated over action windows; it is not
per-pass timestamp-query elapsed time or presentation latency.

## Actual presentation, ABBA

Separate FrameTimeline launches, same binaries and defines. Each cell is
the sum of missed display slots across three 800 ms action windows:

| Action | Control A1 | Candidate B1 | Candidate B2 | Control A2 |
|---|---:|---:|---:|---:|
| Enter | 7 | 12 | 18 | 9 |
| Nested push | 17 | 17 | 9 | 16 |
| Nested pop | 11 | 18 | 15 | 19 |
| Toolbar | 6 | 3 | 13 | 8 |

Over both launches, control/candidate totals are 16/30 enter, 33/26 push,
30/33 pop, 14/16 toolbar. Push shows a possible benefit; entry regresses and
the other actions do not establish a repeatable improvement. Total missed
slots are 93/105 across all selected windows. This aggregate is not an FPS
average or a significance estimate. Long gaps remain up to about 67 ms.

The reader selects real Impeller buffers, maps action MONOTONIC time to
Perfetto BOOTTIME, and preserves merged/dropped buffer observations. It
excludes gaps before/after the first/last mapped presentation in a window.
SurfaceFlinger jank flags are reported separately. Android reports thermal
status zero in every before/after dump; battery temperature spans 34.6 to
35.6 C. Skin HAL snapshots are retained; there is no continuous thermal or
power-rail measurement in this round. ABBA does not remove all DVFS noise.

## Frozen native image checks

Twenty-eight owned framework-root captures per comparison: four actions,
frames 0, 1, 4, 10, 20, 34, 48 under the bench's fixed-step screenshot clock.
These are native Impeller `toImage` renders after timing, not direct Android
screen grabs or proof of display cadence. Only names in the fresh report's
`shot_graphs` are selected; pulled artifact folders also contain stale PNGs.

Active glyph witnesses use the union of transformed source boxes plus a
fixed 100 physical pixel halo. Candidate errors at phase 4 are <=2/255.
At phase 10 the max is 3 enter, 4 push, 5 pop and toolbar; glyph-witness p95
is <=1/255. Changed pixels number roughly 9k-14k per phase-10 image. This
is a small, systematic filtering/raster-placement difference, not an exact
image match. We do not claim a readability or temporal-quality admission.

Repeated control images have zero phase-10 glyph-witness error and <=2 at
phase 4 (one changed push pixel). Both control/control and control/candidate
also have unrelated isolated native contour/page outliers up to 64/255
outside active glyph witnesses. The raw full-frame differences retain
those outliers; they are not silently excluded to claim exact equivalence.
The repeat supports distinguishing that sparse noise from the candidate's
systematic phase-10 change.

## Verification and disposition

1409 package tests, 21 example tests, zero analyze/dartdoc warnings,
format/diff checks, macOS release and web Wasm builds passed. Metal
AUTODEMO completed all gallery pages without an exception, using default
renderer flags. It is a baseline integration check, not a performance or
fidelity qualification of the bounded candidate on Metal.

The experimental flag and its placement/hit tests are retained for isolated
research, default false. There is no production FPS claim, commit, push,
SDK restoration or gallery APK restoration. Pixel ends with the control
benchmark installed, following the ongoing beta research workflow.

Next work should reduce compatible foreground/material submissions and
measure native pass topology, not assume a smaller child box means fewer
GPU pixels. Preserve separate sigma, transform, overlap, opacity and apart
semantics when batching. The shared-backdrop and analytic-geometry paths
remain independent research axes; the audit records which parts already
exist so a second navigation architecture is not built unnecessarily.
