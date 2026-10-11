# Engine rules

The constraints every change to morph code must respect: API vocabulary,
the one-implementation rules, the flight invariants, motion principles
and the approaches that are rejected on purpose.

## API conventions

- One vocabulary: every public type is `Morph*`. The liquid subsystem is
  "the skin": `MorphSkin` / `MorphPiece` / `MorphLink` / `MorphSkinStyle`
  / `MorphStroke`, with the knob `blend:` (the widget name for the smin
  `k`; the internal math layer keeps `k`, the SDF literature's name).
  "Liquid" is the technique name inside liquid_field.dart only; nothing
  `Liquid*` is exported.
- Raw SDF masses for `MorphSkin.extraMasses` are `MorphMass`: one sealed
  type with const redirecting factories `.box(rect, radius:)` and
  `.bridge(a, b, radius:)`, subclasses private. A mass has no morph
  identity and cannot fly.
- The flat "kind + 5 params" record (stride `liquidMassSignatureStride`)
  is the canonical mass flattening. `liquidMassSignature` (@internal) is
  its one implementation, written into both the tracer's cluster keys and
  the skin's input signature (a preallocated Float64List, full
  parameters: two diagonal bridges can share an outerRect yet trace
  differently). The only other kind-switch is the field sampler, which
  keeps per-vertex math free of dispatch.
- The motion profile parameter is `motion:` everywhere, never "speed" (a
  profile carries character, not just tempo). Springs are
  `MorphSpring(response, dampingRatio)` in UIKit terms; widget tunings
  expose MorphSprings, not motor Motions.
- `MorphMenuItem` names `MorphMenuButton`'s rows (`title`, `icon`,
  `destructive`, `onSelected`).
- Export diet: foundation.dart is the whole engine surface; liquid_field
  internals, RenderMorphSkin and the shared-element machinery are not
  exported (package-internal tests import src/ directly). widgets.dart
  exports by explicit `show` lists; the widget machinery (clock,
  integrator, timeline, spring state, lens driver, focus, glass layer) is
  @internal. The minimal motor vocabulary (Motion, CupertinoMotion,
  MaterialSpringMotion, CurvedMotion) is re-exported.
- Engine seams that must stay public for cross-file use are annotated
  `@internal` (scope registries, tag machinery, controller.notifyFrame,
  flight route/shared plumbing) so the analyzer warns consumers off.
- Design-system package: morph imports
  `package:material_ui/material_ui.dart`, never the in-SDK
  `package:flutter/material.dart`. The two are separate copies of
  Material with incompatible types (`material_ui.Theme` is not
  `flutter/material.Theme`), so a consumer on the in-SDK library migrates
  too or wraps the morph subtree in `MaterialUiCompatibilityBridge`.
  `cupertino_ui` is transitive only: morph uses no SDK Cupertino
  (`CupertinoMotion` comes from motor). Icons resolve through
  `uses-material-design: true`.
- Engine-to-Material debt: the core still touches Material in four
  places, so foundation.dart pulls material_ui onto every consumer:
  - `theme.dart`: MorphTheme extends ThemeExtension, read via
    `Theme.of().extension`.
  - `flight.dart`: `Theme.of().colorScheme`, the shuttle's Material
    container, the optional MaterialLocalizations barrier label.
  - `route.dart`: MaterialLocalizations barrier label, colorScheme, the
    settled page's Material.
  - `show.dart`: DialogThemeData / BottomSheetThemeData adoption.
  scope.dart and target.dart import material_ui for types only. The
  shuttle's Material is what lets dialog content use InkWell and default
  text styles; removing it is a behavior break. MorphWidgetsTheme is a
  ThemeExtension too.
- Retarget contract: a repeated showMorph on a live tag retargets the
  existing flight. It keeps its target, builder, barrier and scrim
  (content lives in the shuttle and cannot be swapped mid-air); only
  motion, dismissal routing and semanticLabel update.
- `from:` is optional in showMorph* / showMorphRoute: inside the source
  tag's subtree the nearest enclosing MorphTag is the source
  (`MorphTag.idOf`). The shuttle does not republish that marker, so
  dialog content names its source explicitly; calls from elsewhere pass
  the id.
- Surface rendering is an opinion, not engine contract: the contract ends
  at `MorphTag.specOf`. Render the surface from specOf with your own
  design system and a GestureDetector, or use MorphGlassButton for a
  button that is a morph source.
- `MorphPageRoute.barrierLabel` is the localized dismiss label (passed by
  showMorphRoute), not the route name; that is `semanticLabel`.

## Structural conventions

