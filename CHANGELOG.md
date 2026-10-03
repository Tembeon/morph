# Changelog

Versions are git tags; pin one. Pre-1.0, minor versions may break API.

## 0.7.0 - 2026-10-02

The widget layer becomes the measured one. morph always meant to move
like iOS Liquid Glass; the controls measured from UIKit on iOS 27 -
every spring read from the platform's tuning or fitted to
frame-by-frame recordings of the real controls, and replayed against
those recordings in the tests - now ARE `package:morph/widgets.dart`,
and every hand-tuned physics recipe they supersede is gone. The engine
moves on UIKit's measured liquid morph too. BREAKING throughout; the removed
implementations stay reachable at the v0.1.0 - v0.4.0 tags (0.5.0 and
0.6.0 were never tagged).

- The measured controls: `MorphSegmentedControl` (+
  `MorphSegmentedStyle`) and `MorphTabBar` (+ `MorphTabItem`,
  `MorphTabBarStyle`) - one liquid selection lens on
  `MorphLensMotion`/`MorphLensTuning`, the segmented control selecting
  on release, the tab bar on contact with the whole bar swelling while
  pressed; `MorphSwitch` and `MorphSlider` on the small lens
  (`MorphSmallLens`, `MorphSwitchMotion`, `MorphSliderMotion`);
  `MorphStepper`; `MorphGlassButton` (+ `MorphGlassButtonMotion`) - a
  uniform lift of `1 + lift / width` whose lift and springs come from
  `MorphFlexSpec.forSize`, a lean after a finger that drags off, the
  touch glow; `MorphMenuButton` (+ `MorphMenuItem`, `MorphMenuStyle`,
  `MorphMenuMotion`, `MorphMenuTuning`, `MorphMenuBlob`) - a round
  glass button that becomes its own menu on UIKit's `liquidMorph`
  tuning (`MorphMenuMorphSpec`), opening on a tap's release or under a
  hold that slides onto a row. `MorphSpring` is UIKit's spring
  vocabulary (response, damping ratio), convertible to a motor
  `Motion`. The motion objects are pure functions of explicit time and
  work without their widgets.
- BREAKING: `package:morph/native.dart` is gone - the layer it held is
  `package:morph/widgets.dart` now, and every `MorphNative*` name lost
  its infix (`MorphNativeTabBar` -> `MorphTabBar`, `MorphNativeSpring`
  -> `MorphSpring`, ...); `MorphNativeMorphSpec` is
  `MorphMenuMorphSpec`.
- BREAKING: removed `Tug`, `MorphPillHost`, `MorphSquash`,
  `SpringButton`, `ChaseSpring`, `morphPressGrowth`, and the popover
  menu `showMorphMenu` with its `MorphMenuItem` - the name now belongs
  to `MorphMenuButton`'s rows (`title`, `icon`, `destructive`,
  `onSelected`). Their replacements are the measured controls above:
  `MorphGlassButton` for presses, `MorphTabBar` and
  `MorphSegmentedControl` for selection pills, `MorphMenuButton` for a
  button that becomes its menu.
- BREAKING: `MorphContextMenuRegion.pressGrow` is replaced by `lifts`.
  The held hero lifts the way a glass button does - a uniform scale by
  `MorphFlexSpec.forSize` for its size, the press on the tracking
  spring, the release on the scale spring - instead of on the Tug
  spring's fixed pixel growth. Everything else about the region is
  unchanged.
- Example: the gallery is the example app. The tour of phone-mockup
  chapters, the playground sandbox and its lab chrome are removed (they
  stay at the v0.4.0 tag); `example/lib/main.dart` runs the measured
  gallery (`example/lib/gallery/`), one page per control, so a plain
  `flutter run` opens it. `--dart-define=MORPH_AUTODEMO=true` walks
  every gallery page with synthetic gestures and exits;
  `--dart-define=MORPH_BENCH=true` still runs the release bench, now on
  a card of its own. The web build draws frosted glass: the liquid
  glass renderer sits behind a conditional import, so the web example
  builds without that package.
- The glass seam: `MorphGlass(painter:)` installs a `MorphGlassPainter`
  whose `buildSurface` renders every glass surface of the controls below
  it - track, lens, knob, thumb, button, bar, menu (`MorphGlassKind`) -
  as a widget placed at the surface's bounds each frame, so a painter can
  sample the backdrop or run a shader; `buildLayer` receives all the
  surfaces of one control together with the content drawn over them
  (segment labels, tabs), so a painter can share one backdrop sample,
  fuse neighbors (a menu and its button) or show the content through a
  lens. `MorphGlassSurface` carries the
  deformed shape, the flat color as a tint, the brightness, the lift and
  the lens's `MorphGlassOptics` (UIKit's refraction values, `small` and
  `large`). Without a painter the controls draw their flat fills as
  before.
- Example: the gallery draws every control in liquid glass - a
  `LiquidGlassRendererPainter` over whynotmake-it's Flutter GPU
  renderer (`liquid_glass_renderer` 1.0.0-dev.1, Apache-2.0, vendored
  under `example/third_party/` as a path dependency of the example only;
  the package stays shader-free), installed at the gallery root. The
  Glass renderer page edits one session-wide settings model - renderer
  (liquid, frosted, flat), material preset, blur, refraction, rim light,
  tint, frost on controls, fallback glass, appearance, right to left,
  disabled - and every page follows at once. Resting lenses, knobs and
  thumbs stay opaque platters and turn into glass as they lift; a lifted
  lens magnifies what it covers by `1 + 0.16 * lift`. The iOS and macOS
  runners enable Impeller and Flutter GPU; the Pages workflow builds on
  Flutter 3.47.2 and drops the renderer from the web build, whose
  shader compiler rejects its fragment shaders.
- Theming: every control takes a `style` (`MorphSwitchStyle`,
  `MorphSliderStyle`, `MorphStepperStyle`, `MorphGlassButtonStyle`
  join `MorphSegmentedStyle` and `MorphTabBarStyle`), each with `light`
  and `dark` tables from the iOS system colors. Resolution is the
  explicit style, then the `MorphWidgetsTheme` ThemeExtension, then the
  table for the ambient brightness (the Theme's, else the platform's).
  BREAKING: the `style` parameters and the switch, slider and stepper
  color parameters are nullable now; an explicit color still wins over
  the style.
- Accessibility and keyboard: each segment is a selectable button in a
  mutually exclusive group; the tab bar carries the tab bar and tab
  roles; the switch and slider take a `semanticLabel`; the slider's
  adjust actions and arrow keys move it by `MorphSlider.keyboardStep`;
  the stepper reads as two buttons (`decrementLabel`,
  `incrementLabel`) carrying the value. Every control is focusable and
  draws a systemBlue focus ring; Space and Enter toggle the switch,
  press the glass button and increment the stepper, the arrow keys move
  the segmented and tab bar selections.
