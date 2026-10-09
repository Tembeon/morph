# Owned background with real Morph optics, 2026-10-08

This is an opt-in architectural experiment on Flutter 3.49.0-0.2.pre and
Pixel 6a / Mali G78 / Vulkan, release arm64, 60 Hz. It connects an explicitly
owned texture to the actual Morph optical shader, rather than replacing the
glass with a blur-only overlay. Production keeps its existing backdrop path.

The background owner generates a 1024x2048 opaque texture. Four or sixteen
rounded lenses cover a constant total 30% of it. Their silhouettes, optical
matte, refraction, color model, highlights and foreground are Morph's normal
ones. Every consumer is explicitly invalidated on each source/glass tick,
including the stock controls. Only a uniform iOS27 regular-light appearance
and translation are measured. Neither live compositor acquisition nor
Navigation is part of this fixture.

## Implementation

`OwnedGlassBackdrop` is an internal borrowed-image contract. The harness owns
the immutable texture contents and their retirement; each optical layer owns
its own shader instance. A null `debugOwnedBackdrop` hook preserves normal
rendering. Example-only runtime wrappers specialize the existing optical
shader with `OWNED_BACKGROUND`; no new production asset or public widget API
is introduced. Sampling maps the displaced local coordinate into the source
plane. Existing local backdrop bounds still constrain refraction.

Source generation is scheduled inside the frame before consumer painting;
the background painter only draws the already published image. Updating the
source in that painter was insufficient: Flutter can paint a deeper consumer
RepaintBoundary first despite its later visual order. Earlier prototypes could
therefore show an old texture inside the glass for one frame. Their dynamic
results are diagnostic only. Idle mounting/capture requests schedule a frame
callback so the producer's retirement epoch remains valid. The optical draw
also refreshes its borrowed binding after coordinate inputs. The final provider
returns the normal path until its requested filtered images actually exist.

Controls separate different kinds of sharing:

| Mode | Optical graph / source |
| --- | --- |
| glass-grouped | N separate Morph layers, one shared BackdropKey |
| glass-merged | One Morph layer containing N shapes, stock composed blur/filter |
| glass-zero | One common Morph layer with zero requested frost |
| owned-raw | One common optical layer sampling the unfiltered owned source |
| owned-cached | One common layer sampling a once-generated stock Gaussian |
| owned-tent | Shared five-pass tent pyramid, two adjacent levels sampled in optics |
| owned-wide | Three-pass collapsed tent producer, same optical consumer |
| foreground | Background and identical labels, zero optical layers |

Fresh cases update the source and move the glass every frame. Reuse cases
move the glass over unchanged source content; no producer submission occurs
inside those timed windows. Cached Gaussian is tested only with unchanged
source content. Its initial production cost is recorded separately.

## Rejected batching and capture diagnostics

The initial frozen `RepaintBoundary.toImage` controls were invalid for this
comparison. Stock shader-filter geometry retained its screen mapping while
the boundary was replayed at an origin of zero: glass moved by (28,176)
physical pixels relative to its labels. Native `adb exec-out screencap -p`
shows correct alignment on the display. The final capture protocol preserves
the full displayed frame and a separate physical crop. Captures happen after
all timed windows and never serve as the blur source.

Recording multiple dependent render passes in one public `CommandBuffer`
was also tested. The Pixel process died with SIGSEGV in
`vulkan::command_buffer::end_renderpass`, through
`InternalFlutterGpu_CommandBuffer_Submit`, before producing a report.
Installed beta source begins a Vulkan render pass in `RenderPassVK`'s
constructor, whereas the GPU wrapper retains its encodables until Submit.
`OnEncodeCommands` then ends it. Creating several passes before submission
therefore nests their begin scopes before the deferred ends. This source
inspection explains the observed failure; no engine fix has been built or
validated. The safe benchmark retains separate submissions. The rejected
input snapshot, build identity, native crash log and relevant installed
engine sources are preserved; batching is absent from the working harness.

The stage runner now fails promptly if the benchmark process exits and saves
its process log, instead of waiting for the report timeout.

Follow-up on 2026-10-09: the archived batching implementation crashes twice
on stable 3.47.2 at the same native Vulkan frame; separate submissions complete
twice. Upstream #193867 describes the missing sequential pass lifecycle as a
new capability. See `codex-gpu-pass-lifecycle-report.md` for exact build identity,
source comparison, controls and the distinction from #193804's load/store test.

## Admission and next work

### Final measured result

The final `owned-optics-admission-gpu-1` binary includes pre-paint source
publication and has three shuffled repeats, 400 ms warm-up and 1200 ms samples.
The table shows medians across repeats. UI, raster and GPU stages overlap;
their times must not be added. This is one GPU launch, followed by two
independent presentation launches of the same source with N=16 only.

| N=16 case | UI p95 ms | Raster p95 ms | App GPU active ms/frame |
| --- | ---: | ---: | ---: |
| Separate layers, shared key, unchanged source | 11.772 | 23.430 | 13.065 |
| One common stock layer, unchanged source | 4.046 | 6.646 | 5.498 |
| Common optics, cached stock Gaussian | 4.276 | 4.200 | 2.879 |
| Common optics, reused tent | 4.612 | 4.474 | 2.863 |
| Common optics, reused collapsed tent | 3.727 | 4.526 | 2.662 |
| One common stock layer, fresh source | 6.284 | 6.685 | 5.801 |
| Common optics, fresh tent | 9.510 | 4.530 | 4.055 |
| Common optics, fresh collapsed tent | 10.929 | 4.153 | 4.115 |
| Common stock glass without frost, fresh source | 6.093 | 5.296 | 4.298 |
| Common owned glass without frost, fresh source | 6.635 | 4.644 | 3.036 |

