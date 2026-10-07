# Round 5: current-frame glass and resource experiments

2026-10-07. Production renderer behavior is unchanged. The native stand
now exports phase images after timing, and the restoring runner accepts
native audit APKs. These tooling changes landed as 7aae68c and 629776c.
The field preparation and released-texture byte-budget candidates were
reverted. Grouping measurements establish a useful application policy;
they do not imply a 50 percent gallery-wide improvement.

## Protocol and evidence

Pixel 6a, Mali-G78, Impeller Vulkan, Flutter 3.47.2, portrait,
1080 x 2400, DPR 2.625, 60 Hz. Runtime experiments use c80a905 as their
source base; each APK has explicit file hashes and defines. No new
production dependency was added. GPU tracing and ODPM energy tracing
ran in separate launches, with one recorder, starts below 37 C,
owned device locks and original-gallery restoration after each launch.

Native images compare phases -1, 0 and 1 after all measured windows;
there are no per-frame readbacks. The stand counts all rendered frames.
Field audits use the existing active-frame denominator instead. Never
subtract their costs from each other. GPU work periods measure active
work, not presentation latency. Rails measure the whole phone, including
the display. RSS is process-wide resident memory, not a texture census.

Compact raw frame reports, filtered GPU traces with verified identical
reductions, energy caches, PNG hashes, build manifests and experimental
patches live in `../ios_reference/perf/2026-10-07-round5/`. Large APKs,
Perfetto traces and full-size PNGs are omitted; their hashes remain.
Patches reproduce the experiments; they are not new public APIs.

## Field-only preparation: reject adoption

The candidate skips analytic shape/RSE/bounds packing and the unused
4656-byte analytic uniform emplacement when a fused field alone shades
the layer. It preserves validation and the 80-byte field block; materials
and analytic paths remain unchanged. It does not reduce a warmed shared
uniform arena: the earlier 0.57 MiB capacity remains. The candidate patch
also contains a mixed 80/4656-byte arena test across frame slots.

Native frozen-shader and candidate/baseline PNGs are identical in four
cases: fused field, regular dark, mixed models and tint pair (max channel
error 0). GPU A/B/B/A, five repeats per scene: controls remain about
4.94 ms/frame and menu about 7.5 ms/frame. UI preparation shows at most
small changes; no repeatable GPU gain appears.

Energy was repeated in eight clean launches, A/B/B/A then B/A/A/B,
five transitions/runs per scene in each launch. Four-launch medians:

| Scene | Baseline mW | Candidate mW | Difference |
|---|---:|---:|---:|
| Controls | 683.5 | 720.3 | +5.4% |
| Menu | 804.4 | 821.4 | +2.1% |

The first order alone looked worse (+9/+4 percent); the reversed order
narrows the difference. Controls barely exercise the changed path, so
this does not prove that field preparation itself causes the power
increase. It does fail to establish the required energy benefit. Keep
the reproducible patch for a future targeted encode benchmark; do not
advertise a speedup or merge this candidate.

## Grouping: measured, existing APIs

Two GPU launches and two separate energy launches, three shuffled repeats
per case, 600 ms warmup and 2400 ms windows. Four non-overlapping equal
surfaces over one background, sigma 2. Independent filters, shared key
and one merged layer use the existing renderer. No intervening content
or glass-over-glass is present. All 48 native comparisons are identical
(max channel error 0). Filters/capture keys: 4/4 -> 4/1 -> 1/1.
Values below are medians of launch medians.

| Layout / plan | GPU ms/frame | Mcycles/frame | UI p95 ms | Raster p95 ms | Whole-phone mW |
|---|---:|---:|---:|---:|---:|
| Cluster independent | 9.716 | 4.239 | 10.941 | 11.280 | 1155.1 |
| Cluster shared | 8.289 | 3.597 | 10.216 | 11.424 | 1086.9 |
| Cluster merged | 4.057 | 1.761 | 11.146 | 13.125 | 841.1 |
| Spread independent | 9.853 | 4.276 | 11.312 | 11.625 | 1183.5 |
| Spread shared | 8.286 | 3.596 | 12.274 | 11.351 | 1073.3 |
| Spread merged | 4.976 | 2.159 | 11.132 | 12.593 | 949.5 |