- Disabled: BREAKING: `onChanged` is nullable on `MorphSegmentedControl`
  and `MorphTabBar`. A disabled control ignores input and dims to its
  style's `disabledOpacity` (0.5 for the switch and slider, 0.35 for
  the rest - not yet measured on a device).
- Right to left: the segmented control, tab bar, switch and slider
  mirror in an RTL context; the stepper keeps minus on the left.
- Text scale: segment labels follow the text scale up to 1.4 and size
  by the wider of their two styles; tab labels follow it up to 1.25 and
  the tabs widen to fit the widest label.
- Reduced motion: `reducedMotion` on `MorphLensMotion`,
  `MorphSmallLens` and `MorphGlassButtonMotion`, set by the widgets
  from `MediaQuery.disableAnimations`: the lens and the knob travel, the
  button glows, but nothing lifts, deforms, leans or swells. An
  approximation until Reduce Motion is recorded on a device; off by
  default, so the fixture replays are unchanged.
- BREAKING: the engine's motion is measured. `MorphMotion.liquid` -
  UIKit's liquid morph progress spring, open `MorphSpring(0.35, 0.75)`,
  close `MorphSpring(0.49, 0.80)` - is the default everywhere a motion
  resolves (`MorphController`, `showMorph*`, `MorphTheme` unset). The
  open now overshoots slightly (about 3 percent), as UIKit's does; the
  close still dips below zero for the handoff latch. Removed the
  hand-tuned presets `MorphMotion.slow`, `normal`, `glass` and `fast`;
  `glacial` is now `liquid` with every response times five (a magnifier
  for the eye) and `instant` keeps its reduced-motion contract.
  `MorphMotion.values` is `[liquid, glacial, instant]`.
  `MorphMotion.springs(open:, close:)` builds a profile from
  `MorphSpring`s and exposes them as `openSpring`/`closeSpring`;
  `openMotion`/`closeMotion` are getters now. The public constructor
  for custom profiles stays.
- BREAKING: `MorphSpring` lives in the engine
  (`package:morph/foundation.dart`; `widgets.dart` still re-exports it).
- BREAKING: the landing bump is gone - UIKit's landing is the close
  spring's own undershoot, nothing added on top. Removed
  `MorphTag.bumpScale`/`bumpRecoil` and the squash-and-recoil transform
  the tag played after the handoff latch, `MorphTheme.bumpScale`/
  `bumpRecoil`, `morphLandingBump`, `morphBumpedRect`,
  `MorphFlight.impactAxis`, `MorphMotion.closeVelocityHint` and
  `morphCloseHintScale` (a close from rest now starts still). The
  handoff latch itself is unchanged: the shuttle still hands the surface
  back on the close spring's first zero crossing, and
  `MorphFlight.isLanding` still marks the span between the latch and
  the final rest.
- `MorphTargetSpec.vessel(rectFor:, repaint:)`: a target whose content
  draws the whole morph itself - laid out over the entire overlay in
  overlay coordinates, at full opacity, no surface, shadow, source ghost
  or crossfade, taking pointers while the flight is open or opening -
  with everything else a flight provides (overlay choice, modal barrier,
  pop layering, focus trap, events, source-lost dissolve). The scrim's
  dismiss label no longer requires `MaterialLocalizations`.
- BREAKING: `MorphMenuButton` flies on the engine: its menu is a
  `MorphFlight` on a vessel target with the measured progress spring,
  the scrim at zero opacity, so the overlay choice, Esc and back, focus,
  `MorphFlight.events` (`onOpen:` hands out each flight) and the
  dissolve of a removed button come from the engine; its own overlay
  entry, history entry and clock are gone. It uses an ambient
  `MorphScope` or brings its own. The menu is hit-testable from its
  first frame and places itself clear of the keyboard.
  `MorphMenuMotion` reads its progress from a `MorphMenuProgress`
  (`MorphMenuProgress.spring` for a pure function of time). The kicks
  are no longer replayed from recorded tables: the menu shape's kick is
  a spring driven by the progress spring's velocity while opening and
  struck by the close (`openKickSpring`/`openKickGain`,
  `closeKickSpring`/`closeKickImpulse`/`closeKickDelay`/
  `closeKickReach` on `MorphMenuTuning`), the button shape's kick a
  spring driven by the closing velocity (`sourceKickSpring`/
  `sourceKickGain`), with per-height amplitudes; removed
  `MorphMenuTuning.kickHandoff`.
