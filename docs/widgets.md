# The measured widget layer

How a control in `lib/src/widgets/` is built, the machinery it runs on,
and the policies every control follows.

## Measured spec

Measured numbers live in `tool/ios_reference/spec/`: `README.md` holds
the protocol (probe, recorder, synthesizer quirks, fixtures, device lock,
provenance, status), and there is one passport per control or family.
Read the passport of the control you touch, and `lens-and-flex.md` for
anything that lifts. When a measurement changes, update the passport and
the tuning class dartdoc in the same change. The phone is shared: take
`/tmp/morph-native/device.lock` (see the README) before touching it.

## Shape of a control

- A pure motion class: a function of the touches it is fed and the time
  it is advanced to. No widgets, no tickers; it replays in a plain
  `test()`.
- A thin widget host: a raw `Listener` stamps pointer events on the
  motion clock, calls `motion.pointerDown/Move/Up/Cancel`, advances the
  motion per tick and paints. The host owns only the `MorphClock`, the
  `Listener`, focus/semantics and painting.
- A `style` with `light`/`dark` tables taken from the iOS system colors.

Measured constants live in tuning classes (`MorphLensTuning`,
`MorphMenuTuning`, `MorphFlexSpec`, `MorphSheetTuning`, the `*Motion`
statics, ...) with the measurement in their dartdoc, never as a bare
literal in a widget. Motions use `MorphSpringState` for every spring,
`MorphChannel` for every value UIKit drives as an animatable channel (a
flex scale or drift, a pulse), `MorphTimeline` for every delay and
`MorphSubClock` for every per-frame filter. A control's ticker sleeps when its motion settles:
at a visible rest (`MorphRest`, spring_state.dart: every spring's remaining
swing, `MorphSpringState.reach`, under 0.1 pt, an opacity's under half an
8-bit step), after which `MorphClock.settleMotion` snaps the motion onto its
targets before the last frame paints (NEAR, invisible).

