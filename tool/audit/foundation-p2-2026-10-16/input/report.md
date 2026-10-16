# P2: recorded pointers, pending routes and contour counterexamples

Date: 2026-10-16. Base: `7d0968a7` on `wip/measured-liquid-glass`. Flutter 3.47.2 stable (`d3b14c876900e553bc736ca19295fc09e3853e8e`), Dart 3.13.2. Host: macOS `flutter_test`. Source/evidence hashes are in `artifacts.json`.

**P2 remains open.** Recorded input works with an early pending route. Two acceptance gaps remain reproduced: model-driven dismissal bypasses SDK veto, and replacing the menu fusion law at hand-back changes the contour. Green negative controls below demonstrate rejected behavior; they do not pass those acceptance gates. No production implementation, measured constant or fixture tolerance changes. No device was acquired or launched.

## Work state

- [x] Feed recorded pointers through the real GestureBinding and root route, including occurrence/delivery time and an injected pointer-clock offset.
- [x] Preserve hold/drag by installing a pending route on the source down, defer content/focus, honor real pointer cancellation and release input resources.
- [x] Compare the adapter with an uninterrupted model at every observed command/frame; verify selections against recorded actions.
- [x] Measure the isolated contour boundary under both fusion laws, preserving the failed pixel-zero attempt and images.
- [ ] Ask SDK permission before model-driven closing changes the motion phase.
- [ ] Preserve the carried field/outline through actual bar rendering and prove per-frame contour continuity.
- [ ] Check early-route observer/isCurrent implications, remaining menu API, device fidelity/timing/energy and P3 publication ordering.

## Reproduce

From `example/`:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 60s --dart-define=P2_CONTOUR_OUTPUT=/tmp/morph-p2-contours test/proto
```

`P2_CONTOUR_OUTPUT` is optional; when present the contour test exports its own rendered PNGs. From the package root:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/menu_button_test.dart test/menu_drag_out_test.dart test/menu_source_test.dart test/menu_fusion_test.dart test/morph_clock_test.dart test/motion_route_ownership_test.dart test/sheet_zoom_test.dart test/bar_fusion_test.dart
nice -n 10 flutter analyze --no-pub
```

Results: 135 prototype checks (106 previous + 20 recording replays + six input/lifecycle checks + three contour counterexamples); 122 existing regression checks; clean root analysis. `host-tests.log`, `regression-tests.log` and `analyze.log` hold the outputs. `summary.json` extracts recording and contour metrics. Terminal padding is trimmed from analyzer and archived failure logs; passing test logs are unchanged. Full package/example suites were not run.

The implementation stays in `example/lib/proto/` and `example/test/proto/`. Existing owner work in bar buttons, their passport and capture harness is unchanged by this increment. Earlier reports identify older committed prototype versions; their evidence is not overwritten.

## Recorded input

`menu_route_replay_test.dart` plays these ten existing iPhone captures at both 60 and 120 Hz:

- `center3-tap`, `center3-dismiss`, `center3-hold700`.
- `center3-select`, `center3-dragselect`, `center3-closemidopen`.
- `center3-reopen2-50`, `center3-reopen2-350`.
- `drag-out-flex`, `drag-out-upward-flex`.

The two flex files include `delivered_t`; the earlier captures do not, so delivery equals occurrence for those cases. Events due before a display frame enter the real binding in recorded order, with their original relative occurrence times. During dispatch the injected engine-now function reports delivery time; pumping then advances the fake engine to the next 60/120 Hz frame. This models delivery within a frame interval, not a native platform event queue. At 120 Hz, pointer timestamps are additionally shifted back 37 seconds and converted through the injected offset. No FFI offset is measured on hardware here.

Every recorded event must reach the host. Input unrelated to an already closed menu may be ignored: the harness verifies that such streams start outside the source with no active route, pair their remaining events and leave the model unchanged. The long downward/upward flex captures contain eight/four such events respectively. The test does not confuse legitimately ignored input with a pointer stream lost after Navigator cancellation.

An independent reference receives every accepted command and frame at the adapter's canonical times. Time, progress and opacity agree within 1e-9; kicks, fusion radius and geometry within 1e-8. Recorded action indices agree too: Share selects index 1, held drag-select selects Delete at index 2. Every presentation is disposed, source ownership returns and the global pointer-router subscription count returns to baseline after unmount.