- The tab bar's scrub is measured (recaptured on an iPhone 16 Pro, iOS
  27.0.1). A press on the selected tab lifts it `pressDelay` after the
  touch (50 ms; the segmented control's 40 ms). The lens then follows
  the finger's travel since the touch times `MorphLensTuning.dragGain`
  (1.013 for the tab bar, 1 for the segmented control) on the follow
  spring `MorphSpring(0.271, 0.803)` (was 0.196/0.903), and past the
  first and last tabs it meets a tight rubber band (4.55 px, stiffness
  0.95) instead of a clamp. The 1.055 - 1.064 gain the recording shows
  on screen is that gain times the bar's own press swell, which scales
  the lens around the bar's center. The release picks the tab nearest
  the finger; the travel there and the landing start `releaseDelay`
  (30 ms) after the touch-up, the travel on the tab travel spring
  carrying the scrub's velocity, which also accounts for the short
  return from a rubber band. BREAKING: `MorphLensTuning.rubberBand` is
  a required (limit, stiffness) record and `pressDelay` is required;
  `dragGain`, `pressHang` and `releaseDelay` are new.
- A tap on the already selected segment or tab lifts it in place after
  `pressDelay` and lands no earlier than `pressHang` (0.25 s) after the
  touch, or `releaseDelay` after the release of a longer hold. The tab
  bar lens that seems to drift outward while held is the bar's swell;
  the lens itself does not move.
- BREAKING: `MorphSwitch` decides a drag the way UIKit does: the drag
  commits when the knob's target reaches the far end and uncommits only
  when it returns to the starting end, the track color following each
  change after `MorphSwitchMotion.colorDelay` (90 ms); the release keeps
  the committed state if the drag ever committed and toggles like a tap
  otherwise. Crossing the middle no longer decides anything. The 5 px
  dead zone now applies only to a drag that starts moving within
  `deadZoneWindow` (0.1 s) of the touch; a finger held still that long
  drags the knob directly.
- BREAKING: `MorphSlider` glides on after a moving release as the
  device does: the value keeps the release speed for
  `MorphSliderMotion.glideCoast` (0.04 s), then the speed decays
  exponentially with `glideDecay` (0.083 s), stopping at the ends - a
  release at speed v travels 0.123 s times v further. Removed
  `glideSpring`, `glideDelay`, `flingTime` and `flingThreshold`. The
  widget still measures the release speed with Flutter's
  `VelocityTracker`.
- A tap on a `MorphMenuButton` while its menu closes re-opens the same
  morph on the touch-up, the progress reversing onto the open spring
  with its velocity. For that the scrim of a `MorphTargetSpec.vessel`
  takes pointers only while the flight is open or opening, like its
  content: a closing vessel lets touches through to the page.
- BREAKING: skin pieces land without a bump too: removed
  `MorphPiece.bumpScale`/`bumpRecoil` and the skin's landing squash of
  a piece's mass and content; a piece's content transform is its
  `MorphPieceChannel` alone. The debug assert that a manual `MorphTag`
  inside a piece zero its own bump went with it.
- BREAKING: removed `MorphReveal`, the staggered unfolding of content
  blocks on sub-ranges of the flight's spring. Flight content arrives
  with the surface, as UIKit's does; `MorphContextMenuRegion`'s
  satellites no longer unfold separately.
- BREAKING: removed the surface adapters `MorphSurface` (Material plus
  InkWell rendered from `MorphTag.specOf`) and `MorphTapTarget`. Use
  `MorphGlassButton` for a button that is a morph source, or render the
  surface from `MorphTag.specOf` with your own design system and a
  `GestureDetector`; the `MorphTag.specOf` contract is unchanged.
- BREAKING: `MorphSlider` begins a drag after
  `MorphSliderMotion.panSlop` = 11 pt (was 10), fitted to the slow
  drags recorded on an iPhone 16 Pro and in the simulator; the drag still maps the finger onto the
  value by the full track width, which the recordings confirm (fitted
  divisor 298 - 302 pt for a 300 pt track, 199 - 200 for 200). The
  extra thumb lag the device showed was the later start, not a smaller
  gain.
- Example: the opening scene keeps its Motion and Interrupt layers (the
  Landing layer is gone) and its compose button is a `MorphGlassButton`;
  the playground lost its landing and close-kick knobs; dialog, sheet,
  player and lesson-page content arrive without a cascade; chapter
  cards, album cards and the mini bar render their surfaces from their
  spec with a plain `GestureDetector`, the filter chips tap through one.
- BREAKING: the skin merges by the law iOS 27 Liquid Glass draws,
  measured on an iPhone 16 Pro (UIKit `UIGlassContainerEffect` and
  SwiftUI `GlassEffectContainer` agree). The smooth minimum's width at
  each point is `blend * (1 - dot(na, nb)) / 2`, where `na` and `nb` are
  the unit normals of the two surfaces: facing surfaces blend over the
  full width, edges running side by side not at all, so aligned tops
  and bottoms of fused pieces stay straight instead of lifting by a
  quarter of the blend. `blend` is the glass container's spacing, 1:1 in
  logical px: two facing surfaces lean toward each other below a gap of
  `blend` and touch at `blend / 2`. Replayed against the device's
  silhouettes (pairs of capsules and circles, spacing 10 - 80, gaps 40
  to -5 pt) the traced skin stays within 0.17 - 0.32 pt rms, the
  screenshots' own noise floor. Removed the presets
  `MorphSkinStyle.geometric` and `goo`: they were taste values with no
  measurement behind them. `MorphSkinStyle.subtle` (8) is SwiftUI's
  default spacing and is now the builtin a skin without a style or a
  theme falls back to (was blend 24). `MorphPieceChannel.birthScale`
  (0.2) and `birthSpring` (`MorphSpring(0.492, 0.711)`) are how a Liquid
  Glass shape is born and leaves, fitted to SwiftUI's `glassEffectID`;
  the living-layout chapter's chips are born and removed on them.
- The controls share a scroll view the way UIKit's do
  (`delaysContentTouches` with `touchesShouldCancel` false for a
  control). Every touch enters the gesture arena on contact and the
  control owns it once held for 150 ms, or, for the switch, slider,
  segmented control and tab bar, once it drags past the touch slop
  along the control's own horizontal axis - unless an enclosing
  scrollable runs along that axis too, where the delay alone decides.
  An owned touch stays the control's however it moves: a held glass
  button leans and can be dragged off without the list scrolling, a
  menu button's hold slides onto its rows, a stepper repeats. A quick
  swipe that the list wins first cancels the control's touch, and a
  slider drag taken over this way returns to the value it started from.
  The press feedback still starts on contact. `MorphContextMenuRegion`
  keeps its tap and long press and adds one claim: a press that stayed
  still for 150 ms and then wanders is no longer taken by the list.
  Disabled controls leave their touches to the gestures around them.
- `MorphSlider` at its ends, measured on an iPhone 16 Pro (iOS 27.0.1)
  with 200 and 260 pt sliders dragged slowly, fast and from a thumb
  resting near or at an end, 40 - 80 pt past either end and back: the
  native thumb does not catch up with the finger. The value maps the
  finger by the full track width all the way, so it reaches an end with
  the finger leading the thumb by the slop plus 37 pt times the travel
  that was left (30 pt from the middle, 49 pt from the far end); only
  past that point does the track stretch, on the rubber band fitted in
  the simulator (13 pt, 0.74, within 0.35 pt on the device), and on the
  way back the value moves again where it reached the end, with no
  re-basing. The model already followed that law; the 13.5 pt slop it
  started from left its thumb 2.5 - 3 pt behind the device's through a
  slow drag, which the 11 pt slop closes (thumb within 0.4 - 1.9 pt rms
  of the recordings on slow drags, 3.4 on fast ones).
- `MorphMenuButton` traced on the iPhone 16 Pro (profile build, every
  frame's painted shapes and FrameTimings, against the recorded UIKit
  menu): the menu now draws from its own measured progress spring on the
  clock its kicks run on (it read the flight's controller, which starts a
  frame late at elapsed 0: the first menu frame was held at the button
  and the kick ran 8 - 17 ms ahead of the shape - open kick error vs
  UIKit 1.14 pt rms / 3.7 max, now 0.27 / 1.0), and the end of a close
  plays out on the button: the engine latch used to drop the menu at the
  close's zero crossing while the button shape was still kicked 4 pt
  off, a snap at the end of every close, where UIKit keeps its morph
  until the kicks ring out ~0.85 s later; the button now draws both
  shapes until the motion rests (its close ends when the progress and
  both kicks rest). The button's look blurs out as it fades (4 x
  progress, as UIKit's), the rows are built once per menu instead of
  every frame, the union is one path instead of a `Path.combine` per
  frame, and each crossfade draws through one layer; the resting button
  draws its glyph without a layer, so the glass of resting buttons stays
  in one backdrop group (an extra alpha-255 opacity layer per button
  cost a glass painter ~10 ms of raster per frame on the device).
- `MorphMenuButton` filmed against the native menu (screen recordings of
  the iPhone 16 Pro at 60 fps, both sides on the same light screen, the
  native side paired frame by frame with the probe's layer data): the
  ellipsis no longer rides the whole crossfade. It stays on the button
  shape, widens to 1 + 2.5 x progress while it blurs, and is gone by
  progress 0.42 - two to three frames into an open - and returns only
  as the close nears the button (`lookFadeStart`/`lookFadeEnd`,
  `lookStretch`); before, it faded over the whole progress and its blur
  sampled with a clamp tile mode, so a grey square of smeared glyph
  hung over the menu's top edge for most of every open and close (the
  blurs now use a decal tile mode). The menu content is no longer a
  miniature of the menu: it stays near its final size (`contentScale` =
  1 - 0.5 x (1 - progress) + 1.3 x kick / menu height), centered on the
  menu shape that reveals it, blurs on screen by 8 x (1 - progress) +
  6 x kick / menu height and fades in over progress 0.53 - 1
  (`contentFadeStart`/`contentFadeEnd`, `contentShrink`,
  `contentKickScale`, `contentBlur`, `contentKickBlur`); both fades read
  the progress spring 15 ms ahead (`fadeLead`), as the film shows the
  native fades leading the shapes in both directions. New
  `MorphMenuMotion.contentScale`, `contentRect`, `buttonLookStretch`.
- `MorphSlider` filmed against the native UISlider (screen recordings of
  the iPhone 16 Pro, light and dark, the native side paired with the
  probe's layer rows): the colors are iOS 27's - fill systemBlue
  0xFF0088FF light / 0xFF0091FF dark (was 0xFF007AFF / 0xFF0A84FF), the
  track black or white at 10 percent (was a tinted 16 / 32 percent
  gray). The fill is its own rounded bar ending under the thumb center
  (a square clip before, visible through the lifted clear thumb) and
  within `MorphSliderMotion.fillRamp` (0.0198) of either end it runs
  out to the track end: a full slider is filled to its rounded end, an
  empty one shows no fill (before, 18.5 pt of track stayed unfilled at
  1 and 18.5 pt filled at 0; replayed on 300 and 200 pt sliders within
  0.15 pt). NEW: stepped sliders, `MorphSlider.ticks` (UIKit's
  `numberOfTicks`): 3 pt dots 8.5 below the track at the thumb's stops
  (`MorphSliderStyle.tickColor`), the reported value snaps to the
  nearest stop, the thumb rests near a stop and crosses to the next on
  an S-curve (`tickCurve` 4.5, held within `tickHold` 0.72 of the half
  step, followed on `tickFollowSpring` 0.03 / 1), settles on its stop
  0.035 s after the release on `tickReleaseSpring` 0.115 / 1 and never
  glides; arrows and adjust actions move one stop. New
  `MorphSliderMotion.position`, `fillEnd`, `tickCenters`.
- NEW: iOS 27 bars, measured on the iPhone 16 Pro (iOS 27.0.1) and the
  iOS 27.0 simulator with the probe's new `nav` scene (tuning read live:
  `GlassContainerToolbarPTSettings`, `PocketSettings`,
  `_UIFluidNavigationTransitionsSpec`, `_UINavigationBarTitleTransitionSpec`).
  `MorphToolbar` (floating capsules 48 tall, 28 from the sides and the
  bottom) and `MorphNavigationBar` (54 below the status bar, capsules 44
  tall, 16 from the sides, centered title kept 12 from the buttons) are
  rows of `MorphBarButtonGroup`s - adjacent `MorphBarButton`s share one
  glass capsule, groups float 12 apart, a press lifts the whole capsule
  on the glass-button model (recorded: 1 + 16/width, as `MorphGlassButton`).
  Every change of the items animates with `MorphBarMotion`, the toolbar
  item transition UIKit runs for `setToolbarItems(_:animated:)` and for
  the bar buttons of a push: capsules move and resize on 0.416 / 0.75,
  swell by up to 16 pt (20 percent) and settle height first, new capsules
  bud out of their neighbour's edge at a fifth of their size, items grow
  in from 0.2 with a 10 pt blur and leave the same way (replayed: device
  capsules 1.0 pt rms center, 1.6 width, 0.8 height).
- NEW: `MorphScrollEdgeEffect` (soft / hard) - the scroll edge effect
  that replaced bar backgrounds, as UIKit's own layers draw it: no
  progressive blur stack, one light blur (1.5 soft, 2 hard) over the band,
  the content faded 50 percent (60 dark) toward what lies behind it, the
  hard style adding saturation 1.25 + 3 percent brightness and a 1 px
  hairline at 10 percent; the soft band reaches 40 pt past the bar and its
  fade dissolves from 34 percent of the band. One backdrop blur per edge.
- NEW: `MorphLargeTitle`, `MorphLargeTitleScrollPhysics`,
  `MorphNavigationTitleMotion`: the large title scrolls with the content;
  once it is under the bar the inline title rises 15 pt, sharpens from a
  4 pt blur and fades in on a critically damped 0.45 s spring (leaves on
  0.7 s) with the edge effect on 0.35 s; a scroll set without a finger
  switches at once; a drag released with the title halfway snaps it out
  or under (replayed against simulator drags: title opacity <= 0.06 rms).
- NEW: `MorphNavigationStack` / `MorphNavigationRoute` /
  `MorphNavigationScaffold`: one shared bar and toolbar whose glass
  morphs from screen to screen, a back button labelled with the previous
  title, pages on `_UIFluidNavigationTransitionsSpec` (push 0.3 critically
  damped from full speed, the page below at 30 percent parallax; edge
  swipe 1:1 and release on the interactive 0.3 / 0.85 spring).
- Sheets: `presentMorphSheet` pushes a `MorphSheetRoute` that moves
  like iOS 27's UISheetPresentationController (`MorphSheetMotion`,
  `MorphSheetDetent` `.medium` / `.large` / `.height` / `.fraction`,
  `MorphSheetTuning`, `MorphSheetStyle`, `MorphSheet.of` /
  `MorphSheet.scrollControllerOf`). Measured on the iOS 27 simulator
  (iPhone 16 Pro, XCUITest touches and programmatic transitions): every
  transition is UIKit's CASpringAnimation of stiffness 333.3 / damping
  36.5 (response 0.344 s, critically damped; 0.06 pt rms); the medium
  detent is 0.56 of the maximum UIKit hands a detent resolver; below the
  large detent the sheet floats as the full-width sheet scaled to keep 8
  pt off the sides and the bottom (unscaled corners 38 top, display
  radius minus 8 bottom), and docks through one transform interpolated
  by the height's progress toward the large detent, its systemBackground
  fading in by the same fraction; dimming is black at 0.2 (scaled by
  the progress past an undimmed detent). Touch: a floating sheet swells
  by 0.85 percent on a 0.2835 / 0.70 spring 28 ms after contact; a drag
  moves the height point for point (nothing above the largest detent,
  a slide below the smallest), the release settles 25 ms later on the
  detent nearest to the height projected by 0.143 s of the finger's
  velocity, carrying twice that velocity into the spring; below the
  smallest detent a projected slide past half the visible height or a
  flick faster than 1000 pt/s dismisses (a flicked sheet leaves on
  0.352 / 0.79); a tap on the grabber band cycles the detents 50 ms
  after the lift; a scrollable handed `MorphSheet.scrollControllerOf`
  expands the sheet before it scrolls and moves it down from its top,
  as UIKit's do. Replayed in `sheet_test` and `sheet_drag_test`.
