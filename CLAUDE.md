# morph - identity-based widget-to-overlay morphs

Spring-driven, interruptible morph animations from an inline widget to an
overlay (dialog, sheet, page, menu), plus a "liquid" skin that fuses
nearby surfaces into one shape, plus a widget layer of controls that
move like iOS 27 Liquid Glass. No Navigator coupling. Physics comes from
the `motor` package and from UIKit's own measured tuning.

Not on pub.dev by design (`publish_to: none`); releases are git tags
following semver, and the API follows the owner's app. Owner-local
context (roadmap, priorities) lives in `CLAUDE.local.md`, untracked.

## Direction (owner directive, 2026-10-02)

morph COPIES iOS 27 Liquid Glass physics. Measured UIKit behaviour is
the spec: every spring, delay, gain and threshold in `lib/` is either
read from UIKit's tuning on the device (PTSettings defaults) or fitted
to frame-by-frame recordings of the real controls, and the tests replay
those recordings. Everything invented or hand-tuned was removed in
0.7.0; the old behaviour lives in git history. Tags that exist:
v0.1.0 .. v0.4.0. 0.5.0 (THE HOLD) and 0.6.0 (measured targets,
keyboard) were never committed on their own - they sit in the same
uncommitted working tree as 0.7.0, so their pre-measured variants
(Tug-lifted context menu, MorphReveal satellites, the measured
showMorphMenu popover) are reachable only if the owner commits/tags
them separately. No A/B labs, no "feel" knobs: when a value has no
measurement behind it, the job is to measure it, not to tune it.
Example scenes may still carry scene values (layout, blend of a
mockup), never physics that pretends to be native.

## Layers

Flutter-style split, two entrypoints:
- `lib/foundation.dart` - the ENGINE export (identity, flights,
  retargeting, targets, routes, the liquid skin, `MorphSpring`).
- `lib/widgets.dart` - the measured widget layer (`lib/src/widgets/`),
  re-exports foundation. BOUNDARY: widgets import foundation and motor,
  the engine NEVER imports widgets. No glass shader lives in the package
  and none is planned: the layer reproduces how the platform's surfaces
  MOVE; how they refract is the app's business through the glass seam
  (below). `lib/native.dart` is gone (it was this layer before it took
  over widgets.dart; every `MorphNative*` name lost its infix,
  `MorphNativeMorphSpec` became `MorphMenuMorphSpec`).

## The measured widget layer (lib/src/widgets/)

Shape of every control: a PURE MOTION CLASS (a function of the touches
it is fed and the time it is advanced to; no widgets, no tickers,
replayable in a plain `test()`), a thin WIDGET HOST (a raw `Listener`
stamps pointer events on the motion clock, calls
`motion.pointerDown/Move/Up/Cancel`, advances per tick, paints), a
`style` with `light`/`dark` tables from the iOS system colors.

Internal machinery (all `@internal`):
- `spring_state.dart` - `MorphSpringState`: a damped spring in CLOSED
  FORM from its last retarget (under-, critically and over-damped
  branches); time is an explicit argument everywhere, `retarget(t,
  target, spring:)` carries (value, velocity), `setState`, `snap`,
  `isAtRest`. This is what makes the motions pure functions of time.
- `timeline.dart` - `MorphTimeline`: delayed reactions (a landing after
  a hang, an opening after a tap) ordered by due time; each action
  receives ITS scheduled time, so a motion advanced in coarse steps
  still applies every action at its own time; equal times keep insert
  order; `now` reads the running action's time.
- `clock.dart` - `MorphClock` mixin: the ticker's elapsed time
  ACCUMULATED across restarts (time asleep does not count; the ticker
  stops when the motion settles). `stamp(event)`: while ticking, the
  latest frame's clock (the granularity UIKit reacts at); while asleep,
  events keep their own timestamp spacing divided by `timeDilation`, and
  the clock never runs backwards. `motionFrameRate` = 60 when the
  display reports 60 Hz, 120 otherwise (read in didChangeDependencies).
  `frames` is the painter's repaint Listenable.
- `flex_integrator.dart` - `MorphFlexIntegrator`: UIKit's
  `_UIVelocityIntegrator` - three one-pole filters (position, velocity,
  rate of change of SPEED |v|), alpha 0.3 PER FRAME whatever the frame
  interval, dt = the frame interval. `MorphSubClock`: a fixed-rate frame
  clock in MOTION time (frames numbered from zero, every boundary
  crossed is reported, max 600 per advance) - the filters step on it at
  `motionFrameRate`, so the deformation is identical on a 60 or 120 Hz
  host, under timeDilation and under coarse test pumps.
- `lens_driver.dart` - `MorphLensDriver`: MorphClock + raw pointer
  events into a `MorphLensMotion`; primary button only.
- `lens_spec.dart` - `MorphLensSpec` small (lift 0.27/0.625, unlift
  0.5/0.7, small optics) / large (0.25/1 both ways), hang 0.22.
- `control_focus.dart` - `MorphControlFocus` (Space/Enter activate,
  arrows step in visual order), `MorphFocusRing` (systemBlue
  0xFF007AFF), `MorphDisabled` (dims to the style's disabledOpacity).

Public pieces:
- `MorphSpring` (engine, spring.dart): UIKit's vocabulary (response =
  undamped period, dampingRatio). k = (2 pi / response)^2, c = 4 pi zeta
  / response, mass 1. `toMotion()` is a motor `SpringMotion` over the
  exact description - NOT `CupertinoMotion(duration, bounce)`, which
  truncates to whole ms and maps zeta > 1 to 1 / (2 - zeta).
- `MorphFlexSpec` (flex_spec.dart) - ports of UIKit's
  `_UIFlexInteractionSpec`: `forSize` (= dynamicWithSize: lift 16 -> 4
  px by height 44..160, scale spring 0.4/0.375 -> 0.36/0.6 and tracking
  spring 0.262/0.625 -> 0.314/0.625 by width 120..) and `loupeForSize`
  (= liquidLensWithSize). Lengths are absolute px. Press = tracking
  spring, release = scale spring (device-confirmed).
- `MorphLensMotion` + `MorphLensTuning.segmented/.tabBar` +
  `MorphLensSlot` - the selection lens (`_UILiquidLensView`). Frame:
  center on the travel spring 0.392/0.863; lift and slot-width changes
  share ONE critically damped 0.25 s spring; lift +24 x +16 px
  (segmented) / +16 x +16 (tab bar). On top, the closed FLEX LOOP: the
  previous frame's VISIBLE center goes through the integrator, the
  filtered acceleration becomes a drift target D = -T f(g af / T) (soft
  tanh knee, gain sets for lifted/unlifted chosen by the internal lifted
  flag; segmented resting gain 2.5e-5 per px of min(W, 100), lifted
  2.626e-5 per px of W + 24) and scale targets sx = 1 - 2D/W, sy per
  control; drift/sx/sy follow on a presentation spring (segmented
  0.442/0.582, tab bar 0.5/0.73). Width changes by -2D and the center
  shifts by +D: the LEADING edge rides the travel spring exactly, only
  the trailing edge lags. Segmented: selects on touch-UP; a press on a
  non-selected segment does nothing until the release; unlift anchored
  0.25 s after the touch-up (`hangFromTouch`; the lift-start anchor
  varies with input latency, the touch-up anchor does not). Press on
  the selected segment lifts in place after `pressDelay` (40 ms) and
  drags: grab offset preserved, follow spring 0.225/1.0 (device), rubber
  band past the end CENTERS (12, 0.55); release picks the slot nearest
  the FINGER. Tab bar: selects on touch-DOWN, stays lifted while held,
  hang 0.215 s + 0.000274 s/px of travel; press delay 50 ms; scrub = the
  finger's travel since the touch times `dragGain` 1.013 on the follow
  spring 0.271/0.803, rubber band (4.55, 0.95); release after
  `releaseDelay` 30 ms, travel carries the scrub's velocity. The whole
  bar swells by `chromeGrowth` 14.6 px around its center while pressed
  (chrome spring 0.356/0.593, lag 20 ms) - the 1.055..1.064 on-screen
  scrub gain is dragGain times that swell. A tap on the already
  selected item lifts in place and lands no earlier than `pressHang`
  0.25 s after the touch (or `releaseDelay` after a longer hold); the
  tab bar lens that seems to drift outward while held is the bar's
  swell.
- `MorphSegmentedControl` (+Style), `MorphTabBar` (+`MorphTabItem`,
  Style): hosts of the lens. Tab bar geometry is measured (bar 62 tall,
  pitch 86 for 2..4 tabs / 68 for 5, lens 94/98/77 wide), widened when
  a label needs it (labels follow text scale up to 1.25; segment labels
  up to 1.4, sized by the wider of the two styles).