`MorphControlHost` hosts build in `buildControl`; `build` hands back the
last result while `buildsLike(oldWidget)` holds (every field the build
reads is equal, callbacks compared only by nullness), no dependency
changed, no `setState` ran and `buildInputs` (state the build reads, for
example the segmented control's selection) is unchanged. So a build must
never capture a widget callback; it calls `widget.onX` at event time. A
parent rebuilding a page of unchanged controls rebuilds none of them.

A pressable control takes its input through one widget, `MorphPress`
(`press.dart`): keyboard focus (Space / Enter call `onActivate`, what a
tap does; arrows call `onStep`), its semantics and, with a `target`, a
`MorphTouchListener` in the gesture arena. `MorphControlHost` is such a
target and follows its press with the pure `MorphPressTracker`: one
pointer id, the primary button only, the box extended by `pressSlop`
with exit / enter edges, inside or outside at release, and the reason a
press was lost (platform, scroll, disabled). The focus node is attached
directly, not through a `Focus` widget, so a menu or sheet opening over
a page rebuilds none of its controls, and the ring (`focusRing: true`,
for controls that do not draw it themselves) is inserted only while it
shows: focusability costs no build and no paint on a surface that
repaints every frame. The node depends on the enclosing `Focus` scope
and follows it to a swapped node, but its element applies a changed
dependency (parent node, navigation mode) without marking itself dirty,
so focus moving under that scope builds nothing; `MorphPress.build`
therefore reads no other inherited widget. A descendant finds the
control's node through `node.context`, not `Focus.of`.

## Internal machinery (all `@internal`)

`spring_state.dart` - `MorphSpringState`: a damped spring in closed form
from its last retarget (under-, critically and over-damped branches).
Time is an explicit argument everywhere; `retarget(t, target, spring:)`
carries (value, velocity); also `setState`, `snap`, `isAtRest`. This is
what makes the motions pure functions of time. It never retargets before
its last change.

`timeline.dart` - `MorphTimeline`: delayed reactions ordered by due time.
Each action receives its own scheduled time, so a motion advanced in
coarse steps still applies every action at its own time. Equal times
keep insert order; `now` reads the running action's time.

`clock.dart` - `MorphClock` mixin: the ticker's elapsed time accumulated
across restarts (time asleep does not count; the ticker stops when the
motion settles). `frames` is the painter's repaint `Listenable`.
`motionFrameRate` is 60 when the display reports 60 Hz, 120 otherwise.
A frame's time is put on the display's frame grid (`MorphFrameGrid`:
the median of the last steady steps, a node within 1 ms or else a new
grid; NEAR) before the motion samples it, so frames are spaced exactly
and `frameTime` + k `framePeriod` are the coming frames.
`stamp(event)` puts the event's own time stamp on the motion clock - the
reference every device-fitted delay and every replay uses
(UITouch.timestamp to native start, which includes UIKit's delivery
latency). Stamping rules:

- `PointerEvent.timeStamp` counts CLOCK_UPTIME_RAW on iOS / macOS;
  frames and `morphClockNow` (Dart's Timeline clock) count
  CLOCK_MONOTONIC_RAW. `morphPointerClockOffset` reads the difference
  (the device's sleep) through FFI (`pointer_clock_io.dart`; zero
  elsewhere, a stub on web).
- Ticking or dozing: the latest frame's clock + (event time - that
  frame's stamp), 1 - 3 frames in the past (an iOS frame is stamped with
  its display target).
- Asleep: events keep their own spacing divided by `timeDilation`; the
  first frame after the wake counts from the event's time stamp.
- A time stamp outside 0 - 250 ms before now falls back to delivery +
  one frame (UIKit begins a frame after a handler).
- Frame stamps and now disagreeing by more than 50 ms (a test's fake
  clock) fall back to the latest frame's clock.

Evidence: spec/README.md "Clocks".

`live.dart` - `MorphFrameSync`: how a control that reads a motion it does
not advance itself follows it without building every frame. It follows a
source (`frames`, a flight's ticks, a drift), reads a structure record
once per frame in the mid-frame microtasks (after every ticker ran,
before anything builds; a ticker's notification queues one microtask,
one already in that phase reads at once, and one between frames also
asks for a frame, as a setState does), hands a changed record to
`rebuild` and otherwise notifies the `MorphLive*` render objects and
glass hosts that follow it. The build reads its record through `read`.
Menu button and layer, bar row, search toolbar and tab bar, sheet and its
zoom crossfade, push zoom and the engine's flight shuttle use it; `test/frame_sync_test.dart` pins its
timing and that of a glass host following it.

Two other shapes stay correct without it. `MorphChanges` filters a
source down to the frames on which a key changes, for listeners that
only redraw (the slider's track: its glass host hears only the frames
that move the track). A control that reads only the motion its own
`MorphClock` advances may sync inside `advanceMotion`, which runs after
that motion stepped: the date picker overlay sets its two structure
flags (each rebuilds its own subtree) and ticks its box's live render
objects only on frames that move the box, so a page turn or the year
wheels repaint nothing of the box.

`flex_integrator.dart` - `MorphFlexIntegrator` ports UIKit's
`_UIVelocityIntegrator` (alpha 0.3 per frame). `MorphSubClock` is a
fixed-rate frame clock in motion time at `motionFrameRate`: every
boundary crossed is reported (at most 600 per advance), so the
deformation is identical on a 60 or 120 Hz host, under `timeDilation`
and under coarse test pumps.

`flex_interaction.dart` - `MorphFlexInteraction` ports UIKit's
`_UIFlexInteraction`, the one machine behind every flexible glass
surface: four channels (scale x, scale y, drift x, drift y) chase targets
on the size spec's tracking spring while a finger is down and return on
its scale spring. Its pure equations are the shared contract:
`dynamicTargets` (the lift over the long side and the stretch of a
dragging finger), `withMovement` (the deformation of a moving surface,
`movementBounds` and `softClamp`) and the menu variant `menuTargets` with
its pulse channel `MorphFlexPulse`. A surface shows its drift times its
scale (`translation`). Options per control: `stretches`, `glows`,
`activationDelay`, a shared `MorphTimeline`. Passport: lens-and-flex.md.

Who runs on it:
- the interaction itself: glass buttons, bar capsules and the alert
  platter (lift, stretch, glow), the search field and the menu button's
  press (lift after a measured delay, no stretch);
- `withMovement` with `MorphFlexSpec.loupeForSize`: the selection lens
  (`MorphLensMotion`) and the knob / thumb lens (`MorphSmallLens`), each
  stepping its own `MorphFlexIntegrator` on a `MorphSubClock`;
- `menuTargets` and `MorphFlexPulse`: the open menu (`MorphMenuMotion`),
  which shows its targets directly while the finger is down and returns
  on the menu spec's scale spring.

Measured per control and kept apart: the tab bar's touch glow
(`MorphTouchGlowMotion`, its own rise lag and drag growth), the context
menu preview's hold growth, the menu's center drift (not multiplied by
its scale: the menu replays cannot tell the two apart).

`channel.dart` - `MorphChannel` ports UIKit's animatable channel: a
`MorphSpringState` whose targets switch between a tracking spring (a
finger down) and a settling spring, skip an unchanged target (the spring
switch included) and push the velocity by `stiffness x retargetImpulse x
change` on a changed one (`MorphFlexSpec.retargetImpulse`: the open
menu's 0.016). `MorphChannel.stepped` runs the spring on a clock of its
own advanced by `step` (the menu's pulse channel). Not reproduced, NEAR:
UIKit publishes channels at 60 Hz while tracking and 30 Hz while
settling, and lands a channel within about 1e-3 of its target on it;
morph evaluates every frame. Evidence: spec/lens-and-flex.md.

`glyph_scale.dart` - text under an animated transform. Wrap a label (or
any child holding text) whose scale, blur or fade animates in
`MorphGlyphs` (`morphVeiledGlyphs` when the control blurs and fades it);
never pick a drawing mode in a widget. `MorphGlyphPolicy` decides each
frame from what the drawing observes - its screen-scale velocity, a
cover blur from above, whether its content held still - between live
(rest, exact), snapped (slow, NEAR), raster (fast or covered, NEAR) and
the Android pyramid shader (veiled). The drawing reads its scale at
paint: keep it below the animating transform with no repaint boundary in
between (a boundary inside its child is fine). `MorphControlCapsule`
wraps its content, so capsule controls get it for free; a custom painter
uses `MorphGlyphTracker` (the lens copy does). A label that moves sideways
while its scale animates passes `aligned: true` (the tab bar's); a lens
copy keeps the aligned labels it replays on the grid and on whole device
pixels too.

`lens_driver.dart`, `lens_spec.dart`, `control_focus.dart`
(`MorphControlFocus`, `MorphFocusRing` in systemBlue, `MorphDisabled`),
`touch_listener.dart` (`delaysInScrollable`), `press.dart`
(`MorphPress`, `MorphPressTracker`, `MorphPressTarget`).

`menu_fusion_worker*.dart` - `MorphFusionWorker`, the one background
isolate pool in the package. The menu motion peeks its silhouette inputs
at the next three nodes of the clock's frame grid (a pure peek: time and
kicks are restored) and up to four isolates fuse them while frames
render.

- `MorphMenuFusion.outline` serves an arrived fusion only within
  `prefetchTolerance` (0.02 pt per input) and with the same grid and
  kernel; otherwise it fuses in the frame. A served outline is the exact
  law at a time a fraction of a millisecond from the frame's.
- Runs only in profile/release with isolates and at least six CPU cores
  (`prefetches`); debug,
  every test and the web never start it.
- Workers send plain parts (`MorphGlassOutlineParts`: samples + contour
  loops) because dart:ui's `Path` exists only on the root isolate.
- A motion that has only filled its body asks for the edge alone (no
  samples; it serves only a frame without the field); a field fusion
  serves both. When the motion's last fusion envelope ends,
  `MorphMenuFusion.settle` drops waiting requests and untaken fusions, and
  fusions still on a worker are dropped as they arrive.
- Rationale: glass-renderer.md "Menu fusion: the device gap".

## Public controls

One passport each: `MorphSegmentedControl`, `MorphTabBar`,
`MorphSearchTabBar` (their minimizing and bottom accessory:
tab-bar-minimize.md; `MorphTabBarChrome` wraps the bar's cached build, so
a parent's new accessory rebuilds the group, not the bar), `MorphSwitch`, `MorphSlider`, `MorphStepper`,
`MorphGlassButton`, `MorphMenuButton`, `MorphContextMenuRegion` (the
button menu's card on a context attachment, `MorphMenuAttachment`) /
`MorphSatellite` (its accessory), the bars (`MorphNavigationBar`, `MorphToolbar`,
`MorphNavigationStack`, `MorphScrollEdgeEffect`, push zoom), sheets
(`showMorphSheet` including zoom), alerts and action-sheet popovers,
`MorphSearchField` / `MorphSearchToolbar`, `MorphDatePicker`,
`MorphPageControl`, `MorphProgressView`, `MorphActivityIndicator`, the
inset grouped list (`MorphListSection` / `MorphSliverListSection` /
`MorphListRow`). `MorphGlassEffect` puts a glass button's resting glass
(regular or clear, tinted, optionally interactive) behind app content;
`MorphBadge` marks bar buttons and tabs. Capabilities added without a
device measurement (badges, subtitles, clear button press, list glyphs,
first segmented selection, interactive glass) say "not yet measured" in
their dartdoc and passport.
`MorphMenuSource` is the one way a widget becomes its own menu: it owns a
`MorphMenuController` and draws `MorphMenuLayer`, on a tap
(`MorphMenuTrigger.tap`, primary action) or a hold. `MorphMenuButton` is
its glass ellipsis configuration and `MorphGlassButton(menu:)` wraps its
capsule in it, passing its fill or tint as the source `color`. The source
takes the keyboard focus itself; `focusable: false` leaves it to a child
that takes it and calls `MorphMenuSource.open`. Bar items drive the
controller themselves.
`MorphNavigationScaffold` and sheets give their content the body text
style. `MorphSpring` is the engine's (`spring.dart`); `MorphFlexSpec`
ports `_UIFlexInteractionSpec` (lens-and-flex.md).

## Cross-cutting policy

Theming: explicit `appearance` > `MorphWidgetsTheme` (one appearance per
control) > the appearance class's `light`/`dark` table for
`morphBrightnessOf` (Theme, else MediaQuery platform brightness, else
light), with its accent replaced by `MorphWidgetsTheme.tint` (UIKit
`tintColor`). The theme is a Material ThemeExtension or a
`MorphWidgetsThemeScope` (no Material `Theme` needed); the nearer one
wins. A ThemeData is one brightness, so a dark appearance goes in the
dark theme. An explicit color parameter still beats the appearance.
`morphResolveAppearance` builds a tinted table once per (table, tint), so
a control comparing its resolved appearance by identity sees no change.

Naming: a look table (colors and metrics) is `Morph<Control>Appearance`
and every widget takes it as `appearance:` (UIKit precedent:
`UINavigationBarAppearance`); `*Style` names a variant enum as UIKit does
(`MorphProgressViewStyle`, `MorphScrollEdgeEffectStyle`,
`MorphAlertActionStyle`, `MorphBarButtonStyle`,
`MorphPageControlBackgroundStyle`). Color parameters use Flutter's
Cupertino names (`activeTrackColor`, `inactiveTrackColor`, `thumbColor`)
and the dartdoc names the UIKit property.

Libraries: `widgets.dart` exports the controls, their appearances and
the tunings they take as parameters (`MorphMenuTuning`,
`MorphBarMenuTuning`, `MorphPushZoomTuning`, `MorphZoomTuning`);
`motion.dart` the pure motion objects, the other measured tunings and
the layout types; `glass_painter.dart` the surface description a custom
`MorphGlassPainter` shades. Menu layout types are package-internal.

Typography: every label a control paints goes through
`MorphTypography.resolve(style)` (opsz, wght 510/590, CoreText tracking;
Apple platforms only, identity elsewhere). Caller `letterSpacing` /
`fontVariations` win. The result is complete (`inherit: false`), so no
label depends on an ambient `DefaultTextStyle` wherever it is mounted.
Details: typography.md.

Accessibility and input: each segment is a selectable button in a
mutually exclusive group; the tab bar carries tab bar / tab roles;
switch and slider take `semanticLabel`; slider adjust actions and arrow
keys move by `keyboardStep`; the stepper is two buttons carrying the
value. Every control is focusable with a systemBlue ring; Space/Enter
toggle, press or increment. RTL mirrors segmented control, tab bar,
switch and slider.

Disabled: a null `onChanged` / `onPressed` or `enabled: false` draws the
device's disabled look (states.md, test/disabled_test.dart):

- one 0.5 layer over segmented control, switch and slider;
- no change on stepper, page control and tab items (a disabled tab still
  swells the bar);
- content in tertiaryLabel on glass / menu buttons and bar items;
  prominent tint systemGray4;
- search field and date picker labels lose their glass / capsule.

Every change happens in one frame; disabled controls ignore touches.

Reduced motion: `reducedMotion` (from `MediaQuery.disableAnimations`) is
an approximation until Reduce Motion is recorded, off by default so
replays are unchanged.
