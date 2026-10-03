# Sheets passport (detents, drag rules, zoom, scrub)

Status: measured simulator (iPhone 16 Pro geometry) + device recapture
(every drag rule held unchanged); zoom from device film; ported; replayed
(sheet_test, sheet_drag_test, sheet_zoom_test, sheet_widget_test).

## Native

`UISheetPresentationController` (`UIDropShadowView` frame sampled).
Public API (SDK 27.0): `detents` (`mediumDetent`, `largeDetent`,
`customDetentWithIdentifier:resolver:` getting a context with
`maximumDetentValue`), `selectedDetentIdentifier`,
`largestUndimmedDetentIdentifier`, `prefersGrabberVisible`,
`preferredCornerRadius`, `prefersScrollingExpandsWhenScrolledToEdge`,
`prefersEdgeAttachedInCompactHeight`,
`widthFollowsPreferredContentSizeWhenEdgeAttached`, `prefersPageSizing`,
`preferredPlacement` (automatic / leading / center / trailing, new in 27),
`sourceView`, `invalidateDetents`, `animateChanges:`, delegate
(didChangeSelectedDetentIdentifier); detent `backgroundEffect`.
Zoom: `preferredTransition = .zoom` (see navigation-pages.md for options).

## Spec - motion [sim, device-confirmed]

- Two DOFs on `MorphSheetTuning.spring` 0.3441/1.0 (= CASpringAnimation
  333.3 / 36.5) [tuning]: unscaled HEIGHT (detent value + bottom safe area)
  and TRANSLATION (present/dismiss). 0.06 pt rms.
- Medium detent = 0.56 of the maximum the resolver gets.
- Floating (below large) = the full-width sheet scaled by 1 - 16/W (+ a shift
  keeping 8 pt off the bottom); unscaled corners 38 top, display radius - 8
  bottom; docking = one transform lerped by the docking progress, defined
  PER TRANSITION (height fraction between the transition's start and the
  large detent, or back to the floating detent it heads to; between two
  floating detents it stays floating); during a drag the fraction above the
  largest floating detent. systemBackground fades in by the same fraction.
- Dimming black 0.2, scaled by progress past an undimmed detent.
- Touch: floating sheet swells 1.00854 on 0.2835/0.70 after 28 ms.
- Drag moves the height point for point (nothing above the largest detent,
  a slide below the smallest).
- Release: settle 25 ms after the lift on the detent nearest the height
  projected by 0.143 s of finger velocity, carrying 2x that velocity.
- Below the smallest detent: dismiss when the projected slide passes half
  the visible height or v > 1000 pt/s (flick dismissal on 0.352/0.79 with
  0.6x velocity). Boundary flicks fd-1000 (887 pt/s, stays) and lfd-800
  (714 pt/s) are left out of the replay.
- Grabber tap cycles detents 50 ms after the lift.
- A scrollable with `MorphSheet.scrollControllerOf` expands the sheet before
  it scrolls and moves it down from its top.

## Spec - zoom from a source [film, device; invisible to layer sampling]

- Container center and size ride SEPARATE springs (one spring: 10 - 20 pt
  rms): open center 0.349/0.833, size 0.472/0.748 (3.3 pt rms); close
  center 0.442/0.762, size 0.203/1.0 (5.2 pt rms). Native-fidelity
  exemption (widget layer, not an engine flight).
- Content laid out at its size, scaled uniformly to fit from the top
  leading corner; source replica stretched over the container; crossfade a
  0.154 crit spring (0.045 s late on open); dimming on zoomIn 0.34/1.0 and
  zoomOut 0.34/0.92 [tuning; device fits 0.322/1.0, 0.354/0.919].
- SCRUB: a drag down from the smallest detent follows the finger, top a
  little ahead (1.115 per pt), sides drawing in (0.275); release past 100 pt
  or 1050 pt/s zooms into the source from where the finger left it, else
  returns on 0.196 crit (`MorphZoomTuning.scrubFrame`; held drags of 77 pt
  returned, 126+ dismissed). Some device drags (4/5 one session, 2/14
  another) dismissed at once, trigger unknown; morph always scrubs.

## Fixtures

Device `ios27-device/sheet/sheet-{l,ml,sml,undim}.jsonl`,
`ios27-device/sheet-drag/*` (26 drags/flicks, manifest has nominal speeds),
`ios27-device/zoom/{zoom,scrub}.json` (manifest.txt). Simulator
`ios27/sheet`, `ios27/sheet-drag` (16). Device rows replay best UNSHIFTED,
simulator +1/60. Film crop `references/alert-video/sheet-opening-*`.

