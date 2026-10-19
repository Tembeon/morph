# Navigation pages passport (push, edge swipe, push zoom)

Status: measured device; ported; replayed (navigation_pop_motion_test,
navigation_motion_test, navigation_card_test, push_zoom_test);
navigation_stack_test and navigation_api_test pin behaviour without a
fixture. Bars over the pages: [bars.md](bars.md). API parity:
[api/navigation.md](api/navigation.md).
Declarative stacks (`MorphNavigationStack.pages` + `MorphNavigationPage`,
navigation_api_test) create the same `MorphNavigationRoute`s, so pushes,
pops and zooms of a page list move exactly as imperative ones.

## Native

`UINavigationController` push/pop, interactive pop gesture,
`UIViewController.preferredTransition = .zoom(options:sourceViewProvider:)`
(`UIViewControllerTransition`, `UIZoomTransitionOptions`:
`interactiveDismissShouldBegin`, `alignmentRectProvider`, `dimmingColor`,
`dimmingVisualEffect`; also `zoom(...sourceBarButtonItemProvider:)`;
unchanged in iPhoneOS27.1.sdk).
Tuning [tuning]: `_UIFluidNavigationTransitionsSpec`, `_UIZoomTransitionSpec`.

## Spec - push/pop and edge swipe

- Push: spring 0.3 critically damped with v0 8.3 widths/s (fitted: the
  curve starts at full speed); page below at parallax 0.3.
- Edge swipe 1:1; release on interactiveSpring 0.3/0.85 [tuning; device free
  fit 0.294 - 0.300 / 0.85].
- Commit rule [UIKit reading, notes private; device, 2026-10-15]: predict
  `progress + 0.35 * meanVelocity + 0.5 * 0.35^2 * meanAcceleration`;
  pop when that exceeds `min(187.5 / width, 0.5)`. Velocities are in
  widths/s, accelerations in widths/s^2, using the last three accepted
  samples. Each acceleration differs from the previous one by at most 5.
  The pan speed mixes adjacent movement speeds with weights 0.2 / 0.8;
  lifting keeps the last movement speed, even after a hold. Statistics
  accept a sample after 10 ms, or after 1 ms if displacement changed;
  the timing gate counts attempts, not only accepted samples. At lift the
  ordinary timing gate still applies. A recognized drag with no update
  returns; with fewer than three samples, positive average speed commits.
  `MorphNavigationPopMotion` replays all 33 edge/content releases from
  three fresh runs, including speed, acceleration and outcome. Platform
  event delivery and gesture admission remain NEAR. An uninterrupted fast
  flick boosts spring speed by 4.25 until mean speed falls below 1.5 widths/s.
  Six additional fast edge/content captures confirm that boost and all six
  release decisions. Their terminal speed checks are retained; coalesced
  fast inputs whose event/touch timestamps differ are not claimed as
  complete touch-stream reconstructions.
