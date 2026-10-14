# Navigation pages passport (push, edge swipe, push zoom)

Status: measured device; ported; replayed (navigation_motion_test,
navigation_stack_test, push_zoom_test). Bars over the pages: [bars.md](bars.md).
Declarative stacks (`MorphNavigationStack.pages` + `MorphNavigationPage`,
navigation_api_test) create the same `MorphNavigationRoute`s, so pushes,
pops and zooms of a page list move exactly as imperative ones.

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

## Spec - the card and the dim [simulator film and device, 2026-10-15]

- While a page slides it is a card with the display's continuous corners:
  in the native sweep's edge-swipe film (iPhone 17 Pro simulator, iOS 27.0)
  the moving page's leading edge is rounded top and bottom with a radius
  fitted at ~62 pt, the display's. At rest the page is square.
- The page underneath darkens with black alpha 0.1 and a layer opacity
  equal to the covering page's progress. iPhone 16 Pro, iOS 27.0.1,
  `pages-hold20/40/60/85`: actual card x 65.33 / 145.67 / 229 / 327.33
  pt on a 402 pt page gives opacity 0.8375 / 0.6376 / 0.4303 / 0.1857.
  Programmatic push and content-pop rows use the same 0.1 black.
  The former 0.11 maximum was an estimate from one simulator pixel.
- morph: the slide clips the moving page (its own animation running or
  held by a finger) to a rounded superellipse of
  `MediaQueryData.displayCornerRadii` (fallback
  `MorphNavigationTuning.fallbackCardRadius` = 62); the page underneath
  takes black at `underDimOpacity` (0.1) x the top page's progress, on
  pushes and pops with or without a finger. Pinned by navigation_card_test.
  Cost: one rounded-superellipse clip layer on the moving page and a
  direct black paint below it, only while the slide moves. Pixel 6a
  navigation measurements are in the branch-completion audit.

## Spec - the content back swipe [device, 2026-10-15]

UINavigationController's `interactiveContentPopGestureRecognizer` (iOS 26,
on by default) pops from a horizontal drag anywhere in the content. morph:
`MorphNavigationStack.contentPopGestureEnabled` (default true) - past
30 pt of radial touch travel toward the trailing side, the page follows and
releases exactly as the edge swipe (same `popDistance` / `popVelocity`);
a drag toward the leading side never claims the pointer; any horizontal
drag, pan or scale recognizer deeper under the finger (scroll views,
sliders, page views, draggable pieces, InteractiveViewer) wins the arena
first and keeps the drag, at any offset. Device `pages-c0/c20/c25/c26/cslow`
place the radial start at 29.67–30 pt after subtracting the recognizer's
reported translation from the delivered touch travel. `pages-c29` begins;
`pages-c30/c40/c50/c60` do not. Morph's 30 degree angle boundary is NEAR,
fitted to the 29..30 degree bracket; other pointer kinds keep Flutter's pan
slop. Leftward drags do not begin. The horizontal strip scenarios retained
their scroll gesture; end-to-end handoff at all offsets remains unmeasured.

## Spec - the commit rule, re-checked [simulator sweep, 2026-10-14]

Native sweep item 7: XCUICoordinate `press(forDuration: 0.3...)` at x 3,
drag to 230 pt, hold 0.6 s, lift: the native page trailed at ~155 pt
(0.39 W, ~75 pt behind the planned finger) and returned; morph followed at
~207 pt and popped. Not changed: the device rule above (0.3 W pops at
rest) came from logged touches, the simulator run logged none, and the
long press before the drag may change what UIKit's recognizer sees.
Decided by the iPhone capture below (`pages-rel*`, `pages-xcdrag*`).

## iPhone capture plan (navpages)