These are adapter-equivalence tests against the existing measured model, with recorded actions as an additional oracle. They do not recompute all native geometry residuals. Existing fixture replays pass separately with their original tolerances. Center-three-row cases retain the current three-row model; the four-row flex cases reuse the existing flex replay's 41-point vertical-padding configuration. No native footer geometry is newly claimed.

## Why the route is installed early

A late imperative `Navigator.push` cancels active pointers in Flutter 3.47.2. The relevant local SDK paths are `NavigatorState._afterNavigation` / `_cancelActivePointers` and `GestureBinding._handlePointerEventImmediately`. Cancellation removes the hit-test path, so subsequent physical move/up events no longer reach even the global pointer router. A fresh negative-control test observes only down/cancel after a late push, despite sending move/up afterward. Ignoring that cancel in a global route would not restore the stream.

The prototype source therefore processes pointer-down in its own hit-test Listener and installs a pending popup before the ancestor Navigator Listener records that down. The popup takes over the same model and clock mapping. Content is built and SDK focus requested only when measured opening starts. Its barrier is inactive during an uncommitted press, becomes active for a pending tap-open, and remains active while the menu is shown. A real pointer cancel before hold removes the hidden route without building menu content. A secondary mouse button does not prepare a route. A new hold during the source's landing tail also keeps its down/move/up sequence and can choose a row.

This refines the earlier architecture's installation time. It uses public APIs but relies on their observed dispatch order; the regression is required for each supported SDK. Root `NavigatorObserver` and underlying `ModalRoute.isCurrent` see the pending presentation before content appears. Those observable lifecycle effects, nested routing and the full accessibility contract need review before production adoption. The recording-mode custom barrier is experimental; its semantics-dismiss path is not validated. The earlier command mode remains for the original SDK lifecycle comparison.

## Dismissal counterexample

The current pure menu model schedules its own close from outside input. The route notices the already-closing phase and calls programmatic `Navigator.pop`; that SDK API bypasses `PopScope`. The new negative control proves that a pointer dismissal closes even when `popDisposition` is `doNotPop`.

The previous successful barrier/PopScope test covers the command-mode SDK barrier, not this raw-pointer path. The accepted contract still requires outside/back/Escape veto before closing starts. A close-request event must precede the model phase change; after SDK approval, the host commands closing using the original reaction time. Refusal keeps the open model intact. Owner replacement and disposal while permission is pending also need checks. This requirement is added to P2 and the typed-event migration in unit 2.4. No acceptance criterion is weakened to accommodate the current prototype.

## Contour boundary

The isolated raster experiment uses the production menu silhouette calculation and the production bar container outline function. At 120 Hz, the first closing zero crossing in its three-row scene occurs at 1.325 s, progress -0.0001403, while the menu's fusion radius is still 2.03077 logical pixels.

Before transfer, the carried Gaussian menu outline is unioned with one neighboring bar capsule. One candidate immediately rebuilds the two transferred blobs and neighbor under container spacing 12. The other retains the same carried menu outline after ownership transfer. All images use the same host rasterizer, common bounds and 3x scale.

| Neighbor gap | Immediate container replacement: changed pixels | Preserved carried outline: changed pixels |
| --- | --- | --- |
| 0 | 1382 | 0 |
| 8 | 1086 | 0 |
| 12 | 981 | 0 |

The original pixel-zero comparison of the immediate replacement fails in all three cases. Its exact source and failure log are preserved as `rejected-contour-test.dart.txt` and `rejected-contour-tests.log`. The current test explicitly treats that replacement as a negative control (`changed > 0`), while retaining exact zero for preservation. This changes the purpose of that experimental assertion, not the P2 acceptance rule: the immediate replacement is rejected and full bar continuity remains unpassed.

`contours/gap-*/before.png`, `container.png` and `preserved.png` are our own raster outputs. White background improves inspection; the gap-12 pair was visually inspected. The count is any differing RGBA pixel, including anti-aliased edges, not an estimate of perceptual severity. This is not a screenshot of UIKit, a shader/optical comparison, or a per-frame golden of the actual toolbar widget.

The result explains why preserving model geometry alone is insufficient. The source needs the carried contour/fusion law as well. The reduced route still paints plain rounded rectangles, so this experiment does not claim that its actual source painter has implemented that fix. Next is the veto handshake and a shared carried-outline path in the real route/bar scene, followed by per-frame comparison and the device batch. P1's projection/controller choice remains open, and the unit-0 production code gate is not applicable to these off-main prototypes.
