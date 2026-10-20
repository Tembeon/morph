# Sheets passport (detents, drag rules, zoom, scrub)

Status: measured simulator (iPhone 16 Pro geometry) + device recapture
(every drag rule held unchanged); zoom from device film; background,
corners and stretch above the largest detent from an iPhone 17 Pro
simulator capture (2026-10-14); ported; replayed (sheet_test,
sheet_drag_test, sheet_native_test, sheet_zoom_test, sheet_widget_test).

## Native

`UISheetPresentationController` (`UIDropShadowView` frame sampled).
Public API (SDK 27.1, unchanged from 27.0): `detents` (`mediumDetent`, `largeDetent`,
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
- Present drift [device and simulator, every floating present]: the
  floating sheet slides in with its frame at the container's leading
  edge (origin x 0, centre x 193 on 402) and moves to its 8 pt inset on
  the present spring itself (x progress = y progress within 0.001). A
  docked present and every dismissal keep x. `MorphSheetMotion.drift`;
  replay: left edge while presenting 0.00 - 0.06 pt rms (2.4 - 3.0
  without).
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
- Touch: floating sheet swells 1.00854 on 0.2835/0.70 after 28 ms. The
  swell holds through the drag the touch turns into (device: the area
  scale sqrt(sx sy) stays 0.96837 = 0.9602 x 1.00854 in every drag of a
  floating sheet), fades as sqrt(1 - p) while the drag docks it (drag-up
  from medium), and goes with the settle, 25 ms after the lift. A sheet
  docked at the touch never swells, even once the drag undocks it
  (large-drag-down: 1.0000 throughout). Replay: area scale 0.0003 -
  0.0018 rms (simulator and device; 0.0024 - 0.0068 when the swell went
  at the drag's start).
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

## Spec - background [sim and device 2026-10-14, read from UIKit, notes private]

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
  Device confirmation: `rec-plan-bg-ml-{1,2,native}` switches to white
  at value 602.67 pt (drag progress 0.5025); table medium / large shots
  confirm the clear / grouped background. Raw captures stay private.

## Spec - corners [sim 2026-10-14, device clip layer 2026-10-03, read from UIKit, notes private]

- ONE OUTLINE: UIKit's floating glass is one SDF element with per-corner
  radii and the continuous curve, the clip's own outline (device shot
  references/dark/sheet-medium.png: the rim runs unbroken round the 54 pt
  bottom corners). morph builds one RRect per frame (`_SheetFrame.bodyShape`)
  for the clip (`MorphLiveBox` `continuous`), the glass and the fills; the
  liquid tier shades its top and bottom radii exactly as Flutter's rounded
  superellipse of those corners (a radius pair, renderer shader type 4).
  Before 2026-10-20 the glass took the top-left radius alone: a 38 pt glass
  cut by the 54 - 62 pt clip lost its rim round the bottom corners (the
  seam). Host proof: example/test/sheet_shape_host_test.dart; every frame of
  every transition: test/sheet_shape_test.dart.
- No shadow: the sheet's glass asks for none (UIKit's shadow view rests at
  opacity 0, and the clip cut the menu shadow away whole).
- Unscaled radii: top 38 always; bottom floating display - 8 = 54 (drawn
  51.85 at the floating scale).
- Bottom, device clip layer per frame (`radii` of test/fixtures/
  ios27-device/sheet, bl/br first): programmatic docking 54 + 8 p (p the
  docking progress, linear in height) to 62, then 0 once the sheet rests
  docked (square: the display's own corner hides it; device screenshots of
  a docked sheet show square corners); undocking from that rest 54 (1 - p),
  from 0; an interrupted or settling change runs from the radius it starts
  at, in step with the docking. A sheet presented docked keeps the display
  radius (large-only: 62 through present and dismissal). Present of a
  floating sheet: 52.67 -> 54 on the slide (corners still below the
  screen; not modelled). `MorphSheetMotion.bottomRadius`; replay against
  the clip layer during detent changes: 0.005 - 0.13 pt rms (sheet_test).
- During a drag the bottom radius is display - inset (1 - p) with the
  inset 8 (1 - p) rounded up to a pixel: display - 8 (1 - p)^2 (58.44 at
  p 0.333 measured, 58.29 modelled without the pixel rounding: NEAR).
- Zoom: the container clips continuous with radii running from the
  source's to the sheet's, and the sheet's background (glass, or the flat
  fill) fills the container while the content stays scaled to fit from
  the top leading corner: one outline. Film evidence (zoom.json `fade`,
  the mean green of the green sheet over the container): 0.983 at 0.161 s
  where content fitted to the height would cover at most 0.953.

## Spec - stretch above the largest detent [sim and device 2026-10-14]

