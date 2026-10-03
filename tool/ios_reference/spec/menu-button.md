# Menu button passport (glass button that becomes its menu)

Status: measured device (layers, traces, film) + simulator; ported;
replayed (menu_button_test, menu_fusion_test, menu_look_test).

## Native

`UIButton` with `menu` + `showsMenuAsPrimaryAction` (glass configuration),
also `UIBarButtonItem(menu:)`. Morph container = `AnimationKit` morph view
(`MagicMorphView`-like SDF layer) holding the menu blob G and the button
blob S, `KickView` translations, `_UIContextMenuView` content.
Tuning `AnimationKit.MorphAnimationSettings.liquidMorph` [tuning].
UIMenu API (SDK 27.0): `children`, `options` (displayInline, destructive,
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
  finger may slide onto a row; item action fires BEFORE the close; menu is
  hit-testable from its first frame; a tap on the button while it closes
  re-opens on the touch-up with velocity reversal.
- EARLY TOUCH [device, center3-closemidopen / retap-midopen /
  early-outside-{10,25,50,100,200}]: a touch between a tap's release and
  the opening (`isOpenPending`) belongs to the menu; outside -> close
  `earlyCloseDelay` 0.016 s after the opening whatever the release time
  (p always peaks ~0.167); on a row's spot -> action at opening +
  actionDelay, close at opening + 0.016 (quick double tap picks row 0 of a
  downward menu); finger still down at opening = menu finger (released
  after: ordinary dismiss, device +0.028 s vs dismissDelay 0.04, the
  early-outside-200 capture, not replayed). Replay 0.008 rms of progress.

## Disabled button [device, light + dark, 2026-10-03]

- A disabled glass menu button (`showsMenuAsPrimaryAction`) looks like a
  disabled `.glass()` button: glass unchanged, the glyph tertiaryLabel (dark 0x4CEBEBF5, light 0x4C3C3C43); no opacity.
  One frame, no animation.
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method in [states](states.md).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): `MorphMenuButton.enabled`,
  `MorphMenuStyle.disabledIconColor`; a tap does not open.

## Platter color, light [device screenshot, 2026-10-03]

- Light menu platter interior (references/light/menu-open.png, page
  242,242,247): 249,249,255 flat; rim 254 top / 251 bottom outer pixels;
  the shadow darkens the page to ~224 - 238 just outside. Dark: 32 over
  black (0xF2222222, ported in daa1bae).
- Identical to the light date picker overlay platter (date-picker.md).
- Ported 2026-10-03: `MorphMenuStyle.light.glassColor` 0xF2F9F9FF. Light
  audit on the simulator (liquid tier): the renderer draws the interior
  246,246,252 - 3 levels under native; the renderer's light material, not
  the color, is off (see glass-optics.md).

## Fixtures

Device `ios27-device/menu/*` (center3 tap/quicktap/hold700/dismiss/
dragselect/select/closemidopen/retap-midopen/repeat/reopen*/early-outside-*,
center-items{2,5,10}, pos-{tl,tr,bl,br,left}, bottom3, wide3, navbar3,
tl-items{1,4,8}, fusion.json); simulator `ios27/menu/*` (manifest documents
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

`MorphMenuButton`, `MorphMenuItem`, `MorphMenuStyle`, `MorphMenuMotion`,
`MorphMenuTuning`, `MorphMenuProgress`, `MorphMenuBlob`,
`MorphMenuMorphSpec` (menu.dart, menu_motion.dart, menu_morph_spec.dart,
menu_fusion.dart); flies on the engine as a vessel flight. Shared host
for bar menus: MorphMenuHost / MorphMenuLayer / MorphMenuFlightProgress.

## Not reproduced (deliberate)

- The second deterministic kick variant (two curves per height,
  alternating - larger canonical).
- Inline-button menu OPEN frame-locked at 1/60 steps even at 120 Hz.
- Re-open velocity carry at ~+100 ms (synthesizer cannot tap that fast).

## API gaps

- Submenus (`PROBE_SUBMENU` exists in the probe, not ported),
  `displayInline` sections and separators, `displayAsPalette`,
  `preferredElementSize` small/medium.
- Checkmark state / `singleSelection`, subtitles, disabled / hidden items,
  `keepsMenuPresented`, deferred elements.
- Menu on a non-round glass button or a text button (`showsMenuAsPrimaryAction`).

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
  squares + stitch + Chaikin); under 1 pt the silhouette is the plain union
  (null outline). The motion exposes `fusionRadius` and `silhouette`; the
  vessel AND the button after the latch hand it to the flat painter and to
  `buildLayer(outline:)`. Shading depth: see glass-renderer.md
  (`MorphMenuFusion.shadedDepth`).
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
  bottom3). Pinned by the placement-invariant group in menu_button_test
  (content attached to G in ten placements incl. clamped ones, the drop
  starting inside the button, no jumps through open / close-mid-open /
  reopen / close). Film harness: MenuAnchorUITests (testAnchorFilm /
  testAnchorTall set PROBE_TRACK to match nothing - the layer log cost a
  third of the frames) + example/integration_test/menu_anchor_video_test.dart.
- EARLY TOUCH plumbing: the widget hears the early touch through a GLOBAL
  pointer route registered at the tap's release (nothing is on screen to
  hit-test yet); the motion holds it and applies an early release at the
  opening.
- Flies on the engine: a `MorphFlight` on `MorphTargetSpec.vessel` with
  the measured progress spring and a zero scrim, so overlay choice,
  Esc/back, focus, events (`onOpen:` hands out each flight) and the
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
- Device trace tool: example/integration_test/menu_trace_test.dart
  (profile build, `--dart-define=TRACE_SCENE=center|gallery`,
  `TRACE_RUN=<id>`, writes `<app tmp>/menu_trace_<id>.json`: FrameTimings,
  a timeline, painted G/S geometry per frame); launch with devicectl and
  pull the file - `flutter drive` needs Rosetta's iproxy on this Mac.
- Frame rates: the inline-button menu OPEN is frame-locked at 1/60 steps
  even at 120 Hz (not copied: morph evaluates in continuous time); the
  nav-bar menu and every close run in continuous time.