- The former 0.3 distance / 1.06 widths/s flick approximation described
  a limited recorded bracket, not a universal release rule.
  `MorphNavigationTuning.popDistance` / `popVelocity` keep those values
  and no route reads them; routes use the predictor.
  The release spring keeps 0.3 / 0.85 and carries the reconstructed pan
  speed into either return or completion. Its 33 recorded curves replay
  with onset fitted from delivered lift and one display-frame uncertainty
  between display-link timestamps and sampled presentation layers (one
  retained sample exposes the following frame early, then holds it).
  Geometry error outside that interval stays below 0.2 pt RMS. The legacy
  `cancelVelocityScale` (2.9) compensated for a 50 ms touch-window speed
  estimate; it does not multiply the reconstructed speed. Only
  navigation_motion_test's legacy settle replay still uses it.

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
  Cost, only while the slide moves (Pixel 6a, one launch each of
  809c5fd4 and of it without the clip or without the dim,
  perf/2026-10-19-bench-navcard-*): the clip 0.6 - 1.0 ms GPU p95 on
  enter, nested push and pop in both tiers, the dim 0.3 - 0.7. The clip
  is kept, a declared cost of the look: Impeller draws a non-rect clip as
  a stencil of its shape plus a depth cover of its bounds, and no render
  with the same pixels avoids it (docs/performance.md, "Navigation card
  clip"). IDENTICAL saving: a page under the opaque card of a navigation
  page above it paints itself and its dim only in the strip that card
  leaves visible (a rect clip, a scissor on Impeller); see
  docs/performance.md, "Covered page cut".

## Spec - the content back swipe [device, 2026-10-15]

UINavigationController's `interactiveContentPopGestureRecognizer` (iOS 26,
on by default) pops from a horizontal drag anywhere in the content. morph:
`MorphNavigationStack.contentPopGestureEnabled` (default true) - past
30 pt of radial touch travel toward the trailing side, the page follows and
uses the edge swipe's release predictor;
a drag toward the leading side never claims the pointer; any horizontal
drag, pan or scale recognizer deeper under the finger (scroll views,
sliders, page views, draggable pieces, InteractiveViewer) wins the arena
first and keeps the drag, at any offset. Device `pages-c0/c20/c25/c26/cslow`
place the radial start at 29.67 - 30 pt after subtracting the recognizer's
reported translation from the delivered touch travel. `pages-c29` begins;
`pages-c30/c40/c50/c60` do not. Morph's 30 degree angle boundary is NEAR,
fitted to the 29..30 degree bracket; other pointer kinds keep Flutter's pan
slop. Leftward drags do not begin. The horizontal strip scenarios retained
their scroll gesture; end-to-end handoff at all offsets remains unmeasured.

The earlier distance-only release approximation missed these outcomes: content
c0 at actual x 170.33 (0.4237 W) pops; c25 at 154.33 (0.3839 W) and c26
at 153 (0.3806 W) pop; c27 at 148.33 (0.3690 W), c29 at 145.67 (0.3624 W)
and chold40 at 132.33 (0.3292 W) return. c20 returns at 160 (0.3980 W),
so these do not establish a new monotonic distance threshold. The angle
test pins gesture admission only, without asserting the native release outcome.
Edge rel35-60 pops at actual x 126.67 (0.3151 W), confirming the earlier
0.3 rule for that capture. Both coordinate drags reached x 213 (0.5299 W),
but a 0.3 s initial press popped and a 0.6 s initial press returned. Release
velocity and cancellation therefore required event-time observations.
Three fresh 2026-10-15 runs confirm the prediction above for all 33 releases.
For example c25 pops in one run and returns in another with the same requested
path: different measured acceleration puts the projected progress on opposite
sides of the threshold. Reconstructing pan speed and all statistics from the
delivered touch coordinates reproduces the recorded values (within 1e-5).
Only own numeric touch/geometry measurements are committed in
`ios27-device/navigation/release-decision.json`; raw runtime rows stay private.

## Spec - the commit rule, re-checked [simulator sweep, 2026-10-14]

Native sweep item 7: XCUICoordinate `press(forDuration: 0.3...)` at x 3,
drag to 230 pt, hold 0.6 s, lift: the native page trailed at ~155 pt
(0.39 W, ~75 pt behind the planned finger) and returned; morph followed at
~207 pt and popped. That sweep logged no delivered touches, so it could
not isolate the cause. The iPhone event-time follow-up above establishes
the prediction from velocity and acceleration; the old 0.3 W bracket
does not describe a page whose recent movement statistics differ.

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
`ios27-device/navigation/release-decision.json` (33 releases, 6 fast
speed checks); `ios27-device/push_zoom/push_zoom.json`. Simulator
`ios27/bars/pop-edge-*`.

## Recapture

