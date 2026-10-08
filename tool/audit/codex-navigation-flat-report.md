# Navigation without glass: measured attribution

## Result

The owner asked to identify what to optimize besides glass before trying
more glass-specific work. On the actual Gallery Navigation page, two
separate bottlenecks remain without any backdrop filters:

1. Animated button glyphs dominate the expensive raster tail. Their blur
   has a repeatable, substantial cost; scaling also contributes.
2. The fused capsule contour dominates a material part of the Dart UI
   work. Flat still calculates the same contour and optical field as liquid.

Removing page painting or translation does not remove the nested-transition
raster tail. Generic list optimization is not the first target for these
particular push/pop cases. This does not certify arbitrary app pages.
All omissions below are visible attribution experiments, not optimizations
accepted into the package. The main library and native motion remain unchanged.

## Protocol

2026-10-07, Pixel 6a, 1080 x 2400, DPR 2.625, 60 Hz, Vulkan/Impeller,
Flutter 3.47.2 / Dart 3.13.2, profile AOT, dark appearance, commit 7170939.
Actual GalleryApp, Inbox, Message 0 and Filter callbacks. Two cooled launches
per binary, three shuffled repeats per action, action prewarm, 500 ms
post-mount warmup, 800 ms collection. Phase observer, screenshots and CPU
profiler off during the four GPU launches. At-rest census: zero backdrop
filters in every case. The separate liquid cold_enter produced by the
stand is excluded from flat attribution; these are warmed action costs.

Tables show median percentiles of three repeats per launch, launch 1 / 2,
not the maximum frame or a presentation-latency measurement. Raw per-repeat
p50/p95/p99, means, frame counts and over-budget counts are preserved.
UI/raster/GPU overlap and are not summed. GPU is exact app-UID kernel work
per produced frame; raster includes native waits. Settled tails are not
jank. The permanent stand's root snapshot boundary remains; Inbox has no
additional repaint boundary. Each exit restores the original release APK.

## First matrix: split page, glyph and contour cost

| Action / variant | UI p95, ms | Raster p95, ms | GPU work/frame, ms |
|---|---:|---:|---:|
| Enter / flat | 11.99 / 11.16 | 13.82 / 13.68 | 2.502 / 2.470 |
| Push / flat | 15.50 / 15.08 | 23.94 / 23.73 | 2.556 / 2.514 |
| Pop / flat | 12.69 / 13.62 | 25.33 / 33.09 | 2.191 / 2.129 |
| Toolbar / flat | 5.43 / 5.63 | 14.72 / 13.40 | 1.734 / 1.706 |
| Push / no glyph paint | 12.31 / 11.81 | 7.42 / 7.44 | 1.697 / 1.677 |
| Pop / no glyph paint | 11.27 / 12.51 | 7.67 / 7.84 | 1.337 / 1.328 |
| Push / plain contour | 10.59 / 8.19 | 22.55 / 24.43 | 2.521 / 2.597 |
| Pop / plain contour | 7.10 / 6.83 | 27.13 / 24.79 | 2.199 / 2.180 |

No-glyphs hides only button content before the original wrappers: motion,
layout, dimensions, inline title and page text remain. It removes raster
p95 tails consistently, while contour calculation still costs UI time.
Plain-contour substitutes the rounded boxes' ordinary union for their
fused outline. It reduces UI time consistently and leaves the raster tail.
Neither is a fidelity-preserving implementation; their deltas are clues,
not the savings promised for a future implementation.

No-body preserves page layout/scrolling but skips shared body painting.
Push raster p95 remains 24.36 / 27.78 ms; pop 26.56 / 29.78. GPU drops
to about 1.3 ms, yet the troublesome raster tail persists. Keeping pages
stationary also fails to remove it: push 22.38 / 35.28, pop 21.46 / 24.69.
That variant changes occlusion as well as translation. It cannot establish
an isolated transform instruction cost. Enter benefits more from hiding
the page: its page construction/paint remains a separate first-use target.

## Second matrix: which glyph effects cost time?

Same protocol, separate binary and launches; compare its own flat baseline.
Only one effect is omitted per case. The inline title's effects remain.

| Variant | Push raster p95, ms | Pop raster p95, ms | Toolbar raster p95, ms |
|---|---:|---:|---:|
| Flat baseline | 29.16 / 23.26 | 23.64 / 28.01 | 14.83 / 14.27 |
| No button blur | 15.76 / 15.41 | 15.24 / 17.34 | 10.14 / 9.87 |
| No button scale | 21.48 / 19.80 | 22.97 / 23.47 | 14.32 / 13.59 |
| Full button presence | 21.84 / 24.57 | 23.86 / 23.10 | 13.53 / 13.91 |

Blur omission lowers push GPU 2.568 / 2.576 -> 1.942 / 1.938 ms;
pop 2.196 / 2.205 -> 1.583 / 1.573. It is a repeatable raster/GPU
lever, but leaving text sharp is not an accepted optimization. Scaling
omission helps the push tail, less consistently the other UI stages, and
barely changes GPU work. Glyph caching alone cannot be assumed to remove
all filter work. Full presence also paints normally invisible glyphs and
raises push GPU to 3.482 / 3.379, pop to 3.321 / 3.197. It cannot
isolate Opacity's cost and gives no efficient production shortcut.

## CPU and native raster anatomy

