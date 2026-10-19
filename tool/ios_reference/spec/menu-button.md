# Menu button passport (glass button that becomes its menu)

Status: measured device (layers, traces, film) + simulator; ported;
replayed in part: fusion (menu_fusion_test), flex under a finger
(menu_drag_out_test), bar item tap and hold lags (bar_menu_tap_test),
close with a submenu stack (menu_api_test). No test replays the open
spring, the kicks, the placement, the early touch or the reopen captures
under `ios27-device/menu/` and `ios27/menu/`: their replays lived in
menu_button_test, removed in 98237e58 (2026-10-19). menu_look_test checks
text style and glyph order, not native data.


The context menu shares this implementation (context-menu.md, unified
2026-10-14): the same controller, motion, layer, rows and haptics on the
context morph (`MorphMenuMorphSpec.context`) with a
`MorphMenuAttachment` instead of a source shape.
## Native

`UIButton` with `menu` + `showsMenuAsPrimaryAction` (glass configuration),
also `UIBarButtonItem(menu:)`. Morph container = `AnimationKit` morph view
(`MagicMorphView`-like SDF layer) holding the menu blob G and the button
blob S, `KickView` translations, `_UIContextMenuView` content.
Tuning `AnimationKit.MorphAnimationSettings.liquidMorph` [tuning].
UIMenu API (SDK 27.0, unchanged in 27.1): `children`, `options` (displayInline, destructive,
singleSelection, displayAsPalette), `preferredElementSize` (small / medium
/ large / automatic), `displayPreferences`, `selectedElements`, submenus;
UIMenuElement `title`, `subtitle`, `image`, `preferredImageVisibility`,
UIAction `state` (checkmark), attributes (disabled, destructive, hidden,
keepsMenuPresented); `UIDeferredMenuElement`;
`preferredMenuElementOrder`.

## Spec - progress and shapes

- `MorphMenuMorphSpec.standard` = liquidMorph, speed 0.7 DIVIDES time:
  eject 0.5/0.75 -> open 0.35/0.75; absorb 0.7/0.8 -> close 0.49/0.80
  [tuning].
- Two blobs as a UNION: G = W x W square scaled to half the button height,
  stretching to the menu height while scaling up, center lerped button ->
  menu plus a VERTICAL kick; S shrinks to 0.25 scale and travels 0.25 of
  the way.
- Opening radius 195.4 -> 32 with a 0.098 s delay (capsule until p crosses
  1); close radius linear in p.
- KICKS (driven secondary springs, exemption): G's open kick chases
  `openKickGain` x dp/dt on `openKickSpring` 0.2048/0.651; a close STRIKES
  it away from the button (`closeKickImpulse` 1450 px/s after
  `closeKickDelay`, shrinking linearly to nothing at `closeKickReach` of
  carried kick), rings on `closeKickSpring`; S's kick chases the closing
  velocity on `sourceKickSpring` (`sourceKickGain`). Amplitudes per menu
  HEIGHT from a measured table (`kickAmplitude`). The close strike is a
  FIT, not a generative law.
- FUSION / NECK [device layers + film]: the container is an SDF layer with
  smoothness 0 whose field is blurred by `gaussianRadius` as a standard
  deviation (fit 0.9 - 1.2), up to 20 pt (`fusionRadius`), rising with
  every open/close and falling back to nothing (`fusionEnvelope`); facing
  edges draw to a point, the shrunk button is absorbed, a neck joins the
  shapes across the gap. Fixture `ios27-device/menu/fusion.json`.
  morph (menu_fusion.dart `morphMenuSilhouette`): the field grid (every
  2nd trace node below a 4 pt step) is sampled everywhere, the trace grid
  only in 2-cell blocks whose corners leave the edge within reach (the
  blurred field is 1-Lipschitz); a node whose blur window sees one
  straight side of the nearer shape keeps its unblurred distance (exact:
  the symmetric kernel leaves a linear field unchanged), one inside a
  single round corner takes the Rice mean of the distance to the corner's
  center with the kernel's variance (within 0.006 pt of the kernel);
  the rest is the separable kernel. Pinned against a brute-force blur by
  menu_fusion_test. Cost: glass-renderer.md.
- ONE CLOCK: the menu draws from its own closed-form progress spring on the
  clock its kicks run on (trace: open kick error 0.27 / 1.0 pt vs 1.14 / 3.7
  when reading the flight controller).
- Landing: UIKit keeps the morph container until the kicks ring out
  (~0.85 s after the latch; button shape still 4 px off at p = 0).

## Spec - look and content [film, 2026-10-03; layer model was wrong]

- Glyph rides S, alpha falls over p 0.07 .. 0.42 (`lookFadeStart/End`),
  width x (1 + 2.5 p) (`lookStretch`), blur 4 p.
- Content rides G at the shape's scale + 1.45 x kick / H
  (`contentKickScale`), blur 8 (1 - p) + 6 kick / H; opening alpha follows
  progress from 0; closing alpha falls linearly to 0 at p 0.53
  (`contentCloseFadeEnd`); fades read the spring 15 ms ahead (`fadeLead`).
- Menu taller than wide keeps its first row on the shape's top edge
  (upward 10-row menu unfolds from the far edge); shorter stays centered.
- Blurs use TileMode.decal. Rows do NOT cascade.
- Rows 17 regular; device menus are 82 + 42 x rows tall vs simulator 20 +
  42 x rows: the +62 pt is the system separator + "Ask Siri" row iOS
  27.0.1 appends (visible in references/dark/menu-open.png); tuning uses
  the simulator padding.

## Spec - placement and triggers

- Down (menu.top = pressed button top) when the button is in the upper half
  of the safe area, else up with rows reversed; centered on the button when
  it fits, else edge-aligned with the PRESSED edge; clamped into the safe
  area unioned with the keyboard.
