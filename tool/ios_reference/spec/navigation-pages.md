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

## Spec - the bars during a push / pop

Each side of the navigation bar (and of the toolbar) changes only with
itself: a group with a counterpart on its side morphs, a side that had no
group shows its groups in place, a side left empty lets them swell and fade
in place - see bars.md "Per-segment transitions" and "the birth and death
law" (scene navseg). UIKit's scroll edge effect belongs to each page and
slides with it; morph fades the bar's one effect (bars.md, open).

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

## Implementation notes (morph side, moved from CLAUDE.md)

- Commit rule constants live on the transition (`popDistance`,
  `popVelocity`, `cancelVelocityScale`). Edge-swipe ownership: see bars.md
  (NavigatorPopHandler, MorphNavigationRoute's edge gesture).
- PUSH ZOOM API: `pushMorphZoom(context, from: tagId, builder:)` /
  `MorphNavigationRoute(zoomSource:)` - the page grows out of the tag as
  UIKit's `preferredTransition = .zoom` push. The route is non-opaque with a
  zero transition (the motion finalizes the pop, as the sheet does); the
  page below does not parallax (canTransitionTo is false toward a zoom
  route); the stack's bars change as on any push. Pinned by push_zoom_test.
- `MorphPushZoomMotion` is four springs in POINTS (center x/y, width,
  height) so a drag can hand over any frame. A drag-dismissal starts from
  the dragged frame AT REST (a 1200 pt/s flick carried no speed) on
  0.45/0.81 (center, width) and 0.33/0.98 (height).
- Crossfade source look -> content: 0.156 crit, 0.01 s late; back 0.191
  crit. Dimming black 0.15 (grey 128 -> 109, unchanged while dragging) on
  zoomIn/zoomOut; shadow black 0.36, sigma 30, 4 down (scaled by the
  dimming - its fade is assumed); corner radius source -> display radius by
  the mean of width and height progress (0.6 pt off); content scaled by
  width / page width from the container's top (a label read off held drags
  confirms both directions).
- DRAG: anywhere on the page (a scroll view with content above the finger
  keeps its drag); only down or toward the trailing edge within 30 degrees
  (31 off down and 30.5 off sideways did nothing; up and leading never);
  slop 13.5. Past it the page shrinks about the touch point - down: width
  0.00078, height 0.00154 per point, center follows 0.61 of the travel;
  sideways: 0.00156 / 0.00168, center 0.95 (rates blend by the squared
  direction components). Release: travel past 132.5 (125 held returned,
  140 dismissed) or > 1050 pt/s along the drag (70 pt at ~900 returned,
  100 pt at ~1200 dismissed) dismisses.
- Replays feed the logged touches one frame early (rows trail the
  reaction) and estimate the release speed over 0.05 s. Zoom geometry only
  shows on film: align each capture by its present/push event against the
  first frame the source grows.
- NOT REPRODUCED (push zoom): a one-frame flash of the final frame at a
  push start and of the source at a drag dismissal (film artifacts); fast
  flicks show the page 2-3 frames behind the logged touches (synthesizer
  bursts - those two replays are loose); the edge drag from x 2 replays at
  9 pt rms.
- PAGE SNAPSHOTS (option, off by default: `--dart-define=MORPH_NAV_SNAPSHOT=true`,
  `MorphNavigationSnapshot` in lib/src/widgets/navigation_snapshot.dart):
  on the slide path of `MorphNavigationRoute` (not the zoom, not reduced
  motion) each page sits in a `SnapshotWidget` (permissive) inside the
  slide's `Transform.translate`, so a frame of the slide moves an image
  instead of re-rasterizing two full pages. The snapshot is allowed exactly
  while the page's own animation or the secondary animation of the page
  pushed over it is running or held by a finger (status forward / reverse,
  so an edge drag counts), and not on the web; at rest the controller is
  off and the page is live. With the option on the widget is mounted
  for the page's whole life and only its controller toggles, so page state
  never remounts. What
  freezes while it moves: the page's scrolling, animations, text input
  and anything under a backdrop filter (glass inside the page reads an
  empty backdrop in the snapshot). The bars are not part of the page and
  stay live. Pinned by test/navigation_snapshot_test.dart; no device
  numbers yet - the Redmi 6A pop raster measurement is pending.