Cluster merge saves 58.2 percent GPU time and 27.2 percent phone power;
spread saves 49.5 and 19.8 percent. Raster p95 rises by 1.85 and 0.97 ms.
Cluster GPU rail drops 375.7 -> 138.5 mW; spread 373.0 -> 176.5 mW.
Union/visible area is 1.157 for cluster and 5.568 for spread; output filter
areas are 0.492 -> 0.406 and 0.451 -> 1.659 Mpixels respectively. Thus
output area alone is not a cost model: repeated captures and filters
can outweigh the larger union. These are geometry proxies, not transient
native-memory or input-capture measurements.

Use one container for compatible surfaces at the same backdrop depth;
shared keys provide a smaller saving when filters must remain separate.
Measure the actual arrangement and raster headroom. Do not blanket-merge
navigation bars and toolbars: their earlier +24 percent regression and
different dependencies remain valid. Current package list grouping
already exists, so no arbitrary production grouping change was made.

## Released texture budget: reject adoption

The candidate bounds the existing four-entry released RGBA8 pool at
16 MiB, drops references in FIFO order and preserves useful entries when
one texture exceeds the budget. It never disposes active/in-flight
textures. The Flutter GPU SDK here exposes no explicit texture dispose;
dropping a Dart reference does not immediately free native allocations.

An initial single/large negative control only retained 6.11 MiB and did
not test the byte cap. Two launches completed; a third was interrupted
before collection and restored the gallery. They are not acceptance
measurements. The strengthened large4/single stress switches between
four broad overlapping layers and one small layer: eight shuffled rapid
reopen repeats, 200 ms warmup and 600 ms windows, A/B/B/A GPU launches
plus separate A/B/B/A energy launches. It reaches the budget and checks
immediate closure and another five seconds without rendered frames.
All 12 native A/B phase comparisons are byte-identical.

| Metric | Count-only baseline | 16 MiB candidate |
|---|---:|---:|
| Released capacity after close | 24.375 MiB | 12.188 MiB |
| RSS after close + 5 s | 387.45 MiB | 467.04 MiB |
| Single GPU ms/frame | 2.885 | 2.839 |
| Large4 GPU ms/frame | 11.512 | 11.630 |
| Single raster p95 ms | 10.466 | 11.104 |
| Large4 raster p95 ms | 11.735 | 12.551 |
| Single power mW | 715 | 696 |
| Large4 power mW | 1566 | 1551 |

The retained references shrink while overall RSS rises by 79.60 MiB
(+20.5 percent). Allocation/finalization churn is a plausible explanation,
not a measured attribution. Energy differences are small in these short
stress windows; raster tails also worsen. This does not meet the resource
goal. The production count limit remains. Pool/helper tests and the
instrumented stress harness are retained only as patches. A future pool
policy must bound total live/native memory and allocation rate, not only
the byte sum of reusable references. The age limit advances on submitted
frames and does not expire while the app is idle.

## Haze 0.5.0: different effect, no replacement