- `MorphPageControl` (+ `MorphPageControlMotion`,
  `MorphPageControlTuning`, `MorphPageControlStyle`,
  `MorphPageControlBackground`): UIPageControl's dots (9.67 pt
  indicators on a 17.67 pt pitch, 25.67 pt tall), a tap on either half
  stepping on the lift, the platter fading in 0.2 s into a resting touch
  (0.106 / 0.97 in, 0.10 / 1.0 out 20 ms after the lift), a scrub
  following the nearest dot, and UIPageControlProgress's capsule (27.33
  pt, its old fill fading on 0.381 / 0.963, widths changing on 0.398 /
  0.927).
- `MorphProgressView` (+ `MorphProgressMotion`, `MorphProgressStyle`):
  UIProgressView's animated change runs linearly for as many seconds as
  the progress changes, at least 0.2 s when the fill appears or
  disappears (an empty bar shows no fill; the fill is never under 8 pt),
  additive like UIKit's. `MorphActivityIndicator` (+
  `MorphActivityIndicatorFrames`): eight spokes, sixteen images per 0.8 s
  turn (`_UIActivityIndicatorSettings.fullLoopDuration`), the head and a
  four-spoke tail read from the rendered pixels.
- `MorphContextMenuRegion` calibrated against UIContextMenuInteraction:
  BREAKING (behavior) the default `holdDuration` is UIKit's measured
  0.78 s (was 0.5 s), and the held hero lifts to UIKit's preview size -
  the smaller of 15 percent and 26 points (1.15 at 120 pt, 1.087 at 300
  pt) - instead of the glass button's lift.