- One frame stream: `MorphFlight.geometryTicks` merges the value spring,
  displacement, content-size channel and target `repaint`; the skin
  subscribes there. `MorphFlight.frameTicks` adds the scrim channel for
  the shuttle, so scrim-only ticks never retrace geometry. New co-drivers
  join the merge, never a controller notifyListeners backdoor.
  Widget-layer driven springs never write into it.
- One geometry: `morphFlightGeometry` + `morphConcentricRadius`
  (frame.dart) are the only implementations of the frame's rect/radius
  math; computeMorphFrame and the skin's mirror blob both call them.
  `MorphTargetSpec.resolveRect` is the one rect resolution (fixed or
  measured); `morphTargetPaddingOf` / `morphContentViewInsets` are the one
  keyboard math, called by the shuttle and the settled route page alike.
- A tag below a paint transform captures its whole local bounds through
  `getTransformTo` + `MatrixUtils.transformRect`. Transforming only the
  local origin while keeping the layout size makes a centered scale jump
  smaller and off-center on the first flight frame.
- One content chain: `buildMorphTargetContent` (flight.dart) is the only
  place the target wrapper chain exists; the shuttle and the route page
  both mount it. The route-mode reparent preserves state only while the
  chains match.
- One drag composition: `morphDragScrimFactor` + `morphDragScale`
  (gesture.dart) are the only implementations of how a live drag dims the
  scrim and recedes the card; the shuttle and the settled route page both
  call them. The displacement channel is `_DragChannel`, a
  ChangeNotifier owned by the flight; the public drag API delegates.
- Rule of three homes for visual constants: an ambient engine default
  lives in MorphTheme; a value drawn by more than one stack lives in one
  named implementation; a local literal is legal only while exactly one
  paint site uses it. In the widget layer a measured constant lives in
  its tuning class (MorphLensTuning, MorphMenuTuning, MorphFlexSpec, the
  *Motion statics) with the measurement in its dartdoc, never as a bare
  literal in a widget.
- Widget-layer motions are pure: explicit time in, geometry out,
  `MorphSpringState` closed-form springs, `MorphTimeline` for every
  delay, `MorphSubClock` for every per-frame filter. A widget host owns
  only the MorphClock, the Listener, focus/semantics and painting. A
  control's ticker sleeps when its motion settles.
- `MorphControlHost` hosts build in `buildControl`; `build` returns the
  last result while `buildsLike(oldWidget)` holds (every field the build
  reads equal, callbacks compared only by nullness), no dependency
  changed, no setState ran and `buildInputs` is unchanged. So a build
  never captures a widget callback; it calls `widget.onX` at event time.
- Example spring recipes ride motor's `SingleMotionController` (retarget
  with velocity carry-over built in); hand-rolling is only for places a
  controller cannot go (the chips wave evaluates sims at t*rate, and a
  controller owns its own clock).

## Invariants

1. Every visual property of an engine flight is a pure, symmetric
   function of one spring's state (value, velocity): no
   direction-dependent curves, no wall-clock time. This gives
   interruption continuity by construction. Precisely: one spring per
   degree of freedom. The gesture displacement is a second, orthogonal
   DOF with its own always-to-zero spring; the content-size channel is an
   endpoint filter, not a clock on a property; the scrim channel
   (`scrimMotion`) is a third DOF whose target is the flight's open /
   closed intent, never the value spring's output. Forbidden in the
   engine: two clocks driving the same property, or a lagging spring
   whose target is fed from the first.
   Native-fidelity exemption (widget layer, measured behaviour only):
   where UIKit itself is not a function of one spring's state, morph
   follows UIKit. Two kinds exist:
   - (a) the flex loop: three one-pole filters, alpha 0.3 per rendered
     frame, over the previous frame's visible position, closed through
     drift/scale targets; it runs on a fixed `MorphSubClock` in motion
     time at the device refresh rate (120, or 60 on a 60 Hz display), so
     it responds per frame like UIKit yet stays identical under
     timeDilation and coarse test pumps;
   - (b) driven secondary springs: the lens drift/scale presentation
     springs chasing per-frame targets, the small lens stretch, the menu
     kicks (chasing the progress velocity, struck on close), integrated
     over every advance.
   Limits of the exemption: every such state retargets from its current
   (value, velocity) and is never restarted; time is the MorphClock's
   motion time (ticker elapsed, timeDilation-aware, events stamped from
   their own timestamps), never a wall clock or Stopwatch; nothing exempt
   feeds `MorphFlight.frameTicks` (the menu runs the flight's progress
   spring on its own motion clock and draws its kicks inside its vessel,
   and on the button after the latch). A new exempt behaviour needs a
   recording that shows it.