- Tap opens on release (`tapOpenDelay`); hold opens after 0.22 s and the
  finger may slide onto a row; a held finger released without having left
  the button chooses nothing and leaves the menu open (center3-hold700,
  navbar3-hold300/700 - no action, no close); item action fires BEFORE the close; menu is
  hit-testable from its first frame; a tap on the button while it closes
  re-opens on the touch-up with velocity reversal.
- EARLY TOUCH [device, center3-closemidopen / retap-midopen /
  early-outside-{10,25,50,100,200}]: a touch between a tap's release and
  the opening (`isOpenPending`) belongs to the menu; outside -> close
  `earlyCloseDelay` 0.016 s after the opening whatever the release time
  (p always peaks ~0.167); on a row's spot -> action at opening +
  actionDelay, close at opening + 0.016 (quick double tap picks row 0 of a
  downward menu); finger still down at opening = menu finger (released
  after: ordinary dismiss, device +0.028 s vs the dismissDelay of the
  time, 0.04 (0.059 since c4d14a7, menu-api.md "Close timing"), the
  early-outside-200 capture, not replayed). Replay 0.008 rms of progress
  (menu_button_test, removed in 98237e58; no test replays it now).

## Keyboard changes after presentation [device, 2026-10-18]

Public UIButton.menu / showsMenuAsPrimaryAction probe, iPhone 16 Pro / iOS 27.0.1, portrait 402 x 874 pt at 3x, source `(161,406,80,48)`, safe area `(0,62,0,34)`, Dynamic Type L, Reduce Motion false. No phone settings changed. Evidence: `tool/audit/foundation-p2-2026-10-18/native-ime/` (repo root), `docs/architecture/menu-native-ime.md`.

Three short-menu controls and two repetitions of three ten-row-menu modes execute real keyboard show/hide through UITextField first-responder commands. Settled public XCUI row frames (1/2/3/10 for tall) remain exactly unchanged within each mode. Initial keyboard state changes tall placement: first row y410 without keyboard versus y ~135 with keyboard. Hiding afterward keeps y135. Showing afterward keeps y410 and last-row bottom 830, while the keyboard notification top is 573; the keyboard visibly covers lower rows. The notification rectangle `(0,573,402,301)` differs from XCUI keyboard element `(0,590,402,226)`.

Snapshots bracket the actual command/completed notification with positive timing margins. A corrupted interval is rejected by the analyzer. This establishes bounded endpoint placement, not transient trajectories, optical-body equality, dismissal/landing, context-menu behavior or Flutter parity. No tuning changes follow from these endpoint observations; active geometry/IME ownership integration remains open.

## Selection and fresh reopen after IME [device, 2026-10-18]

Two serial ten-row none/show/hide repetitions on the same public probe yield six scenes, twelve openings and twelve selected callbacks. Each Native first / Native second selection closes the observed menu, updates count 1/2 and leaves the same source hittable for reuse. Source frame/token stay fixed within each scene. Four observed row frames stay unchanged after the keyboard transition, but fresh reopen uses current IME state: first-row y410 -> 135 for show, y135 -> 410 for hide, y410 -> 410 for control. One control reopen changes x by 1/3 pt; full reopen-frame equality is not claimed.

Both show scenes record first responder at both actions/reopen and receive native through XCTest without retapping the editor. During XCTest typing, WillHide/DidHide occur with first responder retained; the typed AX keyboard exists offscreen (y891 in an 874 pt window). This proves input delivery, not sustained keyboard visibility. Snapshot/event ordering and a corrupted selection-time negative control pass their respective acceptance/rejection gates. Evidence: `tool/audit/foundation-p2-2026-10-18/native-ime-reopen/results.md`. Functional closed reuse does not prove optical morph landing, transient continuity, moving-source or context-menu policy. No motion tuning changes.

## Bar item menu as primary action [device, 2026-10-05]

`UIBarButtonItem(menu:)` WITHOUT a primary action (probe scene `menu`, the
nav bar's ellipsis item; captures navbar3-repeat / quicktap / hold300 /
hold700 / dragselect, ProbeUITests.testMenu; summary fixture
`ios27-device/menu/navbar-tap.json`, raw
`recordings/device-navbar-20261005`). It behaves as the inline
`showsMenuAsPrimaryAction` button, measured on the same metric (first tick
of the morph container):
- Tap opens on RELEASE, 0.013 s later than the inline button: 0.0610 -
  0.0632 s after later releases (4 taps) vs 0.0489 - 0.0495 inline; first
  releases after a launch 0.094 - 0.125 s vs 0.086 - 0.108. morph:
  `MorphBarMenuTuning.measuredMenu` = standard with tapOpenDelay 0.102.
- Hold opens WHILE DOWN at 0.260 - 0.264 s (3 holds) vs 0.256 inline:
  within a frame, `holdDuration` shared. A release on the button after it
  leaves the menu open; a slide onto a row chooses it (action 0.012 s
  after the lift).
- Geometry: the morph out of the bar capsule is the menu motion of
  navbar3-dismiss (no source kick on the close); its replay lived in
  menu_button_test, removed in 98237e58.
- morph: `MorphBarButton(menu:)` with null `onPressed` (bar_items.dart);
  the bar feeds the finger into the menu motion as MorphMenuButton does.
  Pinned by bar_menu_tap_test (also asserts the recorded differences).

## Disabled button [device, light + dark, 2026-10-03]

- A disabled glass menu button (`showsMenuAsPrimaryAction`) looks like a
  disabled `.glass()` button: glass unchanged, the glyph tertiaryLabel (dark 0x4CEBEBF5, light 0x4C3C3C43); no opacity.
  One frame, no animation.
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method in [states](states.md).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): `MorphMenuButton.enabled`,
  `MorphMenuAppearance.disabledIconColor`; a tap does not open.

