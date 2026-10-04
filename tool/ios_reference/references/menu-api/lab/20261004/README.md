# Shared menu audit - iPhone 16 Pro, 2026-10-04

Run `tool/ios_reference/lab/out/menu-phone-20261004-06` on iOS 27.0.1.
UIKit and Flutter profile builds received nine real XCUITest gestures:
root open, More, Deeper, back through Deeper and More, More again,
outside dismissal, root again and outside dismissal. The release gallery
was restored and the device lock released. No simulator was used.

Capture validity passed: 851 global film pairs, every paired gesture
window above 80% coverage, no invalid metadata, accepted/decoded counts
1800 native and 1684 Flutter, zero encoder drops and 100% active marker
coverage. Input path RMS was 0.192450 pt, maximum 0.333333 pt. Application
median cadence was 119.980 / 119.861 Hz. These checks certify acquisition,
not native fidelity. No fidelity thresholds were declared.

The first pilots omitted UIKit's automatic Ask Siri footer on Flutter.
Its extra 62 pt changed the root platter and its appearance beneath More.
The adapter now includes the corresponding divider/row; XCUITest verifies
the footer exists on both sides. Its ordinary 21 pt group gap makes the
footer 63 pt and the root 209 pt, versus native 62/208 pt. This remaining
1 pt harness discrepancy must not become a fitted production constant.
Its Flutter circle glyph is a placeholder. Measurements containing that
glyph do not certify icon fidelity. Content assertions establish presence,
not matching layout or material. The widget test checks the settled 209 pt
root explicitly; a transient spring crossing of 208 pt is not evidence.
The saved shared scenario and raw capture hashes are in `audit.json`.

## Findings

- Parent widths agree: 242.5 pt at one submenu and 235.225 pt at two,
  corresponding to 0.97 and 0.97 squared. Native list-container bounds
  and Flutter row bounds are different quantities during hand-back;
  row clipping does not measure the platter, rim or exterior shadow.
- The material still differs. On the settled More still, encoded RGB
  MAE is 12.021 at the left rim, 8.223 in the left shadow and 1.849 in
  the face region without foreground text. Rim gradient RMS is 16.617.
  Pose, the 1 pt root-height residual and blurred background content
  contribute to those metrics.
  Native has a distinct attached contour; Flutter has a softer edge and
  exposes a rounded parent boundary inside the child.
- Opening phase differs. In the repeated opening, the bright body first
  crosses 100 pt width between 125.531 and 142.200 ms after native up,
  versus 83.815 to 117.083 ms on Flutter. In the initial opening the
  Flutter bracket is wide because of a preserved film gap. These are
  observed photometric intervals, not fitted engine delays.
- During More's outside close, Flutter transfers the separate card
  material earlier in the observed sequence and the rows extend beyond
  the bright body. Native keeps the rows/material together longer.
  Bright body width crosses below 100 pt between 200.293 and 250.301 ms
  on native, versus 167.819 to 185.263 ms on Flutter. A dark label is not
  part of the bright-body mask; this is a visual diagnostic, not an SDF
  outline or a physical touch-to-photon measurement.

`settled-comparison.png` shows native left, Flutter right. Frame panels
show native above Flutter with each frame's actual time from release.
Their JSON files retain marker sequences, original PTS and pairing error.
`open-again.mp4` and `close-submenu.mp4` show native left, Flutter right.
Their frame intervals retain native USB PTS differences, with no constant
frame-rate conversion (`-fps_mode passthrough`). They are cropped/resized
inspection derivatives; raw films stay in the run directory.

The interactive report is `out/menu-phone-20261004-06/report-final/view-light.html`.
Global alignment retains up to 578 ms of runner scheduling drift. Optional
inspection windows use each recorded down, preserving response delay,
release differences and original PTS. No fitted phase shift, duration
stretch or time warp was used. Native marker prediction and Flutter
postFrame observation still have physical-presentation uncertainty.

## Tool corrections and checks

The laboratory now supports content assertions, the automatic footer,
explicit stimulus-relative inspection, original PTS in paired records,
asset reuse, on-demand full-precision frame metrics and ordered image
analysis with four bounded workers. Missing clip channels are unobserved rather than zero; continuity excludes a
render-object replacement while preserving its identity-change count.

34 Python tests passed. The full package passed 1056 tests and the gallery
14. Format checked 251 files with zero changes, analyze reported zero
issues and dartdoc dry-run reported zero warnings/errors. The original
report's window/frame/mode/region controls were exercised
in the browser with no console errors. After the desktop restart, browser
reopening was blocked by its URL policy. The lightweight viewer reduces
the initial payload from about 135 MB to 5.4 MB, with per-frame metrics
loaded on demand. Its export/profile roundtrip and JavaScript syntax pass;
post-restart browser interaction remains unverified. No production physics
or material constants were changed by this audit; the residuals remain work for measured calibration.
