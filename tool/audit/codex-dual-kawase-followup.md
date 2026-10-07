# Dual Kawase follow-up, 2026-10-07

## Verdict and scope

The earlier result did not establish that Dual Kawase is intrinsically
more expensive than Flutter's Gaussian. It measured unsuitable pass graphs
and, initially, unequal filtering and blur widths. This round implements
fused 5/8-tap GPU passes, a bounded region, persistent targets and final
upsample/composition fusion on the Pixel 6a.

These remain experimental implementations on exp/same-frame-backdrop.
The production renderer is unchanged. Raw Gaussian likeness does not
establish glass-optics fidelity, and an owned texture is not arbitrary
widget-backdrop access. The translation-cache result below is specifically
for unchanged owned pixels with a current-frame transform.

## Source audit

The user's [video](https://www.youtube.com/watch?v=YJVYX8tllj4) links to
[Acerola's Godot source](https://github.com/GarrettGunnell/AcerolaFX-Godot/blob/e69d1883f4e4de3c3ac41ba415ae8ce1b55cc3a6/Effects/Blur/acerolafx_blur.gd).
That code consumes `get_color_layer(0)` directly in a compositor effect,
retains half/quarter/eighth/sixteenth targets, uses a linear sampler and
records compute dispatches with barriers in one compute list. Its radius
controls are not Flutter sigma controls. The kernels reference
[Arm's SIGGRAPH 2015 notes](https://community.arm.com/cfs-file/__key/communityserver-blogs-components-weblogfiles/00-00-00-20-66/siggraph2015_2D00_mmg_2D00_marius_2D00_notes.pdf).

The video page and its linked implementation were inspected. The published
caption endpoint returned an empty response. The exact hardware, image
size and timer boundaries behind the title's 50 microseconds could not be
verified; this report does not invent them or claim to have watched an
unavailable transcript. That title is not compared with our whole-app
GPU-work counter as if the two timers measured the same operation.

## What was wrong and what changed

- The first prototype rasterized the source again through toImageSync.
  The new source fixture is rendered once, asynchronously before collection.
  Its ready image supplies both the displayed background and Texture.fromImage,
  which wraps its GPU storage without copying. No source capture runs in
  a measured frame. This is an owned-input kernel test, not a solution for
  capturing arbitrary widget output.
- The first samplers were nearest. Every tested new blur sampler is explicitly
  bilinear, including final composition.
- Requested sigma did not match effective width. Native edge responses now
  calibrate the offsets; equal numbers in different APIs are not assumed
  to mean equal blur.
- The matrix chain had a whole-viewport input and separate matrix resamples.
  The new GPU down pass combines reduction and five taps; up combines
  enlargement and eight taps. It reads a guarded ROI and reuses its targets.
- The final full-resolution intermediate is unnecessary. The final eight
  samples run in the shader drawing the visible rectangle. The direct path
  has three GPU submissions at small sigma and seven at large sigma. A
  shallower large-sigma candidate uses five.
- Image-surface pooling did not stay bounded in the native smoke: 23-36
  backing textures accumulated during short runs. The installed implementation
  excludes externally referenced textures, while submitted command/pass
  wrappers can retain native references until finalization. This is a source
  explanation, not a measured proof of every reference holder. The corrected
  stand uses three fixed outputs, with reuse separated by three submitted
  framework frames. It follows the production renderer's two-frame pipeline
  and ordered-queue reasoning. This is not a general retained-scene lease API.
- An asymmetric text fixture exposed a vertical UV inversion that a vertical
  edge could not detect. Correcting the GPU vertex UV orientation reduces
  native identity-copy error from 205 to at most one channel step.
- Pure source translation does not require repeating a cached blur when the
  source pixels are unchanged. A separate cache candidate keeps the reduced
  result and updates its sampling transform in the current frame. Its guard
  must include both the blur reach and the entire translation range.

## Protocol

Pixel 6a, Vulkan/Impeller, Flutter 3.47.2, DPR 2.625, 1080 x 2400.
Base 620798e, direct-gpu.patch and extended.patch in
`tool/ios_reference/perf/2026-10-07-dual-kawase`. The original gallery SHA
is recorded in every device log and restored by the locked runner.

The direct matrix has two GPU launches and two separate energy launches,
independent seeds 202610072/73, three shuffled repeats, 600 ms warmup and
2400 ms collection per case. The immutable text fixture moves horizontally.
All rendered frames count. PNG readbacks follow collection. Seven phases
include quarter-device-pixel source shifts and both translation endpoints.
Controls and Gaussian see the identical ready source image.

GPU values are application GPU-active work per rendered frame, not isolated
kernel timestamps. Energy is whole-phone ODPM power. Subtraction from the
bare case is a comparative overhead signal, not an exact blur timer. The
source setup, cache misses, arbitrary content changes and production optical
shading are outside the retained-cache steady-state workload.

## Direct GPU results

Medians of per-launch repeat medians; milliseconds except power and cycles.

| Path | GPU ms | Mcycles | UI p95 | Raster p95 | Power mW | Max channel error |
|---|---:|---:|---:|---:|---:|---:|
| Owned source only | 0.860 | 0.373 | 1.396 | 4.160 | 504 | reference |
| Stock Gaussian, sigma 2 | 2.030 | 0.881 | 1.685 | 6.216 | 547 | reference |
| Dual, sigma 2 | 1.492 | 0.648 | 8.569 | 3.508 | 548 | 9 |
| Stock Gaussian, sigma 10 | 2.110 | 0.916 | 1.584 | 6.242 | 534 | reference |
| Dual, four levels, sigma 10 | 2.176 | 0.945 | 14.053 | 3.541 | 639 | 7 |
| Dual, three levels, sigma 10 | 1.865 | 0.809 | 11.872 | 3.378 | 564 | 8 |

The small path reduces whole-app GPU work by 26.5 percent, but does not
reduce power reliably: 545/550 versus Gaussian 575/519 mW across launches.
The shallower large path reduces GPU work by 11.6 percent but raises power
about 5.7 percent. Four levels raise power about 19.8 percent. Direct GPU
submission is therefore not a production optimization despite the improved
kernel work. The four-level large path has eight frames over the 16.67 ms per-stage
budget across the two GPU launches; other direct-matrix paths have zero.
Zero exceedances on this device do not establish a weak-phone margin.

The calibrated vertical edge has second-moment widths 4.428-4.543 device
pixels for Gaussian at sigma 2 and 4.307-4.504 for Dual; sigma 10 gives
21.055-21.195 versus 21.191-21.444. Kernel shape and phase response remain
different. Near-matched width does not imply pixel identity.

## Attribution and alternate encoding

A diagnostic native launch times API calls, including warm/prewarm paints.
Mean per-pass submit time is 0.51-1.46 ms; dynamic uniform upload is around
18-20 microseconds, static uniforms around 1-7. This wall time includes
encoding/queue work, not GPU kernel execution. The installed SDK submits
one render pass per command buffer; nesting passes is unsafe on the backends
already documented in the production renderer. Each native GPU submit also
calls DisposeThreadLocalCachedResources; the Vulkan implementation drops
thread-local descriptor/command pool cache entries. A grouped submission
and explicit pass-end API need engine work, not a different Dart tap loop.

A native-raster variant uses the same ready source and fused kernels,
creating only offscreen blur-pass images with Picture.toImageSync. It never
captures or re-rasterizes the background. One-repeat smoke: sigma 2/10
GPU 2.098/3.270 ms, UI p95 2.18/4.50 versus direct GPU 1.419/2.069 and
8.95/11.97. Pixel errors 10/7. It trades UI overhead for more GPU work and
per-frame pass-image allocation. It is not adopted; no energy saving is
claimed from this smoke.

## Unchanged-source translation cache

Two GPU and two energy launches, seeds 202610075/76, with the same three
shuffled repeats and seven native phases. Values below are medians of
per-launch repeat medians (power: per-launch total energy / duration).

| Path | GPU ms | UI p95 | Raster p95 | Power mW | Max channel error |
|---|---:|---:|---:|---:|---:|
| Owned source only | 0.841 | 1.387 | 4.275 | 502 | reference |
| Stock Gaussian, sigma 2 | 1.982 | 1.617 | 6.119 | 573 | reference |
| Cached Dual, sigma 2 | 0.952 | 1.495 | 4.126 | 500 | 8 |
| Stock Gaussian, sigma 10 | 2.079 | 1.622 | 5.961 | 611 | reference |
| Cached Dual, sigma 10 | 0.972 | 1.523 | 4.322 | 518 | 7 |

Whole-app GPU work falls 52.0/53.2 percent. Power is lower in both launches:
small Gaussian 541/604 versus cache 494/505 mW (8.7/16.4 percent);
large Gaussian 526/696 versus cache 498/538 (5.2/22.6 percent).
The two-launch aggregate gives 12.8/15.2 percent lower power, but the
large baseline varies substantially with CPU placement/frequency. These
are directional fixture results, not an app-wide energy guarantee. Skin
starts are 36.1 and 37.0 C. Every case has zero frames over budget across
both GPU launches and both energy launches.

The native counter stays at three/seven total blur passes, including
prewarm, throughout all repeats: no new blur is submitted on translation.
One output texture is retained per cache. The small guarded ROI is
1028 x 591 pixels, with 514 x 296 and 257 x 148 pyramid targets;
owned RGBA8 target/scratch capacity is 1,369,296 bytes (1.306 MiB).
Large ROI is 1244 x 807, with half output 622 x 404 and deeper levels;
capacity is 2,340,528 bytes (2.232 MiB). The shared ready source is
1080 x 2400, 9.89 MiB. These capacities are not native RSS measurements.

An initial cache omitted the translation guard: at the endpoint its
small-sigma error reached 200. It was rejected and the guard now covers
28 logical pixels of source motion plus the kernel reach. Both final
launches give max 8/7 at every checked phase, including endpoints. This
raw difference affects more than rim pixels; it does not pass production
glass fidelity merely because the maximum is small.

The workload has one immutable source version and 100 percent cache hits.
Source production, cache misses and new widget pixels are excluded from
steady-state timing. The current transform is applied in the frame being
rendered; no one-frame-old background capture is used. Translation of
unchanged, covered pixels is the optimization, not unrestricted reuse of
an old scene.

## Next work

1. Integrate a same-frame owned source into package-owned chrome, with
   explicit source identity/version, coverage and transform. Invalidate on
   actual pixel changes; never treat scrolling virtualized content as an
   unchanged image without proving its coverage.
2. Validate the cache under production optics, fractional glass movement,
   scale/rotation, glass-over-glass and real source changes. Compare source
   production/misses as well as cache hits, GPU, energy and native RAM.
3. For frequently changing arbitrary backdrop pixels, prototype native
   Impeller support for a fused reduced-resolution runtime filter or a
   native Dual filter, and batch pass encoding/submission. Public Flutter
   GPU does not expose the private current backdrop or a compute list.
4. Keep stock Gaussian until full-frame fidelity and energy acceptance.
   A faster uncalibrated kernel, lower GPU work at higher power or a
   one-frame-old widget snapshot is not sufficient.

## Validation and evidence

Portable source patches, build/source hashes, native raw reports, compressed
GPU work traces, energy caches, phase comparison results and PNG hashes are
in `tool/ios_reference/perf/2026-10-07-dual-kawase`. Raw system-wide Perfetto
traces are excluded; their hashes/sizes are retained. The final guarded
source matches both APK build records. Both patches pass git apply --check
against the base. Experimental analysis has zero issues; its three stage
unit tests pass. Main repository gate results are recorded in validation.json.
The locked runner restored the original gallery after every launch.
No production source changes or generic current-backdrop API are installed.