- `MorphContextMenuRegion` grows the held hero as UIKit grows its
  preview before the menu (iPhone 16 Pro, 60 x 40 to 300 x 200
  previews, 28 holds): BREAKING (behavior) instead of lifting on
  contact, the hero scales by `1 + growth / longest side`, where the
  growth (`measuredHoldGrowth`, the same points for every size) is 0
  until 0.184 s, 32 pt/s to 8 pt at 0.434 s, then 20 pt/s to 15 pt;
  the flight takes off from the grown hero, and a release before the
  commit point drops it at once. NEW: a release past
  `measuredCommitDuration` (0.42 s; 0.400 s cancelled, 0.433 s opened)
  opens the menu, and the child's tap no longer fires; the default
  `gap` is UIKit's 16 pt (`measuredMenuGap`, was 8); the satellites
  unfold out of a blob of 0.4 times the hero at its center and retract
  into it on the way home (`measuredRetractScale`). The open preview's
  lift (`measuredLiftScale` / `measuredLiftPoints`) is read along the
  longest side (80 x 160 opens at 92 x 184). The probe gained
  `testW2CtxGrowth` / `testW2CtxCommit`; fixture
  `ios27-device/context_menu/growth.json`.
- NEW: alerts and action sheets (iOS 27 simulator and iPhone 16 Pro,
  2026-10-03):
  `showMorphAlert`, `showMorphActionSheet`, `MorphAlertRoute`,
  `MorphAlertAction` (+ `MorphAlertActionStyle`), `MorphAlertTextField`,
  `MorphAlertStyle`, on `MorphAlertMotion`. The alert fades in with its
  0.2 dimming while it shrinks from 1.199, and fades out at its size, on
  UIAlertController's CASpringAnimation (522.35 / 45.71: 0.275 s,
  critically damped; scale 0.0005 rms, dimming 0.008 rms); 320 pt wide,
  radius 34, 48 pt capsule buttons 8 apart, two in a row with cancel
  first, more in a column with cancel last; a touch lifts the whole
  platter like a glass button of its size (0.09 - 0.25 pt rms) and the
  pressed button's fill drops to 40 percent; a chosen action's handler
  runs once the alert is gone. An action sheet with a source is a glass
  popover (`MorphPopoverMotion`: scale from 0.01 about the arrow tip and
  fade on 0.345 / 0.80 in, 0.373 / 0.85 out, 0.005 rms) placed by
  `morphPlacePopover` (15 of 15 UIKit placements), without its cancel
  action, which a tap outside runs at once; without a source it is an
  alert, as on iOS 27 iPhones.
- NEW: the search field (iOS 27 simulator and iPhone 16 Pro):
  `MorphSearchField` (+
  `MorphSearchFieldStyle`), `MorphSearchToolbar` and
  `MorphSearchTabBar` on `MorphSearchMotion` / `MorphSearchTuning`. The
  bottom search bar widens to 8 pt from the sides and rises 10 pt above
  the keyboard as the toolbar's buttons swell to 1.2 and fade where they
  stand and a close button arrives, all on SwiftUI's search transition
  spring 0.25 / 0.9 starting 0.067 s after the change (0.7 - 2 pt rms
  over 300 pt of travel); a touch lifts the field like a glass
  button 0.05 s after contact. A tab bar's search tab turns into the
  field: the bar shrinks into a circle with the selected tab's glyph
  while the search circle stretches into the field, on 0.276 / 0.80
  fitted to video (1.7 pt rms on the glass edges).
- NEW: the compact date picker (iOS 27 simulator): `MorphDatePicker` (+
  `MorphDatePickerMode`, `MorphDatePickerStyle`) on
  `MorphDatePickerMotion` / `MorphDatePickerTuning`. The label opens its
  calendar (or the hour and minute wheels) in an overlay that grows out
  of the label's center from 0.2 while its box grows from 50 pt and it
  fades in, on 0.32 / 0.80, and closes on 0.348 / 0.86 (fitted, 0.002
  rms); `morphPlaceDatePicker` hangs it 6 pt below the label's center
  toward the leading side (5 of 5 placements). The calendar turns months
  on a 0.3 s sine ease; the label dims under the finger on a 0.47 s
  CABasicAnimation and takes the accent color while open.