## Platter color, light [device screenshot, 2026-10-03]

- Light menu platter interior (references/light/menu-open.png, page
  242,242,247): 249,249,255 flat; rim 254 top / 251 bottom outer pixels;
  the shadow darkens the page to ~224 - 238 just outside. Dark: 32 over
  black (0xF2222222, ported in daa1bae).
- Identical to the light date picker overlay platter (date-picker.md).
- Ported 2026-10-03: `MorphMenuAppearance.light.glassColor` 0xF2F9F9FF. Light
  audit on the simulator (liquid tier): the renderer draws the interior
  246,246,252 - 3 levels under native; the renderer's light material, not
  the color, is off (see glass-optics.md).

## Spec - finger dragged on and off the open menu [tuning + device, 2026-10-13]

Mechanism confirmed live on the device; the equations, the spec numbers
and the 40-point in-bounds term are read from UIKit, notes private (kept
outside the repository).

- It is UIKit's flex interaction (lens-and-flex.md) in its menu variant
  (spec `_UIFlexInteractionSpec.menu` = `MorphFlexSpec.menu`), attached
  by UIKit to `_UIContextMenuListView` (in `interactions`, not a
  `flexInteraction` property) because the list's glass is built
  flexible. The variant skips the velocity integrator: it updates on
  every update-link frame from the finger's translation and a pulse.
- Inputs, from the touch-down point: t = translation, it = the location
  clamped into the list's bounds minus the touch-down point. W, H = list
  bounds.
