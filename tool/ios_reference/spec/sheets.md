# Sheets passport (detents, drag rules, zoom, scrub)

Status: measured simulator (iPhone 16 Pro geometry) + device recapture
(every drag rule held unchanged); zoom from device film; background,
corners and stretch above the largest detent from an iPhone 17 Pro
simulator capture (2026-10-14); ported; replayed (sheet_test,
sheet_drag_test, sheet_native_test, sheet_zoom_test, sheet_widget_test).

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
  largest floating detent of the way to 10 pt below the large detent
  (`dragDockShortfall`; 768 of 778 in every simulator row).
  The opaque fill: see "Spec - background".
- Dimming black 0.2, scaled by progress past an undimmed detent.
- Touch: floating sheet swells 1.00854 on 0.2835/0.70 after 28 ms.
- Drag moves the height point for point between the detents, a slide below
  the smallest; above the largest see "Spec - stretch above the largest
  detent".
- STRETCH [device, 18 drags/flicks]: a sheet floating when the drag
  begins stretches along the drag, up or down alike, keeping its area
  (sqrt(sx sy) holds the swell to 1e-4) about its BOTTOM edge (held still,
  the bottom moves 0.1 pt while the top rings 1.4). Ratio sy/sx = 1 +
  8.9e-5 per pt of finger travel since the drag began (held: 100 pt down
  1.0079, 320 down 1.0270, 140 up 1.0113 = 8.80 - 9.00e-5) + 2.4e-4 x a
  lag that follows the travel and its velocity on 0.8/0.5 (a start or a
  speed-up overshoots: 1300 pt/s flick 1.043 at 168 pt; a stop dips 0.005
  - 0.009). Held from the lift, released with the settle on 0.355/0.62
  (0.0005 - 0.0008 rms). Not on a sheet docked when the drag began
  (large-drag-down, l-*, lfd-*: exactly 1), nor in programmatic detent
  changes. Replay 0.0011 - 0.0066 rms in the ratio (0.0016 - 0.0123
  without the lag); left: two to three frames of UIKit lag in a flick
  and the ringing after the finger starts and stops.
  `MorphSheetTuning.stretchPerPoint`, `stretchLagSpring`,
  `stretchLagGain`, `stretchSpring`.
- Release: settle 25 ms after the lift on the detent nearest the height
  projected by 0.143 s of finger velocity, carrying 2x that velocity.
- Below the smallest detent: dismiss when the projected slide passes half
  the visible height or v > 1000 pt/s (flick dismissal on 0.352/0.79 with
  0.6x velocity). Boundary flicks fd-1000 (887 pt/s, stays) and lfd-800
  (714 pt/s) are left out of the replay.
- Grabber tap cycles detents 50 ms after the lift.
- A scrollable with `MorphSheet.scrollControllerOf` expands the sheet before
  it scrolls and moves it down from its top.

## Spec - background [sim 2026-10-14, read from UIKit, notes private]

- Floating: glass (a glass group under the content, no fill). Docked: the
  glass is removed and the sheet's own layer is systemBackground, light
  white, dark rendered 28, 28, 30 (0xFF1C1C1E, the old 0xFF2C2C2E table
  was wrong). No shadow (its view sits at opacity 0).
- UIKit takes the background of the detent NEAREST the sheet and animates
  every change of it on the sheet spring (bg alpha after the flip 0.146,
  0.256, 0.364, 0.468, 0.574 ... a frame apart = the 0.344 crit spring one
  frame late). A programmatic change or a settle changes it with the frame,
  so it equals the docking fraction (morph as before). A drag flips it
  where the drag's docking progress crosses 0.5 (both ways between 600.0
  and 602.7 pt of value, no hysteresis), so the glass gives way to white
  over 0.3 s at one point of the drag and, once white is opaque, the glass
  is removed while the finger still holds the sheet below the top. This
  is the "line" seen on the phone. `MorphSheetMotion.fill`,
  `backgroundSwitch`.
- Content: an insetGrouped table in the sheet is clear while floating and
  systemGroupedBackground when docked; its cells stay white. morph:
  `MorphListBackground` (the page behind an inset grouped list) reads the
  sheet's fill live and paints the grouped gray at its opacity, so it
  switches with the sheet's background; outside a sheet it is opaque.

## Spec - corners [sim 2026-10-14]

- Continuous corners (cornerCurve continuous) on the sheet's clip: morph
  clips with the rounded superellipse of the same radii (`MorphLiveBox`
  `continuous`); the glass already drew one. The zoom container and a
  zooming or scrubbed sheet clip continuous too (the corner radius still
  runs from the source's to the sheet's).
- Unscaled radii: top 38; bottom floating display - 8 = 54 (drawn 51.85
  at the floating scale), docked = the display radius (UIKit stores
  infinity, the environment radius 62 on this screen).
- During a drag the bottom radius is display - inset (1 - p) with the
  inset 8 (1 - p) rounded up to a pixel: `1 - (1 - p)^2` of the way
  (`cornerBlend`; 58.44 at p 0.333 measured, 58.29 modelled without the
  pixel rounding). Programmatic and settle: from where it was to the end
  on the spring.

## Spec - stretch above the largest detent [sim 2026-10-14]

