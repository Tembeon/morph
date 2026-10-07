# Combined owned-source experiment

Experimental source only; no package-owned backdrop API is shipped.
The final prototype is preserved locally as exp/same-frame-backdrop at
a34b9d0, based on production e85a78e. It passed the full serial gates.
It is not merged: periodic-update energy acceptance remains unresolved.
`combined.patch` replays against c6df35e, the production upstream sync.
The measurement clone was on `exp/same-frame-backdrop`, based on 27fa39e
plus those renderer fixes. The patch input manifest pins the complete
changed text inputs, root lock and build hook. A clean patch replay was
checked and every resulting input hash matched. The final shader core's
owned-input wrapper preserves the existing Morph optics; stock wrappers
are unaffected by its preprocessor conditional.

## Reproduce

Create an isolated checkout at c6df35e on `exp/same-frame-backdrop`, apply
`combined.patch`, and copy `root-lock.txt` to the checkout's pubspec.lock.
Run Flutter dependency resolution and the build/run helpers from that
checkout. `final-build.json` records the actual final APK definitions and
hash. The APK and system-wide Perfetto traces are not committed.

```
python3 tool/ios_reference/perf/stage_bench/run_android.py build \
  --apk /tmp/morph-combined/stage.apk \
  --define STAGE_MODES=mix-bare,mix-native,mix-gaussian \
  --define STAGE_LAYOUTS=cluster --define STAGE_PLANS=merged \
  --define STAGE_MOTIONS=background,updates,dynamic \
  --define STAGE_CONTENT=text --define STAGE_SIGMAS=2 \
  --define STAGE_RUNS=3 --define STAGE_SEED=202610087 \
  --define STAGE_WARM_MS=800 --define STAGE_SAMPLE_MS=2400 \
  --define STAGE_SHOTS=true \
  --define STAGE_SHOT_PHASES=-1,-0.5,0,0.0034013605,0.006802721,0.25,1
```

Use the existing restoring runner twice with `--trace gpu
--pull-artifacts` and twice with `--trace energy`. It owns the shared Pixel
lock, checks temperature, restores the original gallery APK and restores
its kernel/Perfetto recorder state. Do not acquire another device lock
around it. Keep the Pixel in portrait. GPU inputs are gzip-compressed in this archive: decompress each
text-N.gpuwork.txt.gz beside its text-N.json before reduction. GPU
reduction uses the existing stage_bench/summarize.py; energy reduction uses energy.py and its existing
Perfetto Python dependency. `pixels.py` reads only the cases and phases
actually declared by each report, ignoring stale pulled PNGs.
`check_windows.py` validates counted misses/hits and source freshness.

The earlier full protocol is stored as best-gpu/best-energy plus
metrics.json. Replay hybrid.patch, use all four mix modes, sigma 2,10
and seed 202610085. Its small Gaussian uses two images; large Gaussian
already uses the final single-picture topology. The corrected final
small-sigma protocol is corrected-gpu/corrected-energy plus
corrected-metrics.json. Do not combine different APKs as one result.

## Workloads and limits

Four translated-background glass surfaces share one bounded source ROI.
`mix-native` uses the original grouped production BackdropFilter path;
`mix-bare` draws the same source without glass. `mix-gaussian` caches a
full-resolution native Gaussian result. Source plus native filter are recorded into one picture. The filter
receives logical sigma before the canvas scale; small-sigma ROI bounds
are aligned to two physical pixels to preserve the half-resolution grid. `mix-dual` caches a reduced 5/8-tap pyramid and
fuses its final eight taps into the existing optical background reads.
All cache misses occur inside collection. There is no post-frame capture,
readback inside timing, per-pass Dart Flutter GPU submission, or stale
source displayed to disguise a miss.

The immutable text background is recorded once as a base picture. The
source version overlays a changing high-contrast marker. Pure translation
keeps the same version; `updates` quantizes phase into 16 intervals and
makes 30 misses and 114 hits in a typical 144-frame collection window; `dynamic` changes every
frame. Rendering and glass use the same current source version. The
source's current translation remains outside the cached blur.

This is an opaque, picture-owned source with translation-only transforms,
uniform material and one glass depth. It does not cover a general widget
backdrop, nested glass, platform views, external textures, arbitrary affine
transforms, a virtualized list treated as one immutable scrolling image,
or alpha-compositing correctness. ROI guards are for this fixture's blur,
28-point translation and optical displacement. Output bytes are one
retained image, not transient GPU memory, allocator capacity or RSS.
The `blur_passes` counter counts one Gaussian filter operation or each
explicit Dual snapshot pass, excluding its final fused taps; it is not
an engine render-pass or queue-submit census.
ProcessInfo.currentRss is a whole-app snapshot after each collection
window, with mixed-case allocation history.

## Diagnostic variants

`two-images-source.txt` reconstructs the pre-fusion Gaussian source;
`fused-scaled-source.txt` reconstructs the rejected doubled-scale filter.
Replace only example/lib/perf/glass_stage_bench.dart after applying the
patch to replay those diagnostics; their build records pin their inputs.
The final source is in the patch and `final-source.txt`. The original diagnostics also predate the final shader stale-uniform
cache; replacing their bench source reproduces their source/filter topology
but is not an exact performance replay of those APKs. Their source and APK
hashes remain in the native build records. The texture-availability probe is enabled only
in the first smoke and is disabled for all final timed measurements.

## Energy acceptance

The final small Gaussian cuts GPU in all three workloads. Whole-phone
selected-rail power falls 17.6 percent for immutable-source translation,
and only 2.5 percent for all-frame invalidation. Periodic updates average
3.8 percent MORE power (7.5/0.2 percent across launches). CPU scheduled
time is lower in the app, but CPU rail power and frequency are higher;
the traces do not establish a causal explanation. Do not admit this
variant for periodic updates on these results. cpu-attribution.json
contains only app/other totals; raw system-wide traces stay uncommitted.

Gate logs escape non-ASCII test output to keep repository text ASCII.
gates/log-provenance.json pins original log bytes and marks that escaping.
