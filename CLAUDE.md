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
them separately. No production "feel" knobs: when a value has no
measurement behind it, the job is to measure it, not to tune it.
The owner's measurement laboratory in `tool/ios_reference/lab` compares
native and Flutter using shared scenarios, real touches, layers and films;
it is tooling, with no production feel knobs or unmeasured tuning promotion.
Example scenes may still carry scene values (layout, blend of a
mockup), never physics that pretends to be native.

## Layers

Flutter-style split, two entrypoints:
- `lib/foundation.dart` - the ENGINE export (identity, flights,
  retargeting, targets, routes, the liquid skin, `MorphSpring`).
- `lib/widgets.dart` - the measured widget layer (`lib/src/widgets/`),
  re-exports foundation. The old isolation rule (the engine never
  imports widgets) is CANCELLED (owner decision 2026-10-05): widget and
  render quality come first, so the engine may know the widget layer
  and the glass renderer when that makes a surface right. Prefer a
  general Flutter mechanism over a glass special case where one exists
  (InheritedTheme carries the glass painter through flights). The
  package carries ONE glass
  renderer (`lib/src/glass/renderer`, owner decision 2026-10-03 - the
  old "no shader in the package" rule is CANCELLED): the package computes
  every shape once, the renderer only SHADES the outline it is given, at
  a quality tier (see the glass seam below). `lib/native.dart` is gone (it was this layer before it took
  over widgets.dart; every `MorphNative*` name lost its infix,
  `MorphNativeMorphSpec` became `MorphMenuMorphSpec`).

## Measured spec (read this before touching a control)

The measured numbers do NOT live here. `tool/ios_reference/spec/README.md`
holds the protocol (probe, recorder, synthesizer quirks, fixtures, device
lock, provenance, status) and there is one passport per control or family
(lens-and-flex, segmented-control, tab-bar, search-tab-bar, switch, slider,
stepper, glass-button, menu-button, context-menu, bars, navigation-pages,
sheets, alerts, search, date-picker, page-control, progress-view, lists,
activity-indicator, typography, glass-optics, glass-renderer, skin-merge,
engine-flight) - read the passport for the control you touch, and
lens-and-flex.md for anything that lifts.

RULE: when a measurement changes, update the passport AND the tuning
class dartdoc in the same change. CLAUDE.md changes only for architecture
or policy. The phone is shared: take `/tmp/morph-native/device.lock`
(README) before touching it.

## The measured widget layer (lib/src/widgets/)

Shape of every control: a PURE MOTION CLASS (a function of the touches
it is fed and the time it is advanced to; no widgets, no tickers,
replayable in a plain `test()`), a thin WIDGET HOST (a raw `Listener`
stamps pointer events on the motion clock, calls
`motion.pointerDown/Move/Up/Cancel`, advances per tick, paints), a
`style` with `light`/`dark` tables from the iOS system colors. Measured
constants live in tuning classes (`MorphLensTuning`, `MorphMenuTuning`,
`MorphFlexSpec`, `MorphSheetTuning`, the *Motion statics, ...) with the
measurement in their dartdoc.

Internal machinery (all `@internal`):
- `spring_state.dart` - `MorphSpringState`: a damped spring in CLOSED
  FORM from its last retarget (under-, critically and over-damped
  branches); time is an explicit argument everywhere, `retarget(t,
  target, spring:)` carries (value, velocity), `setState`, `snap`,
  `isAtRest`. This is what makes the motions pure functions of time.
- `timeline.dart` - `MorphTimeline`: delayed reactions ordered by due
  time; each action receives ITS scheduled time, so a motion advanced in
  coarse steps still applies every action at its own time; equal times
  keep insert order; `now` reads the running action's time.