This is [ru-ji/haze](https://github.com/ru-ji/haze), the Flutter package,
not the similarly named Compose library. Its official archive, pubspec
and license hashes are recorded. It requires Flutter >=3.41 and Dart
^3.10.4. Its progressive blur uses two sibling custom BackdropFilter
layers, horizontal then vertical, with up to 128 shader taps per axis.
It has no explicit downsample pyramid or automatic capture elimination.
The varying sigma and transition behavior differ from our uniform frost.

One exploratory three-repeat tile launch, moving background, sigma 2/10:

| Effect | GPU ms/frame at 2 | GPU ms/frame at 10 |
|---|---:|---:|
| Stock rectangular Gaussian | 2.125 | 2.155 |
| Production glass | 3.423 | 3.097 |
| Haze | 11.053 | 24.257 |
| Haze with outer ClipRect | 5.253 | 10.927 |

Haze sigma 10 raster p95 reaches 25.31 ms, beyond 16.67 ms. The clipped
variant is cheaper but changes pixels visibly (max channel error
138-157). It is not a fidelity-preserving optimization. These effects
are not visually equivalent, and no energy improvement is claimed from
this GPU-only comparison. Haze remains a laboratory dependency only.

## Same-frame replay and cache: experimental only

The exp/same-frame-backdrop prototype records the known background's
exact current-phase picture once and replays it under the final glass
ImageFilter. The source may be requested before the background paints;
phase and size still select the current frame. There is no delayed screen
snapshot. The picture is disposed on invalidation. The ImageFilter pass
origin includes its pixel-aligned clip and Gaussian padding.

The first three-repeat tile comparison, moving background, shows GPU
3.423 -> 1.955 ms at sigma 2 and 3.097 -> 2.117 at sigma 10. UI p95
rises 5.50 -> 7.09 ms at sigma 2; raster 10.25 -> 10.97. Replaying a
known prefix exchanges GPU capture work for recording/composition work.
Do not treat subtraction as exact native pass attribution.

Native static-chrome parity is max 1-2 channel steps. Translation of the
glass gives max 7/3 on tiles at sigma 2/10; a further retained-filter fix
and native text smoke give max 9/3, so movement identity is unresolved.
The text smoke uses one repeat and 300/600 ms windows; it is a correctness
probe, not a performance estimate. The retained actual ImageFilterLayer
now receives updated shader snapshots, but that alone does not fix the
moving-coordinate difference.

The full-DPR image cache costs an additional 1080 x 2400 RGBA8 image
(9.89 MiB before native overhead). It avoids recapture only for a static
source. Moving background creates a new image every frame. Native pixels
remain visibly wrong, max 215-231 after explicit input-pass and retained
uniform fixes. Its apparently lower static-source GPU time is invalid
as a fidelity-preserving result. Reject the image cache prototype.

The source contract currently covers only this known opaque painter.
Glass over glass, clipped/transformed retained subtrees, textures,
platform views, multiple independent inputs, paint order, input reach,
ROI lifetime and ownership need explicit contracts and native tests.
The prototype must not be merged as a generic backdrop service.

## Dual Kawase and the existing background texture

The initial prototype implements explicit downsample/upsample images
from the Arm SIGGRAPH 2015 5/8-tap filter. It records a bounded current
background picture, rasterizes it with toImageSync, then creates each
intermediate image. It has no CPU readback, but re-rasterizes a source
that is already drawn in the scene. Its observed cost includes that
extra image pipeline and cannot establish the limit of a direct-texture
Dual Kawase implementation. The owner explicitly corrected the research
focus to acquiring/reusing the already available background texture.

The first text smoke and edge calibration have one repeat and 300/600 ms
windows. They are preliminary correctness probes, not acceptance data.
The image sampler initially used the SDK's default nearest filtering;
Dual filtering assumes bilinear taps. The saved current prototype fixes
this with explicit FilterQuality.low. The early PNG/GPU results remain
for provenance but are excluded from valid Gaussian/kernel comparisons.
They also expose unequal effective blur widths: edge-derived native
sigma at nominal 2/10 is about 4.52/21.13 device pixels for stock Gaussian,
versus 5.87/26.44 for the initial prototype. Numeric sigma is not a matched
quality condition. The tentative 0.72/0.80 scale controls were compiled,
but their calibrated image variant was not launched after the owner
redirected the source investigation. They are not production constants
or verified calibration. One longer uncalibrated GPU launch was
interrupted, restored the gallery and has no valid report; its following
GPU/energy queue never ran. No Dual Kawase energy benefit or rejection
of the algorithm itself is claimed.

[Current-frame input audit](codex-backdrop-input-review.md) checks the
installed SDK and its exact clean engine source revision. Flutter GPU
can sample an owned texture, or wrap a ready GPU-backed ui.Image with
Texture.fromImage without copying. It cannot obtain an arbitrary
current backdrop texture from the public Dart API. Our Flutter GPU
textures currently contain geometry/material maps, not the background.
Impeller already has the background texture on the raster thread:
Canvas::SaveLayer/FlipBackdrop -> FilterInput -> RuntimeEffectFilterContents.
That native input is assigned to filter sampler 0 without returning a
Dart image. GpuImageSurface manages our produced images; it does not
capture the framework's existing scene.

A further matrix/runtime-effect composition probe keeps this native
BackdropFilter input inside Impeller, without per-frame capture. The
only picture-to-image operation initializes a 1x1 sampler placeholder
before timing, so its bilinear descriptor remains when the engine binds
sampler 0. Matrix filters alter input transforms; runtime-effect filters
may rasterize the transformed input into reduced native targets. The
size probe writes the actual automatically supplied texture dimensions
to color, rather than assuming a resolution from the filter list.
The native size probe reports RGB 64/64/0 at two downsample levels and
16/16/0 at four: input dimensions are consistent with 270 x 600 and
68 x 150, with 8-bit probe quantization of 4.24/9.41 pixels in width/height.
This proves reduced native input dimensions for this graph on Vulkan;
it does not count native passes or allocation bytes. The source is the
existing current backdrop, not a replayed widget image. The reduced
input tracks the full viewport, despite a smaller output clip. It is
not an optimally bounded ROI pyramid; output clips alone do not prove
bounded native inputs. Native pass flips/copies may still occur.

One-repeat 300/600 ms text smoke: stock Gaussian GPU 2.545/2.583 ms versus
matrix/kernel chain 3.992/4.519 at sigma 2/10. Native maximum channel
errors versus stock Gaussian are 50/35, which is visible and fails
adoption fidelity. These are exploratory costs for different images,
not an equal-quality algorithm comparison. The graph has separate
matrix resamples and kernel passes, so it is not the minimal fused
Dual Kawase graph. No production blur substitution is made.

The focused follow-up uses two GPU and two separate energy launches,
three shuffled repeats, 600 ms warmup and 2400 ms windows, with explicit
bilinear sampling. Median of launch medians:

| Mode | GPU ms/frame | Mcycles/frame | UI p95 ms | Raster p95 ms | Whole-phone mW |
|---|---:|---:|---:|---:|---:|
| Bare text | 1.409 | 0.611 | 10.245 | 12.433 | 663 |
| Stock Gaussian 2 | 2.555 | 1.109 | 10.595 | 12.625 | 895 |
| Native matrix chain 2 | 4.007 | 1.739 | 10.620 | 12.595 | 822 |
| Stock Gaussian 10 | 2.596 | 1.127 | 10.599 | 12.572 | 718 |
| Native matrix chain 10 | 4.541 | 1.971 | 11.229 | 11.907 | 873 |

GPU cost repeats closely in both launches. All fixed-phase matrix
comparisons reproduce the same max errors 50/35. At sigma 10 the chain
raises phone power about 21.6 percent. At sigma 2 the apparent pooled
power reduction is not repeatable: Gaussian launches vary about
1054/737 mW while chain launches are about 822/821. CPU scheduling and
clocking differ; do not sell that pooled median as energy savings.
The image is different in every comparison, so these measurements
characterize this implementation, not an equal-quality algorithm race.
Input ROI, fused resample/kernel passes, effective width, temporal
stability and integration with the final optics remain R&D work.


## Next optimization decisions

1. Prefer existing grouping for compatible chrome, choosing by full
   GPU/energy/raster measurements, not union area alone.
2. Reuse the current source before optimizing the blur kernel: prefer
   native filter graphs for arbitrary backdrops, or an already owned
   texture for Flutter GPU. The known-prefix replay remains a separate
   static-chrome experiment with unresolved native coordinates.
3. Evaluate blur kernels only after including source acquisition, every
   intermediate pass, allocations and temporal/edge fidelity. Calibrate
   actual blur width, not just a numeric sigma argument.
4. Pursue native allocation lifecycle/total memory accounting before
   lowering released-pool budgets. Test GpuImageSurface ownership for
   matte/material outputs against the manual ring; it does not capture
   the backdrop. The small reference count is not RSS.
5. Verify eventual candidates on a genuinely weak Android and iOS; this
   Pixel is one Vulkan device, not a low-end acceptance certificate.

The target remains full current-frame liquid appearance, repeatably lower
whole-phone power and memory, and p95 below the device frame budget with
headroom. This round does not establish Material-level liquid cost.

## Verification and disposition

Final package gates pass: formatter unchanged, analyzer zero issues,
1398 package tests, 21 example tests, dartdoc zero warnings/errors.
The restoring runner's six Python tests pass. All four experimental
patches apply cleanly to c80a905; the laboratory source analyzes cleanly
and its native matrix APK was compiled and measured. Widget fallback
tests are not presented as native renderer proof. The source checkout
used for the engine audit matches the installed SDK and is unmodified.

The original release gallery is restored after every native launch;
expected APK SHA-256 is
46067271b0547de0bc092c52052f1986b1391d36412c350fc1e6c63ede3bd3c3.
The occupied iPhone lock was untouched; no new iOS verification is
claimed. The pre-existing PHASES_ONLY integration-test edit is preserved.
No renderer candidate, Haze dependency, prototype debug hook or shader
is promoted into production. Reproducible research stays in the report
and patches; owned temporary builds and raw captures are cleaned up.
