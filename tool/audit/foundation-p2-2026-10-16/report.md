# P2: whole-menu ownership and clock transfer

Date: 2026-10-16. Base: `5586e8c5` on `wip/measured-liquid-glass`. Flutter 3.47.2 stable (`d3b14c876900e553bc736ca19295fc09e3853e8e`), Dart 3.13.2. Host: macOS `flutter_test`. Source and evidence hashes are in `artifacts.json`.

Status: the first ownership/time experiment passes. **P2 remains open:** this is not yet a menu presented by a real root Navigator route. No production implementation, export, measured tuning or replay tolerance changes. No device acquired or launched for this experiment.

## Work state

- [x] Ground: existing `MorphMenuMotion`, its timeline, driven kicks, fusion envelope and sleep/doze clock policy; `tool/ios_reference/spec/menu-button.md`.
- [x] Sketch refinement: move the whole model with canonical time and an owner-local offset; do not rebase individual springs while leaving other channels behind.
- [x] Implement outside `lib/`: unique owner leases, frame snapshots and hand-back at the first closing progress sample at or below zero.
- [x] Verify: 33 new checks; 88 prototype checks including the earlier P1 scenarios; 117 existing regression checks.
- [ ] Actual root menu route, gesture fixture replay through it, stable content and source loss.
- [ ] Per-frame bar contour continuity, active-source ticker ordering and complete scheduling integration.
- [ ] Device fidelity, first-menu-frame timing and energy on Pixel 6a.

## Files and reproduction

- `example/lib/proto/menu_transfer_probe.dart`: `ProbeMenuTransfer` owns one existing `MorphMenuMotion`, an exclusive identity lease and the translation between its canonical time and the current owner's local time.
- `example/lib/proto/motion_clock_probe.dart`: adds current-frame resumption to the previous extracted-clock prototype. Earlier P1 timing evidence refers to this file as committed in `5586e8c5`, not this extension.
- `example/test/proto/menu_transfer_probe_test.dart`: 24 frame-by-frame model comparisons, one stale-owner check and eight clock-boundary checks.
- `host-tests.log`: all 88 prototype checks; `regression-tests.log`: 117 existing checks; `analyze.log`: root analysis; `artifacts.json`: hashes and reproduction metadata.

From `example/`:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 30s test/proto
```

From the package root:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/menu_button_test.dart test/menu_drag_out_test.dart test/menu_source_test.dart test/menu_fusion_test.dart test/morph_clock_test.dart test/motion_route_ownership_test.dart test/sheet_zoom_test.dart
nice -n 10 flutter analyze --no-pub
```

Trailing terminal padding is trimmed from `analyze.log`; test logs are unchanged. The full package and example suites were not run for this prototype-only change. Existing uncommitted owner work in bar buttons and their passport remains outside this change. No gallery or consumer imports these prototypes.

## What the comparison establishes

The 24 cases combine 60/120 Hz, source-local origins of 0, 0.003 and 73 seconds, and four reopen policies. One model runs continuously on canonical time. A second identical model changes owners and local clock origins, retaining the same model object. Every sampled frame compares progress, button/menu rectangles and radii, kicks, content/button opacity and fusion radius. Time, progress and opacity agree within 1e-9; geometry and kicks within 1e-8.

Closing starts at one second. The source receives the model at its first sampled closing zero crossing, while the complete model is still unsettled. Reopening 50 or 300 ms after closing reverses from the route; reopening after 550 ms reverses from the source while its landing tail is still moving. The latter also hands back after the second close. These timings are test scenarios, not new native tuning. The observed first zero crossing in this scene is around 325–333 ms after closing, depending on the frame grid.

The model's springs, driven kicks, fusion history and scheduled reactions retain their canonical time without copying or rebasing individual fields. The experiment compares the exposed frame channels, not every private field. Existing native fixture replays pass separately without changed tolerances; the new transfer harness has not yet replayed recorded touch traces through a menu route.

Each route instance receives a different lease, even when its role is still `route`. After reopen, old-route advance, open, close and transfer calls all return false and leave the frame unchanged. This rejects stale writers; it does not yet prove source/route disposal in a real Navigator.

## First-frame boundary

The eight widget checks cover settled sleep and timed doze, at normal speed and `timeDilation = 5`, with both a negative control and a frame-anchored transfer. The clock learns a display grid before becoming inactive. Route-model hand-back occurs inside a real post-frame callback. Slow-motion cases stretch physical frame intervals by 5× to compare the same motion-time intervals.

Two insufficient approaches are deliberately reproduced:

1. After settled sleep, plain `wake()` starts a new ticker whose first elapsed time is zero. The model holds its hand-back frame for the first source callback, losing the interval since transfer.
2. A dozing clock's last sampled `time` is stale. Using it as the transfer anchor lets the next callback add elapsed doze time to the newly transferred model, jumping it forward.

`resumeFromFrame` anchors resumption to the current raw engine frame timestamp and returns a current local time that includes elapsed doze time. The mapping uses that returned anchor. The first source frame then advances by the expected 8.333 ms of motion time, preserving the uninterrupted model's sampled geometry at both speeds. Timers and dilation are restored/disposed in each test.

This method is a prototype of a clock boundary, not a final internal API. It currently expects a call during the hand-back frame. Transfer to an already active source, changing dilation during transfer, ambient `TickerMode` changes at that boundary and same-frame ticker order remain unverified. P3 must determine a coherent publication phase rather than relying on callback registration order.

## Architecture consequence

The original sketch assigned `rebase` to `MorphSpringState`. A menu is a composite model with time-bearing state beyond one spring; rebasing the spring alone cannot transfer it. This experiment supports retaining canonical model time with an offset at the owner boundary. The sketch removes the unconditional spring method and records the refinement in the plan and rationale. Capture/resume still needs to account for real content, callbacks/events, source lifetime and presentation ownership before production adoption.

The root route strategy is still undecided. These checks do not favor separate animation projection over SDK controller and do not combine two drivers for the same model. The earlier P1 device results are unchanged. No build-count ceiling or replay tolerance has been relaxed. No performance or pixel-parity claim follows from these host comparisons.