- DEVICE RECAPTURE (2026-10-03 morning, UI automation back on the iPhone
  16 Pro): every finger-driven measurement the night could only take on
  the simulator was retaken on the device; replays of the device
  recordings sit next to the simulator ones. Where the device differed
  beyond noise, the device won:
  - navigation edge swipe: a page released without a flick pops from
    `MorphNavigationTransition.popDistance` 0.3 of the width out (0.27
    returns, 0.32 pops; was 0.5, unmeasured), a flick decides past
    `popVelocity` 1.06 widths/s either way (was 1), a returning page
    leaves carrying 2.9x the release speed (`cancelVelocityScale`,
    fitted 2.7 - 3.1) and a popping one starts from rest. The settle
    spring 0.3 / 0.85, the large-title snap (25 pt back, 30 pt under),
    the inline title and edge effect springs and the bar item lift
    replay the device unchanged.
  - search: `MorphSearchToolbar` holds a focus until the keyboard starts
    to rise (UIKit's field starts 0.015 s after the keyboard's first
    frame, 0.17 - 0.19 s after the tap; `MorphSearchTuning.keyboardLag`,
    with `keyboardWaitLimit` 0.3 s as a guard when no keyboard comes).
    `MorphSearchTabBar` waits the same way and rises and falls on its
    own `tabFocusSpring` 0.3 / 1.0 (0.2 - 0.9 pt rms over 308 pt; the
    toolbar's 0.25 / 0.9 leaves 12), 0.07 s after the keyboard
    (`tabKeyboardLag`) and 0.04 s after the close tap
    (`tabUnfocusDelay`). `MorphSearchMotion.focus` / `unfocus` take a
    `delay`, and its constructor a `spring`.
  - alerts: the lifted platter follows a dragging finger a quarter as far
    as a glass button (`MorphAlertTuning.platterPull` 0.25) and stretches
    0.6 as much (`platterStretch`): 0.06 pt rms of lean and 0.1 - 0.2 pt
    of size against 0.7 - 1.3 and 1 - 4 before, through the new
    `MorphGlassButtonMotion.pull` / `stretch`. An action sheet popover
    no longer lifts under a touch (the device holds it still).
  - page control: the platter fades in after 0.193 s on a critically
    damped 0.100 s spring and out 0.032 s after the lift (120 Hz rows,
    0.013 - 0.017 rms; the 60 Hz simulator read 0.2, 0.106 / 0.973 and
    0.02).
  - confirmed unchanged on the device: sheet detent projection 0.143 s,
    the half-sheet dismissal rule, release gain 2, flick dismissal
    0.352 / 0.79 x 0.6, the touch swell 1.00854, the grabber tap and the
    2 percent stretch below the smallest detent (identical numbers);
    alert lift; the context menu's 0.78 s hold (0.768 - 0.797 s on the
    device), preview lift min(15 percent, 26 pt) and 16 pt menu gap;
    the slider's 11 pt pickup (finger lead within 0.7 pt of the model at
    every end).
- glass audit against the dark UIKit references: only surfaces that are
  Liquid Glass in iOS 27 are handed over as glass. `MorphGlassSurface`
  gains `glass` (false for the segmented, switch and slider tracks and
  the stepper, which are plain fills) and `MorphGlassPainter` gains
  `buildFill`, which draws such a surface flat; the default `buildLayer`
  routes plain surfaces there, and the stepper calls it instead of
  `buildSurface`. The dark tab bar's resting platter is darker than the
  bar, as on the device (`0xB5000000`, was a light 14 percent white).
  In the example's liquid painter a lifted lens, knob or thumb is clear
  glass that refracts what lies under it - the tab bar lens bends the bar
  glass and the magnified labels beneath it instead of covering them -
  and only a menu fuses with its button.
- BREAKING (painters): `MorphGlassPainter.buildLayer` takes
  `contentSlots`, the boxes of the content's items (segments, tabs, bar
  items) in the layer's coordinates; an override must accept the
  parameter. A painter that magnifies content under a lens scales each
  item about its own slot, so a label under a dragged lens stays still
  and only the lens window moves, as in UIKit. The example's liquid
  painter used to scale about the lens center, so the label slid along
  with a dragged lens.
- Navigation (owner's iPhone pass on the gallery's Navigation page):
  - `MorphNavigationStack` owns the pops of its own screens: its
    navigator sits under a `NavigatorPopHandler`, so while it can pop,
    the enclosing route reports `doNotPop` - its Cupertino edge swipe
    and predictive back stay off, and the system back, `maybePop` on the
    enclosing navigator and an Android back pop the stack's top screen;
    at the stack's root they reach the enclosing route as before. An
    edge swipe on a pushed screen used to be won by the enclosing
    `MaterialPageRoute` and left the whole stack.
  - the bar morphs on a push as it does on a pop: a pushed screen's
    configuration arrives one frame after the push, and the stack used
    to show an empty bar for that frame, so capsules died and were
    reborn and the toolbar remounted. The stack now keeps the previous
    screen's bar until the pushed one publishes (or its first frame
    passes).
  - BREAKING: a bar group without an `id` is identified by its place
    counted from the bar's edge, so the outermost trailing capsule
    morphs into the outermost one (as the device does on a push); the
    stack's back button is no longer a separate `morph.leading` group
    and morphs out of the leading capsule it replaces.
  - NEW: `MorphNavigationBarDrift` (`MorphNavigationBar.drift`,
    `MorphBarMotion.setDrift`): during an interactive edge swipe each
    capsule the destination bar also has leans
    `MorphNavigationTransition.barDrift` = 0.5 of the page's progress
    toward its place there, a pure function of the page's position (a
    cancelled swipe leans back with the returning page, a committed one
    hands the leaning capsules to the item transition without a jump).
    Refitted on four new iPhone 16 Pro swipes (0.49 at no lag, 0.50 one
    or two display ticks behind; replay 0.16 - 0.27 pt rms,
    `pop-edge-drift-*` fixtures).


## 0.6.0 - 2026-09-03

The content decides. A target can now be sized by what it holds and
springs to every change while the flight is up, every target stays
clear of the keyboard, and the held menu's column is live - its hero
slot and satellites follow their content. Behavior shifts in two
places, called out below; the rest is additive.

- `MorphTargetSpec.measured(constraintsFor:, placeFor:)`: a target
  measured by its content. The content is laid out under the
  constraints (a tight width, a loose height up to a cap), its size is
  measured, and the placement turns the size into the rect. The first
  measurement seeds the target; every later change - a capsule growing
  on selection, a chip unfolding - springs the surface on the flight's
  open motion while the content lays out at its natural size and the
  surface reveals it as it catches up. A launch never shows a guessed
  box: the shuttle stays invisible and the source visible until the
  first measurement lands. `fitContent` on `MorphTargetSpec.sheet`,
  `dialog` and `popover`, and on `showMorphSheet`/`showMorphDialog`,
  turns the box's height into a ceiling. `MorphFlight.contentSize`
  (smoothed) and `measuredContentSize` expose it; the settled route
  page keeps measuring too. BEHAVIOR: `showMorphMenu` is measured
  unconditionally - the row height no longer follows an arithmetic of
  the text scale, the rows size the menu.
- The keyboard. BEHAVIOR: the padding every `rectFor` receives is now
  the safe area unioned edge by edge with the keyboard, so a sheet
  docks above it, a dialog centers in the room left and a popover
  clamps clear of it - by construction, in every existing factory. A
  fullscreen target, which ignores the padding, still covers the
  screen. The target content sees only the part of the keyboard its
  surface still overlaps (a Scaffold inside no longer avoids it a
  second time); the settled route page applies the same math. Fixed
  dialogs and popovers now cap both axes to that unobstructed room, and
  window insets are translated into the actual flight overlay's local
  coordinates before placement - an offset nested overlay reserves only
  the keyboard strip that intersects it.
- `MorphTargetSpec.repaint`: a `Listenable` whose notifications re-lay
  the frame (the CustomPainter idiom) for a rect that reads state of
  the owner's; `contentAlignment` is overridable, and the class may be
  extended for geometry that follows live state.