- A floating largest detent rubber-bands upward (coefficient 0.55) with
  a dimension of clamp(maximum - detent, 0, 100): a medium-only sheet 100
  (0.2 pt rms over 240 pt of travel, slop 7), a 700 pt detent 78 (0.5 pt
  rms). A docked sheet (largest detent = large) does not move up at all
  (value 778 fixed for 200 pt of travel). `stretchLimit`.
- Not dismissible (isModalInPresentation): the pull below the smallest
  detent rubber-bands with 200 (a 200 pt detent pulled 134 pt fits 200 at
  0.3 pt rms); UIKit takes a quarter of the sheet height capped at 200
  (notes private). `refusedPullExtent` 200 (was an unmeasured 40).
- The area-keeping stretch above rides on top of both.

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

sheet.dart (`showMorphSheet(from:)`, `MorphSheetRoute`, `MorphSheet.of`,
`scrollControllerOf`, `MorphSheetAppearance`), sheet_motion.dart
(`MorphSheetMotion`, `MorphSheetDetent` medium / large / height / fraction,
`MorphSheetTuning`), zoom_motion.dart (`MorphZoomMotion`,
`MorphZoomTuning`). NOTE: a sheet bug fix is in flight in the working tree
(sheet.dart, sheet_zoom_test) - check before editing.

A detent change hands the content's scope the new detent over the same
content: only what reads the sheet through `MorphSheet.of` rebuilds
(`scrollControllerOf` depends on the controller alone). Host recorder,
detent change: 118-123 -> 19-20 builds in the first frame. Still open: the
content is laid out again on every frame of the detent spring (19-25
layouts, 27-42 paints a frame for 0.69 s; native lays it out once at the
target and animates the frame). Laying out at the target, or at the larger
of the two detents, moves what the content pins to its bottom during the
motion: a pixel-changing trade for the owner to judge on the iPhone.

## Not reproduced / open

- The bottom radius during a drag rounds the inset to a pixel in UIKit
  (steps of a third of a point); morph is smooth.
- Measured on the simulator only (background flip, corners, stretch room):
  confirm on the iPhone with the probe scene before calling them device
  truth; the 10 pt docking shortfall and the 100 / 200 pt caps may depend
  on the screen.

- The present's 8 pt horizontal drift (first-frame artifact).
- One frame per docking reading the sheet at y 0.
- The touch swell holds through a drag (sqrt(sx sy) stays 1.00854 x the
  floating scale in every device drag of a floating sheet); morph lets it
  go when the drag begins.
- Keyboard avoidance MOTION (layout only: the maximum shrinks).
- ~0.1 s of interactive scrub before a drag commits; random immediate zoom
  dismissals.

## API gaps

- `preferredCornerRadius`, `prefersEdgeAttachedInCompactHeight`,
  `widthFollowsPreferredContentSize...`, `prefersPageSizing`,
  `preferredPlacement` (iPad / wide), `sourceView` popover adaptation.
- `prefersScrollingExpandsWhenScrolledToEdge = false`.
- Custom detents exist (`MorphSheetDetent.custom(resolver, identifier:)`)
  and a content-sized one (`MorphSheetDetent.fitted`, SwiftUI
  `presentationSizing(.fitted)`; the content is laid out loose and
  measured, the sheet moves on the measured spring when the height
  arrives). Detent `backgroundEffect` is missing.
- Delegate callbacks exist: `onDetentChanged` (on every settle toward a
  new detent, programmatic ones included) and `onDismissAttempt`
  (`dismissible` false or a blocking `PopScope`, which also stops the
  drag). UIKit marks the refused start of a dismissal during the drag but
  reports nothing while the finger is down; after the lift it reports the
  attempt (async, next main-queue turn) only when the pull beyond the edge
  exceeds a quarter of the rubber-band extent, whatever the velocity [read
  from UIKit, notes private; ported: `dismissAttemptShare` 0.25 of
  `refusedPullExtent`]. The extent is 200 at the bottom edge and the 100
  pt cap applies above the largest detent (simulator capture, see the
  stretch section).
- Full-screen / form-sheet presentation styles.

## Implementation notes (morph side, moved from CLAUDE.md)

- `showMorphSheet` pushes a `MorphSheetRoute`, a PopupRoute:
  transitionDuration zero, the reverse controller is stopped in didPop and
  set to 0 when the motion's dismissal rests (which finalizes the route);
  buildModalBarrier is an IgnorePointer, so undimmed detents leave the
  page live and the dimming / tap-to-dismiss is drawn by the sheet itself.
- ZOOM (`showMorphSheet(from:)`, zoom_motion.dart): the zoom is
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
  edge tolerances in the file; the stretch ratio of every one within
  0.0075 rms). The stretch is drawn by the sheet's one MorphLiveBox
  transform (x and y scale apart, bottom-anchored rect from
  `visibleRect`); no frame builds.
- Glass containers in the content: the sheet wraps its content in a
  `MorphGlassContainerGate` that is open only while the content is drawn
  unscaled (docked, not zooming, not scrubbed). A floating sheet scales its
  content to its inset width, where a container cannot keep its members on
  their own raster grids, so their glass draws in layers of its own there
  and shares the container once docked (glass-renderer.md, "Raster ties,
  scaled containers"). The gate widget is reused while its state holds, so
  the per-frame builder rebuilds nothing more.

- Reduce Motion: UIKit feeds the flag into the sheet layout (notes private); its effect needs the device. No detent haptic found.