- Targets while the finger is down [tuning]:
  kx = (|t.x| - |it.x| + 40 |it.x| / W) / 6000 (ky likewise with H);
  sx = 1 + kx - ky, sy = 1 - kx + ky; driftX = sign(t.x) kx W,
  driftY = sign(t.y) ky H. Pulse: p = v * ay / 8000 with v the velocity
  of `translationY`, a spring (0.574, 0.548, tracking) chasing t.y and
  ay = +1 for a menu below its button and -1 above (measured; UIKit reads
  it through the view's anchor). Then sx *= 1 - 50 p / W,
  sy *= 1 + 32 p / H, driftY += ay 22.4 p; sx and sy are clamped to
  [0.9, 1.1]. Lifted: 1, 1, 0, 0.
- The four values are channels (lens-and-flex.md "Channels"): while the
  finger is down they chase the targets on the spec's tracking spring
  MorphSpring(0.15, 0.5), after the lift they return on its scaleSpring
  MorphSpring(0.6, 0.5), and every changed target adds velocity
  stiffness x 0.016 x the change [device: the recorded channel states
  match this on every changed retarget; the release fit lands on
  0.6/0.5].
- Geometry [device]: width W sx, height H sy, center x + driftX, and the
  edge facing the button + driftY (the top of a downward menu, the bottom
  of an upward one). The transform is on the whole list, so the glass,
  rows and footer stretch together.
- Readings: per point the finger travels inside the menu, the menu moves
  40/6000 = 0.0067 pt; per point beyond the edge, W/6000 (0.042 for
  250 pt) along that axis. It grows along the drag by the drift and
  narrows across by k times the cross size. The "sway" is the pulse: the
  vertical finger velocity, filtered by the translationY spring, makes the
  menu narrower, taller and carried along when moving away from the
  button, wider and shorter when moving toward it. Horizontal motion has
  no pulse.
- Validation (`lab/menu_flex_model.py`, fixtures
  `ios27-device/menu/drag-out-flex.jsonl` and `drag-out-upward-flex.jsonl`):
  0.25 / 0.26 pt edge rms with UIKit's recorded translationY velocity and
  no fitted constant; 0.25 / 0.27 / 0.30 pt with the stepped spring
  below (`menu_flex_model.py FIXTURE stepped`, the third the tap capture),
  0.77 / 0.86 / 0.91 pt with the same spring run in wall time.
- translationY is a stepped spring, and its velocity runs 2x its
  presentation rate while the finger moves [observed live on iOS 27.0.1
  via the probe's animation tap; fixture
  `ios27-device/menu/drag-out-animation-tap.jsonl`]:
  - Nothing reaches Core Animation: on every finger move UIKit adds no
    animation to any layer (no CABasic / CASpring, additive or not, no
    UIViewPropertyAnimator). The only adds are the touch-down CAMatch*
    corner / bounds animations of the flex glow container and SDF
    elements; the open and close add only CAMatch* and CATransition
    animations too. The flex is evaluated by UIKit itself and reaches the
    layers as plain model values.
  - The channel advances in whole 1/60 s steps and, while the finger is
    down, publishes at 30 Hz (every fourth 120 Hz frame). An update whose
    target g = t.y changed since the previous one (a retarget) advances
    the spring by ONE step, h = 1/60 s, although 1/30 s has passed; an
    update with an unchanged target (finger held) advances it by the two
    steps that passed, h = 1/30 s. After the lift it runs in wall time.
  - Equation, per update n: (x, v) <- S(x, v; g_n, h_n), with S the exact
    solution over h_n of x'' = w^2 (g - x) - 2 z w x', w = 2 pi / 0.574,
    z = 0.548; h_n = 1/60 when g_n != g_(n-1), else t_n - t_(n-1). One
    step reproduces the recorded presentation and velocity to 0.01 pt and
    0.1 pt/s on 104 of 105 retargets and all 61 held updates of the tap
    capture (84 / 87 and 79 / 79 in `drag-out-upward-flex.jsonl`); the
    misses are the update where the finger stops.
  - The 2x: with updates every D = 1/30 s and h = 1/60, the spring's clock
    runs at h / D = 1/2 of wall time. Its velocity v (the one the pulse
    reads) is per spring second, so v = (D / h) dx/dt = 2 dx/dt. On a
    finger ramp of speed s the presentation approaches s and v approaches
    2s (the device's ~2.1x peaks). Continuous equivalent while the finger
    moves: x is a (1.148, 0.548) spring in wall time and v = 2 dx/dt; a
    held or lifted finger returns to the plain (0.574, 0.548) spring.
- morph (`MorphMenuTuning.flex`, `flexTargets`, `flexInBoundsPoints`,
  `flexPulseSpring`, `flexPulseRate`, `flexPulseRetargetStep`,
  `flexDelay`) ports the above; it replaces the fit of 9d8f32c (pull,
  0.33/0.72 return, separate sway spring):
  - origin = the touch-down on the open menu (a finger that opened the
    menu by holding: where it was when it first moved on the open menu);
    the channel is reset to (0, 0) there and its velocity zeroed at the
    lift. W, H, the clamp bounds and the side come from the menu's rest
    frame.
  - sx, sy, dx, dy are `MorphChannel`s retargeted whenever the targets
    change (a finger move after flexDelay, a pulse step): tracking
    0.15/0.5 while down, 0.6/0.5 after the lift from what shows with its
    velocity, the 0.016 impulse on each change. NEAR: UIKit publishes them
    at 60 Hz tracking / 30 Hz settling; morph evaluates every frame.
  - flexDelay 0.023 s = touch stamp to the flex's translation (14.4 /
    15.9 ms median in drag-out-flex / the tap capture) plus the one
    120 Hz frame the list's frame follows it by [device].
  - the translationY clock is the observed rule above as a LABELED
    APPROXIMATION: 30 steps a second counted from the flex's touch-down,
    a changed target advances 1/60 s, an unchanged one the time that
    passed. UIKit's rule for choosing the target and step from touches
    alone is not frozen (rates other than 120 Hz and Reduce Motion are
    unknown). No global time halving, no velocity factor.
  - NEAR, awaiting approval by eye: while the finger rests the channel
    stops stepping once its largest possible remaining swing cannot move
    an edge by 0.25 pt (`flexPulseRest`, the old sway's rest; perf_counts
    menu-held 224 frames, 238 at 0.01 pt); the flex channels likewise
    count as at rest within 0.25 pt of their targets while the finger is
    down (UIKit itself lands a channel near its target on it). NEAR
    (invisible): the return counts as at rest below 0.01 pt
    (`flexReturnRest`).
  - Perf: a menu frame whose motion stood still since the previous one,
    with no input or pending reaction in between, does not repaint the
    menu layer (`MorphMenuMotion.revision` / `isStill`); between two
    channel steps a resting finger draws nothing new.
  - Input-only replay (touches in, list frame out; menu_drag_out_test),
    pt rms over the four edges: drag-out-flex up 0.13, down 0.13, left
    0.09, right 0.09; drag-out-upward-flex up 0.12, down 0.11; tap
    capture 0.15 / 0.11; after the lifts alone 0.17 / 0.15 / 0.17.
    Holdout `drag-out.jsonl` (drawn frames, the capture 9d8f32c was
    fitted to): 0.16 / 0.12 / 0.06 / 0.06 against the fit's 0.40 / 0.36
    / 0.17 / 0.17.
- CONTENT rides the flex 1:1 (`MorphMenuMotion.contentStretch`): rows,
  icons, the highlight, headers, the glow and submenu cards take the one
  affine map from the unflexed shape onto the flexed one, as UIKit
  transforms the whole list. Hit testing maps the finger back through
  the same map. NEAR: the corners keep their radius while the content
  under them stretches by a few percent at most.
- Not measured: a diagonal drag (the equations combine both axes as
  written).

## Fixtures

Device `ios27-device/menu/*` (center3 tap/quicktap/hold700/dismiss/
dragselect/select/closemidopen/retap-midopen/repeat/reopen*/early-outside-*,
center-items{2,5,10}, pos-{tl,tr,bl,br,left}, bottom3, wide3, navbar3,
tl-items{1,4,8}, fusion.json, drag-out, drag-out-flex, drag-out-upward-flex); simulator `ios27/menu/*` (manifest documents
G_*/S_* row keys). Film crops `references/menu-video/`. Settings dump
`/tmp/morph-native/menu-settings-dump.txt` (volatile).

## Recapture

Scene `menu`: `PROBE_POS` (center/tl/tr/bl/br/bottom/left), `PROBE_ITEMS`,
`PROBE_WIDE=1`, `PROBE_SUBMENU=1`, `PROBE_BTN_X/Y`. Device plans `menu`,
`recapmenu`; MenuAnchorUITests (testAnchor, testAnchorTall, testAnchorFilm
- layer log off for filming). morph traces:
example/integration_test/menu_trace_test.dart (`TRACE_SCENE`, `TRACE_RUN`),
menu_video_test, menu_anchor_video_test.

## morph

`MorphMenuButton`, `MorphMenuItem`, `MorphMenuAppearance`, `MorphMenuMotion`,
`MorphMenuTuning`, `MorphMenuProgress`, `MorphMenuBlob`,
`MorphMenuMorphSpec` (menu.dart, menu_motion.dart, menu_morph_spec.dart,
menu_fusion.dart); the button's press and the open menu's flex run on the
shared flex machine (flex_interaction.dart: `MorphFlexInteraction` lifts
the button after `pressDelay` without the stretch, `menuTargets` and
the stepped pulse channel, `MorphChannel.stepped`, are the menu variant); flies on the engine as a vessel flight. Shared host
for bar menus: MorphMenuHost / MorphMenuLayer / MorphMenuFlightProgress.

`MorphMenuSource` (menu.dart) turns any widget into this menu; the
button is its glass ellipsis configuration, `MorphGlassButton(menu:)`
wraps its capsule in it. Declared approximations, not measured:
- a source that is not a capsule keeps its own corner radius in the
  shrinking source shape (`MorphMenuMotion` `sourceRadius`, capped at the
  capsule); every other number is the round button's;
- `MorphMenuTrigger.hold` (a button with a primary action and a menu)
  opens on the round button's `holdDuration` (0.22 s) and its tap fires
  the action; the long press of such a `UIButton` was not recorded;
- a glass button with a menu lifts by the menu's press (pressDelay,
  flex lift over the long side, read from UIKit, notes private) instead of its own uniform lift, with no
  touch glow or lean;