- A floating largest detent rubber-bands upward (coefficient 0.55) with
  a dimension of clamp(maximum - detent, 0, 100): a medium-only sheet 100
  (0.2 pt rms over 240 pt of travel, slop 7), a 700 pt detent 78 (0.5 pt
  rms). A docked sheet (largest detent = large) does not move up at all
  (value 778 fixed for 200 pt of travel). `stretchLimit`.
- Not dismissible (isModalInPresentation): the pull below the smallest
  detent rubber-bands with 200 (a 200 pt detent pulled 134 pt fits 200 at
  0.3 pt rms); UIKit takes a quarter of the sheet height capped at 200
  (notes private). `refusedPullExtent` 200 (was an unmeasured 40).
  Device held samples: medium 435.67 -> 491.67 pt for 240 pt of actual
  travel; custom 700 -> 742.67 pt for 181.33 pt of travel (the planned
  240 pt path reaches the screen edge). The existing 12 pt device slop
  and 100 / 78 pt room reproduce both within 1.5 pt. A modal 200 pt
  sheet stays 200 pt tall while pulled down, rather than resizing.
- The area-keeping stretch above rides on top of both.

## Spec - keyboard and scrolling [sim and device 2026-10-14]

- A text field focused in the sheet (keyboard 328 pt on 402 x 874, safe
  bottom 34): the maximum stays 778; every detent value grows by the
  keyboard height up to the maximum, and the sheet goes to its largest
  detent. Medium-only: value 435.68 + 328 = 763.68, still floating (top
  100.1). Medium and large: docks at 778. Large: unchanged. The keyboard
  hiding returns it to the detent it had; no detent-change callback
  either way. morph: `_layout` raises the detents by `viewInsets.bottom`
  and moves the motion silently (`MorphSheetMotion.relayout(index:)`).
- `prefersScrollingExpandsWhenScrolledToEdge = false` (`scrollingExpandsSheet`
  false): a 250 pt drag up on a scroll view at medium scrolls it 250 pt
  and the sheet stays (value 435.68 throughout); default true expands
  first (value 435.68 -> 677, released to large), then scrolls.
  Device confirmation: `rec-plan-kb-{m,ml,sml}` measures 435.67 ->
  763.67 -> 435.67, 435.67 -> 778 -> 435.67, and 200 -> 778 -> 200
  respectively. The three-detent case confirms choosing the largest,
  with no detent callback. `rec-plan-se0-up` keeps medium at 435.67
  through a 250 pt upward content drag. Raw data and film are private.

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

## Spec - liquid zoom from a glass source [device, layer sampling; read from UIKit, notes private]

- A zoom out of a glass view runs UIKit's liquid morph
  (`_UIZoomLiquidMorphAnimator`, the morph a glass button grows its menu
  with): the sheet's glass and the source's glass are two shapes fused by
  a blur. A flat source (capsule, card) keeps the zoom above.
- Open: the sheet grows out of a 20.5 pt circle at the source's center;
  center 0.295/0.68, size 0.36/0.74; corners hold a capsule, then round
  from a virtual 500 to the sheet's on 0.40/0.80 after 0.028 s. The
  source's glass travels a third of the way toward the sheet's center on
  0.355/0.74, narrows on 0.205/0.97 and flattens on 0.355/0.74 to a 12 pt
  square that rests inside the sheet.
- Close: size 0.49/0.80; center 0.42/0.82 after 0.033 s; the source's
  glass travels back on 0.42/0.69 after 0.006 s, widens on 0.54/0.74
  after 0.017 s, regains its height on 0.49/0.80; corners round up toward
  201 on 0.48/0.82.
- The source's look and the sheet's content crossfade on 0.207/0.98 both
  ways (within 0.003 of the portal opacities); the look scales uniformly
  with its glass. Dimming keeps zoomIn / zoomOut.
- Replay (liquid_zoom_test, `ios27-device/zoom/liquid.json`): sheet 2.5 -
  3.4 pt rms at the medium detent; source glass under 1 pt; corners
  under 2 pt. NEAR: from the large detent UIKit shrinks the height faster
  (fit 0.38/0.88) into an 11.9 pt circle (one sample); the tuning keeps
  the medium detent's springs, 16 pt rms off there.
- NEAR, assumed: the fusion radius is the menu's envelope
  (`MorphFusionTurns`, `MorphMenuTuning.fusionEnvelope`), not measured for
  the zoom. The source's glass shows until the open's envelope ends, then
  rests unseen inside the sheet.
- Hand-over: the source hides in the frame that first draws the zoom (the
  route hides it at push) and shows again in the frame that drops it
  (sheet_zoom_test, push_zoom_test). Before, it hid and showed a frame
  late: the button blinked out for one frame after a close.

## Fixtures