- `MorphContextMenuRegion`: the column is live. `MorphSatellite.height`
  is optional - a slot without one is sized by its content, seeded at
  launch and springing to every change - and the hero's slot follows
  the hero: a badge appearing on the bubble shows at once, the actions
  slide down on the spring, and the hero stays put while a capsule
  grows above it. The column moves out from under the keyboard with
  the hero travelling in it. A change to the child or the satellites
  while the menu is open rebuilds its content and geometry together.
  `replica:` supplies every overlay copy - source ghost, target slot and
  shared flight - while the live child remains mounted only at home, so
  a visual replica without the child's FocusNode/controller/GlobalKey
  keeps those single-owner objects safe. `opensOnSecondaryTap` leaves
  the right click to someone else.
- Example: chapter 03, Hold to menu - a reaction lands on the bubble at
  once and unfolds a note field in the capsule; the KEYBOARD toggle
  raises the phone's own keyboard (`PhoneFrame.keyboard`) and the open
  menu moves out from under it, the compose bar rising with it.
- The pill host's sympathetic chrome shift is quieter for opaque ink:
  3px instead of the glass reference's 4px. Its uniform breath remains
  unchanged.
- `MorphTag` now captures its full bounds through ancestor paint
  transforms instead of transforming only the top-left and retaining
  the layout size. Context-menu holds consequently launch from the
  exact lifted pixels, keep that press rect stable for the flight and
  release it once takeoff settles, removing the visible handoff shake.
  Context-menu landings are quiet by default (`bumpScale` and
  `bumpRecoil` default to zero): expanding satellites no longer give a
  stationary hero a false impact, and close returns to the natural
  source rect instead of replaying the press growth.

## 0.5.0 - 2026-09-02

The hold. A surface becomes its own context menu when held, and the
engine grows the four seams that recipe needed: a flight announces its
moments, survives losing its source, renders in a chosen overlay, and
can leave its content unclipped. Additive throughout: nothing existing
changes shape or default.

- `MorphContextMenuRegion` and `MorphSatellite` (widgets layer): the
  message-bubble pattern. The hero under the finger lifts on the touch
  (the Tug press; inside a scrollable it waits for the touch deadline,
  so a scroll never flashes it), and on the hold threshold it flies to
  where its satellites fit - slots of a declared height above and
  below, unfolding on the flight's own spring - as a shared element,
  never a copy fading over a copy. The flight's container is a
  transparent vessel: the hero draws its own surface and the app draws
  the rows; the vessel's content alignment is chosen so the hero slot
  coincides with the flying hero at every spring value, which makes
  the satellites ride the hero as one rigid body. The hero stays put
  unless the column would leave the safe area, then the whole column
  shifts. Three doors: the hold, a secondary click, and
  `MorphContextMenuRegion.open(context)` from inside the hero - the
  visible "more" glyph. `onHold` marks the threshold (the haptic
  moment), `onOpen` hands out the flight.
- `MorphFlight.events`: a stream of `MorphFlightEvent` - launched,
  settled, closing, latched, landed, aborted - the seam for haptics and
  app-side choreography. Moments are queued in order and delivered a
  microtask later, so a listener attached in the same synchronous run
  as showMorph hears the launch, and a handler may close the flight
  from inside itself.
- A flight survives losing its source. When the tag leaves the tree
  mid-flight (a row archived from its own menu), the source rect
  freezes where it last stood, open content stays usable, and the
  close DISSOLVES - the container fades over the first half of its
  remaining travel, a pure function of the spring value from the
  moment the dissolve begins - instead of landing on whatever took the
  row's place. `MorphFlight.isSourceLost` and `dissolveOpacity` expose
  it.
- `overlay:` on `showMorph`, `showMorphSheet`, `showMorphDialog`,
  `showMorphMenu` and `MorphAnchor`: the overlay the shuttle renders
  in, for flights that must fly above chrome layered over a nested
  navigator (a floating bar over tab navigators). `morphAnchorRect` and
  `maybeMorphAnchorRect` take the same `overlay:`, so anchors are
  measured in the flight's space. The default stays the nearest
  overlay.
- `MorphTargetSpec.clipBehavior`: `Clip.none` lets content overflow the
  flying container - the vessel case above. The default is unchanged.
- `MorphSurface.onLongPress` and `MorphTapTarget.onLongPress`, with the
  same context-under-the-tag contract as `onTap`. `MorphTapTarget` now
  carries its tap and hold on its own semantics node: the exclusion
  under it had hidden the detector's actions from assistive tech.
- `Tug.glassSpring` is public - the button-scale glass spring, one home
  for every press in the widgets layer.
- Example: chapter 03, Hold to menu - a chat inside a nested navigator
  under a floating compose bar, with the overlay toggle, the events
  trail, and delete-from-the-menu dissolving the bubble.

## 0.4.0 - 2026-09-01

Material leaves the SDK. Flutter 3.47 split Material and Cupertino out
into standalone pub packages and deprecates the in-SDK copies in the
following stable; morph moves now. Nothing in the API changes shape -
only the package its Material types come from.

- morph imports `package:material_ui/material_ui.dart` instead of
  `package:flutter/material.dart`, across 56 files (10 lib, 18 test,
  26 example, 1 benchmark). Every `.dart` change is a single import
  line; no behavior, signature, name or default moved with it.
  BREAKING for consumers all the same: the standalone package is a
  full COPY of Material, not a re-export, so `material_ui.Theme` and
  `flutter/material.Theme` are DIFFERENT types and a `MorphTheme`
  reaches `Theme.of(context).extension<MorphTheme>()` in one world
  only. An app still on the in-SDK library either migrates with
  `dart fix --apply --code=migrate_design_widgets` or wraps the morph
  subtree in `MaterialUiCompatibilityBridge` - and note the bridge
  carries colors, density, platform and legacy localizations but NOT
  `extensions`, so a bridged app must also mount its `MorphTheme` in a
  legacy `Theme` of its own.
- `material_ui` `^1.1.0` is a direct dependency. `cupertino_ui` is
  transitive only: morph uses no SDK Cupertino at all, and
  `CupertinoMotion` comes from motor. Icons still resolve through
  `uses-material-design: true` - material_ui names the bare
  `MaterialIcons` family with no font package of its own.
- The Flutter constraint rises to `>=3.44.0`, material_ui's own floor,
  from the template default `>=1.17.0` it had carried since the split
  from tem_tools.

Known debt, deliberately left for a release of its own: the engine
still reaches for Material in four places - `MorphTheme` is a
`ThemeExtension`, the shuttle and the settled route page draw their
surface as a `Material`, both read `Theme.of(context).colorScheme`,
the barrier label comes from `MaterialLocalizations`, and
`showMorphDialog`/`showMorphSheet` adopt `DialogThemeData` and
`BottomSheetThemeData`. So `foundation.dart` carries material_ui to
every consumer, and the promise that the core blesses no design system
is not yet paid. The shuttle's `Material` is the expensive one: it is
what gives consumer dialog content its ink and default text styles, so
removing it is a change in behavior rather than a rename.

