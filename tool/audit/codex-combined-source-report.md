# Combined source, blur and Morph optics (2026-10-07)

## Result

Upstream renderer fixes through 3cec75eda468f9c6e481bd90b7533dcb5e997b8e
are integrated in production as c6df35e, with changelog e85a78e.
The combined same-frame experiment is preserved locally at a34b9d0 on
exp/same-frame-backdrop. It is NOT merged into the production renderer.

A versioned, bounded owned picture can feed unchanged Morph optics in the
current frame, reuse blur while that source translates, and avoid the
native backdrop read. Final small Gaussian: GPU 4.073 -> 1.900 ms/frame
and selected whole-phone power 738 -> 609 mW for unchanged-source motion.
Native phase max channel error is 3/255, including source updates.
This is NEAR on the tested fixture, not universal fidelity acceptance.

This is not an unconditional replacement. Final periodic-update power
increased 3.8 percent despite lower GPU work. All-frame invalidation only
saved 2.5 percent power. Large-sigma all-frame Gaussian and both measured
all-frame Dual paths spent MORE energy. Keep production Gaussian and
require workload-specific energy/fidelity acceptance before integrating
an owned-source contract into real Morph chrome.

## Production upstream sync

The upstream main snapshot was fetched from
[flutter_liquid_glass](https://github.com/whynotmake-it/flutter_liquid_glass/tree/3cec75eda468f9c6e481bd90b7533dcb5e997b8e) at 3cec75e (Oct 6),
versus the previous vendored ab1c2d2. Only three library Dart files changed;
upstream geometry GPU code and shaders did not change. Local Morph shader,
outline and grouping patches were preserved.

- Hidden layers compare against the committed frame rather than stale
  last-encoded geometry and stop redundant paints; hide/unhide is covered.
- Shadowless fake layers skip their shadow saveLayer.
- Fake appearance overrides have their own clipped transfer while reading
  the shared original source, including when the default transfer is
  identity. Separate shapes are excluded from the shared outline using
  nested inverse clips; no Skia-incompatible path Boolean was introduced.
- Morph explicitly sets the layer/container palette from Morph brightness,
  preserving grouping when system brightness differs. Existing one-filter
  grouping tests and four added upstream regression tests pass.

This sync has correctness and avoided-work evidence, not a numerical
native-device speed claim. Full gates: format unchanged, analyze 0 issues,
1402 package tests, 21 example tests, dartdoc 0 warnings/errors.

## Combined graph and scope

One immutable text/tile base picture is retained. A current source version
records that base plus a changing high-contrast marker. The same version
is drawn as the visible background and sampled by glass in this frame.
One shared ROI covers four fixed glass surfaces, kernel reach, a 28-point
source translation guard and optical displacement guard. No screenshot
of the previously displayed frame is used. ROI rasterization on a miss
is real extra work and is inside the timed pipeline.

mix-native is the grouped production BackdropFilter + Gaussian + complete
Morph optics. mix-gaussian records source and native Gaussian into one
picture on a miss, retains its output, and applies the current translation
when the original optical shader samples it. mix-dual uses deferred native
Canvas 5/8-tap snapshots, retains the reduced result and fuses the final
8-tap upsample into the optical reads. No per-pass Dart Flutter GPU queue
submit is needed by these combined paths. Geometry remains sampler 1;
full existing material/refraction/lighting remain in the optical shader.
The owned wrapper reuses stale-uniform caching and disposes its shader.
Stock shader wrappers preprocess the original behavior.

mix-bare draws the same source without glass. It costs about 1.43-1.45 ms
GPU here; it is NOT a Material benchmark. Material's earlier 0.77 ms
belongs to a different fixture and is not an interchangeable floor.
For final immutable-source motion, glass adds about 0.47 ms above this
fixture's own 1.43 ms bare floor, versus about 2.64 ms on the stock path.
Reducing misses and owned-source raster area is the main remaining lever;
these figures do not certify a slower Android phone or Material parity.

Workloads per typical 144-frame/2.4-second window:

| Source workload | Recordings / ROI misses | Cache hits |
|---|---:|---:|
| Immutable source, current translation | 0 | 144 |
| Quantized marker updates | 30 | 114 |
| Marker changes every frame | 144 | 0 |

All four final native reports pass the freshness/counter checks. The
reported source and blur versions agree. Static prewarm precedes
collection; changing-source misses are included. blur_passes counts one
Gaussian filter operation or explicit Dual snapshot passes, excluding
its fused final taps: it does not count native engine render passes.

This fixture has an opaque owned picture, uniform ios27Dark material,
one glass depth, fixed glass coverage and source translation only. It
does not establish nested-glass semantics, platform-view/external-texture
capture, arbitrary affine/perspective transforms, moving-glass ROI
coverage, alpha composition, or a virtualized list as an immutable picture.
The implementation is an experimental seam, not a general backdrop API.

## Correcting the implementation

The installed Flutter 3.47.2 source d3b14c876900e553bc736ca19295fc09e3853e8e
shows Texture.fromImage sharing ready image storage. A toImageSync image
has deferred raster work; its backing texture is not ready immediately on
the UI thread. The first native smoke verifies that conversion fails on
those misses. A public API does not expose the current private Impeller
backdrop attachment. The combined version uses native deferred image
sampling rather than treating capture as a free framebuffer read.
Primary implementation: [Flutter GPU image import](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/engine/src/flutter/lib/gpu/texture.cc#L149).

Impeller applies nonlinear ScaleSigma to logical sigma BEFORE the entity
scale. The earlier two-image small Gaussian supplied physical sigma to a
filter: nonlinear scaling reduced it below the half-resolution threshold
(about 5.657 device pixels), accidentally buying full-resolution blur.
Naively fusing that physical sigma under a scaled canvas then overblurred
the source (max channel error 87): rejected. Logical sigma in one picture
corrected scale, but an odd 839-pixel ROI width shifted the reduced grid
(max 11 at small sigma): rejected. Aligning small Gaussian ROI to two
physical pixels makes it 840 pixels wide and reduces max error to 3.
An inverse-ScaleSigma two-image diagnostic also reaches max 3 but costs
3.762 ms GPU under all-frame changes versus 3.520 in the fused diagnostic.
The final branch uses the single-picture logical-sigma variant.
Primary implementation: [Impeller Gaussian scale and grid selection](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/engine/src/flutter/impeller/entity/contents/filters/gaussian_blur_filter_contents.cc).

These corrections matter more than quoting a blur-only microsecond
number: the measured graph includes source raster, blur and full optics.

## Native protocols

Pixel 6a, Vulkan/Impeller, DPR 2.625, 1080 x 2400, 60 Hz. Three shuffled
repeats per case, 800 ms warmup, 2400 ms collection; two GPU and two energy
launches in GPU/energy/energy/GPU order. Seven post-collection phase shots:
-1, -0.5, 0, 0.0034013605, 0.006802721, 0.25, 1. No screenshot readback
inside the measured windows. build records pin APK/source hashes and all
defines; device records include temperature.

GPU numbers are medians over the six collected repeat windows. Power is
sum of the available ODPM rails divided by sampled time, then mean of two
launches: selected whole-phone rails, not per-app isolated power or battery
terminal power. UI/raster percentiles are medians across repeat windows.
Raster wall duration includes engine waits; it is not pure CPU execution
or shader time. At 60 Hz low miss counts do not imply the GPU is cheap.

Final corrected-small APK: 708399b38e2b31b45610932b44e93c7eae47c6e8c2bb7d34a9503fc09f724332.
Seed 202610087; 9 cases (bare/native/Gaussian, three workloads, sigma 2).
Native build source hash e9bf0edee55ab963b9a843555316bfa92b62efa4673bd7c3d093f3ff8af85815.
The preserved branch normalizes formatting and contains the same final
operations. combined.patch/input manifest preserves the frozen measured
text inputs against c6df35e, including prior direct-GPU diagnostic modes.

### Final small Gaussian, source + blur + full optics

| Workload | Native GPU ms | Gaussian GPU ms | Native power mW | Gaussian power mW | Energy delta |
|---|---:|---:|---:|---:|---:|
| background | 4.073 | 1.900 | 738.4 | 608.6 | -17.6% |
| updates | 4.064 | 2.234 | 748.3 | 776.6 | +3.8% |
| dynamic | 4.084 | 3.531 | 754.2 | 735.5 | -2.5% |

| Workload / path | UI p50/p95/p99 ms | Raster p50/p95/p99 ms | Counted frames / over budget / gap slots | Power launch 1/2 mW |
|---|---|---|---|---|
| background/native | 1.210/1.883/2.514 | 10.540/12.565/13.389 | 863 / 0 / 0 | 742.7/734.2 |
| background/gaussian | 1.051/2.181/2.990 | 10.570/12.192/13.100 | 864 / 0 / 0 | 591.2/626.0 |
| updates/native | 1.203/1.966/2.329 | 10.464/12.457/13.444 | 864 / 0 / 0 | 736.4/760.3 |
| updates/gaussian | 1.050/1.933/2.891 | 9.360/11.680/12.661 | 864 / 1 / 0 | 791.4/761.9 |
| dynamic/native | 1.190/2.015/2.832 | 10.232/12.631/13.685 | 864 / 1 / 0 | 738.4/769.9 |
| dynamic/gaussian | 1.983/2.694/3.207 | 6.840/8.062/8.982 | 864 / 0 / 0 | 731.4/739.6 |

42 declared phase comparisons (21 per GPU launch) have max channel error
3, face 3, rim 3, outside glass 1. This covers marker-transition phases;
source freshness is also checked during timed windows. No iOS acceptance
or arbitrary-scene identity is claimed.

### Earlier hybrid protocol and Dual comparison

The separate best-floor APK bc7284c84df6692a51b8c3a6b7868594e9ebafc8acd5dce8d44189928634b6f5
used small Gaussian in TWO images and large Gaussian in ONE picture.
Seed 202610085; 21 cases including Dual at sigma 2/10 and three bare cases.
Do not label its small-Gaussian energy as the final branch's energy. The
large Gaussian topology is unchanged in the final source, but large sigma
was not repeated with the final APK. Full percentiles, repeats and launch
variation are in metrics.json.

| Workload / sigma | Native GPU ms / mW | Hybrid Gaussian GPU ms / mW | Dual GPU ms / mW |
|---|---|---|---|
| background/2 | 4.084 / 743.3 | 1.915 / 630.5 | 2.013 / 601.0 |
| background/10 | 3.679 / 680.8 | 1.913 / 588.0 | 2.013 / 601.2 |
| updates/2 | 4.094 / 749.8 | 2.704 / 660.1 | 2.485 / 650.6 |
| updates/10 | 3.691 / 695.7 | 2.339 / 634.9 | 2.888 / 679.8 |
| dynamic/2 | 4.098 / 735.0 | 5.664 / 852.8 | 4.255 / 764.3 |
| dynamic/10 | 3.684 / 688.9 | 4.038 / 724.4 | 5.905 / 992.0 |

Across 84 phase comparisons per algorithm, hybrid Gaussian max error is
4 at small sigma and 5 at large; Dual 8 at small and 5 at large. Neither
removes full optics. Small Dual is closer to the fidelity limit and brings
no final small-Gaussian GPU advantage. Large dynamic Dual reaches UI p95
4.842 ms and costs 992 mW versus native 689 mW: reject for that workload.
The hybrid Gaussian still has useful periodic-update energy results;
its topology is preserved as evidence, not silently mixed with the final
variant. A future policy must be measured rather than chosen on GPU alone.

## Energy anomaly and resource bounds

Corrected periodic-update Gaussian: power +7.5/+0.2 percent by launch.
Its GPU rail drops, while CPU rail power and frequency rise. Additional
scheduler attribution shows app CPU 5200/5327 ms versus native 5536/5598 ms
across about 7.2 seconds of collection; other CPU 6096/6584 versus
6102/6179 ms. UI+raster execution also did not grow. This does not prove
an implementation CPU-time regression, nor establish unrelated background
load as the explanation. DVFS, placement and burst scheduling remain
unresolved. The energy guard rejects admitting this path for periodic
updates on current evidence. Static power improves in both launches;
dynamic improvement is only 0.9/3.9 percent and deserves longer sampling.

One retained Gaussian output is 3.063 MiB at small sigma, 4.717 MiB large;
Dual outputs are about 0.77/1.18 MiB. These exclude base pictures, transient
native passes and allocator retention. Whole-app RSS in the full mixed
protocol ranges approximately 279.5-351.2 MiB; it cannot establish a
per-mode memory advantage. No low-end-phone RSS or sustainable thermal
budget has been demonstrated by this Pixel fixture.

## Next acceptance work

1. Carry the source-version/translation contract into one real owned
   navigation/toolbar fixture; derive dirty ROI/tile retention without
   replaying the entire virtualized list. Include misses and glass moving
   outside prior coverage, rather than relying on static-cache throughput.
2. Resolve the small periodic-update CPU-rail/DVFS anomaly with longer
   interleaved equal-temperature runs and exact native process/placement
   attribution. Recompare single/two-picture Gaussian at equal pixels.
   No automatic runtime governor or new tier is added.
3. Verify real iOS optics, nested glass, transforms, alpha and texture
   boundaries before a public API or production routing decision. Keep
   the stock path for source ownership that cannot be established.
4. Optimize high-churn/large blur only with an energy win. The current
   Canvas pyramid avoids UI submits but has too much miss-time GPU work;
   public Flutter GPU cannot yet import the deferred capture synchronously.
   A ready owned texture/native batched graph is a separate experiment.

## Reproduction and retained evidence

See ../ios_reference/perf/2026-10-07-combined-source/README.md. That directory
contains replay patches with input hashes, source snapshots, lock, native
JSON/build/device records, compressed GPU work, PNG hashes and numerical
fidelity masks, all timing/energy summaries and CPU app/other attribution.
System-wide raw Perfetto traces, APKs and native PNG files are excluded;
energy trace hashes and sizes preserve provenance. Shared recorder state
and the original release gallery are restored by each run. Full package
and example gates pass for the upstream sync and final prototype.

Production commits: c6df35e, e85a78e. Unmerged prototype: a34b9d0.
No changes were pushed. Final restoration.json verifies the original gallery SHA-256,
portrait orientation, and disabled owned trace/GPU recorders. Production report/passport gates are retained with the evidence.