At N=4, reuse GPU work is 7.492 ms for separate layers, 4.799 ms for one stock
layer and 2.159 ms for cached stock Gaussian. The final native phase-zero
frames of separate versus common stock layers are byte-identical for all
four N/update combinations. This grouping result is qualified for this
nonoverlapping, uniform-appearance fixture, not arbitrary widget regrouping.

The cached stock filter reduces N=16 GPU activity by 47.6% relative to the
already common stock layer, or 78.0% relative to sixteen separate layers.
The cache's initial awaited production is 29.304 ms, excluded from the warmed
samples and preserved in the report. No cold-entry or energy win follows.
Its source is owned; Picture.toImage is used once to filter that texture,
not to capture widgets or the live framebuffer.

Actual missed display slots, summed over three 1200 ms windows per launch:

| N=16 case | Launch 1 | Launch 2 |
| --- | ---: | ---: |
| Separate layers, unchanged source | 46 | 71 |
| Common stock layer, unchanged source | 0 | 3 |
| Cached stock Gaussian | 4 | 3 |
| Reused tent | 2 | 2 |
| Reused collapsed tent | 0 | 0 |
| Separate layers, fresh source | 71 | 83 |
| Common stock layer, fresh source | 8 | 8 |
| Fresh tent | 18 | 14 |
| Fresh collapsed tent | 16 | 20 |
| Common stock glass without frost, fresh source | 7 | 6 |
| Common owned glass without frost, fresh source | 0 | 0 |

Combining optical layers is the largest repeatable cadence improvement here.
Caching stock Gaussian saves GPU work but does not improve cadence over the
common stock layer in these launches. Fresh pyramids still lose cadence to
the common stock filter despite their lower GPU cost. Their per-frame producer
CPU recording medians are 5.305 ms for tent and 4.917 ms for collapsed tent,
against 2.016 ms for generating the stock control's source. Separate producer
submissions remain six versus four per dirty frame, including generation.
The previous blur-only 23% recording improvement does not carry over as a
whole-optics claim; no fresh kernel winner is admitted.

### Native image quality and resource limits

Native screen captures compare the requested source at phase zero, after
timing. Owned clear glass has <=1/255 interior error and <=2/255 rim/bounds
error. Owned cached Gaussian has <=1/255 everywhere. In both cases p95 is
zero. Every outside/background and opaque foreground witness is identical.
These checks now agree for fresh and reused source, detecting the earlier
repaint-order delay. They do not certify motion history or arbitrary reveals.

Tent versus stock: interiors max 25/p95 10 at N=4, max 20/p95 9 at N=16;
rim/bounds max 36 and 21 respectively. Collapsed versus tent reaches 2/255
in the optical output, p95 1 (the earlier blur-only result was <=1/255).
Approximate kernels remain research variants with a stated visual difference.

The benchmark reserves all kernel families to keep the matrix stable:
63.46875 MiB of explicit texture rings plus cached Gaussian, including the
source. This excludes optical geometry and native filter intermediates.
Source alone reserves 32 MiB; tent's rings add 10.65625 MiB, collapsed tent
2.15625 MiB, cached Gaussian 8 MiB. No measured whole-process RAM reduction
is claimed. Reuse submits zero producer passes inside its sample windows;
all owned cases record real optical draws, never fallback-only results.

Verification: 1407 package tests, 21 example tests, 47 targeted renderer tests,
22 Python reducer/numerical tests, zero analysis and dartdoc warnings, macOS
release and web Wasm builds, and the Metal gallery AUTODEMO done without an
exception. The native-only explicit-LOD probe now compiles to a SkSL stub for
web; this does not change the Vulkan code used in these native measurements.

The useful architectural distinction is background ownership and reuse.
Pyramid arithmetic does not eliminate native submit/allocation work. A
background that the app already owns is a viable candidate for this path;
arbitrary Flutter content behind a widget still needs an acquisition strategy
and a complete cost comparison. This fixture does not borrow a compositor
texture, call widget capture during measured rendering, or add an intentional
previous-frame source.

Before a production source API: establish paint-order and source-damage
invalidation without unconditional repaints; qualify overlap, partial reveal,
source padding, transparency, rotation/scale and mixed appearances; reduce the
benchmark's union of fixed texture pools; measure cold entry and real weak
Android devices. Actual Navigation needs a separate integration and retains
its nonglass glyph/contour/driver costs. Approximate blur quality requires an
explicit NEAR decision; matching this stock-filter fixture is not Apple
optical admission.

Evidence lives in
`tool/ios_reference/perf/2026-10-08-architecture/owned-optics`.
The exact source snapshots and build JSON identify each binary. Reproduction
uses `run_android.py build --flutter flutter-beta --mode release --target
lib/perf/mip_stage_bench.dart` with the archived defines, then `run` with
`--leave-installed`. GPU/native quality runs additionally use `--screen-shots`
and `--trace gpu`; cadence runs use `--trace presentation` without shots.
Reduce GPU work with `summarize.py`, native quality with
`owned_optics_quality.py`, and actual buffers with `presentation.py`.