## 0.3.0 - 2026-08-29

The tactile pass. The widgets layer learns how a glass surface answers
a finger, and the engine grows the two things that pass needed: a
contour on the mass and one spring family shared by button and flight.
The `Tug` rewrite breaks API; everything else is additive.

- `Tug` is rebuilt on the liquid-glass button model. ONE degree of
  freedom, the raw pull on the chase spring, and every visual is a pure
  function of its (value, velocity). Travel is
  `reach * tanh(give * d / reach)` at give 0.05, so a few percent of
  the finger transmits and the asymptote sits a whole side away
  instead of a wall ten px out; the silhouette reads the raw pull at
  `stretch` gain plus its velocity times `jiggle`, saturated and
  volume-corrected, so the flesh answers more than the body moves;
  pointer-down LIFTS by `pressGrow` px per axis on a 363ms half-bounce
  spring (negative sinks, for ink). The gesture layer is a raw
  `Listener` outside the arena, so a selector or a scrollable inside a
  Tug still wins its own drag, and `vertical` gates both the input and
  scaleY - a bar pins its height. Past a 2:1 aspect the transmission
  fades by itself.
  BREAKING: `follow`, `lean`, `TugPull`/`onPull` and
  `MorphPieceChannel.contentScaleX/Y` are gone. Ink lies on the body
  and cannot slide, so content deforms with the mass 1:1. `dead` is
  gone and `cap` is now `reach`: both changed units in the rewrite, so
  the rename breaks stale call sites loudly instead of silently losing
  20x of their travel.
- `MorphPillHost`: the selection pill's physics as a host you draw
  from. Everything is px along the track axis; the owner maps
  positions through two callbacks (`hit` for taps, `snap` for
  carries), feeds a raw pointer stream in and paints where `centerX`
  and `resolveSize` say. The grab is the native model: the DOWN lifts
  the pill in place on its own item and carries it to a held one, the
  finger then moves it by its own displacement, confined to the slot
  span by the snap grid itself, and the commit waits for the release.
  Every release walks through one door, so an interrupted journey
  cannot strand the pill between slots. Chrome sympathy comes out as
  `chromeShift` and `chromeBreath` for the bar's piece channel.
- `MorphSquash`: deformation from force. Positions in, one signed
  deviation out (`scaleX = 1 + d`, `scaleY = 1 - d`, area held), so
  gaining speed stretches, braking squashes, and constant speed leaves
  the body alone. Only positions are sampled, so it composes with any
  driver; the intended one is a `MorphPieceChannel` write on a
  selection blob.
- `MorphStroke` on `MorphSkin.stroke`: the mass carries its own
  contour. The stroke follows the same traced path as the fill, so
  necks, deformations and flight blobs are outlined for free. Inner by
  contract (clip plus double width), painted after the tints, and
  outside the trace signature - a stroke change repaints without
  re-tracing. `MorphPiece.morphable` folds it into the tag shape and
  the flight frame lerps the side through the concentric rebuild, so a
  container launches outlined and its contour dissolves as the surface
  becomes the dialog.
- `MorphMotion.glass`: the material-unification profile, close 420ms
  at bounce 0.3 with a -1.5 hint. It is a FAMILY, not an instance -
  the same character calibrated for flight mass, while Tug keeps its
  own 363ms spring for finger-scale amplitudes. Sharing the literal
  button spring was tried and rejected by hand: its undershoot past
  the handoff latch turns into a ~22px landing kick over a flight's
  hundreds of pixels.
- `MorphSkin.contentFilterQuality`: content is rasterized once in its
  own space and the channel transform only resamples it, so glyphs
  stop shuffling under a moving matrix. The filter layer is retained
  per child - the raster reuse the knob buys.

Fixes:

- `Tug` forgets its pointer at dispose. A finger still down when the
  subtree left the tree used to report its up into disposed
  controllers. `chaseStiffness` now reaches a live chase instead of
  being captured once, and a negative `volume` can no longer drive a
  NaN into the channel.
- Frames resuming after a gap (a route covering the scene, the app
  backgrounded) finish the journey instead of integrating the whole
  gap in 240Hz substeps.
- A stroked flight drew its contour twice, the shuttle's surface and
  the skin's blob over the same pixels. The blob's box is clipped out
  of the skin's stroke and the replica flies unstroked, the way it
  already flies unshadowed.

## 0.2.0 - 2026-08-16

Two additions, both driven by tools that live over content instead of
covering it.

- `showMorph(modal: false)` (and the same flag on
  `MorphFlight.launch`): a NON-MODAL flight mounts no scrim at all, so
  the page underneath stays fully interactive while the surface hovers
  over it - a search field expanding over the list it filters. Nothing
  dims and there is no tap-outside dismissal (`barrierDismissible` has
  no barrier to attach to); Esc and the local history entry still
  close the flight. Modal stays the default.
- `MorphPiece.tint`: an ink wash that is PART of the skin instead of
  an overlay approximating it. Painted over the fill from the piece's
  RESOLVED geometry, so it stays glued to the mass through channel
  displacement, deflation and the landing squash; an airborne piece
  paints none. Clipped by the traced silhouette, so the neck to a
  neighbour stays untinted - ink soaks the body, not the bond. Content
  paints above it. Toggling only the tint is paint-only: no relayout,
  no re-trace, no subscription resync - a hover wash can flip per
  frame.

## 0.1.0 - 2026-08-09

The first tagged release.

- Engine (`package:morph/foundation.dart`): identity-based
  widget-to-overlay morphs on retargetable springs. `MorphTag` +
  `showMorph`/`showMorphDialog`/`showMorphSheet`, declarative
  `MorphAnchor`, `showMorphRoute` (the destination as a real Navigator
  route: live-state reparenting at settle, predictive back, drag on
  the settled page), `MorphSharedElement` (fade-through or solo
  flight), the displacement drag channel with commit heuristics,
  `MorphReveal` cascades, `MorphMotion` profiles and `MorphTheme`
  defaults. Flights and routes resolve the NEAREST overlay/navigator,
  so nested navigators keep their morphs inside themselves.
- The liquid skin: `MorphSkin`/`MorphPiece`/`MorphLink` fuse surfaces
  into one traced vector mass (no shaders), with flight necks, launch
  fellowships, per-cluster caching, an eval budget for bounded worst
  frames, and `MorphPieceChannel` - app-driven per-frame geometry with
  no widget rebuilds.
- Widgets (`package:morph/widgets.dart`): `showMorphMenu`,
  `MorphSurface`/`MorphTapTarget`, `SpringButton`, `Tug`,
  `ChaseSpring`.
- Example: a seven-scene tour of app mockups in a phone frame plus the
  sandbox playground; live at <https://tembeon.github.io/morph/>, API
  docs at <https://tembeon.github.io/morph/docs/>.