Device `ios27-device/sheet/sheet-{l,ml,sml,undim}.jsonl`,
`ios27-device/sheet-drag/*` (28 drags/flicks, 26 replayed: fd-1000 and
lfd-800 sit on the decision boundary; manifest has nominal speeds),
`ios27-device/zoom/{zoom,scrub}.json` (manifest.txt). Simulator
`ios27/sheet`, `ios27/sheet-drag` (17, 16 replayed: lfd-800 left out).
sheet_drag_test reads device rows unshifted and simulator rows +1/60;
sheet_test shifts every row by one display frame of its recording. Film
crop `references/alert-video/sheet-opening-*`.

## Recapture

Scene `w2sheet`: `PROBE_DETENTS` (e.g. ml, sml, l), `PROBE_GRABBER=0`,
`PROBE_UNDIMMED=m`, `PROBE_SCROLLEXPAND=0`, `PROBE_EDGE=1`, `PROBE_STYLE`,
`PROBE_ZOOM=1`, `PROBE_SHEETBG=1`, `PROBE_SCRIPT` (present, dismiss, large,
medium, small, settings, kb, kbOff), `PROBE_DETENTS` letter `h` (a 700 pt
custom detent, or maximum - 40), `PROBE_MODAL=1` (isModalInPresentation),
`PROBE_FIELD=1` (a text field as the table header, focused by `kb`),
`PROBE_TABLEBG=native` (keep the table's own background). Widgets2UITests testW2Sheet, testW2SheetFlicks.
Zoom: scene `snzoom` (`PROBE_SRC`, `PROBE_SRC_Y`, `PROBE_DETENTS`,
`PROBE_STYLE=full`), SheetNavUITests testSNZoom, testSNZoomScrub,
testSNZoomScrubTiming + MorphRecorder.

## morph

Public (lib/morph.dart): sheet.dart (`showMorphSheet(from:)`,
`MorphSheetRoute`, `MorphSheet.of`, `scrollControllerOf`,
`MorphSheetAppearance`), sheet_motion.dart (`MorphSheetDetent` medium /
large / height / fraction / custom / fitted). Internal: sheet_motion.dart
(`MorphSheetMotion`, `MorphSheetTuning`), zoom_motion.dart
(`MorphZoomMotion`, `MorphZoomTuning`, `MorphLiquidZoomMotion`,
`MorphLiquidZoomTuning`), zoom_source.dart (`MorphZoomSource`,
`MorphSourceGlass`: the glass a glass control hands its tag). The zoom source is a `MorphSource` attached to a
`MorphSourceLink`.

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
- Measured on the simulator only (background flip, corners, stretch room,
  keyboard, scroll-to-expand off): device capture pending. Screen size:
  an iPhone 17 Pro Max simulator (440 x 956) reads the same 100 / 200 pt
  extents, 0.56 medium, 8 pt inset and 38 / 54 radii at rest; its drag
  (the 10 pt shortfall) and the 17e / SE sizes were not captured
  (pending, device plan in the coordinator's queue).

- One frame per docking reading the sheet at y 0 (device and simulator,
  8.3 ms, the frame the clip turns 62 -> 0): whether it reaches the screen
  is unknown; not modelled. sheets-capture.md pass B films it.
- Corner laws assumed, not captured: a sheet first presented docked
  (ml at large) undocks from 62; a drag that settles docked rests square.
  sheets-capture.md pass A records the radii of every drag.
- Keyboard MOTION: morph moves the raised sheet on the sheet spring as
  the insets change; UIKit's curve under the keyboard is not measured. A
  sheet with three detents was not captured (whether the keyboard picks
  the largest detent or the smallest one that fits is assumed: largest).
- ~0.1 s of interactive scrub before a drag commits; random immediate zoom
  dismissals.

## API gaps

- `preferredCornerRadius`, `prefersEdgeAttachedInCompactHeight`,
  `widthFollowsPreferredContentSize...`, `prefersPageSizing`,
  `preferredPlacement` (iPad / wide), `sourceView` popover adaptation.
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
  frame; the source is found and hidden through the `MorphSource` its
  `MorphSourceLink` is attached to, a MorphTag inside (tryCaptureRect
  each frame; hideForFlight at push and reveal from the closing tick, in
  the frame the zoom starts or ends, post-frame only while the tree
  builds). The
  content subtree carries a GlobalKey so the hand-over between the zoom
  layer and the sheet keeps its state.
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
  unscaled (docked, not zooming, not scrubbed). Since 2026-10-20 the gate
  is gone: a plane checks after paint whether it is drawn scaled and
  merges nothing while it is, from the next frame. A floating sheet scales its
  content to its inset width, where a container cannot keep its members on
  their own raster grids, so their glass draws in layers of its own there
  and shares the container once docked (glass-renderer.md, "Raster ties,
  scaled containers"). The gate widget is reused while its state holds, so
  the per-frame builder rebuilds nothing more.

- Reduce Motion: UIKit feeds the flag into the sheet layout (notes private); its effect needs the device. No detent haptic found.
