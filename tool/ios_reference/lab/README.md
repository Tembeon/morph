# Morph measurement laboratory

One shared scenario drives UIKit and Flutter with real XCUITest touches on
the same phone. A capture contains received touches, semantic events,
presentation-layer or render-tree geometry, clips, sampler costs, frame
markers, variable-rate movies, original buffer PTS/color metadata, stills,
source hashes and the test result. Offline tools compare those observations
and build an interactive report. The laboratory does not change production
physics or optimize a widget against an invented target.

## Run

Use Xcode with the iOS 27 SDK, xcodegen, the repo's Flutter SDK, ffmpeg and
Python 3. Install `requirements.txt` in a virtual environment if necessary.
The default target is the owner's iPhone 16 Pro, 402 x 874 pt at 3x.
No command starts a simulator. Unlock the phone and enable UI Automation.

```sh
cd tool/ios_reference/lab
python3 -m unittest discover -s tests -v
python3 lab.py validate scenarios/button-press-drag.json
python3 lab.py capture scenarios/button-press-drag.json --out out/button-001
python3 lab.py compare out/button-001/scenario.json \
  --native out/button-001/native --candidate out/button-001/flutter \
  --out out/button-001/report
python3 -m http.server 8817 --bind 127.0.0.1 --directory out/button-001/report
```

Open `http://127.0.0.1:8817/`. The report has received-input plots, event
counts/timing, numeric value curves, geometry plots, first-response intervals, clip loss, identity
changes, frame selection, native/Flutter split, overlay, amplified difference,
region crops, zoom and horizontal/vertical edge profiles. Per-frame region
metrics and profiles load on demand; the full-precision report.json remains
unchanged. Blue is native;
orange is Flutter. Serve over HTTP for canvas difference operations.

`capture` takes the atomic device lock, builds both applications, launches
MorphRecorder with `open -g -W`, waits for recording readiness, drives the
scenario, pulls telemetry and exports attachments. Laboratory movies use an
AVAssetWriter on the same AVCaptureVideoDataOutput buffers as their metadata,
with original source PTS and H.264 at 32 Mbit/s without frame reordering.
Accepted buffers must equal decoded movie frames; encoder backpressure and
source drops are counted. This is compressed SDR evidence, not lossless or HDR.
Legacy recorder calls without a metadata path retain their original backend.
It stops the recorder
through a private stop file even when the UITest fails. After a Flutter pass
it rebuilds, installs and launches the release gallery, including on error.
The lock is released in `finally`; another owner's lock is never removed.
Use `--side native|flutter`, `--no-film`, `--device`, `--team`, `--flutter`,
`--target` or `--native-scene` when needed. `--leave-lab-installed` explicitly
skips gallery restoration. Outputs are append-only: use a new output path.

`compare` exits 2 for failed checks or incomplete evidence. With no declared
fidelity gates it reports `EVIDENCE`, not a fidelity pass. `--no-film` is a
deliberate geometry/input-only comparison; without it missing films fail.
Always compare the saved `scenario.json`, not a subsequently edited scenario.

Add `--event-windows` to inspect individual transitions from each actually
received down. The Timeline selector switches between the unchanged global
report and those inspection windows. Each window retains start drift, release
duration difference, original movie PTS, marker sequences and pairing error.
It ends before the next received gesture and includes up to 750 ms after
release. No response delay is fitted or removed. Window coverage is reported
separately; a complete local window never overrides a failed global capture.

## Scenarios and adapters

`schema: 1` defines a canvas, appearance, diagnostic background, widgets,
tracks, gesture steps and image regions. The validator rejects invalid
coordinates, non-finite times, duplicate IDs, malformed selectors and unknown
actions/gates. Pixel dimensions and scenario hashes must match the actual
capture. Declared Reduce Motion/Transparency assumptions never substitute
for read-back values. Flutter's transparency read-back comes from the
XCUITest runner on the same phone because Flutter does not expose that flag.

The standard Flutter entrypoint requires successful liquid-renderer
initialization; fallback rendering cannot silently stand in for a glass capture.
A custom LabApp can deliberately select another recorded tier.

Built-in scene controls: glass button, slider, switch, segmented control and
nested menu. `button-press-drag.json` covers tap, hold, drag out/back and
release far outside. `slider-drag-reverse.json` reverses a held thumb.
`menu-stack.json` opens a submenu by its accessibility label and closes
outside after two submenu levels. `menu-return.json` also returns through the
Deeper and More headers, reopens More, dismisses the first submenu outside and opens/closes
the root again. These are input protocols, not measured tuning constants.