- `MorphSmallLens` - the switch knob / slider thumb lens: lift
  0.27/0.625 (peak 1.12; the measured initial velocity is part of the
  fit), min hang 0.22 s from lift start; unlift: the glass progress on
  0.40/1.0, the SIZE decoupled on its own 0.48/0.70 (dips under rest
  size); stretch sx* = 1 + 5.0e-5 a, sy* = 2 - sx* (a = the
  integrator's acceleration), presentation on the smallLoupe spring
  0.444/0.56.
- `MorphSwitchMotion` / `MorphSwitch` (63x28 track, knob 37x24, travel
  22): tap toggles on release, knob travel 0.30/~1.0 carrying velocity,
  track color on its own crit springs (toward on 0.68, toward off 0.40).
  DRAG (device recapture): commit when the knob TARGET reaches the far
  end, uncommit only when it returns to the starting end, color follows
  each change after `colorDelay` 90 ms; release keeps the committed
  state if the drag ever committed, else toggles like a tap; mid-travel
  decides nothing. Dead zone 5 px only for a drag that starts moving
  within `deadZoneWindow` 0.1 s of the touch. Rubber band (12, 0.54).
- `MorphSliderMotion` / `MorphSlider`: only the thumb is a handle (a
  track tap does nothing); pan after `panSlop` 11 pt (slow device drags
  and the simulator agree; fast device starts recognize later - the
  synthesizer's delivery, the simulator shows no such gate); value =
  value0 + finger travel / FULL track width (the thumb trails the
  finger - device divisors 298..302 for 300, confirmed); thumb follows
  the value directly. NO CATCH-UP AT THE ENDS (device slider-ends pass
  2026-10-02, 200/260 pt sliders, 40-80 pt past each end): the value
  hits an end with the finger leading the thumb by ~11 + 37 x (1 -
  value0) pt, the stretch starts only there, the return re-enters the
  range where it left it (no re-basing) - an owner report of "native
  thumbs reach the end under the finger" did not reproduce with
  synthesized touches; a hand-recorded probe drag is the next step if
  it persists. GLIDE after a moving release: release speed held for
  `glideCoast` 0.04 s, then exponential decay `glideDecay` 0.083 s
  (total = 0.123 s x v), stopped at the ends; release speed from
  Flutter's VelocityTracker. Past an end the whole track stretches
  (near edge rubber band 13/0.74, far edge 0.357 of it, height thins
  6 - 0.2936 n) and springs back ~0.63/0.85.
- `MorphStepper`: NO motion - the pressed half gets an instant 8 percent
  black overlay; commit on release; repeat 0.5 s then every 0.5 s, no
  acceleration; sliding moves highlight and repeat; leaving cancels;
  the repeat runs on the motion clock (timeDilation-aware). Minus stays
  left in RTL.
- `MorphGlassButtonMotion` / `MorphGlassButton` (`.glass()` and
  `.prominentGlass()` are identical): ONE DOF, a uniform scale 1 + lift
  / width (lift from `MorphFlexSpec.forSize`: 16 px at height 44 ->
  4 px at 160); press on the tracking spring, release on the scale
  spring (small buttons ring below 1, wide ones barely). Stays lifted
  for the whole touch, even far outside; drag-off LEAN tx = d |d| /
  10000 px plus a stretch along the drag; onPressed fires when the
  finger lifts within 70 px. Glow: overlay 1 - exp(-t / 0.023 s) on
  press, little glow at the touch point to 0.3; on release both fade
  and the little glow scales 1 -> 4 on 0.5/1.0. Device-identical.
- `MorphMenuButton` (+`MorphMenuItem` title/icon/destructive/onSelected,
  `MorphMenuStyle`) on `MorphMenuMotion` / `MorphMenuTuning` /
  `MorphMenuProgress` / `MorphMenuBlob` / `MorphMenuMorphSpec`: a round
  glass button that becomes its own menu. `MorphMenuMorphSpec.standard`
  is the `liquidMorph` tuning read live (speed 0.7 DIVIDES time: eject
  0.5/0.75 -> 0.35/0.75 open, absorb 0.7/0.8 -> 0.49/0.80 close). Two
  blobs drawn as a UNION, no neck: the menu blob G = a W x W square
  scaled to half the button height that stretches to the menu height
  while scaling up, center lerped button -> menu plus a VERTICAL kick;
  the button blob S shrinks to 0.25 scale and travels 0.25 of the way.
  Content top-aligned, crossfades on p (alpha p, blur 4(1 - p)); rows
  do NOT cascade. Opening radius 195.4 -> 32 with a 0.098 s delay
  (capsule until p crosses 1), close radius linear in p. Placement:
  down (menu.top = pressed button top) when the button sits in the upper
  half of the safe area, else up with rows reversed; centered on the
  button when it fits, else edge-aligned with the PRESSED edge; clamped
  into the safe area unioned with the keyboard. Triggers: tap opens on
  release (`tapOpenDelay`), hold opens after 0.22 s and lets the finger
  slide onto a row; item action fires BEFORE the close; the menu is
  hit-testable from its first frame; a tap on the button while it
  closes re-opens on the touch-up, the progress reversing with its
  velocity. KICKS are driven secondary springs (see the exemption under
  Invariants): G's open kick chases `openKickGain` x dp/dt on
  `openKickSpring` 0.2048/0.651; a close STRIKES it away from the button
  (`closeKickImpulse` 1450 px/s after `closeKickDelay`, shrinking
  linearly to nothing at `closeKickReach` of carried kick) and it rings
  on `closeKickSpring`; S's kick chases the closing velocity on
  `sourceKickSpring` (`sourceKickGain`). Amplitudes scale per menu
  height from a measured table (`kickAmplitude`, key = H, not rows).
  It FLIES ON THE ENGINE: the menu is a `MorphFlight` on a
  `MorphTargetSpec.vessel` with the measured progress spring and a zero
  scrim, so overlay choice, Esc/back, focus, events (`onOpen:` hands
  out each flight) and the dissolve of a removed button come from the
  engine; uses an ambient MorphScope or brings its own. ONE CLOCK
  (2026-10-03, device trace): the menu draws from its OWN closed-form
  progress spring in motion time (`MorphMenuProgress.spring` inside the
  widget's progress), the clock the kicks and the radius delay run on,
  and sends the flight the same way; reading `controller.value` instead
  held the first vessel frame at p = 0 and ran p 8..17 ms behind the
  kicks (the controller's ticker starts a frame late at elapsed 0). The
  flight's value now only times the latch and the dissolve. LANDING ON
  THE BUTTON: the engine latch removes the vessel at the close's first
  zero crossing, but UIKit keeps its morph container until the kicks
  ring out (~0.85 s more; the button shape is still 4 px off at p = 0);
  so after the latch the button itself paints both shapes and the look
  from the same motion (button-local coordinates, press transform 1)
  until the motion goes idle, and the motion's close ends only when the
  progress AND both kicks rest. Before, the vessel vanished with the
  button blob mid-kick (a visible snap at the end of every close). The
  vessel builds the rows once (RepaintBoundary, the `child` of its
  per-frame builder) and fades content and the button look through ONE
  layer each (`ImageFilter.compose` of an alpha ColorFilter and the
  blur); the union is one path of two same-direction rounded rects
  (non-zero fill), no Path.combine per frame. The button's own face
  draws its glyph WITHOUT an Opacity/ImageFiltered wrapper (it never
  fades there): an OpacityLayer, even at alpha 255, between the glass of
  the resting buttons broke the gallery liquid painter's BackdropGroup -
  device raster p50 11.8 ms vs 2.3 (the Menu page dropped to 60 Hz); a
  test pins the layer count. Device trace tool:
  example/integration_test/menu_trace_test.dart (profile build,
  `--dart-define=TRACE_SCENE=center|gallery`, `TRACE_RUN=<id>`, writes
  `<app tmp>/menu_trace_<id>.json`: FrameTimings, a timeline, painted G/S
  geometry per frame; launch with devicectl and pull the file -
  `flutter drive` needs Rosetta's iproxy on this Mac).
- `MorphContextMenuRegion` / `MorphSatellite` (THE HOLD, chapter one of
  the Sonatide no-sheets roadmap): a held surface becomes its own context
  menu - hero + satellites above/below. The flight's container is a
  TRANSPARENT VESSEL surface spec (color 0x00000000, elevation 0,
  clipBehavior none) - not `MorphTargetSpec.vessel`: the hero draws its
  own surface and flies as a MorphSharedElement with fade none; the
  vessel's contentAlignment is COMPUTED so the hero slot coincides with
  the flying hero at every spring value - A = heroOffset / (column size
  - hero size) per axis - so the satellites ride the hero as one rigid
  body; they arrive WITH the surface (no unfold). The hero stays put
  unless the column leaves the safe area (or the keyboard edge), then
  the whole column shifts (Telegram's shift). LIFT (`lifts`, replaced
  `pressGrow`): the glass-button model - a uniform scale by
  `MorphFlexSpec.forSize(size).liftScalePoints`, press on the tracking
  spring, release on the scale spring, run on a SingleMotionController.
  Gesture: the State OWNS a TapGestureRecognizer (onTapDown lifts -
  deferred to the touch deadline inside a scrollable, so a scroll never
  flashes it; onSecondaryTapUp opens) and a LongPressGestureRecognizer
  (duration = holdDuration, recreated on change - a RawGestureDetector
  cannot swap a constructor argument without remounting, and a remount
  re-registers the MorphTag mid-frame); fed from a raw Listener with
  deferToChild. The press transform sits ABOVE the tag so the flight
  takes off from the lifted pixels; the natural rect is measured from
  the region's own box above the transform. After the hold wins, the
  press is FROZEN (the tap cancel must not start a second spring under
  a flight re-reading the transformed rect - the hero would shake) and
  released only once takeoff settles (the source is hidden by then) or
  the flight closes. The marker for `MorphContextMenuRegion.open(context)`
  lives INSIDE the tag child so the shuttle's hero copies carry it (a
  "more" glyph in the open menu retargets instead of asserting). THE
  COLUMN IS LIVE (chapter two): the hero slot and every content-sized
  satellite (no height) are measured by MorphContentMeasure and their
  extents spring on the flight's open motion - per-extent
  SingleMotionControllers on the REGION STATE's tickers
  (TickerProviderStateMixin; springs vsync'd by the flight's scope
  tripped the scope's disposed-with-active-ticker assert, because
  flight.closed completes a microtask late), disposed with the flight or
  with the State, whichever comes first. The rect AND the
  contentAlignment are read live: _MenuTarget extends MorphTargetSpec,
  overrides the alignment getter and hands the geometry as `repaint`, so
  frame, alignment and slots move in ONE frame; at value 1 the alignment
  offset vanishes whatever A is, so a settled hero stays put while a
  capsule grows. Slots clip their natural-size content while the extent
  catches up; the hero copy lays out between its launch width and the
  menu width and overflows its slot until it catches up. A child or
  satellite change while open rebuilds the menu (didUpdateWidget ->
  flight.markNeedsBuild, deferred). `replica:` is the source-side copy
  only (snapshotGhost deliberately absent: without a live source marker
  the pair cannot form); `opensOnSecondaryTap` leaves the right click
  to an ancestor. onHold = the threshold (the haptic moment), onOpen
  hands out the flight; the region does NOT abort its flight on dispose
  - a hero deleted from its own menu dissolves via the engine's
  source-lost path. Pinned by morph_context_menu_test. THE GROWTH
  (device, 2026-10-03, fixture context_menu/growth.json): the held
  hero's scale is 1 + measuredHoldGrowth(t) / longest side, t = the
  hold clock (a Ticker started on the pointer down, so the first frame
  after the touch is t = 0; shown only once the tap is down): 0 until
  0.184, 32 pt/s to 8 pt at 0.434, 20 pt/s to 15 pt - absolute points
  on every size (60x40 and 300x200 both +14 by 0.74 s), long axis (an
  80x160 grows in height). The long-press recognizer runs at the COMMIT
  point (min(0.42 s, holdDuration)); past it a release opens the menu
  (UIKit: 0.400 cancels, 0.433 opens, knee 0.434) and a Timer opens it
  at holdDuration. The tap's cancel arrives BEFORE the winner's
  onLongPressStart, so _drop's verdict waits a microtask; pointer up /
  cancel on the raw Listener stops the clock (a swipe taken before the
  touch deadline never sends tap down/cancel). An early release snaps
  to rest (UIKit too, next frame). The open preview in UIKit continues
  to min(15 percent of the long side, 26) - NOT ported: the menu's hero
  stays at its natural size (the column geometry and its tests), so the
  grown hero shrinks back on takeoff. Satellites unfold out of / retract
  into a 0.4 x hero blob at the hero center as a pure function of the
  flight value (_Retract; the device blob is 0.4 of the SHORTER side
  tall, 300x200 -> 83x80, 80x160 -> 32x32 - the uniform 0.4 is exact
  for landscape <= 1.5:1). Gap 16 (device). The engine's own flight
  carries everything else (UIKit's dimming and the preview's
  undershooting return are not modelled).
- BARS (bar_items.dart, bar_motion.dart, toolbar.dart, navigation_bar.dart,
  navigation_motion.dart, navigation_stack.dart, scroll_edge_effect.dart;
  measured 2026-10-03, fixtures ios27{,-device}/bars, tuning dump in
  ios27-device/bars/tuning.txt). `MorphBarButtonGroup` = one glass
  capsule (UIKit groups adjacent bar items; groups 12 apart); metrics
  navigation 44/36/pad 4/gap 16/label 12/icon 7, toolbar 48/38/5/14/11/8
  (min 38), toolbar 28 from sides and screen bottom, nav bar 54 below the
  status bar, 16 side inset on 402 pt (20 on 440). A press lifts the
  whole capsule on the glass-button model (recorded 1 + 16/w). Item
  changes run `MorphBarMotion` = SwiftUI `GlassContainerToolbarPTSettings`
  (frame 0.416/0.75 after 0.05 s, pulse up 0.292/0.5 to min(1.2, 1+16/len)
  after 0.065 s, height back 0.416/0.584 +0.113, width 0.416/0.5 +0.142,
  appearance scale 0.2 + blur 10; delays FITTED from the call, births on
  the neighbour's facing edge in the layout where they exist, a survivor
  next to a newborn waits 0.1 s). The SAME transition drives nav bar
  buttons on push/pop. Inline title: crit 0.45 in / 0.7 out, +15 pt, blur
  4; edge effect alpha crit 0.35; programmatic offsets switch at once
  (UIKit only animates with a finger). Scroll edge effect is NOT a
  progressive blur: uniform variableBlur 1.5 (soft) / 2 (hard) with a full
  mask, a "replay" of the background at 0.5/0.6 (soft: gradient from 0.34
  of the band, band = bar + 40), hard = thinFilm (sat 1.25, +0.03, 1 px
  hairline 10 percent), automatic under a nav bar = hard; nothing under a
  floating toolbar. Pages: push spring 0.3 crit with v0 8.3 widths/s
  (fitted, the curve starts at full speed), parallax 0.3, edge swipe 1:1,
  release on interactiveSpring 0.3/0.85 (device free fit 0.294-0.300 /
  0.85). The commit rule is the DEVICE's (2026-10-03 recapture): a page
  released still pops from 0.3 of the width out (0.27 returns, 0.32
  pops), a flick past 1.06 widths/s decides alone either way (+1.02
  returns 3/3, +1.10 pops; -1.02 still pops at 0.51 W, -1.28 returns;
  +1.25 returned 3/3 - a synthesizer artifact or an unmodelled rule, not
  reproduced); a returning page carries 2.9x the release speed outward
  (fits 2.7-3.1), a popping one starts from rest (~0.03 s after the
  lift). Large title: device 10 pt slop, 25 pt scrolled snaps back, 30
  under (threshold half the title, 26). `MorphNavigationStack` keeps ONE
  bar + toolbar over its Navigator (the Navigator widget is built once:
  rebuilding it calls changedExternalState on every route and the pages'
  config publishing looped); scaffolds publish a signature-compared
  `MorphNavigationConfig`. A pushed screen publishes one frame after
  the push: the stack keeps showing the screen below until it does (or
  its first frame passes), otherwise the bar flashed empty for a frame,
  its capsules died and were reborn and the toolbar remounted - the
  push did not morph. The Navigator sits under a NavigatorPopHandler:
  while the stack can pop, the ENCLOSING route is doNotPop, which turns
  off its Cupertino edge swipe / predictive back (popGestureEnabled) and
  routes system back and outer maybePop into the stack (the gallery's
  MaterialPageRoute used to win the edge swipe - its edge Listener sits
  above the page in hit-test order, so its recognizer joins the arena
  first). Groups without an id are keyed by place counted from the
  bar's EDGE (the device morphs the outermost trailing capsule into the
  outermost one), and the stack's back button has no id of its own, so
  it morphs out of the leading capsule. EDGE-SWIPE DRIFT
  (`MorphNavigationBarDrift`, `MorphBarMotion.setDrift`): while the
  finger drags a page, every capsule the destination bar also has (same
  id) is drawn `barDrift` 0.5 x page progress of the way toward its
  destination rect, items riding the capsule center - a pure function of
  the page, so a cancel leans back with the returning page; on commit
  the next setLayout snaps the springs onto the leaning rects and the
  item transition starts from there (device: the drift freezes at the
  lift, the transition follows). Refit 2026-10-03 on four device swipes
  (pop-edge-drift-*: 0.49 at no lag, 0.50 at 1-2 ticks, 0.16-0.27 pt
  rms); the inner capsule with no counterpart stays put on the device
  too. The stack learns of the swipe from MorphNavigationRoute's edge
  gesture (start / settled), not from userGestureInProgress. NOT
  reproduced: the back button long-press menu, the large title's
  tall-bar inset bookkeeping (ours scrolls as content), a drift of the
  toolbar (not measured).
- SHEETS (sheet.dart, sheet_motion.dart; 2026-10-03, iOS 27 simulator,
  iPhone 16 Pro geometry, XCUITest touches): `presentMorphSheet` pushes a
  `MorphSheetRoute` (a PopupRoute: transitionDuration zero, the reverse
  controller is stopped in didPop and set to 0 when the motion's
  dismissal rests, which finalizes the route; buildModalBarrier is an
  IgnorePointer, so undimmed detents leave the page live and the
  dimming/tap-to-dismiss is drawn by the sheet itself). Two DOFs on
  `MorphSheetTuning.spring` (0.3441/1.0 = UIKit's CASpringAnimation
  333.3/36.5): the unscaled HEIGHT (detent value + bottom safe area)
  and the TRANSLATION (present/dismiss). Floating = the full-width sheet
  scaled by 1 - 16/W (+ a shift keeping 8 pt off the bottom), docking =
  one transform lerped by the docking progress, which UIKit defines PER
  TRANSITION (height fraction between the transition's start and the
  large detent, or back to the floating detent it heads to; a move
  between two floating detents stays floating); during a drag it is the
  fraction above the largest floating detent. Measured release rules:
  projection 0.143 s, settle 25 ms after the lift with 2x the finger's
  velocity, dismissal below the smallest detent when the projected slide
  passes half the visible height or v > 1000 pt/s (flick dismissal on
  0.352/0.79 with 0.6x velocity), grabber tap cycles detents after 50
  ms, press swell 1.00854 on 0.2835/0.70 after 28 ms. Not reproduced:
  the present's 8 pt horizontal drift (a first-frame artifact), the one
  frame per docking that reads the sheet at y 0, the ~2 percent vertical
  stretch of a sheet pulled below its smallest detent, the zoom
  transition (`_UIZoomTransitionSpec` zoomIn 0.34/1.0, zoomOut 0.34/0.92
  read, geometry not captured), keyboard avoidance (layout only: the
  maximum shrinks by the keyboard). Replays: sheet_test (programmatic,
  0.8 - 2.1 pt rms incl. present jank), sheet_drag_test (16 simulator +
  26 device drags/flicks, outcomes exact, tolerances in the file; the
  device rows replay best UNSHIFTED, the simulator's +1/60). Every drag
  rule above held on the device unchanged (2026-10-03 recapture: two
  flicks sit on the boundary, fd-1000 and lfd-800, left out).
- ALERTS (alert.dart, alert_motion.dart; 2026-10-03, iOS 27 simulator
  iPhone 18 Pro Max 440 x 956, programmatic presents + XCUITest touches,
  springs confirmed on the iPhone 16 Pro by devicectl-launched scenes,
  fixtures ios27{,-device}/alert): `showMorphAlert` /
  `showMorphActionSheet` push a `MorphAlertRoute` (the sheet's
  PopupRoute pattern: zero transition, the motion finalizes the pop).
  Alert = `MorphAlertMotion`, two DOFs on ONE spring (CASpringAnimation
  522.35/45.71 = 0.2749/1.0): progress (alpha + the 0.2 black dimming,
  both ways) and scale (snapped to 1.199 at present - device; 1.196 on
  the simulator - heads to 1; a dismissal only fades). Layout read from
  the view tree: 320 wide, radius 34, centered in the safe area +
  keyboard, text inset 30, header top 22, title 17 semibold (alone: 17
  regular), message 15 secondaryLabel, 7.33 between, 4.33 / 3.67 below,
  buttons 48 capsules (tertiarySystemFill) 16 inset, 8 apart; exactly
  two actions sit in a row with cancel FIRST, otherwise a column with
  cancel LAST; preferred = accent fill + white semibold; a text field is
  a 290 x 48 capsule. A touch lifts the WHOLE platter with
  `MorphGlassButtonMotion` at the alert's size (forSize: lift 4 ->
  1.0125, device-identical springs); a dragging finger pulls it with
  `pull` 0.25 and `stretch` 0.6 of a button's (`MorphAlertTuning.
  platterPull` / `platterStretch`, device: 0.4 pt of lean for 120 pt of
  drag, 0.06 pt rms) and the pressed button's fill drops
  to 0.4 of its alpha; the finger may slide between buttons; handlers
  run after the dismissal (UIKit: ~0.45 s after the touch-up). Action
  sheet with a source = glass popover (`MorphPopoverMotion`: one
  progress, scale 0.01 -> 1 about the arrow tip + alpha, present
  331.9/29.15 = 0.345/0.80, dismiss 283.97/28.65 = 0.373/0.85), content
  240 wide, arrow 28 x 13, radius 34, cancel omitted and run at once by
  a tap outside; the popover does NOT lift under a touch (device).
  `morphPlacePopover`: candidates above, below, trailing,
  leading; centered on the source across, slid into 10 pt margins and
  the safe area, toward the source by at most the arrow length (UIKit
  overlaps a source by 3 pt rather than switching sides); a candidate
  whose slide brings the arrow within 48 pt (radius + half arrow) of a
  corner is skipped; least total slide wins (15/15 captured placements).
  Without a source an iPhone action sheet IS an alert (cancel last). NOT
  reproduced: the source button's tint dimming, the 0.7 s first popover
  present latency on the simulator, the arrow in the glass painter (the
  arrow is always drawn flat).
- SEARCH (search_field.dart, search_motion.dart, search_tab_bar.dart;
  iOS 27 simulator + the toolbar transition on the iPhone 16 Pro,
  fixtures ios27{,-device}/search): `MorphSearchField` = 48 pt capsule,
  magnifier at 12, text at 40.67 (17 medium, placeholder
  secondaryLabel), clear button 20 pt 13.33 from the end; a touch lifts
  it on the glass-button model 0.05 s after contact.
  `MorphSearchToolbar` (bottom placement, what UIKit uses on iPhone):
  rest = items in 48 circles + flexible field, 28 from sides/bottom, 12
  apart; focused = field + 48 close button, 8 from the sides, 10 above
  the keyboard. ONE progress on SwiftUI
  `GlassContainerSearchTransitionPTSettings` 0.25 / 0.9 (free fits
  0.238-0.246 / 0.92-0.94, sim and device), starting 0.067 s after the
  change (device cancel; 0.077-0.086 sim; a close tap starts it 0.080 s
  after the lift on the device). A FOCUS that brings up the keyboard
  waits for it: the device field starts 0.015 s after the keyboard's
  first frame (`keyboardLag`; 0.17-0.19 s after the tap, 0.28 for the
  launch's first keyboard), so the toolbar holds the focus until
  viewInsets turn positive, with `keyboardWaitLimit` 0.3 s as a guard
  (no keyboard, tests): the field rect lerps; arriving items
  (close) scale 1.2 -> 1 with alpha = progress and blur, moving from
  their slot in the OLD configuration; leaving items freeze where they
  stood (the close button fades in place while the keyboard drops);
  returning items come from the focused layout WITHOUT keyboard (UIKit's
  virtual slots, y = H - 10 - 24). Vertical: the field lerps toward 10
  above the LIVE viewInsets (UIKit aims at the final keyboard frame;
  Flutter gets the platform's per-frame inset). Not reproduced: UIKit
  moves the close button two frames behind the field (alpha/scale on
  time), the large-title nav bar collapsing during search (app's
  business). `MorphSearchTabBar`: rest = `MorphTabBar` 21 from
  side/bottom + a 62 pt search circle; searching = 48 tab circle
  (selected glyph) at 28 + field 88..W-28; focused = field 8..W-64 +
  close 8 apart, 8 above the keyboard (tab circle fades; the keyboard
  covers it in UIKit). The morph between is a rect lerp of the two glass
  bodies on 0.276/0.80, FITTED to video frames (no tuning value; UIKit's
  view frames jump to the endpoints, the glass morph lives in SwiftUI -
  still true on the device); the field then focuses itself
  (`automaticallyActivatesSearch`) and, once the keyboard rises (+0.07
  s, `tabKeyboardLag`), rises above it on its OWN `tabFocusSpring` 0.3 /
  1.0 (device 0.19 pt rms over 308 pt; 0.25/0.9 leaves 12) and falls back
  on it 0.04 s after the close tap (`tabUnfocusDelay`).
- DATE PICKER (date_picker.dart, date_picker_motion.dart; iOS 27
  simulator via XCUITest, fixtures ios27/date_picker): compact labels
  115 x 34.33 (date) / 70 x 36 (time) capsules, tertiarySystemFill,
  padding 12, 4 apart; the text dims toward ~0.5 under a touch on a 0.47
  s CABasicAnimation (0.25, 0.1, 0.25, 1) and turns accent while open.
  The overlay (`_UIDatePickerOverlayPlatterView`, radius 28, 320 x 332
  calendar for five weeks, 232 x 204 wheels) rides ONE progress: scale
  0.2 -> 1 about the anchor, alpha, box height 50 -> full (content
  revealed from the anchored edge); open 0.32/0.80, close 0.348/0.86
  (fitted, no CASpringAnimation to read). `morphPlaceDatePicker`: top 6
  below the label's center (bottom 6 above it when no room below), the
  trailing edge 6 before the center then clamped to 20 pt margins; the
  anchor is the label's center x clamped onto the overlay (5/5
  placements). Picking a day applies at once and keeps the overlay open;
  a tap outside (on touch-up) or Escape closes. Months page on a 0.3 s
  sine ease (2 px rms; UIScrollView's exact curve differs). Simplified:
  the calendar is drawn by morph (header, weekday initials, day grid,
  today tint, selected disc - geometry from the view tree), the time
  wheels are ListWheelScrollViews.
- `MorphPageControl` (page_control.dart): dots 9.67/7.67 pt on a 17.67
  pitch, tap halves step on the lift, platter after 0.193 s of touch on
  a critically damped 0.100 s spring, out 0.032 s after the lift on
  0.100 (device 120 Hz rows; the 60 Hz simulator read 0.2 / 0.02 and
  replays within a frame), scrub = nearest dot +-1.5 pt; progress capsule 27.33 pt. A long scrub
  far past the dots steps irregularly in UIKit (pc-scrub-far) - not
  modelled. `MorphProgressView` (progress.dart): linear, |delta| seconds,
  >= 0.2 s when the fill shows/hides, additive. `MorphActivityIndicator`
  (activity_indicator.dart): 8 spokes, 16 frames / 0.8 s.
- Context menu calibration (2026-10-03, device-confirmed the same
  morning: 0.768-0.797 s, previews 138 x 92 and 326 x 217.3): UIKit
  opens at 0.78 s (default
  `holdDuration`), preview lift min(15 %, 26 pt); its preview ramps
  linearly from 0.2 s and pops at the commit, the menu sits 16 pt from
  the preview and retracts INTO the preview on close (a 48 x 32 blob) -
  the region still flies on the engine and keeps its 8 pt gap.
- The GLASS SEAM (glass.dart): `MorphGlass(painter:)` installs a
  `MorphGlassPainter`; every control below builds its glass surfaces
  (`MorphGlassKind`: track, lens, knob, thumb, button, bar, menu)
  every frame behind its content. Multi-surface controls go through
  `buildLayer(surfaces, content:)` (`MorphGlassLayer`, rebuilt on the
  clock's `frames`; the segmented labels and the tab row ride in as
  `content`, the menu hands button + platter in one call); single
  surfaces (stepper, glass button) call `buildSurface`, placed at
  `MorphGlassSurface.bounds`. The default `buildLayer` positions
  `buildSurface` results and the content over them, so a painter that
  only overrides `buildSurface` keeps working. The
  surface carries the deformed shape, the flat color as a tint,
  brightness, lift, and `MorphGlassOptics` (UIKit's refraction values,
  `small`/`large`; `displacementAt`/`blurRadiusAt` interpolate by lift).
  Without a painter: flat fills. The package stays shader-free; the
  gallery installs `LiquidGlassRendererPainter`
  (example/lib/gallery/liquid_glass_painter.dart) at its root over the
  VENDORED whynotmake-it renderer (example/third_party/
  liquid_glass_renderer, Apache-2.0, upstream commit in its VENDORED
  file, excluded from analysis): body surfaces in one layer (a blend
  group when several - the menu fuses with its button) reading the
  nearest BackdropGroup's shared copy (root group in GalleryApp, own
  groups for the glass page's scene and card; bars/menus take their own
  copy); a resting lens/knob/thumb is an opaque platter, lifted it is
  glass in its own layer above body + content, and a lens shows the
  content once more inside itself at `1 + 0.16 * lift`, cut out of the
  plane below (the renderer never enlarges its backdrop). Device
  verdicts (iPhone 16 Pro, 2026-10-03): LiquidGlassCapture drops whole
  controls on iOS (renders on macOS) - not used; FROST is the dear part
  (~1 ms raster per frosted surface per frame, Controls page 13-15 ms
  vs 2.6 ms), so only bars, menus and lifted lenses frost unless the
  "Frost controls" setting is on. The web build cannot compile the
  renderer's .frag shaders: pages.yml `pub remove`s it before building
  the tour. The session settings
  (GalleryGlassSettings/GalleryGlassScope, glass_settings.dart) live in
  GalleryApp's State; the Glass renderer page edits them.
- THEMING: explicit `style` > `MorphWidgetsTheme` (a ThemeExtension, one
  style per control; a ThemeData is one brightness, put a dark style in
  the dark theme) > the style class's `light`/`dark` table for
  `morphBrightnessOf` (Theme, else MediaQuery platform brightness, else
  light). An explicit color parameter still beats the style.
- A11Y / INPUT: each segment is a selectable button in a mutually
  exclusive group; the tab bar carries tab bar / tab roles; switch and
  slider take `semanticLabel`; slider adjust actions and arrows move by
  `keyboardStep`; the stepper is two buttons carrying the value. Every
  control is focusable with a systemBlue ring; Space/Enter toggle,
  press, increment. RTL mirrors segmented, tab bar, switch, slider.
  Disabled = null `onChanged` (BREAKING in 0.7.0 for segmented and tab
  bar) dims to `disabledOpacity` (0.5 switch/slider, 0.35 others - NOT
  measured on a device yet). REDUCED MOTION (`reducedMotion` on
  MorphLensMotion, MorphSmallLens, MorphGlassButtonMotion; set from
  `MediaQuery.disableAnimations`): lens and knob travel, the button
  glows, nothing lifts, deforms, leans or swells - an approximation
  until Reduce Motion is recorded; off by default so replays are
  unchanged.

## Architecture (lib/src/)

- `spring.dart` - `MorphSpring` (see above); in the engine since 0.7.0,
  `widgets.dart` re-exports it.
- `motion.dart` - `MorphMotion`: a pair of `Motion`s from **motor**
  (openMotion/closeMotion, getters). `MorphMotion.springs(open:,
  close:)` builds one from MorphSprings and exposes them as
  `openSpring`/`closeSpring`; the public constructor takes ANY Motions
  (Material tokens, curves, custom springs). Built-ins (`values`):
  `liquid` - THE DEFAULT everywhere a motion resolves (controller,
  showMorph*, MorphTheme unset): UIKit's liquid morph progress spring,
  open 0.35/0.75 (overshoots ~3 percent, p peaks 1.028), close
  0.49/0.80 (undershoots ~1.5 percent - the handoff latch's zero
  crossing); `glacial` = liquid with every response x5, a magnifier for
  the eye, not a design choice; `instant` = 281 ms critically damped
  both ways (reduced motion and tests - NOT a cut). Value equality
  (MorphTheme equality and the controller's setter compare by ==).
- `controller.dart` - `MorphController`: one scalar ticker,
  `motion.createSimulation` as the single physics seam; handoff latch on
  the first zero crossing; scrub API (`beginScrub`/`updateScrub`) for
  custom gesture driving; `animation` adapts it to `Animation<double>`.
  A close from rest starts still (no velocity hint any more).
- `frame.dart` - `computeMorphFrame`: ALL visual properties of a flight
  frame derived from one spring value. Corner radius is derived from live
  geometry (concentric-corners model), not lerped as a shape.
  `morphFlightGeometry` + `morphConcentricRadius` are the one geometry.
- `scope.dart` - `MorphScope` (tag/flight registry + TickerProvider) and
  `MorphTag` (identity: rect/shape/surfaceColor/elevation/replica/spec).
  No landing transform on the tag any more: the landing IS the close
  spring's own undershoot (UIKit adds nothing on top).
- `flight.dart` - `MorphFlight` + the shuttle (OverlayEntry): retarget
  instead of new flights, live per-frame tracking of source and target,
  snapshot ghost (opt-in `snapshotGhost`; the capture waits for the
  frame's paint and the tag hides only AFTER the shot - a launch from
  the button's own tap happens mid-ripple with a dirty boundary, where
  toImage asserts, and a hidden tag never repaints so the dirt would be
  permanent; the shuttle's replica covers the extra visible frames),
  `MorphFlightScope` for content. The replica RIDES the container
  geometry (uniform scale by the width ratio; exactly 1 at the home end,
  so the latch swap stays pixel-identical) and renders from the source
  spec with elevation ZEROED: a natural-size copy floating inside a
  grown container, or one casting its own shadow, reads as a second
  surface - "one mass, one shadow" holds INSIDE the shuttle too (pinned
  by morph_shuttle_render_test). Semantic getters `isAirborne` /
  `isLanding` (the span between the latch and the final rest).
  EVENTS: `MorphFlight.events` streams `MorphFlightEvent` (launched,
  settled, closing, latched, landed, aborted) - the haptics seam.
  Moments are RECORDED synchronously into a queue and handed to the
  broadcast stream in a microtask: a broadcast stream drops what nobody
  hears yet, and showMorph announces the launch before it returns, so
  the deferral is what lets a listener attached in the same synchronous
  run (before any await) hear it; the queue keeps the order, and a
  handler may close the flight from inside itself without re-entering a
  firing controller. launched is queued BEFORE controller.open() so an
  instant profile's synchronous settle can never precede it; a re-open
  of an already open flight is not a launch. The stream closes after
  landed/aborted (pinned by morph_flight_events_test). SOURCE LOST:
  refreshSourceRect sees `!tag.mounted` (mounted, not isTreeActive - a
  deactivate/activate reparent is transient and must not flip it; the
  loss is therefore seen one frame after the dropping build) and freezes
  the rect where it last stood; open content stays usable; a close
  DISSOLVES - the container fades over the first half of its remaining
  travel, opacity = clamp((progress / dissolveStart - 0.5) * 2), a pure
  function of the spring value from the moment the dissolve begins
  (continuous at 1) - instead of landing on whatever took the row's
  place; a re-open lifts it. Pinned by morph_source_lost_test. VESSEL
  flights (see target.dart) skip surface, shadow, ghost and crossfade
  and mount the content over the whole overlay.
- `show.dart` / `anchor.dart` - imperative `showMorph*` (escape hatch)
  and declarative `MorphAnchor(isOpen, onDismiss)` - the morph as a
  function of state; identity is the State itself unless an explicit
  `tagId` is given. Overlay flights render in the NEAREST enclosing
  Overlay: the flight belongs to the world its scope lives in, so a
  nested navigator (a tab, an embedded device mockup) keeps its flights
  inside itself. `overlay:` (showMorph*/MorphAnchor/MorphMenuButton/
  MorphContextMenuRegion) CHOOSES the shuttle's home for chrome layered
  over nested navigators (Sonatide: tabs are nested navigators under a
  floating bar; sheets sit on the shell's own navigator, which is
  neither the nearest nor MaterialApp's root - hence an explicit
  OverlayState, not a useRootOverlay flag). Coordinates stay honest by
  construction: the tag rect is captured against the flight's overlay
  box, the target's rectFor gets that overlay's size, and
  `morphAnchorRect(context, overlay:)` measures anchors in the same
  space (the overlay must be an ancestor of the context, or
  getTransformTo asserts). Pinned by morph_overlay_choice_test.
- `target.dart` - `MorphTargetSpec` (rectFor, surface, contentAlignment,
  clipBehavior) and the anchor helpers. Factories: dialog, sheet,
  fullscreen, popover (anchored, flips above when out of room),
  `measured`, `vessel`. `clipBehavior` defaults to antiAlias; `Clip.none`
  is for a transparent surface whose content draws its own surfaces
  (with the clip on, satellites would wipe in along the growing edge);
  the route page's Material honors it too. VESSEL (0.7.0,
  `MorphTargetSpec.vessel(rectFor:, repaint:)`): the content draws the
  WHOLE morph itself - laid out over the entire overlay in overlay
  coordinates, full opacity from the first frame, no surface, shadow,
  source ghost or crossfade; it takes pointers while the flight is open
  or opening, and so does its scrim (a CLOSING vessel lets touches
  through, so its source can re-open it). Everything else a flight
  provides still applies (overlay choice, modal barrier, pop layering,
  focus trap, events, source-lost dissolve). MorphMenuButton is its
  consumer. MEASURED TARGETS (chapter two):
  `MorphTargetSpec.measured(constraintsFor:, placeFor:)` and
  `fitContent:` on sheet/dialog/popover (and showMorphDialog/Sheet). The
  content lays out under constraintsFor inside `MorphContentMeasure`
  (measure.dart, @internal: an aligning shifted box that reports the
  child's laid-out size in a POST-FRAME callback - a report retargets
  springs and rebuilds owners, neither legal mid-layout, so one frame of
  lag by construction; the shuttle uses it for fixed targets too, with
  tight constraints and no reporting, so the chain is ONE). The flight's
  `_ContentSizeChannel` seeds on the first report and springs per axis
  on the flight's openMotion afterwards - an endpoint filter joining
  frameTicks, not a second clock on any property - and
  `resolveRect(overlay, padding, contentSize)` is the ONE rect
  resolution both stacks call. STAGED FIRST FRAME: a measured target's
  shuttle is laid out but invisible (Opacity 0 + IgnorePointer +
  ExcludeSemantics, wrappers present on every frame so the tree never
  remounts) and the tag stays visible until the first measurement lands
  (`_hideTagWhenStaged`, one door shared with the snapshot-ghost path);
  the hide runs AFTER controller.open() because hasHandedOff reads true
  while the controller is idle. `contentAlignment` is a getter over a
  private field, overridable, and `repaint` is a Listenable merged into
  frameTicks (the CustomPainter idiom). KEYBOARD: the padding every
  rectFor receives is `morphTargetPaddingOf` - the safe area unioned
  edge by edge with viewInsets - so every factory avoids the keyboard
  by construction (a sheet docks above it, a dialog centers in the room
  left, the context menu column shifts, a menu places itself clear of
  it) while fullscreen ignores padding and keeps its insets. The
  content's MediaQuery carries `morphContentViewInsets`: only the part
  of each inset the container still overlaps (a Scaffold inside must
  not avoid twice). iOS animates viewInsets per frame and the target
  follows per frame; Android jumps, like every Flutter widget. Pinned
  by morph_measured_target_test and morph_keyboard_test.
- `route.dart` - `showMorphRoute`/`MorphPageRoute`: the destination as
  a REAL Navigator route with the flight as its transition. The route
  pushes into the NEAREST enclosing navigator (`useRootNavigator:` opts
  into the root). The route is pushed immediately (back button,
  predictive machinery and further pushes behave like on any page; the
  flight overlay is passed `navigator.overlay` explicitly - the
  navigator's context sits ABOVE its overlay); the page stays empty
  while the shuttle plays. At settle the SECOND latch fires:
  `MorphFlight.routeOwnsContent` flips, both sides rebuild in the same
  frame, and the content subtree - carrying the shared `routeContentKey`
  GlobalKey - REPARENTS into the route page with its live state (the one
  sanctioned GlobalKey move; the wrapper chain under the key must stay
  IDENTICAL on both sides: KeyedSubtree > MorphFlightScope >
  MorphSurfaceSpecScope > SharedSideScope > Builder). A pop hands the
  content back the same way and plays the ordinary close; a close
  launched from the flight side retires the route automatically via the
  route's controller listener. Scrim swaps between owners at full
  opacity on both latches (the route's modal barrier stays transparent
  and only contributes dismiss taps and semantics); pre-latch scrim taps
  route through the Navigator (onDismissRequested -> pop) so the route
  lifecycle stays the single source of truth. The settled page applies
  the DISPLACEMENT CHANNEL with the same rigid-body shift, recede and
  scrim math as the shuttle, driven by the same frameTicks stream, and
  resolves its rect through the same `resolveRect` /
  `morphTargetPaddingOf` / `morphContentViewInsets`, measuring a
  measured target inside its Material. PREDICTIVE BACK: the route
  reimplements the PredictiveBackRoute hooks on the flight (the default
  TransitionRoute impl drives the route's zero-duration shell
  controller) - the gesture hands the content back to the shuttle and
  scrubs the value shallowly (depth 0.18); cancel springs back and the
  second latch re-hands the content, commit pops and the close plays
  from the scrubbed value. A private binding observer bridges the system
  events to the route hooks, because the material page-transitions
  detector never wraps a PopupRoute.
- `gesture.dart` - primitives for building your own drag-to-dismiss
  (rubber band c=0.55, velocity projection `morphProjectValue`,
  `morphDragRecede`, `morphDragArm`, `morphDragScrimFactor`,
  `morphDragScale`, commit thresholds `morphDragCommitDistance` /
  `morphDragCommitVelocity`). A prebuilt drag widget is intentionally
  NOT provided - but the MECHANICS live on the flight as the
  DISPLACEMENT CHANNEL: `MorphFlight.beginDrag`/`dragBy`/`endDrag`.
  While the finger is down the WHOLE container (surface, shadow,
  content, shared elements) follows it 1:1 as one rigid body - the
  morph value does not move, so no fade-through midstates can show; the
  scrim thins and the card recedes slightly, both pure functions of the
  displacement. Releasing always springs the offset home on its own
  always-to-zero simulations (per-axis closeMotion with carried
  velocity); past the commit heuristic (projected distance or speed,
  overridable via `endDrag(commit:)`) the ordinary close flight plays
  SIMULTANEOUSLY - "the card flies home out of the hand". The offset is
  a genuine second degree of freedom (at value 1 it must equal both the
  release offset and zero at settle); the shuttle applies
  `appliedDragOffset` = (raw offset + arm lean) x progress, so it
  vanishes exactly at the handoff latch, and the liquid mirror blob
  rides the same offset. COMMIT FEEDBACK: past the commit distance the
  card "arms" (`morphDragArm`, a smoothstep over 60 px - pure and
  reversible): extra recede, extra scrim thinning, a 12 px drift toward
  the source; `MorphFlight.isDragArmed` exposes the threshold for
  haptics. The core never attaches a gesture. Value-scrubbing the morph
  itself remains the controller-level expert path (beginScrub/
  updateScrub) - it exposes midstates when frozen under a finger.
- `liquid_field.dart` / `skin.dart` - liquid fusion: CPU SDF (rounded
  box / capsule) + smooth-min + marching squares + Chaikin smoothing
  producing a single vector `Path` skin behind live content
  (`MorphSkin`/`MorphPiece`/`MorphLink`/`MorphStroke`). THE MERGE LAW is
  Apple's (measured on an iPhone 16 Pro, UIKit `UIGlassContainerEffect`
  and SwiftUI `GlassEffectContainer` agree): the mix-form polynomial smin
  evaluated with a PER-SAMPLE width k' = k (1 - dot(na, nb)) / 2 =
  k sin^2(theta/2) (`liquidMergeWidth`), na/nb the unit normals of the
  two operands; facing surfaces blend over the full k, edges running
  side by side not at all, so aligned tops/bottoms of fused pieces stay
  STRAIGHT. The fold carries the accumulated unit gradient and mixes
  normals by the smin's own weight (exact for two masses; for 3+ the
  natural fold, unmeasured). `blend` (k) == the glass container spacing,
  1:1 in logical px: facing surfaces lean toward each other below a gap
  of blend and touch at blend / 2; blend depth at the middle of a FACING
  gap is still ~k/4, zero along aligned edges. `cell` is a distance too.
  Field bounds are padded by k (otherwise the neck would clip); contour
  recomputation is cached by an input signature. No shaders, no
  blur+threshold - no halos; "one mass - one shadow" holds by
  construction. Replayed against device silhouettes
  (liquid_apple_merge_test, fixtures ios27-device/merge: capsule and
  circle pairs, spacing 10..80, gaps 40..-5): 0.17..0.32 pt rms, the
  screenshots' noise floor; compare at the field's 0.40 level (Apple's
  tint fill sits ~0.4 pt outside the SDF zero).
- **Tracing hot path is optimized and guarded**: sampling runs through
  an allocation-free flat evaluator (`_FieldSampler`: typed arrays, no
  Offset objects or virtual dispatch per vertex; accumulated distance
  AND normal live in fields; a mass whose distance differs by >= k
  merges by plain min and skips the dot product), and shapes are split
  into connectivity clusters (bounds gap <= k, transitive), each traced
  on its own tight grid - EXACT, not approximate: k' <= k, so beyond a
  gap of k the smin equals plain min identically, distance AND carried
  normal (proof sketch at `_clusterShapes`). The per-cluster grid cap
  logs loudly in debug instead of failing silently. Correctness is
  pinned by `test/liquid_regression_test.dart` (field-sign/contour
  consistency probes plus near-range bulge and far-range
  no-deformation checks) and the Apple merge replay - any pipeline
  change must keep both green. Microbenchmarks: `flutter test
  benchmark/liquid_benchmark_test.dart` (benchmark_harness; JIT numbers,
  use for relative before/after only).
- **Render-object implementation**: `MorphSkin` is a thin stateless
  facade over `RenderMorphSkin`. Spring ticks call markNeedsPaint ONLY -
  no widget rebuild and no relayout in an animation frame - and
  app-driven geometry has the same citizenship through the piece
  geometry channel; the group is its own repaint boundary. A piece's
  content transform is its `MorphPieceChannel` ALONE (the landing squash
  is gone), with transform-aware hit testing; layout runs solely when
  piece geometry changes from the outside. Flight subscriptions live in
  attach/detach. Optional Gradient fill (MorphSkin.gradient) shaded
  across the group bounds; `MorphStroke` draws the inner contour of the
  same living path (paint-only, after tints). Safety nets: geometry
  snapshots (test/liquid_geometry_golden_test.dart, regenerate via
  test/golden_dump_helper.dart; they changed BY DESIGN with the 0.7.0
  merge law) and seeded fuzz (test/liquid_fuzz_test.dart); the frame
  benchmark (benchmark/group_frame_benchmark_test.dart) measures the
  full build+layout+paint cost per pumped frame during a glacial flight,
  plus the orbit scene both ways (rebuild-driven vs channel-driven).
- **Piece geometry channel**: `MorphPieceChannel` (skin.dart, on
  `MorphPiece.channel`) - "frameTicks for pieces". The payload is
  (offset, scaleX, scaleY) over the base rect, applied about its
  center; no rotation by construction (SDF boxes are axis-aligned).
  Scale ZERO is legal and deflates the mass to nothing; a degenerate
  content transform paints nothing and hit testing skips it.
  BIRTHS: `MorphPieceChannel.birthScale` 0.2 and `birthSpring`
  `MorphSpring(0.492, 0.711)` - how a Liquid Glass shape is born (at a
  fifth of its size at its final center) and leaves (shrinks back,
  parked inside the survivor), fitted to SwiftUI's `glassEffectID`
  per-frame rects (peak ~3 percent over at 0.38 s, settled by 0.7 s).
  A write is markNeedsPaint ONLY: no rebuild, no relayout, no
  _syncFlightSubscriptions, no allocation (channel identity is part of
  piece geometry equality, so a swap resyncs; subscriptions live in
  attach/detach with one shared handler). EFFECTIVE rects (base +
  channel) feed the whole pipeline: resolve, trace signature (a stale
  contour is impossible), launch fellowship (captured at flight
  subscription from that moment's effective rects), bridge endpoints,
  blob fallback. Content rides as ONE RIGID BODY on a child-local paint
  transform; layout stays at the base rect - content paint-scales, text
  does not rewrap: the channel's contract. applyPaintTransform mirrors
  the paint transform, so localToGlobal / MorphTag measurement / anchor
  measurement see the displaced rect - without that override a flight
  would launch from the base position while the piece visibly stands
  elsewhere. Transient motion commits into the base rect at rest (the
  sandbox pattern: dragBy writes the channel, endDrag commits and resets
  - one rebuild per gesture). Consumers: the sandbox drag, the stress
  orbits, the dock selection blob, the toolbar merge, the chips births.
  The companion pattern for CONTENT whose values derive from the same
  spring (label emphasis, icon opacity/glyph): the content listens to
  the spring itself inside a stable piece child. Pinned by the channel
  group in morph_skin_test (re-trace isolation via
  LiquidTracer.lastMissCount, no-rebuild/no-relayout counters,
  displaced launch rect, fellowship from displaced geometry,
  resubscription).
- **Per-cluster cache**: `LiquidTracer` (one per MorphSkin State) -
  only clusters whose geometry changed re-trace; the rest reuse their
  loops. Keys are full per-cluster signatures compared element-wise on
  hash collision; the cache swaps wholesale per trace, so it never
  outgrows the scene. Instrumented via lastMissCount/lastClusterCount.
- **Bounded worst frame**: `evalBudget` (default
  `MorphSkin.defaultEvalBudget` = 200k field evaluations per cluster;
  internally `liquidDefaultEvalBudget`) - when a scene exceeds it, the
  grid coarsens by exactly the overshoot factor: quality degrades
  before the frame rate does. Deterministic function of geometry (no
  time, no hysteresis); null disables.
- **Fill rule is evenOdd**: interior holes (a ring of linked pieces)
  must stay hollow; the stitcher walks loops in arbitrary directions,
  so the default nonZero rule filled holes by winding accident and
  popped on topology changes.
- **Flight neck is a core feature, and free**: the group finds flights
  in MorphScope by its piece ids (listens to `scope.lastFlight` for
  discovery and to each flight controller for ticks; unsubscribes on
  `closed`, which is guaranteed to run before the controller's deferred
  dispose). Airborne: the home mass turns off and a companion blob
  follows the shuttle (a mirror of the flight frame geometry via
  `morphFlightGeometry`/`morphConcentricRadius`; coordinates translated
  through the group's localToGlobal); explicit links of the flying
  piece detach. LAUNCH FELLOWSHIP: at subscription the skin captures
  the connectivity component of the flying piece over solid pieces AND
  their MorphLink bridges (labeled by `liquidConnectivityLabels` - the
  ONE body predicate the tracer's cluster split also delegates to), and
  the blob necks ONLY to those - a flight stays attached to what it was
  part of, not to whatever it passes. Fellowship entries outlive
  subscription blips and are erased only on flight close or skin
  detach. Landing: the mass is home again (no squash). Perf gate: if
  `liquidRectGap` to every FELLOW piece exceeds k, the neck provably
  cannot exist and the blob is skipped (still exact under the
  normal-modulated law, k' <= k). Instrumented via lastFlightBlobCount.
  STRAY FLIGHTS: a flight can outlive its tag (the scope owns flights; a
  disposing tag only unregisters) - engine consumers go through
  `MorphScopeState.liveFlightOf` (null when the tag is not
  tree-active), which guards BOTH doors: the skin's `_flightFor` and the
  retarget lookup in `MorphFlight.launch`; the public `flightOf` stays
  honest for observers/HUDs. Outside a MorphScope the group degrades to
  pure fusion (`MorphScope.maybeOf`).
- **Surface model and ambient defaults** (`MorphSurfaceSpec`,
  `MorphTheme` in theme.dart): the surface model (shape, color,
  elevation) is a first-class value declared ONCE at the tag
  (`MorphTag.spec`) and read back by any rendering stack via
  `MorphTag.specOf(context)` - drift between the visible surface and
  the flight's belief is structurally impossible; the core blesses no
  design system. App-wide archetype vocabularies belong in the APP's
  own ThemeExtension holding spec values. Engine defaults live in the
  `MorphTheme` ThemeExtension (motion, maxScrimOpacity, scrimColor,
  shadowColor, skinStyle) with the resolution order explicit parameter
  > MorphTheme > builtin, everywhere. scrimColor is a hue whose own
  opacity COMPOSES with the animated scrim opacity; shadowColor is
  applied verbatim and resolved by BOTH flights and MorphSkin against
  ONE builtin (60% black) - Material elevation and the skin draw through
  the same canvas.drawShadow primitive (RenderPhysicalShape.paint).
  History: the skin's builtin was opaque black until 2026-08-11;
  converging DOWN to the flights' 0x99 was chosen because skins sit at
  elevation 2-6 while flights reach 24. The skin's builtin style is
  `MorphSkinStyle.subtle` (blend 8 = SwiftUI's default container
  spacing; was blend 24 before 0.7.0). No new scopes: MorphScope stays
  an identity/flight registry only. The SAME surface model describes
  both ends of a flight: MorphTargetSpec accepts `surface:` (winning
  over its individual fields), and the shuttle publishes the target's
  resolved model so custom content reads it via MorphTag.specOf.
  Custom dialogs/sheets = a custom MorphTargetSpec with your content
  builder; showMorphDialog/Sheet are presets over it.
- **Shared elements inside a flight** (`MorphSharedElement` in
  shared.dart): content marked with the same id on both sides TRAVELS
  between its endpoint rects instead of riding the fade-through. Both
  sides live in the one shuttle, so the flying frame is a lerp of
  endpoint rects by the RAW spring value (interruption-continuous by
  construction), crossfaded on the same fade-through curves and
  clipped by the morphing container shape. `MorphSharedFade.none`
  (declared by EITHER side) renders the TARGET copy alone at full
  opacity: fade-through dims both faders mid-flight, so applying it to
  identical content reads as a blink. Elevation in the frame lerps on
  p^1.5 (`p * sqrt(p)`), not p - linear shadow makes a nearly-home
  container float on a borrowed dialog shadow (visible at glacial);
  pinned by morph_frame_test's continuity check. Registry lives on the
  flight; sides register via SharedSideScope (internal). Markers hide
  by the registry's canFly - the set of ids the fly-layer builder
  ACTUALLY measured this shuttle build - not by hasPair: the pair
  registers during the shuttle's first build but nothing is measurable
  until its layout runs, so hasPair-hiding left the element visible
  NOWHERE for one frame (pinned by morph_shared_element_test's
  launch-continuity test). Markers must never touch render objects
  themselves - during the route-mode reparent their subtree is briefly
  inactive and findRenderObject asserts. Degradations: an unpaired id
  renders in place; snapshotGhost has no live source markers so pairs
  do not form; marker children must not carry GlobalKeys. The shuttle
  republishes the SOURCE tag's surface spec around the replica.
- **Pop layering**: an OVERLAY flight opened above a ModalRoute
  registers a LocalHistoryEntry on it, so Esc (DismissIntent ->
  maybePop), the Android back and a plain Navigator.pop close the
  TOPMOST surface first - the flight - and only the next pop touches
  the route. Route-mode flights skip the entry (their route IS the
  history); MorphPageRoute.didPop and the predictive-back hooks yield
  when willHandlePopInternally - a stacked entry owns the pop.
- **Overlay accessibility**: the scrim is a real modal barrier
  (BlockSemantics + Semantics label + onDismiss when dismissible; the
  label is looked up with `Localizations.of`, so MaterialLocalizations
  is no longer required); the container is a semantic route
  (scopesRoute, and namesRoute when `semanticLabel` is passed); a
  FocusScope + FocusTraversalGroup trap Tab traversal inside the open
  overlay; Esc and focus restore. The source ghost is ExcludeFocus'd:
  the live replica stays mounted INSIDE the trap for the whole flight
  (shared markers must keep measuring), and before the exclusion Tab
  reached the invisible copy and Enter fired its onTap (pinned by
  morph_focus_test). An explicit FocusNode in the tag child still
  ATTACHES to the replica mid-flight (undetectable, GlobalKey's benign
  cousin - GK crashes, so it is asserted) - but focus cannot enter and
  requestFocus is a no-op while airborne.
- **Layer-1 API (typical cases without ceremony)**:
  `MorphPiece.morphable(...)` - an auto-MorphTag (piece id, shape from
  its radius, skin color/elevation); the consumer just calls
  `showMorph*(from: pieceId)` from ANY context. `MorphSkinStyle` - named
  knob presets; only `subtle` (8) remains; explicit blend/cell/
  smoothPasses override the style. `showMorphDialog`/`Sheet` adopt shape
  and color from `DialogTheme`/`BottomSheetTheme` unless overridden.
  `MorphAnchor.tagId` gives the anchor's flight a public name - a
  MorphPiece with the same id gets the neck for free.

## Measurement pipeline (how the spec is obtained)

- PROBE: `tool/ios_reference/` - a UIKit app (Sources/: App, Scenes,
  Controls, Merge, Recorder, Settings) and an XCUITest driver
  (UITests/ProbeUITests.swift). `Recorder` samples, every display-link
  tick, the presentation layers of the tracked UIKit internals: lens
  frame rows, `_UIFlexInteraction` / `_UIVelocityIntegrator` state, the
  menu's morph container layer tree, control layers, touches (from a
  RecordingWindow.sendEvent override) and a `dl` row per tick
  (timestamp, targetTimestamp, duration, previous tick cost - the
  achieved frame rate is always known). Modes lens / controls / menu by
  scene. Simulator path: `build.sh` (swiftc, ad-hoc sign, install on the
  booted sim; launch with `SIMCTL_CHILD_PROBE_SCENE=<scene> xcrun simctl
  launch ...`), `pull.sh` copies Documents into recordings/. Device
  path: `device.sh` (xcodegen from project.yml -> build-for-testing with
  automatic signing -> test-without-building -> devicectl pull).
  Env: PROBE_PLAN (lens|controls|menu|dragtiming|recaplens|bars|
  recapcontrols|recapmenu|refs|merge|mergedyn|all), PROBE_ONLY,
  PROBE_UDID (default the owner's iPhone 16 Pro), PROBE_TEAM (default
  83S63575XD, the owner's own team), PROBE_STEP_HZ (default 30),
  PROBE_SKIP_BUILD, PROBE_RESULT (keep the xcresult; refs screenshots
  are attachments, export with xcresulttool). The phone must be
  unlocked, trusted, in developer mode, with Settings > Developer >
  Enable UI Automation on. Do NOT edit device.sh while it runs (sh reads
  it incrementally). `recordings/` and `build/` are gitignored;
  `references/` holds lossless reference PNGs (dark set + merge crops).
  Third pass (alerts, search, date picker): Sources/Extras.swift
  (`x3alert`, `x3search`, `x3date` scenes; `X3Sampler` logs every
  matched view per tick WITH label text/font/weight/color, PROBE_X3TRACK
  overrides the class pattern - `.` samples everything; PROBE_DARK,
  PROBE_SCRIPT actions show/dismiss/focus/type/clear/cancel/tab:search/
  open/close/settings/tree-*) and UITests/ExtrasUITests.swift (simulator
  touches: date picker taps, alert holds, search presses; a compact
  date picker cannot be opened programmatically; `testX3Device` takes
  every coordinate from the window size, so it runs on the 402 pt phone
  too). Device runs of the other UITests classes
  (Widgets2UITests, BarsUITests, ExtrasUITests) go through
  `xcodebuild test-without-building -only-testing:ProbeUITests/<Class>/
  <test>` with TEST_RUNNER_PROBE_ONLY / TEST_RUNNER_PROBE_STEP_HZ, then
  `devicectl device copy from` Documents (device.sh's PROBE_PLAN covers
  ProbeUITests and bars only). XCUIElement keyboard frames exclude the
  bottom row: the iPhone 16 Pro keyboard is 328 pt tall (top 546). Glass morphs that live
  in SwiftUI (the tab bar's search morph) do not show in view frames:
  record the simulator screen (`xcrun simctl io <udid> recordVideo
  --codec=h264`), extract frames with ffmpeg and read glass edges from
  pixel rows; alpha that UIKit animates outside the sampled layers
  (alerts) also reads best from video.
- READING UIKIT'S TUNING LIVE: enumerate classes with
  `objc_copyClassList` and walk the RAW pointer array (load each entry
  as an OpaquePointer, unsafeBitCast to AnyClass - Swift's typed view of
  the list crashes on some classes), keep PTSettings subclasses,
  alloc/init + `setDefaultValues` through typed IMP calls, then read
  properties via `class_copyPropertyList` + typed IMP casts per type
  encoding. NEVER KVC on private classes: `value(forKey:)` throws on
  non-object or missing keys and kills the probe. (KVC on public
  CALayer key paths such as filters.<name>.inputRadius is fine.)
- XCUITest SYNTHESIZER QUIRKS (device): dense paths replay late and in
  bursts (120 Hz points: a 1 s ramp arrived in 0.48 s with jumps), 60 Hz
  is smooth but ~16 percent slow, 30 Hz smooth ~9 percent slow (UIKit
  still receives touches at 120 Hz, interpolated) - hence
  PROBE_STEP_HZ 30; flings under ~100 ms collapse into one jump move;
  strokes in ONE record are re-timed (each starts at the previous lift
  whatever the planned gap); two synth requests in flight are refused
  (XCTDaemonErrorDomain 21); separate synth calls have ~217 ms minimum
  latency. Analyses always use the LOGGED touch rows, never the plan. A
  nearly full host disk produced 0.3..1.7 s main-thread stalls in held
  gestures (AnimationKit dispatch sync) - discard such passes.
- FIXTURES: `test/fixtures/ios27/{lens,controls,menu}` (iOS 27.0
  simulator, 60 Hz) and `test/fixtures/ios27-device/{lens,controls,
  menu,merge}` (iPhone 16 Pro, iOS 27.0.1, 120 Hz ProMotion), compact
  jsonl rows + manifest per family; recaptures APPEND (manifest note
  "recapture 2026-10-02"), nothing is overwritten. `test/support/
  trace.dart` loads them (`Trace`, `TraceTouch` with UITouch phases,
  `TraceFrame` with window-space bbox, bounds, transform scale, row
  fields like `ctl`). Fit reports and parameter JSON live outside the
  repo (/tmp/morph-native: lens-model.md, controls-model.txt,
  menu-model.txt, device-report.txt, recapture-report.txt,
  merge-report.txt, *-params.json; /tmp/cn1/REPORT.md) - volatile; the
  fixtures and the tests are the durable record.
- REPLAY TESTS (what they mean): the recorded touches are fed into the
  PURE motion class at their recorded times, the motion is advanced to
  each recorded frame, and the model's geometry is compared with the
  presentation layer within per-quantity tolerances (center, width,
  height in pt, sx/sy in scale). Frames the recorder missed must still
  be stepped (UIKit's integrator ran them). lens_test (segmented on sim
  60 Hz AND device 120 Hz; tab bar on the undeformed frame only),
  lens_scrub_test, switch_test, controls_test, menu_button_test,
  liquid_apple_merge_test. A replay test going red is a fidelity
  regression, not a flaky test; tolerances are not knobs.
- FRAME RATES (device findings): the flex integrator runs every 120 Hz
  tick with alpha 0.3 PER FRAME (filter time constant 23.4 ms at 120 Hz,
  46.7 ms at 60 Hz) - normalizing alpha by time or running a fixed 60 Hz
  sub-clock is WRONG on device (sx error 0.051 vs 0.006). Hence the
  sub-clock at the DEVICE refresh rate. Most lens geometry the loop
  reads refreshes at ~60 Hz on the device (the integrator consumes
  repeated values - a 60 Hz ripple); the inline-button menu OPEN is
  frame-locked at 1/60 steps even at 120 Hz, the nav-bar menu and every
  close run in continuous time.
- KNOWN UIKIT ARTIFACTS, DELIBERATELY NOT REPRODUCED: the tab bar's
  bar-local glitch (one frame of bar-local coordinates fed into its own
  integrator at each lift after the first: a spurious drift/scale kick
  on device, a vertical sag in the simulator); the menu's second
  deterministic kick variant (two kick curves per height, alternating -
  the larger one is canonical); lens geometry refreshing at ~60 Hz on a
  120 Hz device; the inline menu's 1/60 frame lock (morph evaluates the
  progress in continuous time). Also: device menus are 82 + 42 rows tall
  vs the simulator's 20 + 42 rows: the +62 pt is the system's own
  separator + "Ask Siri" row iOS 27.0.1 appends to every menu (visible in
  references/dark/menu-open.png), not padding; the tuning
  uses the simulator's padding and keys kick amplitudes by height.
- Static references: dark-mode PNGs in
  tool/ios_reference/references/dark/ (the phone was in dark mode); the
  LIGHT set is pending (switch the phone to Light, rerun
  `PROBE_SKIP_BUILD=1 PROBE_PLAN=refs PROBE_RESULT=... ./device.sh`,
  export into references/light/).

## Example

The app is a TOUR - an introduction to the library where the app itself
is the first exhibit (`example/lib/tour/`). The home is a SECTIONED grid
of chapter cards, each card a QUESTION its scene answers; every card
opens AS a morph route (container transform via showMorphRoute,
fullscreen target) - the navigation is the thesis. The tour runs on
`MorphMotion.liquid`. ONE SCENE = ONE USE CASE, styled as a real app
mockup inside a `PhoneFrame` (device.dart): the frame hosts its OWN
MorphScope + Navigator, so every flight, popover and route stays inside
the glass (this is what forced nearest-overlay/nearest-navigator engine
semantics). `SceneScaffold` is the responsive chapter layout: lesson
chrome (layer tabs, knobs, hints via PanelSection/PanelKnob/PanelHint)
sits beside the phone on wide screens, above it on narrow - the mockup
never carries lesson chrome. Engine PROPERTIES are layers and toggles
inside one scene, never separate lookalike screens. Sections and
chapters:
- THE FLIGHT - 01 THE MORPH (morph_scene.dart): a mail app, compose
  button (a MorphGlassButton) -> dialog; layers Motion (profile
  selector) / Interrupt (torture storm) drive the same flight.
- CONTROLS - 02 BUTTON TO MENU (menu_lesson.dart): a photo app's
  floating toolbar of a MorphGlassButton and two MorphMenuButtons.
  03 HOLD TO MENU (hold_lesson.dart): a chat; a held bubble becomes its
  own context menu (reactions capsule above, actions below). The mockup
  mirrors Sonatide's shell on purpose - the chat is a NESTED Navigator
  with a compose bar floating over it, so the OVERLAY toggle (chat tab /
  whole app) shows the menu hiding under the bar vs flying above it; the
  phone's overlay is captured from the PhoneFrame's app builder context
  and handed down. The lesson state reaches the nested page through an
  InheritedWidget (_ChatScope) because a route page is an overlay entry
  - an island no ancestor rebuild reaches. Delete from the bubble's own
  menu removes the source mid-close (the dissolve); a reaction lands on
  the bubble AT ONCE (the hero slot is live) and the capsule unfolds a
  note field (`_NoteRow`, its own State so the text survives the menu
  rebuilding around it); the KEYBOARD toggle drives the phone's own
  keyboard (`PhoneFrame.keyboard`, a ValueListenable<double> inset
  injected as MediaQuery.viewInsets above its navigator, key panel
  keyed `PhoneFrame.keyboardKey`); the EVENTS panel prints the flight's
  moments. Bubbles are keyed by message id so a deletion never hands a
  region's State (and its tag) to the next bubble.
  04 TOOLBAR MERGE (toolbar_lesson.dart): reading list; scroll fuses the
  actions into one pill on a single retargetable merge spring (a scene
  value, CupertinoMotion 600 ms / 0.42 - not measured).
- PAGES - 05 CARD TO PAGE (page_scene.dart): a music library; the
  overlay/route TOGGLE holds everything else constant, so the difference
  IS the demo (Lyrics stacks only on the route; shared covers +
  displacement drag in both). Cards, album cards and the mini bar render
  their surfaces from their spec with a plain GestureDetector. The mini
  bar is the fling-to-open recipe on the expert path: a FLICK (commit by
  release velocity ALONE - a slow pull meets ~14px of heavy give and
  springs back; the slingshot variant was built and rejected by eye),
  with the release velocity injected one frame later via
  controller.open(velocity:) once the shuttle has measured both rects
  (px/s -> value/s by flight distance). NOTE the retarget-clock nuance
  the fling test pins: a retarget restarts the controller's ticker and
  Ticker.elapsed restarts from zero, so the first post-retarget tick
  evaluates the sim at t=0 - a test sampling right after the injection
  frame must pump once more.
- LIQUID - 06 LIQUID SELECTION (goo_dock_example.dart): a feed app dock,
  one fused mass whose selection blob lifts, travels and lands on the
  tab bar lens's measured springs (`MorphLensTuning.tabBar` travel and
  lift via SingleMotionController), writing its piece channel.
  07 THE BAR (bar_lesson.dart): a `MorphTabBar` beside a glass send
  button (a MorphGlassButton that is still a real morph source - its
  compose dialog flies out of the glass you pressed).
  08 LIVING LAYOUT (chips_example.dart): search filter chips as one
  fused row; layout-as-targets, births/deaths at
  `MorphPieceChannel.birthScale` on `birthSpring` (a removed chip parks
  inside its survivor; the last chip deflates to nothing), the
  stiffness wave (sims evaluated at t*rate, rate falling by slot
  distance - hand-rolled on purpose; NOTE the ticker-clock trap:
  Ticker.elapsed restarts from zero on every start(), so idle-restart
  flows must reset their own clock or springs evaluate at negative time
  and thrash). Scene blends (18/24 in the lessons) are mockup values.
- THE LAB - 09 PLAYGROUND: always last (the autodemo opens it by
  position).
The honesty criterion: a morph must TRANSFORM IDENTITY (the thing you
touch becomes the surface you use); spring-skinning ordinary controls
is animation, not morph.

The second gallery, `example/lib/gallery/` (`flutter run -t
lib/gallery/gallery.dart`): the measured widgets one page each -
Segmented control, Tab bar (2..5 tabs, press growth, scrub), Controls
(switch, slider, glass button, stepper), Menu, Glass renderer (a frosted
BackdropFilter painter, dark, RTL, disabled), Size to physics
(spec_inspector: how MorphFlexSpec derives lift and springs from a
size). A SLOW-MO toggle cycles `timeDilation` 1x/5x/10x: the measured
motion runs on ticker time, the flex filters step on the sub-clock in
that same time and touches are stamped on it, so the widgets slow down
as a whole and trace the same curves; only the finger keeps real time.

`example/ios/` exists (untracked so far; Runner, bundle
dev.tembeon.morphExample, team 83S63575XD) for running the tour and the
gallery on the owner's iPhone next to the native controls. Each Runner
config still carries a stale duplicate `DEVELOPMENT_TEAM = 5743F3SV5C`
line before the 83S63575XD one - remove it before committing.

The Playground chapter (`example/lib/playground/`) is the sandbox
builder:
- pieces (box/stadium/circle) are added, selected, dragged, resized from
  the sidebar; all fused by one liquid skin;
- every piece is a morph source: double-tap = a real flight (dialogs or
  a sheet by id % 4); torture and the autodemo fly from piece id 2;
- MorphLink bridges: select a piece -> link -> tap another (repeat to
  unlink); link chips in the sidebar;
- keyframes A/B: scene snapshots (geometry by id + blend); playback is a
  spring morph from the CURRENT state on the profile's openMotion;
  pieces missing from a snapshot stay put;
- sidebar sections: MOTION (motor's vocabularies: cupertino, m3, curve
  - the curve family shows why close needs a spring) / SANDBOX /
  KEYFRAMES / LIQUID (blend presets are measured container spacings 8
  (SwiftUI default) / 20 / 40 / 80, plus free blend and detail sliders
  and the Contour switch) / STRESS;
- THE LAB CHROME RUNS ON THE WIDGETS LAYER (example/lib/ui/
  lab_chrome.dart): LabSegmented = MorphSegmentedControl, LabSwitchTile
  = MorphSwitch, LabActionButton/LabIconButton = MorphGlassButton; panel
  and canvas swaps are SpringSwitcher (example/lib/ui/
  spring_switcher.dart) - a MorphController-driven crossfade-and-rise
  with TWO STABLE KEYED SLOTS (the outgoing element keeps its tree
  position until settle; a mid-flight swap flips value := 1 - value via
  the scrub API). Lab chrome, not a library candidate (worked through
  and rejected for promotion on 2026-08-09). Sliders stay plain;
- stress mode (example/lib/playground/stress_lab.dart): N pieces on
  deterministic golden-angle orbits re-trace the skin every frame, with
  an on-screen FPS meter (average + worst frame per window). Judge
  numbers in --profile/--release, debug is pessimistic.

Flight-to-skin coupling lives entirely in the core: the demo uses
`MorphPiece.morphable` and just calls `showMorph*(from: pieceId)`.
Hard-won rules still enforced in the core:
- Stack children in MorphSkin MUST be keyed by piece id - otherwise
  removing a piece from the middle of the list confuses the identity of
  stateful content (MorphTag used to hit 'duplicate id' asserts);
- content with a MorphTag stays HOME for the whole flight (it must not
  move: the flight tracks the source through the tag); only the mass
  blob travels.

## Reference provenance

- UIKit itself is the reference: iOS 27.0 simulator (iPhone 18 Pro /
  18 Pro Max / 17e) and iOS 27.0.1 on the owner's iPhone 16 Pro, captured
  2026-10-02 with tool/ios_reference. Tuning names quoted in dartdoc
  (`_UIFlexInteractionSpec.dynamicWithSize`, `liquidLensWithSize`,
  `_UILiquidLensView` small/large, `AnimationKit.MorphAnimationSettings
  .liquidMorph`, smallLoupe) are what the probe read live.
- Codename One PR #5906 (codenameone/CodenameOne, merge 850bb54, read at
  75a7a31): an independent iOS 27 floating tab bar measurement, used as
  a CROSS-CHECK only. GPLv2+CPE: re-derive numbers, never copy code.
  Where it disagrees with our own captures (follow spring 0.196/0.903,
  the "remaining travel < 3.5 pt" unlift rule, a hard clamp at the end
  tabs) our device data wins.
- whynotmake-it/flutter_liquid_glass `liquid_glass_renderer`
  (release/01-renderer-core @ cbbac845, sdf.glsl): same base smin, same
  normal-modulation idea with the WRONG exponent (sin(theta/2) chord vs
  Apple's sin^2) - necks too fat by +0.5..+8 pt as spacing grows. Not a
  source; a comparison.
- Superseded references (kept for history): Kyant0/AndroidLiquidGlass
  (`LiquidButton.kt`, `LiquidBottomTabs.kt`, `DampedDragAnimation.kt` at
  65ab177e) and liquid_glass_easy - the basis of Tug and MorphPillHost,
  both deleted in 0.7.0.

## API conventions

- ONE vocabulary: every public type is `Morph*`. The liquid subsystem is
  spoken of as "the skin": `MorphSkin`/`MorphPiece`/`MorphLink`/
  `MorphSkinStyle`/`MorphStroke`, knob `blend:` (the widget name for the
  smin k; the internal math layer keeps `k` - SDF literature language).
  "Liquid" survives as the technique name INSIDE liquid_field.dart only;
  nothing `Liquid*` is exported. Raw SDF masses for
  `MorphSkin.extraMasses` are `MorphMass` - ONE sealed type with const
  redirecting factories `.box(rect, radius:)` and `.bridge(a, b,
  radius:)`, subclasses private. A mass has no morph identity, it cannot
  fly. The flat "kind + 5 params" record (stride
  `liquidMassSignatureStride`) is the CANONICAL mass flattening:
  @internal `liquidMassSignature` is its one implementation, written
  into both the tracer's cluster keys and the skin's input signature (a
  preallocated Float64List; exact - full parameters, because two
  diagonal bridges can share an outerRect yet trace differently). The
  only remaining kind-switch outside it is the field sampler, which
  exists precisely to keep per-vertex math free of dispatch.
- The motion profile parameter is `motion:` everywhere (never "speed" -
  a profile carries character, not just tempo). Springs in UIKit terms
  are `MorphSpring(response, dampingRatio)`; widget tunings expose
  MorphSprings, not motor Motions.
- `MorphMenuItem` now names `MorphMenuButton`'s rows (`title`, `icon`,
  `destructive`, `onSelected`); the old popover `showMorphMenu` is gone.
- Export diet: foundation.dart is the whole engine surface; liquid_field
  internals, RenderMorphSkin and the shared-element machinery are not
  exported (package-internal tests import src/ directly). widgets.dart
  exports by explicit `show` lists; the widget machinery (clock,
  integrator, timeline, spring state, lens driver, focus, glass layer)
  is @internal. The minimal motor vocabulary (Motion, CupertinoMotion,
  MaterialSpringMotion, CurvedMotion) is re-exported.
- DESIGN-SYSTEM PACKAGE: morph imports
  `package:material_ui/material_ui.dart`, never the in-SDK
  `package:flutter/material.dart` (migrated 2026-09-01 on Flutter 3.47,
  `dart fix --code=migrate_design_widgets`). The two are SEPARATE COPIES
  of Material - `material_ui.Theme` and `flutter/material.Theme` are
  different types - so a consumer app on the in-SDK library must
  migrate too or wrap the morph subtree in
  `MaterialUiCompatibilityBridge`. `cupertino_ui` is transitive only:
  morph uses no SDK Cupertino (`CupertinoMotion` comes from motor).
  Icons resolve through `uses-material-design: true`.
- ENGINE-TO-MATERIAL DEBT: the core still touches Material in FOUR
  places, so `foundation.dart` drags material_ui onto every consumer -
  the "core blesses no design system" promise is not yet paid. Map:
  `theme.dart` (MorphTheme extends ThemeExtension +
  Theme.of().extension), `flight.dart` (Theme.of().colorScheme, the
  shuttle's Material container, the optional MaterialLocalizations
  barrier label), `route.dart` (MaterialLocalizations barrier label,
  colorScheme, the settled page's Material), `show.dart`
  (DialogThemeData / BottomSheetThemeData adoption). scope.dart and
  target.dart import material_ui for types only. The shuttle's Material
  is what lets consumer dialog content use InkWell and default text
  styles; dropping it is a behavior break, not a rename. The widget
  layer's MorphWidgetsTheme is a ThemeExtension too.
- Engine seams that must stay public for cross-file use are annotated
  `@internal` (scope registries, tag machinery, controller.notifyFrame,
  flight route/shared plumbing): the analyzer warns consumers off.
- RETARGET CONTRACT: a repeated showMorph on a live tag retargets the
  existing flight - it keeps its target, builder, barrier and scrim
  (content lives in the shuttle and cannot be swapped mid-air); only
  motion, dismissal routing and semanticLabel are updated.
- `from:` is OPTIONAL in showMorph*/showMorphRoute: inside the source
  tag's own subtree the nearest enclosing MorphTag is the source
  (MorphTag.idOf; the marker is installed by the tag itself and
  deliberately NOT republished by the shuttle - dialog content names
  its source explicitly). Calls from elsewhere keep the explicit id.
- Surface RENDERING is an opinion, not engine contract: the engine's
  contract ends at `MorphTag.specOf`. The Material adapters
  MorphSurface/MorphTapTarget are gone (0.7.0): render the surface from
  specOf with your own design system and a GestureDetector, or use
  MorphGlassButton for a button that is a morph source.
- MorphPageRoute.barrierLabel is the localized dismiss label (passed by
  showMorphRoute), NOT the route name - that is semanticLabel.

## Structural conventions

- ONE frame stream: `MorphFlight.frameTicks` merges the value spring,
  the displacement channel, the content-size channel and a target's
  `repaint`; the shuttle and the skin subscribe THERE. A new co-driver
  of the frame joins the merge - never a notifyListeners backdoor on the
  controller. Widget-layer driven springs never write into it.
- ONE geometry: `morphFlightGeometry` + `morphConcentricRadius` in
  frame.dart are the only implementations of the frame's rect/radius
  math; computeMorphFrame and the skin's mirror blob both call them.
  `MorphTargetSpec.resolveRect` is the one rect resolution (fixed or
  measured) and `morphTargetPaddingOf` / `morphContentViewInsets` the
  one keyboard math, called by the shuttle and the settled route page
  alike.
- A tag below a paint transform captures its WHOLE local bounds through
  `getTransformTo` + `MatrixUtils.transformRect`. Transforming only its
  local origin while retaining the layout size makes a centered scale
  jump smaller and off-center on the first flight frame.
- ONE content chain: `buildMorphTargetContent` (flight.dart) is the
  only place the target wrapper chain exists; the shuttle and the route
  page both mount it - the route-mode reparent preserves state only
  while the chains match.
- ONE drag composition: `morphDragScrimFactor` + `morphDragScale`
  (gesture.dart) are the only implementations of how a live drag dims
  the scrim and recedes the card; the shuttle and the settled route
  page both call them. THE RULE OF THREE HOMES for visual constants: an
  ambient engine default lives in MorphTheme; a value drawn by more than
  one stack lives in ONE named implementation; a local literal is legal
  ONLY while exactly one paint site uses it. In the widget layer a
  measured constant lives in its tuning class (MorphLensTuning,
  MorphMenuTuning, MorphFlexSpec, the *Motion statics) with the
  measurement in its dartdoc, never as a bare literal in a widget.
- The displacement channel is `_DragChannel`, a ChangeNotifier owned by
  the flight; the flight's public drag API delegates.
- Widget-layer motions are pure: explicit time in, geometry out,
  `MorphSpringState` closed-form springs, `MorphTimeline` for every
  delay, `MorphSubClock` for every per-frame filter. A widget host owns
  only the MorphClock, the Listener, focus/semantics and painting. A
  control's ticker sleeps when its motion settles.
- Example spring recipes ride motor's `SingleMotionController`
  (retarget with velocity carry-over built in); hand-rolling remains
  ONLY where a controller cannot go - the chips wave evaluates sims at
  t*rate, and a controller owns its own clock.

## Invariants (never break these)

1. **Every visual property of an ENGINE flight is a pure SYMMETRIC
   function of a single spring's STATE - (value, velocity).** No
   direction-dependent curves, no wall-clock time. This yields
   interruption continuity by construction. Precisely: ONE SPRING PER
   DEGREE OF FREEDOM. The gesture displacement is a second, ORTHOGONAL
   DOF with its own always-to-zero spring; the content-size channel is
   an endpoint filter, not a clock on a property; each DOF stays pure
   and continuous, and their superposition preserves the guarantee.
   Forbidden in the engine: two clocks driving the SAME property, or a
   lagging spring whose target is fed from the first.
   NATIVE-FIDELITY EXEMPTION (widget layer only, measured behaviour
   only): where UIKit itself is not a function of one spring's state,
   morph copies UIKit - fidelity over single-spring purity. Two kinds
   exist: (a) the FLEX LOOP - three one-pole filters, alpha 0.3 PER
   RENDERED FRAME, over the previous frame's visible position, closed
   through drift/scale targets; it runs on a fixed `MorphSubClock` in
   MOTION time at the device refresh rate (120, or 60 on a 60 Hz
   display), so its response is per frame like UIKit's yet identical
   under timeDilation and coarse test pumps; (b) DRIVEN SECONDARY
   SPRINGS - the lens drift/scale presentation springs chasing per-frame
   targets, the small lens stretch, the menu kicks (chasing the progress
   velocity, struck on close), integrated over every advance. The
   exemption's limits are absolute: every such state retargets from its
   current (value, velocity) - continuous through every reversal, never
   restarted; time is the MorphClock's motion time (ticker elapsed,
   timeDilation-aware, events stamped from their own timestamps), never
   a wall clock or Stopwatch; and nothing exempt ever feeds
   `MorphFlight.frameTicks` - the menu runs the same measured progress
   spring as its flight on its own motion clock and draws its kicks
   inside its vessel (and on the button after the latch), the flight
   stays pure. A new
   exempt behaviour needs a recording that shows it.
2. Retarget = a new simulation starting from the current (value,
   velocity). One active flight per tag; re-showing retargets it. UIKit
   does the same (a close mid-open fits only with velocity carried).
3. Handoff latch: the shuttle-to-widget swap happens exactly on the
   first zero crossing of the close; the rest of the close spring's
   undershoot plays on the live widget (`isLanding`). There is no added
   landing bump anywhere.
4. Target content lives in the shuttle for the whole flight (no
   reparenting except the route's sanctioned second latch; a GlobalKey
   inside the tag child is forbidden - assert).
5. Shadow and elevation belong to the shuttle and lerp source->target
   (a button with its own shadow must declare `MorphTag.elevation`).
   Vessel targets draw neither.
6. closeMotion must be able to go below zero (a spring), otherwise the
   latch degrades gracefully; `snapToEnd` must stay false - the handoff
   latch lives on the zero crossing. Enforced in debug:
   MorphMotion.debugContractViolation, asserted whenever a profile is
   installed into a controller. The OPEN may overshoot (liquid does).

## Motion design principles

- The measured platform is the spec (see Direction). Springs are
  spoken in UIKit's vocabulary (response, damping ratio); a number in
  lib/ carries its source in its dartdoc (read from tuning, or fitted,
  with the fit's spread when it matters).
- The engine default is UIKit's liquid morph: open 0.35/0.75 overshoots
  ~3 percent, close 0.49/0.80 undershoots ~1.5 percent; the landing is
  that undershoot and nothing else; a close from rest starts still.
- Reversal is a retarget with velocity, everywhere - flights, lenses,
  knobs, menus.
- Content arrives WITH its surface: no cascades (UIKit's menu rows and
  context-menu satellites do not cascade).
- "One mass - one shadow" for engine flights; the menu is two blobs in
  a union with no neck (as UIKit draws it); the skin merges by the
  normal-modulated smin.
- Deformation comes from UIKit's flex loop (acceleration, not
  velocity), never from a hand-made squash.
- For the eye: `MorphMotion.glacial` for flights, the gallery's
  slow-mo (`timeDilation`) for widgets - both preserve the curves.

## Rejected approaches (deliberate - do not reintroduce)

- **Hand-tuned physics in lib/** (all removed 2026-10-02, history in
  git): Tug (Kyant0 LiquidButton model), MorphPillHost and THE BAR's
  hand-approved grab, MorphSquash, SpringButton, ChaseSpring,
  morphPressGrowth, the popover showMorphMenu, MorphSurface/
  MorphTapTarget, MorphReveal cascades, the landing bump (MorphTag/
  MorphPiece/MorphTheme bumpScale/bumpRecoil, morphLandingBump,
  morphBumpedRect, impactAxis), closeVelocityHint/morphCloseHintScale,
  MorphMotion slow/normal/glass/fast, skin presets geometric/goo, and
  the promotion candidates GooSelector/SpringToggle. A/B feel labs are
  out too: the replay is the judge, not side-by-side taste.
- **Kyant0's five-spring DampedDrag** (rejected 2026-08-26 for buttons,
  now moot): superseded by UIKit's own flex loop.
- **Replaying recorded kick tables frame by frame**: the menu kicks are
  driven springs now - a table cannot carry a reversal.
- **A fixed 60 Hz sub-clock or a time-normalized alpha for the flex
  loop**: device data proves alpha is per rendered frame.
- **Reproducing UIKit artifacts** (tab bar bar-local glitch, the second
  menu kick variant, 60 Hz geometry refresh on 120 Hz, the inline
  menu's 1/60 frame lock).
- **Plain (unmodulated) smooth-min**: lifts aligned edges by k/4, which
  Apple never does (rms 9 pt at spacing 80). Also rejected: the
  renderer's sin(theta/2) chord (necks too fat).
- **Shader/blur-based liquid neck** (SDF shader, blur+threshold
  metaballs): halos and mush. The CPU vector path is the only supported
  skin; glass RENDERING belongs to the app via MorphGlassPainter.
- **Prebuilt drag widget**: gesture policy for dismissing a flight
  belongs to the app. The primitives and the scrub API remain.
- **Snapshot ghost by default**: a frozen ripple looks worse than a live
  widget replica. Kept as opt-in for heavy content.
- **"Position leads, size follows"** and back-out on position: not
  supported by platform references and caused a wind-up on close.
  Geometry is linear in the value; character comes from physics.
- **MotionController from motor** for the engine flight: its settle
  semantics conflict with the handoff latch. Only Motion-as-simulation-
  factory is used there. (Widgets and recipes may ride
  SingleMotionController.)
- **anchorScale** in the frame: dead remnant of a two-blob model.
- Built-in gesture driving of flights, text/layout morphing - out of
  scope.

Deliberately kept although the engine does not use it:
`MorphFrame.cornerRadius` (public info for consumer accessories, covered
by a test).

## Documentation conventions

- One strict analysis_options at the package root (strict-casts/
  inference/raw-types plus a hand-picked lint set:
  always_use_package_imports, prefer_final_locals, no_default_cases,
  avoid_catches_without_on_clauses and friends); the example includes
  it via `include: ../analysis_options.yaml`. `flutter analyze` must
  stay at zero. Tried and DROPPED (style-only, tax exceeded value):
  cascade_invocations, join_return_with_assignment,
  prefer_if_elements_to_conditional_expressions. Owner's call
  (2026-08-29): do NOT write cascades in new code at all - the parser
  glues a `..` section onto a preceding expression-bodied lambda
  (`..onHandoff = () => x++ ..open()` parses the open() onto x++), and
  the readability gain never pays for that trap. Existing cascades may
  stay where the receiver is configured at construction; actions that a
  test asserts on live as plain statements.
- `public_member_api_docs` is ON in BOTH analysis_options (package and
  example): every public member carries a dartdoc, including the
  unexported src/ machinery and the example's teaching code - the lint
  is the coverage gate.
- Dot shorthands (`.center`, `motion: .liquid`, `rect: .fromLTWH(...)`)
  and pattern matching (switch expressions, relational and object
  patterns, if-case) are the house style where the context type is
  known; there is no built-in lint for shorthands. For a full sweep,
  temporarily add the `prefer_shorthands` analyzer plugin to
  analysis_options (as of 0.4.7 it needs its analyzer/analyzer_plugin
  constraints widened and a small port to the analyzer 14 AST names),
  apply its findings, then remove it. Known false positive:
  `Object.hashAll` in an int context.
- Example layout: `tour/` (home, lesson framework, device.dart - the
  PhoneFrame/SceneScaffold/Panel* chapter chrome, lessons/ - all
  chapter scenes and dialog_contents.dart), `gallery/` (the measured
  widgets gallery, its own main), `playground/` (the sandbox, stress
  rig, HUD and the chapter shell), `ui/` (lab chrome: lab_chrome.dart,
  spring_switcher.dart), `perf/` (the release bench), flags.dart,
  main.dart. Tests that replay fixtures live in the PACKAGE (test/), the
  fixtures under test/fixtures/.
- Dartdoc speaks to the CONSUMER in the present tense: behavior,
  contract, the constraint the code cannot show - and, in the widget
  layer, the measurement a value comes from. Design history, bug
  archaeology and test pointers live HERE (CLAUDE.md) and in commit
  messages, never in doc comments.
- Effective Dart style: single-sentence summary first, noun phrases
  for properties, square brackets only for resolvable identifiers
  (ranges like `[0, 1]` are backticked), no caps-shouting for emphasis.
- `dart doc --dry-run` must report zero warnings (broken references).
  Because widgets.dart re-exports the whole engine, every engine symbol
  is pinned canonical in foundation via the `{@canonicalFor}` block in
  foundation.dart's library doc - a NEW engine export needs its line
  there or the gate warns; dartdoc_options.yaml silences the scorer's
  coin-toss over the src library entities themselves.
- CHANGELOG entries: `## X.Y.Z - DATE`, a prose lead saying what the
  release IS, then bullets; BREAKING inline in the bullet it belongs to.
  READ the file before writing to it.

## Verification workflow

```bash
dart format lib test example/lib example/test && flutter analyze
flutter test && (cd example && flutter test)
cd example && flutter build macos --release
cd example && flutter run -d macos --dart-define=MORPH_AUTODEMO=true
cd example && flutter run -t lib/gallery/gallery.dart   # measured widgets
```

Every step must be green after each change (analyze from the package
root also covers example). Motion fidelity is judged by the REPLAY
tests against the recordings; the human eye judges on glacial / slow-mo
and, for the widgets, on the iPhone next to the native controls (the
example has an iOS target). Agent self-verification is the tests (555
in the package + 49 in example) plus the autodemo with no EXCEPTION in
the log (autodemo: opens the Playground chapter AS a morph route -
exercising the card flight and the second latch - then a dialog flight
from a piece -> interruption torture -> 4 keyframe morphs A/B).

Test traps:
- `tester.getSize` reads the LAYOUT size and ignores paint transforms -
  a press lift or any Transform shows only in `tester.getRect`.
- The first tick after a ticker (re)start evaluates at t = 0, so a
  sample right after a start or retarget needs one more pump (the
  retarget-clock nuance); a size change reported post-frame starts its
  spring on the NEXT pump, whose first tick is at t = 0, so a mid-value
  sample needs pump() + pump(16ms) + pump(N).
- A tag dropped by a build is only DEACTIVATED that frame and unmounts
  at the frame's end, so `MorphFlight.isSourceLost` reads true one frame
  later.
- A broadcast-stream subscription made after an `await` misses what was
  queued before it.
- A motor SingleMotionController settles within ~1e-4 px of its target:
  use moreOrLessEquals with an epsilon, never equality.
- `find.byKey(heroKey).last` in a context-menu test is the shuttle's
  GHOST replica (scaled by the container's width ratio, hidden by
  opacity, mounted for the whole flight) - the slot copy is the one
  under the menu's Column.
- `MorphMotion.instant` is a 281 ms critically damped spring, not a
  cut - a reduced-motion size change still moves.
- Widget-layer hosts pick their sub-clock rate from the test display's
  refresh rate (60 in flutter_test), while device replays pass 120
  explicitly to the pure motion; a widget test and a 120 Hz replay of
  the same gesture differ in deformation by design.
- Replays must step every frame the recorder missed; skipping them
  doubles the scale error.
For changes touching the tracing pipeline additionally run the
microbenchmarks (`flutter test benchmark/liquid_benchmark_test.dart`)
and compare against the previous numbers on the same machine (JIT -
relative only).

## Performance passport (AOT)

The absolute numbers come from the RELEASE bench - the same scenes as
the microbenchmarks (shared via src/benchmark_scenes.dart, so the two
harnesses cannot drift) measured inside an AOT build, plus real engine
FrameTimings during a glacial flight:

```bash
cd example && flutter build macos --release --dart-define=MORPH_BENCH=true
./build/macos/Build/Products/Release/morph_example.app/Contents/MacOS/morph_example
| grep BENCH
```

Baseline 2026-07-30, Apple Silicon macBook (tembeon), macOS release.
NOT re-measured since: the 0.7.0 merge law adds one normal per mass per
sample and a dot product inside the k band, and glacial is now liquid
x5 - rerun before quoting these numbers.

| scene                   | us/op  |
|-------------------------|--------|
| fusedPair               |     86 |
| sandboxSpread           |    231 |
| flightFar               |    177 |
| manyPieces              |    437 |
| megaCluster64 (budget)  |  1 997 |
| megaCluster64/unbounded |  8 551 |
| oneMoving/pure          |    158 |
| oneMoving/cached        |     57 |

Frame timings (glacial open+close, n=1087): build avg 0.22 / p95 0.35
/ worst 0.60 ms; raster avg 0.79 / p95 1.33 / worst 6.8 ms (the worst
raster frame is first-use shader work). Reading: the cached animated
frame costs 57 us - under 1% of a 120 Hz budget; the 64-piece
worst-case cluster re-traces in 2.0 ms with the eval budget (fits
120 Hz) vs 8.6 ms unbounded (would blow it) - the budget is what keeps
the worst frame inside the envelope. AOT runs ~9x faster than the JIT
test VM across every scene.
