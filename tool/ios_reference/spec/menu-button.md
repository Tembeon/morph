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