The owner's iOS adds an automatic 62 pt Ask Siri footer to the root menu.
Menu scenarios declare `systemFooter: "askSiri"`; the Flutter adapter adds
the corresponding divider/row, while UIKit supplies its own system row.
The ordinary MorphMenuDivider gap is 21 pt, making this adapter footer
63 pt and the root 209 pt, versus native 62/208 pt. This 1 pt harness
residual is recorded rather than treated as production physics. The
adapter uses a placeholder circle glyph for Siri; exclude that glyph from
optical metrics. An `assert` step with an `anchor` and boolean `exists`
checks actual accessibility content on both sides. Missing/failed assertions
invalidate comparison. A shared JSON hash alone cannot establish that UIKit
has not added platform content. Root/content-container metrics and glass
geometry must still be distinguished during hand-back.

Absolute points are in window pt. A gesture has increasing `points` times,
`upAt` and an optional `after` wait. `paths` holds simultaneous fingers.
An `anchor` resolves an identifier or label once per finger; points then
become offsets from that element's center. `fx`/`fy` select another position
inside its frame; `last` disambiguates a menu row from an identically named
source. Wait, shot and background/foreground steps use the same runner.
Screenshots are independent attachments; do not put them inside a spring
measurement window because taking one can disturb that window.

The native XCUITest synthesizer has the documented limitations in
`../spec/README.md`: planned point times are not achieved timing, separate
requests add latency, dense paths can burst and very short flings collapse.
Analyze received touches. The native runner does not invent touch-cancel
events. Real cancellations can be recorded manually; `replayLabTouches` in
`example/test/support/` replays phase 4 and concurrent pointers in widget
tests. Synthetic widget replay is a logic/geometry check, not a device film.

For a new or complex widget, supply a native scene through `Scenes.make` and
`--native-scene`, reading `PROBE_LAB_JSON`. On Flutter use `LabApp(child:)`
for a complete scene, or `LabApp(builders:)` for additional widget kinds.
Builders receive the shared specification and an event emitter.
`observables` adds named numeric motion/state channels. None of this needs
changes to the package engine or access to a widget's private State.

Native selectors support view class regex, accessibility identifier/label,
ancestor identifier, index or all matches. `source: layer` traverses the
actual CALayer tree under those views and filters `layerClass`.
`source: flex` reads available flex channels through the probe's typed
Objective-C getters. `scalars` maps a channel name to a getter path; missing
getters stay unobserved. Private runtime inspection belongs only to the
reference probe. Flutter selectors use widget type, ValueKey, Text, ancestor
key, index or all matches. `paintChild: true` includes a Transform's painted
child transform. `properties` limits both sides to corresponding quantities.

Choose matching quantities, not similar class names. UIKit glass buttons
animate an internal `_UIMultiLayer` while their outer UIButton and its
background UIView facade keep fixed frames. A root-frame RMS of zero proves
layout only. The shipped button scenario therefore tracks both layout and
the internal platter/scale, compared with Flutter's painted Transform.

## Materials and fitting

```sh
python3 lab.py matrix scenarios/glass-optics.json --out out/optics-scenes
python3 lab.py image scenarios/glass-optics.json \
  --native native.png --candidate flutter.png --out out/image.json
python3 lab.py transfer scenarios/glass-optics.json \
  --native-black native-black.png --native-white native-white.png \
  --candidate-black flutter-black.png --candidate-white flutter-white.png \
  --out out/transfer.json
python3 lab.py fit-spring out/button-001/native/trace.jsonl \
  --track lift --property scaleX --start 0 --end 0.4 \
  --holdout out/button-002/native/trace.jsonl --out out/spring.json
```

The matrix generates black, white, RGBW grid and position-encoding ramp
backgrounds in both appearances. Capture these as separate immutable runs.
The glyph-free `glass-optics.json` keeps text out of the face and rim regions.
Use regions that exclude foreground content when interpreting material errors.
Regions keep face, rim, shadow and background measurements separate. Metrics
include encoded RGB MAE/P95/bias, gradient residual, near-white samples and
mean edge profiles. Black/white differences separate effective transmission
from additive lift; nonlinear tone mapping means this is not physical alpha.
The ramp is a diagnostic scene; source-coordinate inversion is not automated
yet. Color-profile mismatches fail film color comparison. SDR PNGs and this
USB stream do not recover HDR intensity or prove EDR correctness.