- a source with a surface of its own (`MorphMenuSource.color`, a glass
  button's fill or tint) draws the source shape in that color at both
  hand-offs and crosses it into the menu glass on the look fade
  (lookFadeStart - lookFadeEnd of the progress); without a painter its
  rim fades with it. Without a painter the fused body takes the mixed
  color and the source shape keeps the menu's shadow, not the button's.
  The color hand-off of a tinted `UIButton` was not recorded.

Every menu source's tap (the tap trigger's opening tap as well as the hold
trigger's tap through) keeps the glass button's measured 70 pt
touch-up-inside slop (glass-button.md) as `MorphMenuTuning.tapSlop`: a
release farther from the source cancels and opens nothing. A finger
that slides beyond the same slop before `holdDuration` forfeits the hold
too: the menu never opens under a finger that is cancelling. No capture
releases a menu button tap outside; the bound is the glass button's.

Per-frame work (lifecycle.md, 2026-10-14): the content shows through a
`MorphLiveWindow` laid out once over the overlay (it moves, resizes and
clips by paint), and the button's look is centered by `MorphLiveCenter`,
laid out in the source's box of the frame but again only when that can
change it: the ellipsis is the same 24 pt box in any box as large, and a
look the fade hides keeps its layout. Pixels identical (control
goldens). Host: open 11 layouts a frame to 1 (flat; liquid 16 to 6, the
glass host's surfaces), the landing after the close 6 to 0. Side effect,
policy-declared: the ellipsis now holds still while it shows, so while
its scale sweeps fast the glyph policy may draw it from its raster
(`MorphGlyphMode.raster`, NEAR) where the per-frame layout made it snap
before. A look whose layout depends on its box (a glass button's label)
still follows the box every frame while it shows.

## How UIKit renders it [simulator 2026-10-14 + device lifecycle runs]

Read from UIKit, notes private. iOS 27.0 simulator (iPhone 17 Pro, its display at 60 Hz)
with every layer write, layout, draw and added animation logged per frame, plus the
device lifecycle runs of lifecycle.md (iPhone 16 Pro, iOS 27.0.1). Counts and threads
are evidence; simulator times are not timings (the host was heavily loaded).

- Built once, at the final size. The frame that opens the menu creates and lays out the
  whole menu (device: 150 layouts + 269 view and layer creations; simulator 141 - 182
  layouts) at its final size and place, draws each row's text once (one draw per row),
  and never lays it out again during the open or the close. The real menu sits at its
  final place, hidden, which is why it takes touches from its first frame.
- Scaled, not revealed. The morph shows the laid-out menu through a live mirror inside
  the menu blob: the mirror is scaled with the blob by a layer transform (scale, height,
  vertical position), blurred and cross-faded against the blob's plain shape, and
  clipped by the blob. There is no growing mask over unscaled content and no layout at
  intermediate sizes. The button's look rides the small blob the same way.
- Text. Row labels and icons are bitmaps drawn once at 3x at pixel-aligned final
  positions. While the morph scales them the render server resamples those bitmaps:
  no re-layout, no new glyph rasters, no snapping, no rasterized copy and no snapshot.
  That is why the text does not jitter. At rest the same bitmap is shown 1:1; text is
  drawn again only when a row's state changes (2 - 3 labels per highlight change).
- Where the motion runs. The open and the close add no spring or basic animation to any
  layer; the only render-server animations bind the glass shape to the two blobs. Every
  moving value (blob scale, height, position, kick, corner radius, shadow, content blur
  and fade, fusion radius, lens, glass parameters: 25 - 35 values) is evaluated each
  frame by a display link on a BACKGROUND thread and written straight to the render
  server, with no commit and no layout. The main thread does nothing per frame after the
  first two (blips of 1 - 3 layouts at ~0.1 s and ~0.45 s); in one capture it was
  blocked for 0.7 s and the morph kept running. The link asks for 48 - 120 Hz.
- Close. Nothing is rebuilt: the menu takes its final scale (0.2) and opacity 0 as its
  model values while the morph mirror keeps showing its content; the morph container is
  created again in the close frame (device 60 layouts + 70 creations); the cleanup
  removes everything ~0.95 s (open) / ~1.2 s (close) after the start.
- Glass. One glass layer serves both blobs: the background is captured at a quarter of
  the resolution (the button's own glass at half), the shape is the union of two
  rounded rectangles bound to the blobs on the render server, the fusion blur radius is
  a per-frame value of that shape (computed on the GPU), and a lens layer distorts the
  content beneath (zoom 1.57 -> 1). The button's glass and the menu's own glass are
  hidden during the morph; the menu's glass appears when the morph container goes.
- Rows. List cells, built synchronously at the opening for the list's own bounds,
  which are the window height and not the clipped menu height: a 30-row menu capped at
  520 pt builds 21 rows at the opening, then one row per frame as rows scroll in. A
  touch on a row highlights it ~0.1 s in; a scroll then clears it.
- Submenu (tap). The tap's release frame builds a new card (its own list, a 62 pt
  title row with a separator, its own glass) stacked over the parent at the row; the
  parent scales to 0.97 and the card's height springs, again from the background thread.
- Highlight under a sliding finger. One highlight platter per list (inset 10 pt, row
  height, radius 21, white with vibrancy), not one per row, SLIDES to the row under the
  finger on a critically damped spring of response 0.12 s [simulator; an exact fit of
  two row changes at 60 Hz: 0.78, 0.48, 0.26, 0.14, 0.07 of the step left after each
  frame; it snaps under ~0.3 pt; device unconfirmed]. A row change costs the two rows'
  highlight state, 2 - 3 text draws and one layout; the flex is one transform on the
  whole list and the glow follows the finger, both written from the background thread.

### morph against it

| | UIKit | morph (lifecycle.md, flat / liquid) |
|---|---|---|
| content at intermediate sizes | laid out once, scaled by a layer transform | laid out once in `MorphLiveWindow`, scaled by a paint-time transform: same |
| row text while scaling | bitmaps drawn once, resampled | one raster while the card moves, live at rest (`MorphGlyphs` card policy, 07f65b78): same idea, plus a raster-to-live swap at rest |
| rows built | in the opening frame | ahead of the opening while armed (`menuRowsKey`), moved in by one GlobalKey move |
| main thread per open frame | 0 layouts, 0 draws | 0 builds, 1 / 6 layouts, 22 / 29 paints |
| close | no rebuild of the rows | 10 - 11 layouts a frame |
| fusion | blurred-SDF union on the GPU | `morphMenuSilhouette` on the CPU, served ahead by isolates |
| menu glass background | captured at 1/4 resolution | renderer default |
| highlight | one platter sliding on a 0.12 s spring; no rebuild | a box that jumps to the row; the root list's widget is rebuilt (`_rootKey` holds the highlight) |
| tall menu | rows for the visible window, one more per frame while scrolling | the whole root card |

### Optimizations to adopt (ranked)

1. Highlight as one sliding platter (fidelity and frame time): paint the highlight from a
   listenable in a layer of its own under the rows, move it on MorphSpring(0.12, 1.0)
   (NEAR until the device confirms it), take the highlight out of the root list's key so a
   row change rebuilds nothing; only the two rows' text color changes. Owner's eye on the
   iPhone (it is a visible change: the platter slides where morph's jumps).
2. Composite-only frames for the content: the rows' raster taken at the opening is a
   retained layer that each frame only re-transforms (no picture recorded per frame), and
   the look and shapes write layer properties, not paints. A background thread is not
   available to Flutter; the nearest equivalent is a frame that only composites. Target:
   0 layouts and a constant handful of paints per open frame (today 22 / 29).
3. Close without rebuild: the close keeps the open menu's content and moves only its
   transform and fade (today 10 - 11 layouts a frame); lifecycle.md backlog item 9.
4. Keep the rows' raster at rest when the card lands exactly on scale 1 at a pixel-aligned
   position (as UIKit keeps its bitmap) instead of swapping back to live text: removes the
   swap frame's glyph strike; IDENTICAL only if the raster equals the live drawing at 1:1,
   to be proven by the control goldens.
5. Menu glass background at a quarter resolution (UIKit's capture scale for the menu; half
   for the button): NEAR under the glass blur; check what the renderer captures today.
6. Tall menus: build the rows the visible window needs plus a margin and add the rest as
   they scroll in (UIKit: one row per frame); helps the opening frame of 20+ row menus only.
7. Fusion on the GPU: the blurred-SDF union as a shader over the two rounded rectangles
   (UIKit's place for it). Largest change; the isolate-served silhouette already hides most
   of the cost on the Pixel (served 86 - 93 percent).

Device follow-up (needs the iPhone): the highlight spring at 120 Hz, the rows' selection
haptic, the background display link's rate during the open (the 1/60 steps above) and its
cost per frame, the glass capture scales.

## Not reproduced (deliberate)

- The second deterministic kick variant (two curves per height,
  alternating - larger canonical).
- Inline-button menu OPEN frame-locked at 1/60 steps even at 120 Hz.
- Re-open velocity carry at ~+100 ms (synthesizer cannot tap that fast).

## API gaps

The menu content API (submenus, sections, palettes, element sizes,
selection, deferred and live content) is measured and ported in
[menu-api](menu-api.md); the API parity page is [api/menus](api/menus.md).

- Menu on a non-round glass button or a text button
  (`showsMenuAsPrimaryAction`): served by `MorphMenuSource` with the round
  button's numbers (see morph above); a recording would replace them.

## Implementation notes (morph side, moved from CLAUDE.md)

- FUSION detail [device layer log + film of the bottom-centre ten-row
  menu, menu_fusion_test]: the container is an AnimationKit.LensingSDFLayer
  with smoothness 0 (plain min of its two CASDFElementLayers), its distance
  field Gaussian-blurred by `gaussianRadius` AS A STANDARD DEVIATION (film
  fit 0.9 - 1.2 x, best 1.0; row widths ~2 pt rms incl. a ~1 pt rim bias of
  the film). The radius is an ENVELOPE per open/close, not a spring of the
  progress: 20 x (1 - exp(-t / rise)) x a critically damped fall on
  0.4286 s (= blurIn 0.3 / speed 0.7, free fit 0.424 - 0.433) after a hold;
  open rise 0.0161 hold 0.199 (clamped at 20), close rise 0.0213 hold 0.057
  amplitude 20.95 (peaks 19.7); cut to 0 under 0.2; a reversal takes the
  max of the running envelopes (continuous value, not velocity). The blur
  makes facing edges POINTED, eats the small shrunk button (it vanishes
  ~30 ms into a tall close and comes back as a drop), then a NECK joins the
  shapes across the ~19 pt gap; it narrows each shape by ~s^2 / 2r.
- `MorphMenuFusion` / `morphMenuSilhouette` (menu_fusion.dart): SDF on a
  grid of step clamp(s/3, 2, 6), separable blur evaluated only within
  1.26 s + 1.5 step of the edge (a blur moves an SDF by at most
  s sqrt(pi/2)), traced by `liquidGridContours` (the skin's marching
  squares + stitch + Chaikin); under 1 pt the silhouette is the exact
  plain union of the two boxes (no field: path union, each box shaded as
  its own rounded rectangle; glass-renderer.md). The motion exposes `fusionRadius` and `silhouette`; the
  vessel AND the button after the latch hand it to the flat painter and to
  `buildLayer(outline:)`. Shading depth: see glass-renderer.md
  (`MorphMenuFusion.shadedDepth`). A host whose glass only fills the body
  (`MorphGlassRenderer` on the flat tier, or no painter) asks for the edge
  alone (`silhouetteFor(withField: false)`): the same crossings bit for
  bit, without the shaded depth, optics or field samples (2026-10-11,
  JIT host 7 - 24 percent less per fusion, more at small radii).
- CONTENT UNFOLDS OUT OF THE DROP (second film, the owner's slow-mo report:
  ours showed nothing until p 0.53, then a near-final menu): content rides
  G at G's scale plus a kick swell, k = s_G + 1.45 kick / H, alpha = p on
  the way in (row ink on film: 0.5 at p 0.51, 0.92 at 0.86 - the layers'
  alpha p was right, the first film's 0.53 ramp was blur misread as fade);
  a close fades linearly from where it was to 0 at p 0.53 (ink 0.53 at p
  0.85, 0.2 at 0.73) and a re-open fades back from there to 1 at p 1, so
  every reversal is continuous (anchored on the phase's start, like the
  closing radius).
- ALIGNMENT: H > W keeps the first row on G's TOP edge (screen top, both
  directions: up = far edge, down = near edge; filmed bottom10 and tl10) -
  a list at scroll offset 0; H <= W is CENTERED on the kicked G (center3,
  bottom3). The placement-invariant group of menu_button_test that pinned
  this (content attached to G in ten placements incl. clamped ones, the
  drop starting inside the button, no jumps through open /
  close-mid-open / reopen / close) was removed in 98237e58. Film harness: MenuAnchorUITests (testAnchorFilm /
  testAnchorTall set PROBE_TRACK to match nothing - the layer log cost a
  third of the frames) + example/integration_test/menu_anchor_video_test.dart.
- EARLY TOUCH plumbing: the widget hears the early touch through a GLOBAL
  pointer route registered at the tap's release (nothing is on screen to
  hit-test yet); the motion holds it and applies an early release at the
  opening.
- Flies on the engine: a `MorphFlight` on `MorphTargetSpec.vessel` with
  the measured progress spring and a zero scrim, so overlay choice,
  Esc/back, focus, events (the `@internal` `onOpen` hands out each
  flight; the public API has no open callback) and the
  dissolve of a removed button come from the engine; uses an ambient
  MorphScope or brings its own.
- ONE CLOCK: the menu draws from its own closed-form progress spring
  (`MorphMenuProgress.spring`) in motion time and sends the flight the
  same way; reading `controller.value` held the first vessel frame at
  p = 0 and ran p 8..17 ms behind the kicks (the controller's ticker starts
  a frame late at elapsed 0). The flight's value only times the latch and
  the dissolve.
- LANDING ON THE BUTTON: the engine latch removes the vessel at the
  close's first zero crossing; after it the button itself paints both
  shapes and the look from the same motion (button-local coordinates,
  press transform 1) until the motion goes idle; the close ends only when
  the progress AND both kicks rest (before: the vessel vanished mid-kick,
  a visible snap at the end of every close).
- Paint cost: the vessel builds the rows once (RepaintBoundary, the
  `child` of its per-frame builder) and fades content and the button look
  through ONE layer each (`ImageFilter.compose` of an alpha ColorFilter
  and the blur); the union is one path of two same-direction rounded rects
  (non-zero fill), no Path.combine per frame. The button face draws its
  glyph WITHOUT an Opacity/ImageFiltered wrapper: an OpacityLayer (even at
  alpha 255) between resting glass broke the BackdropGroup - device raster
  p50 11.8 ms vs 2.3, the Menu page dropped to 60 Hz; a test pins the
  layer count.
- Built ahead of the opening (2026-10-06, Pixel 6a frame dumps): the
  open frame was the worst frame of every menu run (build 28 - 50 ms on
  the Pixel, 6.3 on the iPhone 16 Pro) - inflating and laying out every
  row of the root card. A press now builds those rows out of sight while
  a touch may still open the menu (`MorphMenuMotion.isArming`: finger
  down on the button, or a tap's opening pending - the measured
  `tapOpenDelay` gives ~90 ms of frames), 6 elements per motion advance,
  in an overlay entry under `MorphMenuHost.menuRowsKey`; the opening
  moves them into the vessel (one GlobalKey move, state and layout kept).
  Loading rows and `MorphMenuWidget` rows are left to the opening: their
  state has to start with the menu. The prebuilt rows never rasterize
  their glyphs offscreen (they are offstage, and their cover
  `menuRowsBlur` is 0 until the vessel sets it): an early offscreen raster moved icon and check-mark edges by a few
  device pixels on the iPhone, so the picture is recorded at the opening
  as before. The root card's list below its moving frame is one
  remembered widget while nothing it shows changes, and a card's element
  widgets are made once per layout. Open frame: Pixel worst build 35.5 ->
  23 - 26 ms, iPhone 6.3 -> 5.0 ms; perf_counts builds -0.9 .. -1.3 per
  frame; identical frames (menu_prebuild_test, glass_frames, device
  shots at the run-to-run floor). Not removed: the vessel's own first
  build and every Text/Icon rebuild that the GlobalKey move triggers
  (activate re-runs didChangeDependencies), ~2.4 ms of the iPhone's 5.
- The menu's UI p95 on the Pixel is the fusion, not the open frame:
  timed per frame (an instrumented build), `morphMenuSilhouette` costs
  p50 2.8 / p95 9 / max 16 ms in the ~40 percent of frames that fuse
  (liquid; flat p50 3.7 / max 30), 4 - 10x its tight-loop time
  (outline_us menu10-r4 0.76) - and the build p95 without it is 9.2 ms
  (liquid) / 5.0 (flat), inside the round-two targets. Dart CPU samples
  of builds over 5.6 ms: fusion 20 percent, glass paint 15 (UI-side
  geometry pass and its submit), compositing 24. GC is in no over-budget
  build (3 of ~95 frames), so the `DartPerformanceMode.latency` window
  was not added. Lever F (next frame's silhouette on an isolate) cannot
  be IDENTICAL here: frame timestamps jitter by microseconds (vsync
  deltas 16.670 - 16.695 ms), so a predicted frame's inputs never equal
  the real ones bit for bit; a speedup needs either a tolerance (not
  identical) or a cheaper exact fusion. Tool:
  example/integration_test/menu_frames_test.dart + perf/menu_frames.py
  (perf/2026-10-06-pixel6a-menu-frames).
- The fusion is computed ahead (2026-10-06, glass-renderer.md "Menu
  fusion: the device gap and the fusion ahead"): its device cost was core
  placement and DVFS of a light UI thread (paced 4 - 12x the tight loop;
  a pinned A55 8.9x a pinned X1). The motion predicts the next three
  frame times, peeks its silhouette inputs there and a pool of background
  isolates fuses them; a frame within 0.02 pt per input is served that
  outline (the exact law at the predicted time, served pairs <= 0.06 pt
  off), else fuses its own. Served 55 - 69 percent of fusing frames
  (Pixel 6a), 56 - 66 (iPhone 16 Pro); menu build p95 iPhone flat 2.4 ->
  1.5, liquid 2.7 -> 2.3, Pixel flat 12.0 / 12.4 -> 11.2 / 10.9, liquid
  14.0 / 15.1 -> 13.3 / 13.6 ms. The kernel reach no longer flips to ten
  taps a side on a rounding error (`MorphMenuFusion.reachOf`).
- Frame grid and row raster (2026-10-12, tool/bench, Pixel 6a liquid
  menu, perf/2026-10-12-bench-menu-*): frame times are put on the
  display's frame grid before the motion samples them
  (`MorphFrameGrid`, now in clock.dart; NEAR: up to 1 ms, typically
  tens of us). The predictions then hit their frames: served 62 -> 86 - 93
  percent; the misses left are a motion's first two frames, whose time
  is set by the tap. The motion's frame period carries over to the next
  motion, and requests within 0.0004 pt of one in flight are not sent
  twice. The root card's rows also draw from their raster while the
  content scale is more than 0.002 from 1, not only under the blur (NEAR:
  resampled while the card scales, live at rest): a live label struck
  its glyphs at every scale (UpdateAtlasBitmap 15 ms in the worst
  frames). Menu scene: UI p95 14.0 -> 11.0 ms, frames over budget 5.3 ->
  3.0 percent, glyph atlas 380 -> 54 ms per scene. Left: encode and
  saveLayer on the raster thread, and the first frames' fusions.
- The frame grid in the clock (2026-10-12, tool/bench, Pixel 6a,
  perf/2026-10-12-bench-clockgrid-*, A B A B): `MorphFrameGrid` moved
  from the menu host into `MorphClock` (clock.dart), so every measured
  motion samples its frames on the grid (NEAR, up to 1 ms) and the clock
  offers `frameTime` / `framePeriod`. The menu predicts its coming
  frames as the grid's next nodes; its own least-squares period estimate
  and step limit are gone. Served ahead liquid 90 / 88 -> 90 / 88
  percent, flat 83 / 90 -> 88 / 87; menu UI p95 liquid 12.0 / 11.0 ->
  12.5 / 10.6 ms, flat 6.9 / 7.3 -> 7.6 / 6.8; power and frames over
  budget within the run-to-run spread on every scene (the one outlier,
  liquid controls 6.9 percent over in grid-2, is a waitForBufferRelease
  episode on the raster thread, seen before on unchanged code).
- One glyph policy (2026-10-12, glass-renderer.md "One glyph policy"):
  the rows' raster switch (blur >= 0.5 pt or scale off 1 by 0.002) and
  the button glyph's live drawing gave way to `MorphGlyphs`: the rows
  read the content blur as their cover (`menuRowsBlur`) and draw live at
  rest, from one raster while the card moves fast or under the blur,
  snapped while it settles; the glyph follows its morph scale the same
  way. Pixel 6a menu scene, A B B A: frames striking glyphs liquid 9.7 ->
  4.4 percent, flat 9.9 -> 4.5; atlas flat 0.17 -> 0.12 ms per frame;
  frames over budget within the spread (liquid 2.9 / 3.8 -> 3.7 / 3.8).
- The rows draw as a card (2026-10-14): from one raster while the card
  moves, live at rest, never snapped. A snap scales the whole rows layer
  about its center, so in the spring's tail, flipping between grid scales
  and the exact one, the far rows shook against the card's edges at the
  end of the open (host: up to 1.2 pt at 60 Hz on a ten-row menu, up to
  7 pt frame to frame on the gallery's tall settings menu).
  test/menu_open_end_test.dart pins it. NEAR (resampled while moving),
  as the alert and date picker cards.
- Device trace tool: example/integration_test/menu_trace_test.dart
  (profile build, `--dart-define=TRACE_SCENE=center|gallery`,
  `TRACE_RUN=<id>`, writes `<app tmp>/menu_trace_<id>.json`: FrameTimings,
  a timeline, painted G/S geometry per frame); launch with devicectl and
  pull the file - `flutter drive` needs Rosetta's iproxy on this Mac.
- Frame rates: the inline-button menu OPEN is frame-locked at 1/60 steps
  even at 120 Hz (not copied: morph evaluates in continuous time); the
  nav-bar menu and every close run in continuous time.