## Recapture

Scene `w2sheet`: `PROBE_DETENTS` (e.g. ml, sml, l), `PROBE_GRABBER=0`,
`PROBE_UNDIMMED=m`, `PROBE_SCROLLEXPAND=0`, `PROBE_EDGE=1`, `PROBE_STYLE`,
`PROBE_ZOOM=1`, `PROBE_SHEETBG=1`, `PROBE_SCRIPT` (present, dismiss, large,
medium, small, settings). Widgets2UITests testW2Sheet, testW2SheetFlicks.
Zoom: scene `snzoom` (`PROBE_SRC`, `PROBE_SRC_Y`, `PROBE_DETENTS`,
`PROBE_STYLE=full`), SheetNavUITests testSNZoom, testSNZoomScrub,
testSNZoomScrubTiming + MorphRecorder.

## morph

sheet.dart (`presentMorphSheet(from:)`, `MorphSheetRoute`, `MorphSheet.of`,
`scrollControllerOf`, `MorphSheetStyle`), sheet_motion.dart
(`MorphSheetMotion`, `MorphSheetDetent` medium / large / height / fraction,
`MorphSheetTuning`), zoom_motion.dart (`MorphZoomMotion`,
`MorphZoomTuning`). NOTE: a sheet bug fix is in flight in the working tree
(sheet.dart, sheet_zoom_test) - check before editing.

## Not reproduced / open

- The present's 8 pt horizontal drift (first-frame artifact).
- One frame per docking reading the sheet at y 0.
- ~2 percent vertical stretch of a sheet pulled below its smallest detent.
- Keyboard avoidance MOTION (layout only: the maximum shrinks).
- ~0.1 s of interactive scrub before a drag commits; random immediate zoom
  dismissals.

## API gaps

- `preferredCornerRadius`, `prefersEdgeAttachedInCompactHeight`,
  `widthFollowsPreferredContentSize...`, `prefersPageSizing`,
  `preferredPlacement` (iPad / wide), `sourceView` popover adaptation.
- `prefersScrollingExpandsWhenScrolledToEdge = false`.
- Custom detent identifiers + programmatic `animateChanges` detent change
  (morph: needs check), detent `backgroundEffect`.
- Delegate callbacks (selected detent changed, should dismiss).
- Full-screen / form-sheet presentation styles.

## Implementation notes (morph side, moved from CLAUDE.md)

- `presentMorphSheet` pushes a `MorphSheetRoute`, a PopupRoute:
  transitionDuration zero, the reverse controller is stopped in didPop and
  set to 0 when the motion's dismissal rests (which finalizes the route);
  buildModalBarrier is an IgnorePointer, so undimmed detents leave the
  page live and the dimming / tap-to-dismiss is drawn by the sheet itself.
- ZOOM (`presentMorphSheet(from:)`, zoom_motion.dart): the zoom is
  INVISIBLE to presentation-layer sampling (the sheet's views sit at their
  final frames from the first tick; only the source's _UIReparentingView
  alpha and a portal alpha move) - measured from device film of probe
  scene snzoom (grey page, magenta source, green sheet; chromatic-pixel
  bbox per frame). Two springs on one container is a native-fidelity
  exemption, so it lives in the widget layer, not in an engine flight
  frame; the source is found and hidden through the engine's MorphTag
  (tryCaptureRect each frame, hideForFlight / reveal deferred to
  post-frame). The content subtree carries a GlobalKey so the hand-over
  between the zoom layer and the sheet keeps its state.
- SCRUB detail (scrub.json): `MorphZoomTuning.scrubFrame` per point of
  travel since the drag began: top +1.115, sides in 0.275, bottom up 0.04;
  above the start it grows by at most 17 pt of travel; travel counts from
  where the drag recognizer accepted (UIKit's begins later on a fast
  drag). Past 100 pt or 1050 pt/s (the push's threshold, unmeasured here)
  the scrub frame becomes the zoom's destination, so the close is
  continuous. The scrub is drawn in the ordinary sheet tree (one Transform
  maps the laid-out box onto the drawn rect, the body clipped shorter):
  swapping to the zoom layer mid-drag would unmount the drag recognizer.
  Immediate native dismissals: first device session (light) 4 of 5 drags
  dismissed at the slop with no scrub, later dark session 2 of 14 (a slow
  20 pt drag, a fast one from 480) - not press time 30..140 ms, not speed,
  not start point.
- Replays: sheet_test (programmatic, 0.8 - 2.1 pt rms incl. present jank),
  sheet_drag_test (16 simulator + 26 device drags/flicks, outcomes exact,
  tolerances in the file).
