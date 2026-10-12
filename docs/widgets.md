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
`MorphTimeline` for every delay and `MorphSubClock` for every per-frame
filter. A control's ticker sleeps when its motion settles.

`MorphControlHost` hosts build in `buildControl`; `build` hands back the
last result while `buildsLike(oldWidget)` holds (every field the build
reads is equal, callbacks compared only by nullness), no dependency
changed, no `setState` ran and `buildInputs` (state the build reads, for
example the segmented control's selection) is unchanged. So a build must
never capture a widget callback; it calls `widget.onX` at event time. A
parent rebuilding a page of unchanged controls rebuilds none of them.

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

`flex_integrator.dart` - `MorphFlexIntegrator` ports UIKit's
`_UIVelocityIntegrator` (alpha 0.3 per frame). `MorphSubClock` is a
fixed-rate frame clock in motion time at `motionFrameRate`: every
boundary crossed is reported (at most 600 per advance), so the
deformation is identical on a 60 or 120 Hz host, under `timeDilation`
and under coarse test pumps.

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
uses `MorphGlyphTracker` (the lens copy does).

`lens_driver.dart`, `lens_spec.dart`, `control_focus.dart`
(`MorphControlFocus`, `MorphFocusRing` in systemBlue, `MorphDisabled`),
`touch_listener.dart` (`delaysInScrollable`).

`menu_fusion_worker*.dart` - `MorphFusionWorker`, the one background
isolate pool in the package. The menu motion peeks its silhouette inputs
at the next three predicted frame times (a pure peek: time and kicks are
restored) and up to four isolates fuse them while frames render.

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
`MorphSearchTabBar`, `MorphSwitch`, `MorphSlider`, `MorphStepper`,
`MorphGlassButton`, `MorphMenuButton`, `MorphContextMenuRegion` /
`MorphSatellite`, the bars (`MorphNavigationBar`, `MorphToolbar`,
`MorphNavigationStack`, `MorphScrollEdgeEffect`, push zoom), sheets
(`presentMorphSheet` including zoom), alerts and action-sheet popovers,
`MorphSearchField` / `MorphSearchToolbar`, `MorphDatePicker`,
`MorphPageControl`, `MorphProgressView`, `MorphActivityIndicator`, the
inset grouped list (`MorphListSection` / `MorphListRow`).
`MorphNavigationScaffold` and sheets give their content the body text
style. `MorphSpring` is the engine's (`spring.dart`); `MorphFlexSpec`
ports `_UIFlexInteractionSpec` (lens-and-flex.md).

## Cross-cutting policy

Theming: explicit `style` > `MorphWidgetsTheme` (a ThemeExtension, one
style per control) > the style class's `light`/`dark` table for
`morphBrightnessOf` (Theme, else MediaQuery platform brightness, else
light). A ThemeData is one brightness, so a dark style goes in the dark
theme. An explicit color parameter still beats the style.

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