Scene `nav` with `PROBE_AUTO=push|pushpop` (programmatic), BarsUITests
(edge swipes). Push zoom: scene `snpush` (`PROBE_SRC=capsule|card|glass`,
`PROBE_SRC_Y`), SheetNavUITests testSNPush, testSNPushDrag, testSNPushDrag2,
filmed with MorphRecorder (the zoom is invisible to layer sampling).

## morph

navigation_motion.dart (`MorphNavigationTuning`,
`MorphNavigationPopMotion`), navigation_stack.dart
(`MorphNavigationStack`, `MorphNavigationPage(from:)`,
`MorphNavigationRoute(from:)`, `MorphNavigationScaffold`,
`MorphNavigationConfig`), push_zoom.dart, push_zoom_motion.dart
(`MorphPushZoomMotion`, `MorphPushZoomTuning`), zoom_source.dart
(`MorphZoomSource`; the source is `MorphSource(link:)` in scope.dart),
predictive_back.dart (Android predictive back drives the same
interactive pop and zoom dismissal: an approximation, iOS has none;
Pixel check tool/audit/foundation-5.2-2026-10-19/predictive-back.md).
The stack's navigator sits under a NavigatorPopHandler (the enclosing
route is doNotPop while it can pop).

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
- Three fresh no-bounce and already-scrolled horizontal-strip captures
  retain their scroll gesture, with no content-pop callback. The original
  probe disabled alwaysBounceHorizontal only; the verified version sets
  bounces=false too. Handoff outside these cases remains unmeasured.
- Synthesized gesture commands must be compared with delivered touches,
  not requested paths. Historical release captures without event-time
  speed/statistics do not isolate a new threshold or a returning-flick rule.
- Exact push curve is a fit (no read value for v0).
- Interrupted transitions (a push during a push, a swipe started during
  a push, a pop during a push zoom) are not captured. morph starts a pop
  during a push from the page's current place at the push speed, and
  turns a push zoom around with its velocity.
- Under Reduce Motion UIKit cross-fades the bar with the pages
  (states.md); morph's bar items snap. The zoom's Reduce Motion
  behaviour is not decoded; morph zooms unchanged.
- A zoom source resolves once, at the push. UIKit asks its source
  provider again during the transition, so a pop can return into
  another or a rebuilt cell; morph dissolves when the first source is
  gone.

## API gaps

Full list and ranking: [api/navigation.md](api/navigation.md).

- `alignmentRectProvider` (zoom into a sub-rect of the destination),
  `interactiveDismissShouldBegin`, custom `dimmingColor` /
  `dimmingVisualEffect`.
- Zoom from a bar button item; a full-screen modal zoom outside a stack.
- Other `preferredTransition`s (coverVertical, crossDissolve, flip, curl;
  SwiftUI `.crossFade`, iOS 27).
- State restoration: `MorphNavigationPage.restorationId` is accepted but
  the stack's inner Navigator has no `restorationScopeId`.

## Implementation notes (morph side, moved from CLAUDE.md)

- Release prediction and settle speed live in `MorphNavigationPopMotion`;
  spring parameters remain on `MorphNavigationTuning`. Edge-swipe ownership: see bars.md
  (NavigatorPopHandler, MorphNavigationRoute's edge gesture).
- PUSH ZOOM API: `MorphNavigationRoute(from: link)` /
  `MorphNavigationPage(from: link)` with the source wrapped in
  `MorphSource(link: link)` - the page grows out of the source as
  UIKit's `preferredTransition = .zoom` push. The source resolves once,
  at the push. The route is non-opaque with a
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
- Pages are never snapshotted during the slide: the snapshot option was
  measured and rejected (docs/performance.md, "Navigation snapshots").

- Reduce Motion, read from UIKit (notes private): pushes and pops without a finger cross-fade both pages over 0.5 s (UIView ease-in-out); an edge swipe keeps the slide. Ported (`MorphNavigationTuning.crossFadeDuration`); see states.md.