Spring fitting reports response, damping, delay, initial/target position and
velocity, residuals, Jacobian rank, local uncertainty, boundary parameters
and optional independent holdout error. Constant layout cannot identify a
spring. Multiple animation channels, correlated samples and unknown delay
require independent recaptures and review. Nothing writes a fitted value
into `lib/`; promoting measurements still requires a passport and replay.

Optional global gates: `geometryRmsPt`, `geometryMaxPt`, `horizontalStepPt`,
`clipLossPt`, `touchPathRmsPt`, `eventLatencyMs`, `frameGapMs`. Region gates:
`mae`, `p95`, `edgeRms`. Limits are supplied by the measurement specification.
A horizontal-step gate applies to the entire scenario: isolate a close
window when enforcing its 0.5 pt continuity requirement. A swipe intentionally
moves farther. Rectangular clip loss does not measure rounded-corner cuts or
shadow extents; use the film and region profiles for those.

## Clocks and validity

Geometry uses the first delivered touch as its origin on both sides. Input
paths use the first source timestamp so dispatcher latency does not change
their measured duration. Source timestamps, delivery timestamps, Flutter
source-clock values and frame-clock values are retained separately. A
source-time recording cannot be equated with a delivery-time recording. The
global comparison has no duration stretch, per-gesture alignment or time
warping. Optional stimulus-relative inspection is explicitly separate from
that comparison and uses recorded down times rather than fitted phase shifts. Input-path/duration
error and inter-gesture drift remain visible. Geometry interpolation never
crosses a gap over 50 ms or a render-object identity change. Missing tracks,
missing corresponding properties, unfinished/cancelled gestures, invalid
metadata, runtime errors and stale scenario hashes cannot produce a pass.

The 20-cell marker encodes a 16-bit sequence with fixed black/white guards
and parity. It changes continuously to prevent static-period movie-clock
compression. ffmpeg extraction uses `-fps_mode passthrough`; every PNG keeps
the original PTS. Marker decoding associates it with application telemetry,
rejects ambiguous/corrupted pixels and counts duplicate or missing markers.
Lead/tail frames outside the marker's active interval are recorded separately.
Valid markers alone cannot hide a missing gesture: each source and paired film
must cover at least 80% of every down-through-release-plus-500-ms window. This
is an acquisition completeness floor, not a motion tolerance. Duplicate and
backwards movie timestamps are reported; backwards timestamps require review.
Film pairs must be within the declared `filmToleranceMs` (default 25 ms).
This is a pairing tolerance, not a claim of 25 ms physical accuracy.

Native markers predict display-link targetTimestamp; native layer samples
use timestamp. Flutter markers and geometry are logged postFrame, before
guaranteed physical presentation. Physical presentation is not timestamped;
latency comparisons retain display/embedding uncertainty. Movie cadence,
raw USB-buffer cadence and application cadence are reported separately.
Delegate drop callbacks do not include omissions upstream or in movie output.

Sampler median/P95/max costs expose observer overhead. The marker repaints
without rebuilding the complete Flutter scene, but it still keeps the
display active. Compare a quiet capture before extrapolating performance.
Callback timing retains signed dispatch ordering. An activation may precede
the global pointer observer's up record by a fraction of a millisecond; a
10-ms association window retains that signed delta instead of inventing
physical latency.
The report is evidence, not a single aggregate score hiding a damaged rim.

## Provenance and further data sources

This implementation is local tooling, informed by whynotmake-it's
`apple_match` laboratory at the renderer's already-vendored commit
`ab1c2d294683f7eea6ee8da6c81d5cd0225ee129`. No upstream optical constants,
optimizer output or macOS measurements are promoted into morph physics.
See the shared scene, regional metrics, ramp and HDR research in that repo.

ScreenCaptureKit on iOS 27 is a possible additional source. Its iOS API does
not expose macOS minimumFrameInterval/queueDepth/pixelFormat controls.
This laboratory currently implements the measured USB path; it does not
claim an in-app 120 Hz/HDR capture backend. Metallib/AIR inspection and native
material recipes can guide experiments, while runtime layers and films
remain the reference for the complete compositor.

Raw runs and HTML reports live under ignored `out/`. Preserve reviewed
fixtures/passports and a compact verification record in version control;
avoid committing whole derived-data or xcresult directories.
