# Navigation pages passport (push, edge swipe, push zoom)

Status: measured device; ported; replayed (navigation_motion_test,
navigation_stack_test, push_zoom_test). Bars over the pages: [bars.md](bars.md).

## Native

`UINavigationController` push/pop, interactive pop gesture,
`UIViewController.preferredTransition = .zoom(options:sourceViewProvider:)`
(`UIViewControllerTransition`, `UIZoomTransitionOptions`:
`interactiveDismissShouldBegin`, `alignmentRectProvider`, `dimmingColor`,
`dimmingVisualEffect`; also `zoom(...sourceBarButtonItemProvider:)`).
Tuning [tuning]: `_UIFluidNavigationTransitionsSpec`, `_UIZoomTransitionSpec`.

## Spec - push/pop and edge swipe

- Push: spring 0.3 critically damped with v0 8.3 widths/s (fitted: the
  curve starts at full speed); page below at parallax 0.3.
- Edge swipe 1:1; release on interactiveSpring 0.3/0.85 [tuning; device free
  fit 0.294 - 0.300 / 0.85].
- Commit rule [device recapture]: a page released still pops from 0.3 of the
  width (0.27 returns, 0.32 pops) = `popDistance`; a flick past 1.06
  widths/s decides alone either way (`popVelocity`; +1.02 returns 3/3, +1.10
  pops; -1.02 still pops at 0.51 W, -1.28 returns); a returning page carries
  2.9x the release speed outward (`cancelVelocityScale`, fits 2.7 - 3.1); a
  popping one starts from rest ~0.03 s after the lift. +1.25 returned 3/3
  (synthesizer artifact or unmodelled rule - not reproduced).

## Spec - push zoom [film, device 2026-10-03]

- Center and width open on 0.317/1.0, height on 0.406/0.925 (0.98 pt rms over
  4 pushes); pop rides zoomOut 0.34/0.92 (0.54 pt rms).
- Source look crossfades into the page (0.156 s, back 0.191 s); the page
  underneath dims black 0.15 and takes the container's shadow; corners run
  from the source's to the display's.
- Interactive dismiss: a finger dragging down or toward the trailing edge
  within 30 degrees shrinks the page about the touch point (measured rates
  per direction); release zooms into the source past 132.5 pt or 1050 pt/s
  (from rest, on 0.45/0.81 and 0.33/0.98), else returns on 0.278/0.927.
  Replay: 5 transitions + 10 drags, outcomes exact.

## Fixtures

Device `ios27-device/bars/push-pop.jsonl`, `pop-edge-*.jsonl`;
`ios27-device/push_zoom/push_zoom.json`. Simulator `ios27/bars/pop-edge-*`.

## Recapture

Scene `nav` with `PROBE_AUTO=push|pushpop` (programmatic), BarsUITests
(edge swipes). Push zoom: scene `snpush` (`PROBE_SRC=capsule|card|glass`,
`PROBE_SRC_Y`), SheetNavUITests testSNPush, testSNPushDrag, testSNPushDrag2,
filmed with MorphRecorder (the zoom is invisible to layer sampling).

## morph

navigation_motion.dart (`MorphNavigationTransition`), navigation_stack.dart
(`MorphNavigationStack`, `MorphNavigationRoute(zoomSource:)`,
`MorphNavigationScaffold`, `MorphNavigationConfig`, `pushMorphZoom`),
push_zoom.dart, push_zoom_motion.dart (`MorphPushZoomMotion`,
`MorphPushZoomTuning`). The stack's navigator sits under a
NavigatorPopHandler (the enclosing route is doNotPop while it can pop).

## Not reproduced / open

- +1.25 widths/s returning flicks.
- Exact push curve is a fit (no read value for v0).

## API gaps

- `alignmentRectProvider` (zoom into a sub-rect of the destination),
  `interactiveDismissShouldBegin`, custom `dimmingColor` /
  `dimmingVisualEffect`.
- Zoom from a bar button item.
- Other `preferredTransition`s (coverVertical, crossDissolve, flip, curl).
