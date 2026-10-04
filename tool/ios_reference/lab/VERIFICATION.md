# Device verification - 2026-10-04

The owner-approved iPhone 16 Pro ran both UIKit and Flutter on iOS 27.0.1.
No simulator was started. The release gallery was rebuilt, installed and
launched after each Flutter pass; the atomic device lock was released.
Machine-readable summaries and hashes are in `verification.json`. Raw
traces, movies, screenshots, xcresults and reports remain under ignored `out/`.

## Button: tap, hold, drag out/back, release outside

Run: `out/button-phone-20261004-09`. Both XCUITest passes succeeded.
The report is `EVIDENCE`: capture-validity checks passed; this protocol
declares no fidelity thresholds and does not certify a native match.

- Native/Flutter received three gestures and emitted two activations.
  Releasing the final gesture outside did not activate the button.
- Received path RMS: 0.105092 pt; maximum: 0.718540 pt.
- Application telemetry: native median 119.980 Hz, Flutter 119.768 Hz.
  P95 sampler cost: 1.134 ms / 1.155 ms. These costs are observer overhead.
- Native/Flutter accepted and decoded exactly 933 / 1009 movie frames.
  Native encoder rejected 14 buffers, counted explicitly;
  Flutter rejected zero. Both movies have zero duplicate/backwards PTS.
- USB and movie median cadence: approximately 60 Hz, with variable gaps.
  USB omissions remain possible; accepted-frame equality does not prove
  complete display capture. The longest movie gaps were 466.667 / 283.333 ms.
- 244 film pairs meet the 25 ms pairing tolerance. Temporal coverage of
  each paired down-through-release-plus-500-ms window: 88.773%, 80.510%,
  83.909%. The 80% completeness floor is an acquisition check.
- The outer button's bounds remain fixed. Its internal `_UIMultiLayer`
  reaches scale 1.144039, compared with Flutter's painted Transform at
  1.144105. Actual platter width RMS is 0.583824 pt, maximum 5.361853 pt;
  scaleX RMS is 0.004865. Root layout alone would conceal this motion.

The single offset preserves inter-gesture scheduling drift. UIKit samples
presentation layers on display-link timestamp, while Flutter samples a
pending painted tree postFrame. First-response intervals retain this phase
uncertainty; they are not physical touch-to-photon latency measurements.
The button film's foreground text contributes to image differences. Use
the glyph-free optical scenario when measuring material transfer.

## Menu: root and two nested levels

Run: `out/menu-phone-20261004-03`. Both XCUITest passes succeeded.
Four gestures opened the root, More, Deeper and dismissed outside.
Native/Flutter observed all three content instances:

| Track | Native samples | Flutter samples | Paired samples |
| --- | ---: | ---: | ---: |
| rows/0 | 1031 | 916 | 902 |
| rows/1 | 680 | 571 | 550 |
| rows/2 | 336 | 236 | 208 |

This pass explicitly used `--no-film`. Its screenshots are exported in
each source's `shots/` directory. It validates selectors, real accessibility
anchors and nested telemetry, not a full frame-by-frame optical match.
The content rows are selected, so their clip loss must not be interpreted
as clipping of the glass platter, rim or exterior shadow. Anchor resolution
also introduced 179.229 ms RMS inter-gesture scheduling drift; the report
retains that drift instead of concealing it with per-gesture alignment.

## Regression and capture validity

Earlier runs exposed two instrumentation defects: selecting fixed outer
views missed the moving glass layer, and the standard movie output omitted
whole gesture windows despite valid markers on retained frames. Those raw
runs remain preserved. The updated analyzer correctly marks button run 07
as `REVIEW` for incomplete temporal film coverage. The shared-buffer writer
replaced the movie backend for laboratory calls; legacy calls remain usable.

The Python suite has 24 checks, including discontinuities, clip loss, absent
cards/properties/events, stale scenarios, different clock bases, incomplete
input, marker corruption, original PTS, incomplete film windows, immutable
outputs, lock ownership, optical transfer and spring holdout recovery.
Three Flutter laboratory tests cover activation, cancellation and nested
short-menu telemetry. The full package has 1056 passing tests; the gallery
has 14. Formatting checked 251 files with zero changes; analyze and dartdoc
dry run reported zero issues. Swift probe/recorder compilation succeeds;
the backward-compatible writer APIs produce macOS 27 deprecation warnings.

The HTML report was checked with Node and exercised in the in-app browser:
motion-channel selection, next/last frame navigation, split, overlay,
amplified difference, region crop, true 4x zoom and edge-profile selection.
No browser errors were reported. HDR, a ScreenCaptureKit backend and
automated ramp-coordinate inversion are not implemented.