- `clock.dart` - `MorphClock` mixin: the ticker's elapsed time
  ACCUMULATED across restarts (time asleep does not count; the ticker
  stops when the motion settles). `stamp(event)` stamps the event's OWN
  TIME STAMP on the motion clock - the reference every device-fitted
  delay and every replay uses (UITouch.timestamp to native start, which
  includes UIKit's 10 - 25 ms delivery latency). PointerEvent.timeStamp
  counts CLOCK_UPTIME_RAW on iOS / macOS, frames and `morphClockNow`
  (Dart's Timeline clock) CLOCK_MONOTONIC_RAW; `morphPointerClockOffset`
  reads the difference (the device's sleep) through FFI
  (pointer_clock_io.dart; zero elsewhere, stub on web). While ticking or
  dozing: the latest frame's clock + (event time - that frame's stamp),
  1 - 3 frames in the past (an iOS frame is stamped with its display
  TARGET); while asleep, events keep their own spacing divided by
  `timeDilation` and the first frame after the wake counts from the
  event's time stamp. A time stamp outside 0 - 250 ms before now falls
  back to delivery + one frame (UIKit begins a frame after a handler);
  frame stamps and now disagreeing by > 50 ms (a test's fake clock) fall
  back to the latest frame's clock. `MorphSpringState` never retargets
  before its last change. Evidence: spec/README.md "Clocks".
  `motionFrameRate` = 60 when the display reports 60 Hz, 120 otherwise.
  `frames` is the painter's repaint Listenable.
- `flex_integrator.dart` - `MorphFlexIntegrator` (UIKit's
  `_UIVelocityIntegrator`, alpha 0.3 PER FRAME) and `MorphSubClock`: a
  fixed-rate frame clock in MOTION time at `motionFrameRate` (every
  boundary crossed is reported, max 600 per advance), so the deformation
  is identical on a 60 or 120 Hz host, under timeDilation and under
  coarse test pumps.
- `lens_driver.dart`, `lens_spec.dart`, `control_focus.dart`
  (`MorphControlFocus`, `MorphFocusRing` systemBlue, `MorphDisabled`),
  touch_listener.dart (`delaysInScrollable`).
- `menu_fusion_worker*.dart` - `MorphFusionWorker`, THE ONE BACKGROUND
  ISOLATE POOL in the package (2026-10-06): the menu motion peeks its
  silhouette inputs at the next three predicted frame times (a pure peek:
  time and kicks restored) and up to four isolates fuse them while
  frames render;
  `MorphMenuFusion.outline` serves an arrived fusion only within
  `prefetchTolerance` (0.02 pt per input) and the same grid/kernel, else
  fuses in the frame as before - so a served outline is the exact law at
  a time a fraction of a millisecond from the frame's. Profile/release
  with isolates only (`prefetches`); debug, every test and the web never
  start it. Workers send plain parts (`MorphGlassOutlineParts`: samples
  + contour loops) because dart:ui's Path exists only on the root
  isolate. Why: the fusion's device cost is core placement and DVFS of a
  light UI thread (glass-renderer.md "Menu fusion: the device gap").

Public controls (one passport each): MorphSegmentedControl, MorphTabBar,
MorphSearchTabBar, MorphSwitch, MorphSlider, MorphStepper,
MorphGlassButton, MorphMenuButton, MorphContextMenuRegion /
MorphSatellite, the bars (MorphNavigationBar, MorphToolbar,
MorphNavigationStack, MorphScrollEdgeEffect, push zoom), sheets
(presentMorphSheet incl. zoom), alerts and action-sheet popovers,
MorphSearchField / MorphSearchToolbar, MorphDatePicker,
MorphPageControl, MorphProgressView, MorphActivityIndicator, the inset
grouped list (MorphListSection / MorphListRow; MorphNavigationScaffold
and sheets give their content the body text style).
`MorphSpring` is the engine's (spring.dart); `MorphFlexSpec` ports
`_UIFlexInteractionSpec` (lens-and-flex.md).

Cross-cutting policy:
- THEMING: explicit `style` > `MorphWidgetsTheme` (a ThemeExtension, one
  style per control; a ThemeData is one brightness, put a dark style in
  the dark theme) > the style class's `light`/`dark` table for
  `morphBrightnessOf` (Theme, else MediaQuery platform brightness, else
  light). An explicit color parameter still beats the style.
- TYPOGRAPHY: every label a control paints goes through
  `MorphTypography.resolve(style)` (opsz, wght 510/590, CoreText
  tracking; Apple platforms only, identity elsewhere; caller
  letterSpacing / fontVariations win; the result is complete,
  `inherit: false`, so no label depends on an ambient DefaultTextStyle
  wherever it is mounted) - typography.md.
- A11Y / INPUT: each segment is a selectable button in a mutually
  exclusive group; the tab bar carries tab bar / tab roles; switch and
  slider take `semanticLabel`; slider adjust actions and arrows move by
  `keyboardStep`; the stepper is two buttons carrying the value. Every
  control is focusable with a systemBlue ring; Space/Enter toggle,
  press, increment. RTL mirrors segmented, tab bar, switch, slider.
  Disabled = null `onChanged` / `onPressed` / `enabled: false` draws the
  DEVICE's disabled look (states.md, test/disabled_test.dart): one 0.5
  layer over segmented / switch / slider; no change on stepper, page
  control, tab items (a disabled tab still swells the bar); content
  tertiaryLabel on glass / menu buttons and bar items (measured rendered
  colors), prominent tint systemGray4; search field and date picker
  labels lose their glass / capsule; every change in one frame; disabled
  controls ignore touches. REDUCED MOTION (`reducedMotion`, from
  `MediaQuery.disableAnimations`) is an approximation until Reduce Motion
  is recorded; off by default so replays are unchanged.

## The glass seam and the renderer (contract; numbers in glass-renderer.md / glass-optics.md)

- Seam (glass.dart): `MorphGlass(painter:)` installs a
  `MorphGlassPainter`; controls build their glass surfaces
  (`MorphGlassKind`) every frame behind their content via
  `buildLayer(surfaces, content:, spacing:, contentSlots:, outline:)`,
  `buildSurface`, `buildFill`, `buildGlow`. `MorphGlassSurface.glass` is
  false for plain fills (tracks, stepper), drawn flat through
  `buildFill`. ONLY NATIVE GLASS IS GLASS: bars, glass buttons and bar
  capsules, menus, popovers, the date picker overlay, alerts, floating
  sheets, the search capsule; a lens/knob/thumb is an opaque platter at
  rest and clear glass only while lifted. Without a painter: flat fills.
- THE SURFACES CHANNEL (glass_channel.dart, 2026-10-05): controls never
  call the painter themselves; they mount a `MorphGlassHost` per painter
  entry (layer / surface / fill / body; `MorphGlassLayer` is the layer
  host plus its MetaData) with a frame closure (`MorphGlassFrame`:
  surfaces, outline, contentSlots, spacing). With `MorphGlassRenderer`
  itself the host builds its tree ONCE per STRUCTURE
  (`MorphGlassRenderer.structureOf`: tier, roles and counts, glows,
  lifted lenses, platters, outline kind) over a `MorphGlassChannel`, and
  every later frame is PUSHED: render objects bound by
  `GlassLiveBinding` (renderer internal/glass_live.dart) write the new
  values through their own setters - `MorphLiveStack` /
  `MorphLivePositioned` boxes, live clips, backdrop filters, decorations,
  painters repainting on a key of what they read, `LiquidGlass.live` /
  `LiquidGlassLayer.live`. A host its parent rebuilds pushes from
  `update` without building (a custom element); a frames-driven host
  builds once per frame (the ListenableBuilder it replaced) and returns
  the same tree; `keep` hands back the same glass widgets when only the
  content changed. Other painters are asked every frame as before.
  MorphGlassRenderer's buildLayer / buildSurface / buildBody build the
  same trees from a fixed source: ONE implementation. Rules: whatever a
  tree BRANCHES on belongs in structureOf (a missing one shows stale
  pixels; test/glass_frames_test.dart compares every perf-counts scene on
  every tier against `debugMorphGlassRebuildEveryFrame`); a live widget
  that replaces a stock one subclasses it (tests find them with
  `find.bySubtype`).
- A surface presented ABOVE its source draws with the painter installed
  above the SOURCE; a MorphGlass inside a page is invisible from the
  navigator's overlay. `MorphGlass` is an InheritedTheme, and every
  presenter carries the source's InheritedThemes (themes.dart,
  `MorphThemeCarrier`, the popup-route precedent): engine flights
  (`MorphFlight.sourceThemes`, the whole shuttle and the settled route
  page - ghost, surface, content), alerts / action sheets / sheets / the
  date picker (captured from the presenting context up to the
  navigator, recaptured on each page build), the zoom replica (from its
  tag). Menus also carry `MorphMenuHost.menuGlass` explicitly.
- Fade glass through `MorphGlassSurface.opacity`, never through an
  Opacity above it (it reads an empty backdrop), and never put an
  OpacityLayer between resting glass (it breaks BackdropGroup sharing).
  The same holds for every BackdropFilter: the scroll edge effect fades
  through `MorphScrollEdgeEffect.opacity` (an alpha matrix composed onto
  its blur); under an Opacity it showed the page sharp under the bar for
  the whole fade (edge_effect_fade_test).
- FLAT EDGE EFFECTS (2026-10-06): `MorphScrollEdgeEffect` reads the
  installed renderer's effective tier. Flat draws its fade/hairline only,
  no blur, color-matrix backdrop filter or seed copy; fake/liquid and
  custom painters retain the edge effect. The flat audit census is zero
  backdrop filters in all seven scenes (home-scroll, segmented, tab-bar,
  controls, menu, sheet, list).
- BACKDROP GROUPS: a shared group member does NOT read the backdrop at
  its own place in paint order. On iOS (Metal reads from the resolve
  texture) every member after the first reads the pass texture as it
  stood at the LAST backdrop flip before it (any filter's), elsewhere the
  copy of the first member. So only glass whose backdrop is complete
  before the group's first glass may share: the page's resting body
  glass shares the root group; anything floating over the page reads a
  copy of its own or its own group - bar / menu kinds (both tiers, also
  through buildSurface), the navigation bar + toolbar (one
  `MorphChromeBackdrop` key per screen, chrome_group.dart), the search
  tab bar, a sheet's content, a menu's card, a context menu's hero and
  satellites, lifted glass and a lifted lens / knob / thumb. Two
  resting body glass surfaces with content painted between them: the
  later one misses that content (it cannot be detected per frame -
  pictures carry no drawn bounds). OWNER DECISION 2026-10-05, option C:
  no automatic grouping; the app wraps a section painted over earlier
  glass in its own `BackdropGroup(child: section)` (MorphAdaptiveGlass
  dartdoc, backdrop_section_test; options and device costs in
  glass-renderer.md). The scroll edge effect keeps its
  own copy: in the bars' group the capsules would miss its fade
  (measured, glass-renderer.md).
- GLASS CONTAINER (glass_container.dart, 2026-10-05): the opt-in
  `MorphGlassContainer` shades the resting glass of the controls below it
  in ONE layer (one geometry pass, one filter); everything inside it is
  content above its glass. A host joins only when its glass would look
  the same: still (`MorphGlassLayer.still`; only the glass button tells),
  separate resting body glass with the container's settings and one tint,
  no fade / clip / filter / viewport between (a MorphTag source never
  joins), at most 32 shapes (MAX_SHAPES). The decision is part of the
  host's structure. A moving member would re-encode the container's matte
  every frame - that is why only still glass joins (the glass button, the
  search capsule and the bars tell `still`). No host under a BackdropGroup
  of another key joins. RASTER PHASE: a joined host's shapes sit under a
  `GlassRasterAnchor` and the container shifts them by the difference of
  the two nearest-sampling phases, so off the pixel grid they read the
  pixels of their own layers (1 - 3 channel steps, was 48 - 76).
  STAGES (`MorphGlassStage`, internal): containers the package owns where
  it owns the paint order, open only while it neither fades nor moves its
  members (`MorphGlassStageFade`); MorphSearchToolbar is one, and every
  MorphListSection card (2026-10-06): the stage sits over the card fill,
  `sharpOnly` closes it while controls frost (resting unfrosted glass
  samples only inside its own outline, so the rows' text and separators
  painted after the stage are never read), and a row whose highlight
  shows keeps its accessories out through `MorphGlassContainerBarrier`
  (an InheritedWidget the reach check depends on, like
  MorphTagVisibility). The navigation stack's chrome is NOT (measured:
  one screen-high layer costs the GPU more than the raster saves); the
  scaffold body gets no flag (a container above its scroll view joins
  nothing: the viewport blocks); app sections stay explicit (option C).
  Numbers and gates in glass-renderer.md "Glass container".
- GLASS INSPECTOR (glass_inspector.dart, public, 2026-10-06):
  `MorphGlassInspector` overlays the frame's backdrop filters, captures,
  owners (GlassLayerOwners when set, else the nearest composited render
  object's Morph widget chain) and hints: resting joinable hosts outside
  a container grouped by their nearest blocker
  (`morphGlassContainerBlocker`, the reach check's own predicate) and
  settings, and hosts inside one kept out by a blocker. Debug and
  profile only (kReleaseMode builds the child alone; the code is
  tree-shaken); one persistent frame hook for all inspectors, a layer
  walk per frame, the element walk only when the filter set changes;
  `MorphGlassInspector.census()` is the same data for tests. The
  gallery's Glass renderer page toggles it.
- ONE renderer in the package (lib/src/glass/renderer, vendored
  whynotmake-it, Apache-2.0, VENDORED lists local patches; owner decision
  2026-10-03 - the old no-shader rule is cancelled). Public entry
  `MorphGlassRenderer` with `MorphGlassTier` flat / fake / liquid (fake =
  the liquid layers through the renderer's FakeGlass: no refraction, no
  Flutter GPU - the pre-capability fallback and the web's tier; frosted
  removed 2026-10-05, owner decision);
  `MorphAdaptiveGlass` picks the tier ONCE per session, never at runtime
  (owner decision 2026-10-05: no tier switching from frame timings - the
  old governor flapped flat/liquid on the Pixel 6a): explicit tier wins,
  else `MorphAdaptiveGlass.tierFor(deviceClass, best)` - liquid on
  Vulkan/Metal, the single `MorphAdaptiveGlass.cheapTier` (flat: fake
  glass costs about what liquid costs on the GLES Pixel, measured in
  glass-renderer.md) on the GLES fallback and Apple GPUs before
  the A13, probed from Flutter GPU (glass_device_native.dart) once the
  liquid capability resolved.
- OUTLINE IS TRUTH: the package computes every shape once and fuses
  (skin merge law, the menu's blurred SDF) into a `MorphGlassOutline`;
  the renderer only SHADES the outline it is given and never fuses on its
  own. A plain union (spacing 0: the menu's tail under 1 pt, submenu
  cards) carries its boxes instead of a field - path union for the edge,
  each box shaded as its own circular rounded rectangle - exact, and no
  per-frame trace or upload.
- Glass shadows clip to outside the glass (an even-odd path), never a
  saveLayer + dstOut per surface: no offscreen pass, no shadow under the
  translucent body (GlassShadow, MorphGlassBodyShadow).
- PACKAGING: the build hook writes `build/shaderbundles/`; its pubspec
  asset entry must stay. Flutter 3.47.2 does not request data assets
  from hooks, so a data-asset-only bundle silently lost liquid glass on
  the device (fixed in f8b921d). Verify packaging on a native device.
- The web build compiles: the liquid tier is behind a conditional import
  and its final-render shaders compile to stubs under Skia.

## Architecture (lib/src/)

- `spring.dart` - `MorphSpring` (engine-flight.md); in the engine since 0.7.0,
  `widgets.dart` re-exports it.
- `motion.dart` - `MorphMotion`: a pair of `Motion`s from **motor**
  (openMotion/closeMotion, getters). `MorphMotion.springs(open:,
  close:)` builds one from MorphSprings and exposes them as
  `openSpring`/`closeSpring`; the public constructor takes ANY Motions
  (Material tokens, curves, custom springs). Built-in profiles:
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
  Required lookups throw descriptive FlutterErrors in release as well
  as debug. `MorphScopeState.tryTagOf` is the optional lookup for callers
  that can degrade when a source is missing; duplicate ids are reported.
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
  place; a re-open lifts it. Pinned by morph_source_lost_test. SOURCE
  THEMES (2026-10-05): the shuttle and the settled route page build
  everything under `MorphFlight.sourceThemes` - the InheritedThemes
  between the source tag and the flight's overlay (Theme, DefaultTextStyle,
  IconTheme, MorphGlass, ...), Flutter's popup-route precedent with the
  tag's context as the launching context, so target content gets the
  source's themes too. Captured once at launch (one ancestor walk); the
  flight makes the tag depend on those theme elements, and the tag's
  didChangeDependencies asks a live flight to recapture after the frame
  (a MorphAdaptiveGlass tier switch reaches an open dialog one frame
  late). The kinds captured are fixed at launch (a recapture that finds
  other kinds is ignored, so the subtree never changes shape); a lost
  source keeps the last capture. The wrap sits ABOVE the route content
  key on both sides, so the content chain under the key is unchanged.
  Pinned by flight_theme_carry_test. VESSEL
  flights (see target.dart) skip surface, shadow, ghost and crossfade
  and mount the content over the whole overlay. THE SCRIM CHANNEL
  (scrim.dart, 2026-10-03): `scrimMotion: MorphScrimMotion(motion:,
  openDelay:, closeDelay:)` on launch / showMorph gives the scrim its
  OWN spring - a third orthogonal DOF (internal MorphScrimChannel on the
  scope's ticker, joined to frameTicks): it follows the controller's
  TARGET (open / close / re-open), never its value, each retarget after
  its direction's delay from the current (value, velocity), a newer
  request replacing a pending one; the scrim opacity is maxScrimOpacity
  x clamp(value) (`MorphFlight.scrimOpacity` / `scrimValue`, the one
  read for the shuttle, the vessel and the settled route page), the
  drag thinning still multiplies it. Without it the scrim stays
  morphScrimOpacity of the progress. It OUTLIVES THE LATCH: the shuttle
  then draws only the scrim (IgnorePointer, no semantics - the page is
  live), finalize waits for both the value and the scrim to rest (landed
  comes after the dim), and a re-open during that tail re-hides the tag
  and rebuilds the content. Reduced motion: instant, no delays. A
  rebuild of the shuttle's outer build after a consumer disposed a
  `repaint` Listenable re-subscribes it (the merged Listenable is new
  each build) - so the latch does not markNeedsBuild the entry; the
  frame builder sees the latch on the same tick. Pinned by
  morph_scrim_test.
- `show.dart` / `anchor.dart` - imperative `showMorph*` (escape hatch)
  and declarative `MorphAnchor(isOpen, onDismiss)` - the morph as a
  function of state; identity is the State itself unless an explicit
  `tagId` is given. Overlay flights render in the NEAREST enclosing
  Overlay: the flight belongs to the world its scope lives in, so a
  nested navigator (a tab, an embedded device mockup) keeps its flights
  inside itself - except across a `MorphPresentationBoundary`
  (presentation.dart; MorphNavigationStack installs one): presenters
  default to `morphPresentationOverlayOf` / `morphPresentationNavigatorOf`,
  the overlay / navigator around the OUTERMOST boundary, so menus,
  context menus, dialogs and sheets from a stack page cover the stack's
  bars as on iOS (pinned by presentation_boundary_test); morphAnchorRect
  measures in the same overlay by default. `overlay:` (showMorph*/MorphAnchor/MorphMenuButton/
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
  republishes the SOURCE tag's surface spec around the replica. The
  target anchor sits below the shuttle's reveal scale: target rects are
  layout-space endpoints, not the 0.95 - 1 revealed pixels.
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

## Example

The example app IS the measured gallery (`example/lib/gallery/`, one
MorphNavigationStack whose pages are GalleryPage scaffolds and list
sections, no Material Scaffold/AppBar/ListTile;
`example/lib/main.dart` runs `GalleryApp`, so a plain `flutter run`
opens it): one page per measured widget family plus the Glass renderer
page (tier, material, dark, RTL, disabled) and Size to physics
(spec_inspector). A SLOW-MO toggle cycles `timeDilation` 1x/5x/10x: the
measured motion runs on ticker time, the flex filters step on the
sub-clock in that same time and touches are stamped on it, so the
widgets slow down as a whole; only the finger keeps real time. The
gallery root installs `MorphAdaptiveGlass` with the session's
`MorphGlassRenderer` (glass_settings.dart); liquid_glass.dart only keeps
`precacheLiquidGlass()`.

The tour, the Playground sandbox, the stress lab and the lab chrome were
removed on 2026-10-03 (they live at v0.4.0 and in history). The honesty
criterion they established still holds: a morph must TRANSFORM IDENTITY
(the thing you touch becomes the surface you use); spring-skinning
ordinary controls is animation, not morph.

Entry points (main.dart): `--dart-define=MORPH_AUTODEMO=true` runs
`runAutodemo` (lib/autodemo.dart) - every gallery page in order, a
center tap, a horizontal drag and an upward scroll through synthetic
pointer events, pop home, `AUTODEMO` lines, exit (the web build stays on
the home page); GalleryApp takes an optional `navigatorKey` for it.
`--dart-define=MORPH_BENCH=true` runs `ReleaseBenchApp`
(lib/perf/release_bench.dart). Device-side harnesses (profile builds
launched with devicectl) live in example/integration_test/ and are listed
in the passports.

`example/ios/` (Runner, bundle dev.tembeon.morphExample, team
83S63575XD) runs the gallery on the owner's iPhone next to the native
controls.

Flight-to-skin coupling lives entirely in the core: a consumer uses
`MorphPiece.morphable` and just calls `showMorph*(from: pieceId)`.
Hard-won rules still enforced in the core:
- Stack children in MorphSkin MUST be keyed by piece id - otherwise
  removing a piece from the middle of the list confuses the identity of
  stateful content (MorphTag used to hit 'duplicate id' asserts);
- content with a MorphTag stays HOME for the whole flight (it must not
  move: the flight tracks the source through the tag); only the mass
  blob travels.

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

- ONE frame stream: `MorphFlight.geometryTicks` merges the value spring,
  displacement, content-size channel and target `repaint`; the skin
  subscribes there. `MorphFlight.frameTicks` adds the scrim channel for
  the shuttle, so scrim-only ticks never retrace geometry. New co-drivers
  join the merge, never a controller notifyListeners backdoor.
  Widget-layer driven springs never write into it.
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
  control's ticker sleeps when its motion settles. `MorphControlHost`
  hosts build in `buildControl`; `build` hands back the last result
  while `buildsLike(oldWidget)` holds (every field the build reads equal,
  callbacks only by nullness - so a build must never capture a widget
  callback, it calls `widget.onX` at event time), no dependency changed,
  no setState ran and `buildInputs` (state the build reads, e.g. the
  segmented control's selection) is unchanged: a parent rebuilding a page
  of unchanged controls rebuilds none of them.
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
   an endpoint filter, not a clock on a property; the scrim channel
   (`scrimMotion`) is a third DOF whose target is the flight's open /
   closed INTENT, never the value spring's output; each DOF stays pure
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
- "One mass - one shadow" for engine flights; the menu is two blobs
  fused by UIKit's blurred SDF (a transient Gaussian of up to 20 pt on
  their union, so a neck while they part); the skin merges by the
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
  skin; the glass renderer shades the outline the package hands it and
  never fuses on its own (the renderer's blend groups are not used).
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
- Example layout: `gallery/` (the measured widgets gallery, one file
  per page plus the glass settings and painters), `perf/` (the release
  bench), autodemo.dart, main.dart (the entrypoint and its two
  dart-define modes). Tests that replay fixtures live in the PACKAGE (test/), the
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
cd example && flutter build web --wasm   # as is: the liquid tier compiles to stubs there
```

Every step must be green after each change (analyze from the package
root also covers example). Motion fidelity is judged by the REPLAY
tests against the recordings; the human eye judges on glacial / slow-mo
and, for the widgets, on the iPhone next to the native controls (the
example has an iOS target). Agent self-verification is the tests (966
in the package + 11 in example; run them with `nice -n 10 flutter test
-j 2` when the Mac is shared) plus the autodemo with no EXCEPTION in
the log and `AUTODEMO done` at its end (autodemo: every gallery page in
turn - push, center tap, horizontal drag, upward scroll, pop home - then
the app exits).

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
  doubles the scale error. A replay feeds the recorded touches into the
  PURE motion class at their recorded times and compares geometry per
  frame within per-quantity tolerances: a red replay is a fidelity
  regression, never a flaky test, and tolerances are not knobs.
For changes touching the tracing pipeline additionally run the
microbenchmarks (`flutter test benchmark/liquid_benchmark_test.dart`)
and compare against the previous numbers on the same machine (JIT -
relative only).

## Performance passport

ROUND 5 native resource experiments (Pixel 6a, 2026-10-07, c80a905):
no production renderer substitution. Existing grouping, two GPU + two
energy launches with three repeats: four compatible cluster surfaces
independent -> merged, GPU 9.716 -> 4.057 ms/frame, whole-phone power
1155 -> 841 mW, raster p95 11.280 -> 13.125 ms, 48 native comparisons
max channel error 0 across cluster/spread and shared/merged plans.
Spread GPU 9.853 -> 4.976, power 1184 -> 950 mW; raster p95 +0.97 ms.
These are same-depth synthetic arrangements, not gallery-wide savings.
Field-only preparation has identical native pixels and unchanged GPU;
eight energy launches establish no repeatable power benefit: reverted.
A released-texture 16 MiB cap lowers retained capacity 24.375 -> 12.188
MiB but raises post-close RSS 387.45 -> 467.04 MiB in rapid reopen stress:
reverted; reference bytes alone do not bound native memory. Haze 0.5.0
costs 11.05/24.26 ms GPU at sigma 2/10, versus stock Gaussian 2.13/2.16;
its cheaper outer ClipRect visibly changes pixels. Same-frame known
picture replay saves capture GPU work but moving-coordinate fidelity is
unresolved; full-DPR cached image input has visibly incorrect native
pixels and is rejected. Method and reproducible experimental patches:
tool/audit/codex-round5-optimization.md,
perf/2026-10-07-round5. The stage stand's phase readbacks are outside
collection; no Haze dependency or generic backdrop API is installed.
The installed Flutter GPU Texture.fromImage wraps a ready ui.Image without
copying, but does not expose the private current backdrop to Dart. A
matrix/runtime-effect native chain instead keeps that backdrop inside
Impeller: probe dimensions confirm quarter/sixteenth inputs without
per-frame scene capture. Its image and pass topology are not yet suitable
for adoption: two GPU/energy launches with three repeats give GPU
stock Gaussian 2.555/2.596 versus chain 4.007/4.541 ms at sigma 2/10,
max channel error 50/35, sigma 10 power 718 -> 873 mW. Sigma 2 power
varies too much across launches to claim a benefit. Source-path audit:
tool/audit/codex-backdrop-input-review.md.

Standalone stage stand (2026-10-07, base bdab3cb; no renderer change):
example/lib/perf/glass_stage_bench.dart compares bare/capture/blur/optics/
glass with shuffled windows, exact raw timings and separate GPU/energy
launches. Pixel 6a Vulkan default smoke, three repeats: GPU ms/frame
0.829 bare, 1.733 capture, 2.121/2.140 raw blur sigma 2/10, 2.179 optics,
3.570/3.123 production glass frost 2/10. Differences change topology and
are proxies, not exact native pass attribution or optimization acceptance.
The 36-case text/motion/grouping smoke verifies independent/shared/merged
native filter/key counts 4/4, 4/1, 1/1. Bounds are output geometry, not
capture input size or GPU RAM. Stand usage:
tool/ios_reference/perf/stage_bench/README.md;
method/evidence: tool/audit/codex-stage-bench-report.md.

ROUND 4 resource study (Pixel 6a, 2026-10-06, source 8cfcd21):
no production rendering change. Separate three-run GPU captures,
flat/liquid Mcycles/frame: tab 1.050/4.142, controls 0.434/2.153,
menu 0.687/3.289, sheet 0.971/6.002. Full liquid still costs 3.9-6.2x
flat GPU cycles here. Current menu census mean 2.89 backdrop filters,
not the old 8.8; sheet maximum 7 filters / 4 captures. Three-run
counter probe finds zero identical analytic matte encodes; sheet
median only 16 encodes/run. Per-renderer RGBA8 ring peaks reach
16.22 MiB for the animated menu and 16.50 MiB for the broad container;
not total RSS. Field-only preparation and byte-budgeted retention are
next experiments, not proven wins. Native GC does not overlap recorded
UI BeginFrame intervals. The VM allocation probe is only a heap census.
energy.py now sums duplicate raster threads; old cached CPU accounting
is warned/recomputed. The energy runner cleans its recorder on failure.
The exploratory energy runs had an extra recorder; use their rails only
with the report's limitations, not as a clean production power floor.
Full method/evidence: tool/audit/codex-round4-resource-study.md and
perf/2026-10-06-round4-*.

ROUND 3 (Pixel 6a, 2026-10-06; tool/audit/codex-round3-report.md):
flat scroll edges now keep only the fade/hairline. Census maximum
backdrop filters is 0 in all seven audit scenes. Energy A/B/B/A,
five runs per scene per launch, two launches per variant: home-scroll
590 -> 465 mW, tab bar 661 -> 519, list 553 -> 447; GPU-rail energy
-65 to -66 percent in those scenes. Raster p95 10.88 -> 9.19,
10.93 -> 8.47, 10.98 -> 8.45 ms respectively. Scenes without an edge
have no repeatable energy change. Fake/liquid deterministic frame
hashes are identical; only nav-scroll/flat changes (approved).
Separate GPU-work launches, same three scenes: 4.110 -> 2.009,
5.113 -> 2.413, 4.525 -> 2.159 ms/frame at 434 MHz (-51 to -53 percent).
One-binary interleaved scroll bench, 5 repeats: Material / morph flat /
flat without edge GPU 0.743 / 0.957 / 0.871 ms/frame, raster p95
5.85 / 6.40 / 6.01 ms. The fade adds 0.086 ms GPU; a small content/
chrome premium remains. Native baseline controls trace (2 runs): UI
QueueSubmit 0.887/frame, 0.915 ms/frame; raster 1.998 submits/frame,
2.155 ms/frame. Native self PAINT 1.615, COMPOSITING 1.284 ms/frame.
Liquid controls profiling (FRAMES_SCENE=controls, 3 runs, 250 us CPU
samples): flat/liquid BUILD mean 1.027/1.067 ms, PAINT 0.558/1.937,
COMPOSITING 0.710/2.411. Extra UI work is paint/composition and native
GPU encode/submit. A coordinate-uniform/translation-inverse trial was
REJECTED: build p95 12.32 -> 12.27 ms, raster p95 11.64 -> 12.49,
power 666 -> 645 mW; GPU 5.014 -> 4.993 ms/frame (within noise).
The original renderer remains. Full evidence lives under
tool/ios_reference/perf/2026-10-06-round3-*.

Three harnesses, one per question:

- DEVICE FRAME COST (the passport): `tool/ios_reference/perf/audit.sh`
  builds example/integration_test/glass_audit_test.dart as a profile app
  per glass tier (`AUDIT_SOURCE=` a git worktree at a fixed commit, so
  other agents' uncommitted edits stay out), runs it on the iPhone 16 Pro
  under the phone lock with `AUDIT_RUNS=5` timed repeats per scene, and
  stores `tool/ios_reference/perf/<date>-<label>/<tier>.json`;
  `summarize.py <dir> [<dir>]` prints the median of the runs'
  percentiles over ACTIVE frames (build or raster > 0.3 ms) and the
  delta between two runs; `shotdiff.py` diffs the screenshots.
- WORK PER FRAME (deterministic, every `flutter test`):
  test/perf_counts_test.dart counts rebuilds, paints, re-recorded
  pictures, backdrop captures, offscreen layers, outlines traced from
  sampled fields,
  snapshot image fallbacks and idle frames per animated frame of eleven
  scenes x three tiers, pinned as CEILINGS in
  test/fixtures/perf/counts.json (`PERF_COUNTS_UPDATE=true` rewrites it
  after a change that lowers a count). flutter_test has no Impeller: the
  liquid tier builds its real tree but paints the fallback.
- SKIN / FLIGHT (AOT): the release bench, `cd example && flutter build
  macos --release --dart-define=MORPH_BENCH=true`, run the binary, grep
  BENCH.

Device, iPhone 16 Pro, iOS 27.0.1, 120 Hz, profile, 2026-10-05, audit
without the semantics tree (as for a user without VoiceOver; buildDuration
never included the semantics flush), median of 5 runs, ms; build p95 is
2026-10-05-p2-base (2fc1dbe) -> 2026-10-05-p2-head2 (phase 2: menu face
built once, plain-union field from the box distances, container fusion
grids kept across calls, controls not rebuilt by an unchanged parent):

| tier / scene        | build p50 | build p95     | raster p50 | raster p95 |
|---------------------|-----------|---------------|------------|------------|
| liquid segmented    |      1.16 |  1.36 -> 1.41 |       1.69 |       1.94 |
| liquid tab bar      |      1.02 |  1.54 -> 1.48 |       2.19 |       2.69 |
| liquid controls     |      1.22 |  3.05 -> 2.34 |       2.27 |       2.94 |
| liquid menu         |      1.27 |  2.01 -> 2.02 |       1.25 |       3.00 |
| liquid home scroll  |      0.78 |  1.26 -> 1.26 |       1.52 |       2.20 |
| liquid sheet        |      0.78 |  1.33 -> 1.34 |       2.53 |       3.19 |
| frosted controls    |      0.71 |  1.93 -> 1.51 |       3.06 |       3.61 |
| frosted menu        |      1.45 |  3.95 -> 3.87 |       1.37 |       2.29 |
| frosted sheet       |      0.40 |  0.83 -> 0.85 |       3.23 |       3.92 |
| flat controls       |      0.40 |  2.42 -> 1.68 |       0.66 |       0.76 |
| flat menu           |      1.55 |  4.27 -> 3.85 |       0.61 |       1.60 |

Reading: every scene fits the 8.3 ms budget at p95 on every tier. The
controls scene's p95 frames were the gallery page rebuilding every
control on each slider move; the flat menu's were the silhouette (a
blurred trace at small radii, the plain union every frame of the settle
tail) plus old-generation GC landing mid-frame (10 -> 2 collections per
three opens after the container grids stopped being reallocated). The
menu's p50 build AND raster rose ~0.1-0.3 ms with the grid change
(frosted 1.12 -> 1.45 / 1.25 -> 1.37) although raster work is untouched
by it - read as the CPU clocking down under a lighter load, not as cost.
Raster is captures and blurs (flat raster is a third of liquid's); the
levers left change pixels (tool/audit/perf-research-2026-10-05.md 3.2).
Outline fusion on the device (100-call mean after a warm-up pass; the
first case after the scenes pays ~45 ms of one-time work, which read as
"4 pt 1.13 ms"): menu blur 4 pt 0.67 ms, 10 pt 0.62, 20 pt 0.36, plain
union of a 260 x 600 menu 0.49 (0.73 before), two bar capsules 0.12.
The backdrop-group fix (2026-10-05-bdg-base -> -bdg-fix, same table's
scenes) left every liquid percentile within noise; frosted menu raster
p95 2.40 -> 2.79, frosted sheet 3.93 -> 2.63 (glass-renderer.md).

The 2026-10-05 batch checked on the same iPhone (perf/2026-10-05-apple-
verify, glass-renderer.md "Apple check"): HEAD f3b812d against 268a8c2
(fake against ae40643, its first commit), 5 runs, median, ms, base -> head:

| tier / scene      | build p50    | build p95    | raster p50   | raster p95   |
|-------------------|--------------|--------------|--------------|--------------|
| liquid segmented  | 1.31 -> 1.12 | 1.56 -> 1.32 | 1.54 -> 1.35 | 1.85 -> 1.68 |
| liquid tab bar    | 0.93 -> 0.96 | 1.63 -> 1.56 | 2.04 -> 2.06 | 2.72 -> 2.82 |
| liquid controls   | 1.42 -> 1.12 | 2.74 -> 2.56 | 2.06 -> 1.55 | 2.68 -> 2.25 |
| liquid menu       | 1.41 -> 1.25 | 2.28 -> 2.12 | 1.96 -> 2.03 | 3.10 -> 3.05 |
| liquid home scroll| 0.64 -> 0.70 | 1.33 -> 1.39 | 1.56 -> 1.51 | 2.43 -> 2.32 |
| liquid sheet      | 0.95 -> 0.72 | 1.46 -> 1.33 | 2.30 -> 2.10 | 3.00 -> 2.76 |
| fake controls     | 1.04 -> 0.87 | 2.20 -> 2.20 | 2.52 -> 1.95 | 3.64 -> 3.93 |
| fake menu         | 0.88 -> 0.83 | 1.80 -> 1.68 | 2.23 -> 2.18 | 3.69 -> 3.37 |
| fake sheet        | 0.73 -> 0.60 | 1.36 -> 1.23 | 2.55 -> 2.36 | 3.26 -> 3.08 |
| flat menu         | 0.81 -> 0.84 | 3.75 -> 2.57 | 0.63 -> 0.68 | 2.45 -> 1.76 |

Every other cell moves by <= 0.1. Over budget 0 on liquid and flat; fake
controls and menu 0 - 4 frames per run on both sides (launch spread, ABBA
checked). Shots: identical within run-to-run noise. Density (liquid, raster
p50): 16 resting buttons 2.50 ms, 1.19 in a MorphGlassContainer; 32: 3.53
-> 1.46; the 96-button stress phase draws every render (geometry_failures
0). macOS: 20 gallery launches and 72 / 200 liquid buttons without a hang;
the autodemo is clean.

FIRST USE (pipeline warm-up in `MorphGlassRenderer.precache`,
glass-renderer.md "First use"): the first glass frame's worst UI / raster
ms before -> after, cold install. Pixel 6a (Vulkan): liquid 102 / 74 ->
5 / 11, frosted 2 / 64 -> 5 / 19; precache 3 ms -> 0.33 - 0.43 s, launch
to first frame +90 to +270 ms; second launches the same (the Vulkan disk
cache does not help). iPhone 16 Pro (Metal): liquid 69 / 362 -> 2 / 42,
frosted 2 / 60 -> 2 / 10; precache 0.3 - 0.5 s -> 0.85 s on a fresh
install, 1 -> 17 - 21 ms on later launches.

PIXEL 6A (Vulkan, Mali-G78, 60 Hz = 16.67 ms budget), UI-thread work,
2026-10-05, profile, 5 runs median (audit_android.sh / glass_phases;
dirs pixel6a-cpu-*, -gpu-*, -retain-*; glass-renderer.md "UI thread on a
weak device"). Every change pixel-identical (glass_frames_test hashes,
recorded fusion inputs and field renders hashed on device):

| change | measure | before | after |
|---|---|---|---|
| menu fusion (9678703) | menu build p95 flat / liquid | 14.02 / 18.96 | 11.58 / 14.80 |
| menu fusion | menu frames over budget flat / liquid | 15 / 27 | 12 / 23 |
| menu fusion | one outline, recorded inputs, AOT macOS | 383 us | 198 us |
| field uploads (07bb27d) | menu UI QueueSubmit calls / PAINT per frame | 1236 / 1.42 ms | 880 / 1.16 ms |
| retained glass layers (e2f9c4e) | 16 resting liquid buttons, COMPOSITING | 2.53 ms | 1.24 ms (flat 0.49) |
| retained glass layers | same scene, build p50 / p95 | 2.41 / 5.46 | 1.48 / 3.28 |

Liquid menu raster p95 (~20 ms) is unchanged: the saveLayers per frame
(10 vs flat 1) are one BackdropFilterLayer per glass layer and are the
effect itself.

GLYPH ATLAS (2026-10-06, glass-renderer.md "Glyph atlas under animated
scales"; perf/2026-10-06-*-glyph-base -> -after, 5 runs median, engine
timeline on both sides): Impeller keys glyphs by screen scale (1/200), so
text under a sweeping scale re-rasterized glyphs nearly every frame. The
lens copy now snaps its screen scale to a 64/octave grid while lifting
(<= 0.54 percent about the slot center, exact at rest and held) and the
menu's root rows draw from one raster while its content blur is >= 0.5 pt
(`MorphGlyphScale`, `MorphGlyphRaster`). Atlas updates/s, raster p95:
Pixel liquid tab bar 6.57 -> 2.33, 17.99 -> 17.32 (update ms per run 113
-> 13); liquid menu 12.19 -> 7.50, 20.67 -> 16.69 (130 -> 41; over budget
29 -> 20); flat menu 9.60 -> 5.14, 13.45 -> 9.70 (p99 27.93 -> 13.15).
iPhone liquid tab bar 5.80 -> 1.15, menu 8.43 -> 4.93; flat menu 12.18 ->
2.75 (p99 4.26 -> 1.99).

MENU FUSION AHEAD (2026-10-06, glass-renderer.md "Menu fusion: the
device gap and the fusion ahead"; perf/2026-10-06-fusion-probe and
-fusion-ab): the fusion's 4 - 12x device-over-loop gap is core placement
and DVFS (Pixel paced 5.3 ms against 0.43 ms in a loop, the paced calls
on the A55 / A76 cores; a pinned A55 3.4 ms, X1 0.39 ms). Fused ahead on
background isolates and served within 0.02 pt per input: menu build p95
(5 runs, median of two launches) iPhone flat 2.44 -> 1.55, liquid 2.67 ->
2.30; Pixel flat 12.2 -> 11.1, liquid 14.5 -> 13.4 ms; a served frame's
UI cost 0.04 ms (iPhone) / 0.19 ms (Pixel) against 0.85 / 7.5 ms paced.

ENERGY (2026-10-06, glass-renderer.md "Energy: ADPF and the fusion
workers"; perf/2026-10-06-pixel6a-energy, exp/adpf): Pixel 6a ODPM power
rails per audit scene (perf/energy_android.sh + energy.py, ABBA, cooled
starts). At rest the gallery home draws no frames: 286 mW for the whole
phone (display 133). ADPF (hint sessions for the UI and raster threads,
FrameTiming durations) cut menu frames over budget 16 -> 4 but cost +9
percent energy on the menu, +3 on the sheet (the UI thread moves to the
A76 / X1 cores): rejected, kept on branch exp/adpf; the engine has none.
The menu fusion workers cost 4.5 - 6 percent of the menu scene's energy
(~45 mJ a transition, the three speculative fusions a frame) for 3 - 5
fewer frames over budget in 40 transitions; one frame ahead costs
nothing and gains nothing.

SMALL BLURS (2026-10-06, glass-renderer.md "Small blurs"; perf/2026-10-06-
pixel6a-smallblur-*): a backdrop blur whose clip grown by the kernel
leaves the pass (a band along the screen edge) makes Impeller blur the
WHOLE pass, and below 5.66 device px of sigma at full resolution. The
scroll edge effect blurs a copy of its band (`morphBackdropSeed` under a
clip grown by `morphBlurReach`, within 1 - 2 steps); a frost just below
half resolution is raised to it by at most 12 percent
(`morphHalfResolutionSigma`, 2 -> 2.17 pt at 2.625, 2 - 6 steps on real
content, up to 23 on 1 px stripes). Pixel GPU ms a frame: bench scroll
flat 8.47 -> 3.71, liquid 11.15 -> 6.28; audit home-scroll 8.14 -> 4.46,
list 9.92 -> 7.68, tab bar 11.61 -> 9.33; energy home-scroll 906 -> 565
mW, tab bar 1683 -> 905, list 954 -> 705; raster p50 +0.3 - 0.8 ms (one
more backdrop filter). iOS not yet verified.

Release bench 2026-10-05, Apple Silicon macBook (tembeon), macOS:

| scene                   | us/op  |
|-------------------------|--------|
| fusedPair               |     88 |
| sandboxSpread           |    239 |
| flightFar               |    183 |
| manyPieces              |    436 |
| megaCluster64 (budget)  |  1 939 |
| megaCluster64/unbounded |  8 239 |
| oneMoving/pure          |    161 |
| oneMoving/cached        |     57 |

Frame timings (glacial open+close, n=756): build avg 0.21 / p95 0.52
/ worst 0.83 ms; raster avg 0.71 / p95 1.33 / worst 4.33 ms. The cached
animated skin frame costs 57 us; the eval budget keeps the 64-piece
worst case at 1.9 ms (8.2 ms unbounded).