A separate unmodified-flat diagnostic launch collects own-isolate VM CPU
samples at 1 ms. Counts enter/push/pop/toolbar: 619/698/788/398, with
samples in all twelve windows. Fused contour inclusive share:
25.2 / 28.9 / 34.3 percent on enter/push/pop. _FieldSampler.eval alone
is 10.2 / 12.8 / 15.4 percent exclusive. flushLayout includes 40.7 /
46.6 / 50.6 percent, because LayoutBuilder builds and field preparation
occur inside layout. These percentages overlap; they are not additive.
_buildItem itself is only 0.2 / 1.3 / 0.9 percent inclusive. Optimizing
its Dart wrapper allocations alone is not equivalent to eliminating its
native rendering cost.

The end-of-run timeline ring covers only the last push/pop windows:
42 complete raster slices each, zero for the other repeats/actions. Its
coverage is explicit in timeline-windows.json. In the covered pop window,
SurfaceFrame::Encode is 262.42 ms cumulative / 37.46 ms maximum over
42 frames. CreateGlyphAtlas is 21.56 ms cumulative; its twelve bitmap
updates sum to 11.89 ms. The push atlas work is lower. Atlas updates are
real, but attributing the entire raster tail to them is unsupported.
Encode is a broad native boundary containing command/filter processing
and possible waits, not measured pure CPU time. Individual child named
slices are inclusive and must not be added to their parents.

The profiler was successfully enabled before an optional timeline-flags
RPC failed because of its quoted list encoding. Existing default streams
remained active and later CPU/timeline reads succeeded. Error, source and
coverage are preserved. This diagnostic launch is excluded from performance
acceptance and all clean GPU tables.

## Next implementation priorities

1. Optimize the animated glyph/filter path while preserving blur, scale,
   opacity and exact timing. Compare retained small glyph sources with
   their current ImageFiltered path, then a bounded shader implementation
   that combines work where the compositing law permits. Existing
   MorphGlyphRaster takes an extra small snapshot; it is not a free image
   read. Its source capture, resampling, lifetime and sharp/blurred handoff
   must be quantified. ImageFiltered is already a repaint boundary in this
   SDK, so adding one blindly is not the solution.
2. Separate flat/fake silhouette work from liquid's optical field work:
   keep the same sampler, trace grid, contour crossings and spline, but
   avoid preparing unused normal/thickness fields. Today's shared frame
   parts are tier-independent, so this needs an explicit contract, separate
   cache keys and parity tests rather than a global mode flag. For liquid,
   exact sampling/culling or precomputation remains a separate question.
   The previous two-box optimization did not establish a device win.
3. Reduce bar layout/build work only after removing those known costs.
   Measure retained item-position updates and preserve hit testing,
   semantics, menu handoffs, RTL and motion replays. Do not replace the
   measured animation with a cheaper approximation.
4. Capture real presentation jank and first-flat-entry separately. A
   60 Hz Pixel does not validate 120 FPS; that needs an actual 120 Hz
   device and about 8.33 ms per stage. A useful first target here is UI
   and raster p95 below 16.667 ms, then headroom toward 8 ms.

Any production candidate still requires full native frames, motion replays
and repeated long-window energy/GPU comparison. Visible ablation wins
have no pixel-fidelity or energy acceptance status. No library optimization
is admitted by this report.

## Owner's Flutter commit and downsampling

[Flutter commit 0c52dee3](https://github.com/flutter/flutter/commit/0c52dee3bc3653a6fefd86409b68f4e10cc4194f)
adds filterQuality to ImageFilter.shader's implicit input sampler, defaulting
to nearest sampling. Bilinear sampling can support paired Gaussian taps
or custom Kawase filters over the engine-provided input. It does not itself
reduce target resolution, pool targets, remove passes or change ImageFilter.blur.
This is a useful API capability for a prototype, not an automatic FPS fix.

Installed SDK HEAD d3b14c876900e553bc736ca19295fc09e3853e8e / engine
stamp a804b261645ef8c13eb3d5c44a5c2fb0340c5539: the commit is not an
ancestor, cached dart:ui still accepts only ImageFilter.shader(shader), and
the engine input setup still uses nearest sampling. Local history contains
the commit object; that does not mean the installed engine includes it.
The owner authorizes a follow-up SDK update for this experiment. No SDK
update or engine patch was needed for this attribution campaign. Explicit image samplers in
our previous Flutter GPU blur experiments already used bilinear filtering.

Downsampling can be tested before exhausting every idea. Scope it to the
blur intermediate, retain full-resolution sharp glyphs/edges and calibrate
the effective sigma. Half width/height means a quarter of texels for that
intermediate, not a fourfold whole-frame speedup. Stock Impeller already
reduces larger Gaussian blurs; the actual transform-adjusted sigma matters.
Linear sampling and downsampling are distinct controls. A custom
ImageFilter.shader does not provide arbitrary access to the current
framebuffer or a free configurable-resolution capture. Quality during
motion and the small-sigma handoff, command count and energy determine
whether a lower-resolution blur is useful here.

## Evidence and verification

Source, exact defines, APK hashes, pinned package inputs, four successful
GPU matrices, raw GPU streams, own-isolate CPU, partial timeline and
reduction scripts are in perf/2026-10-07-navigation-flat. The original
release gallery was restored after every launch. Large temporary APKs,
clones and streams are cleaned after evidence preservation. Serial verification passed: format 309 files / zero changes, analyze zero
issues, 1402 package tests, 21 example tests, dartdoc zero warnings/errors.
Both archived patches apply cleanly to 7170939; all four reports have
three repeats and zero backdrop filters. Timeline reduction reports zero
stack mismatches. Verification logs and final device state are archived
with the evidence. The owner's glass_phases_test.dart changes remain untouched.