2. Retarget is a new simulation from the current (value, velocity). One
   active flight per tag; re-showing retargets it.
3. Handoff latch: the shuttle-to-widget swap happens exactly on the first
   zero crossing of the close; the rest of the undershoot plays on the
   live widget (`isLanding`). No landing bump is added anywhere.
4. Target content lives in the shuttle for the whole flight. No
   reparenting except the route's second latch; a GlobalKey inside the
   tag child is forbidden (asserted).
5. Shadow and elevation belong to the shuttle and lerp source to target
   (a button with its own shadow declares `MorphTag.elevation`). Vessel
   targets draw neither.
6. closeMotion must be able to go below zero (a spring), otherwise the
   latch degrades; `snapToEnd` stays false. Enforced in debug by
   `MorphMotion.debugContractViolation`, asserted whenever a profile is
   installed into a controller. The open may overshoot.

## Motion design principles

- Measured UIKit behaviour is the default spec. Springs are spoken in
  UIKit's vocabulary (response, damping ratio), and a number in lib/
  carries its source in its dartdoc (read from tuning, or fitted, with
  the fit's spread when it matters). Fidelity may be traded for
  performance where the eye cannot notice it, with the trade stated as
  identical, near or approximation.
- The engine default is UIKit's liquid morph: open 0.35/0.75 overshoots
  about 3 percent, close 0.49/0.80 undershoots about 1.5 percent. The
  landing is that undershoot and nothing else; a close from rest starts
  still.
- Reversal is a retarget with velocity everywhere: flights, lenses,
  knobs, menus.
- Content arrives with its surface: no cascades (UIKit's menu rows and
  context-menu satellites do not cascade).
- One mass, one shadow for engine flights. The menu is two blobs fused
  by UIKit's blurred SDF (a transient Gaussian of up to 20 pt on their
  union, so a neck while they part); the skin merges by the
  normal-modulated smin.
- Deformation comes from UIKit's flex loop (acceleration, not velocity),
  never from a hand-made squash.
- For the eye: `MorphMotion.glacial` for flights, the gallery's slow-mo
  (`timeDilation`) for widgets; both preserve the curves.

## Rejected approaches

- Hand-tuned physics in lib/ (Tug, MorphPillHost, MorphSquash,
  SpringButton, ChaseSpring, morphPressGrowth, landing bumps, close
  velocity hints, MorphMotion slow/normal/glass/fast, skin presets
  geometric/goo, GooSelector/SpringToggle): unmeasured; the replay is the
  judge.
- A/B feel labs: side-by-side taste does not replace the replay.
- MorphSurface/MorphTapTarget Material adapters: surface rendering is the
  app's opinion, the contract ends at `MorphTag.specOf`.
- MorphReveal cascades: native content arrives with its surface.
- The popover showMorphMenu: replaced by MorphMenuButton.
- Kyant0's five-spring DampedDrag: superseded by UIKit's flex loop.
- Replaying recorded kick tables frame by frame: a table cannot carry a
  reversal; the kicks are driven springs.
- A fixed 60 Hz sub-clock or a time-normalized alpha for the flex loop:
  device data shows alpha is per rendered frame.
- Reproducing UIKit artifacts (tab bar bar-local glitch, the second menu
  kick variant, 60 Hz geometry refresh on 120 Hz, the inline menu's 1/60
  frame lock): bugs are not spec.
- Plain (unmodulated) smooth-min: lifts aligned edges by k/4, which Apple
  never does. The renderer's sin(theta/2) chord: necks too fat.
- Blur+threshold liquid necks (metaballs, blur-based SDF shaders): halos
  and mush. The skin stays the CPU vector path and the renderer's blend
  groups are unused; the analytic shader path is an exact evaluation of
  the package's own merge law, not blur+threshold.
- A prebuilt drag widget: dismiss gesture policy belongs to the app; the
  primitives and the scrub API remain.
- Snapshot ghost by default: a frozen ripple looks worse than a live
  replica; it stays opt-in for heavy content.
- "Position leads, size follows" and back-out on position: unsupported by
  platform references and wound up on close. Geometry is linear in the
  value; character comes from physics.
- motor's MotionController for the engine flight: its settle semantics
  conflict with the handoff latch. The engine uses Motion only as a
  simulation factory (widgets and recipes may ride
  SingleMotionController).
- anchorScale in the frame: a remnant of a two-blob model.
- Built-in gesture driving of flights, text/layout morphing: out of
  scope.

Kept although the engine does not use it: `MorphFrame.cornerRadius`
(public info for consumer accessories, covered by a test).