`PROBE_PLAN=navpages tool/ios_reference/device.sh` (BarsUITests
testNavPages, scene `nav` with `PROBE_PAGES=4` and `PROBE_HSCROLL=1`;
recordings `rec-pages-*.jsonl`: touches, `B` rows of the navigation
controller's views to depth 4 with corner radius / curve / masked corners
/ shadow / background / opacity, `gr` rows of both pop recognizers' states
and translations, `hs` rows of the strip's offset and frame). Film
`pages-hold40` and `pages-hold40-dark` too (MorphRecorder or screen
recording): if the card's corners are not a layer property, the film is
the corner evidence.

| capture | input | decides |
|---|---|---|
| pages-auto, pages-auto-dark | programmatic push + pop | dim and card on a push without a finger |
| pages-hold10 .. pages-hold85 (+ hold40-dark) | edge drag to 0.1..0.85 W over 0.8 s, held 1 s, lift | dim(progress) law and maximum, corner radius while held, held release outcome |
| pages-rel35..57 - 25 / 60 | edge drag to 0.35..0.57 W in 0.25 / 0.6 s, held 0.6 s, lift | item 7: page vs finger lag, commit at rest past 0.3 W |
| pages-xcdrag3, pages-xcdrag6 | the sweep's input: XCUICoordinate press 0.3 / 0.6 s at x 3, drag to 230 at 300 pt/s, hold 0.6 | whether the long press explains the 75 pt lag and the return |
| pages-c0 .. pages-c60 | from (120, 0.8 H) 200 pt at 0..60 degrees up from horizontal, 0.5 s, held 0.6 | content swipe angle cutoff, slop (`gr` ctx at began), commit rule |
| pages-cleft, pages-cslow, pages-chold40 | leftward; 80 pt over 1.6 s; to 0.4 W held 1 s | leading drags ignored; slop; content swipe dim/card like the edge |
| pages-h0, -h0nb, -h0pg, -h300, -h300l, -h804 | drag 200 pt inside the horizontal strip (y 480; check `hs` y0/y1) at offset 0 (bounce, no bounce, paging), 300 (right / left), 804 (trailing end) | who wins: the scroll view or the content pop |

## Spec - a push whose first frame is slow [device, 2026-10-13]

UINavigationController pushes a page whose view spends 60 ms in
`layoutSubviews` (or 60 ms of work before the transaction commits), iPhone
16 Pro, iOS 27.0.1, the incoming page's screen x on every display-link tick
(lab captures; notes private):

| push | x on the frames after the push (pt) |
|---|---|
| light | 402, 342, 282, 227, 181 |
| 60 ms in layout | 402, 335, 275, 222, 176 |
| 60 ms before commit | 378, 316, 258, 207, 164 |

The stall delays the motion; it skips none of it: the first frame after it
shows the page at the start of its path (within one step) and the motion
moves on by its usual 60 - 67 pt a frame. morph: `MorphFirstFrameStart`
counts the push spring from the frame after the one that builds the page,
as if that frame had lasted one display period (unchanged without a slow
first frame).

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

navigation_motion.dart (`MorphNavigationTuning`), navigation_stack.dart
(`MorphNavigationStack`, `MorphNavigationRoute(from:)`,
`MorphNavigationScaffold`, `MorphNavigationConfig`, `pushMorphZoom`),
push_zoom.dart, push_zoom_motion.dart (`MorphPushZoomMotion`,
`MorphPushZoomTuning`). The stack's navigator sits under a
NavigatorPopHandler (the enclosing route is doNotPop while it can pop).

Bar item content and the inline title ride their scale, blur and
presence through `morphVeiledGlyphs` (glyph_scale.dart): the glyph policy
(`MorphGlyphPolicy`) draws them exact at rest, snapped or from a raster
while the item scale moves, and on Android blurred and faded through the
pyramid shader; off Android the blur and fade are layers under the
drawing's own opacity. Policy measured on the tab bar and menu
(tab-bar.md, menu-button.md); the navigation bench is unchanged within
its spread (glass-renderer.md "One glyph policy").

Per-frame work (lifecycle.md, 2026-10-14): the route's scope builds its
transition on every tick of either animation; `MorphNavigationRoute`
hands back the transition it built before while the page, the
animations, their status, the direction and Reduce Motion are the same,
so the slide (a live transform) and the edge-swipe region no longer
rebuild (6 -> 2 builds a frame mid-transition; the 2 left are the
framework's own listenable builders of the two routes). The stack's bars
are a repaint boundary, the inline titles and every bar item one each:
an item that only moves is composited again, and the navigator around the
bars no longer repaints with them. Host recorder, flat: push 6/5/75-97 ->
2/5/38-46 a frame, pop 6/5/78-92 -> 2/5/39-47, the tail after the slide
0/3/58 -> 0/3/18 and 1.26 -> 0.96 s (bars.md "Rest").

## Not reproduced / open

- The exact angle boundary within 29..30 degrees and scroll-to-pop
  handoff rules outside the recorded horizontal-strip cases.
- The commit rule's returning-flick anomaly below; synthesized gesture
  commands must be compared with delivered touches, not requested paths.

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
  `MorphNavigationRoute(from:)` - the page grows out of the tag as
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
  so an edge drag counts), not on the web, and only under a
  `MorphGlassRenderer` whose effective tier is flat; at rest the controller
  is off and the page is live. FLAT TIER ONLY: on fake / liquid (and with
  no renderer above the page) every page stays live. SnapshotWidget
  renders the page through toImageSync in a pass of its own whose origin
  is the page, while the renderer maps its shader-filter coordinates with
  getTransformTo(null) (filter_pass_transform.dart), which includes the
  slide's translate - backdrop shaders, glass containers and raster-phase
  anchors inside a snapshot would shade offset by the captured slide
  offset (a pushed page by about the full width, the page under a pop by
  parallax x width). Snapshots on those tiers would need the renderer to
  treat a snapshot as its own pass (as GlassCompositionProbe.seededPassOrigin
  does) - not implemented. With the option on the widget is mounted for
  the page's whole life and only its controller toggles (the tier is read
  in didChangeDependencies), so page state never remounts. What freezes
  while it moves: the page's scrolling, animations, text input and
  anything under a backdrop filter (glass inside the page reads an empty
  backdrop in the snapshot). The capture happens on the FIRST MOVING
  FRAME, so whatever the page shows then stays for the whole slide:
  content that settles in a post-frame callback, images still decoding,
  and a tag a flight launched mid-slide hides keep their first-frame
  state. Each snapshot adds an offscreen pass on that frame (a push or pop
  takes two toImageSync calls, one per page) - a raster spike to look for
  on the device. The bars are not part of the page and stay live. Pinned
  by test/navigation_snapshot_test.dart; no device numbers yet - the
  Redmi 6A pop raster measurement is pending.

- Reduce Motion, read from UIKit (notes private): pushes and pops without a finger cross-fade both pages over 0.5 s (UIView ease-in-out); an edge swipe keeps the slide. Ported (`MorphNavigationTuning.crossFadeDuration`); see states.md.
