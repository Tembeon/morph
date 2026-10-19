# Glass button passport

Status: measured device + simulator; ported. The lift by size replays
against the simulator captures, the drag-off against simulator and device,
the device holds, taps and scroll-view touches against the touch stamps.
Flex spec: [lens-and-flex.md](lens-and-flex.md). API parity:
[api/buttons.md](api/buttons.md).

## Native

`UIButton` with `UIButtonConfiguration.glassButtonConfiguration`,
`prominentGlassButtonConfiguration`, `clearGlassButtonConfiguration`,
`prominentClearGlassButtonConfiguration`; `_UIFlexInteraction`. Config API:
`title`, `subtitle`, attributed variants, `image`, `imagePlacement`,
`titleAlignment`, `titlePadding`, `buttonSize` (mini / small / medium /
large), `cornerStyle` (fixed / dynamic / small / medium / large / capsule),
`baseForegroundColor`, `baseBackgroundColor`, `showsActivityIndicator`,
`contentInsets`, transformers; UIButton `menu`, `showsMenuAsPrimaryAction`,
`changesSelectionAsPrimaryAction`. `UIGlassEffect` (`regular` / `clear`,
`interactive`, `tintColor`).

## Spec

- It is the flex interaction (lens-and-flex.md "Flex interaction") with
  the dynamic spec of the button's size, lift and stretch on.
- A still finger: ONE degree of freedom, uniform scale (L + lift) / L, L
  the long side (read from UIKit, notes private; 1 + lift / width on a
  wide button); lift from `MorphFlexSpec.forSize` (16 px at short side
  44 -> 4 px at 160) [tuning].
- Press on the tracking spring, release on the scale spring (small buttons
  ring below 1, wide ones barely).
- Onset [device, from the touch's own time stamp, spec README "Clocks"]:
  the lift starts 22.5 - 29.2 ms after the touch (median 26.1; the last
  three taps of `button-glass-44x44-taps`, the five touches in a scroll
  view) and the return 22.1 - 28.3 ms after the release (median 26.0,
  the seven holds; the four 83 ms taps 13.5 - 22.2): UIKit's delivery
  plus the frame the flex begins on. `touchDelay` 26 ms: the flex takes up
  every touch (down, moves, release) that long after its stamp. The first
  touch after the button appears lifts 37.8 - 46.9 ms after its stamp (8
  captures; the display link's next frame comes 20.6 - 21.5 ms after the
  one before instead of 8.3): a one-time setup, not reproduced.
- Stays lifted for the whole touch, even far outside.
- A dragging finger stretches the button along the drag and narrows it
  across by k = |it| / (4 T) + (|t| - |it|) / T per axis (t the travel,
  it the travel clamped into the button, T the spec's stretch threshold)
  and shifts it by W k toward the finger, shown at the button's scale
  (tx = sx W k) [read from UIKit, notes private; replay of
  drag-off-back: tx 0.028 pt rms simulator, 0.065 device, sx - sy 0.0015
  / 0.0016; the former fit d |d| / 10000 left 0.17 / 0.155 and 0.0029 /
  0.0035]. `onPressed` fires when the finger lifts within 70 px.
- Release outside [device, 2026-10-13, 120 x 44, press at the center,
  slide straight off, release]: activates 70 pt above the top edge, not
  80; 60 pt beside the right edge, not 70 (30 and 50 activate too). One
  70 pt bound with the far edges excluded, as `CGRectContainsPoint` and
  `Rect.contains` test a point, gives all four; morph's `highlightSlop`
  70 agrees (the top edge 70 is inside, the right edge 70 outside).
  Below and left are not measured.
- Inside a `UIScrollView` (default `delaysContentTouches`) [device,
  2026-10-13]: a still hold lifts the button 41-45 ms after contact
  (three runs, scale past 1.001, peak 1.144); the lift starts within
  1.5 ms of `touchDelay` after the stamp on all five touches, as outside a
  scroll view, so the scroll view holds nothing back; a swipe that starts on the button lifts it to 1.02-1.09
  and drops it when the scroll takes the touch, with no activation.
- Glow: overlay 1 - exp(-t / 0.023 s) on press (from `touchDelay` after
  the stamp, with the lift), little glow at the touch point to 0.3; on release both fade and the little glow scales 1 -> 4 on
  0.5/1.0. No source is recorded for the rise, the 66 pt little glow
  (`littleGlowSize`) or the fall spring; the captures log the glow
  container's frame, not its opacity. The tab bar's measured glow
  (tab-bar.md: rise 0.1 s critical after 0.042 s, 93 pt spot, fall 0.5 s
  after 0.02 s, x4) differs in rise, delay and size; whether a button
  glows the same is open. morph lights the capsule in the liquid tier's
  final glass pass (docs/glass.md "Touch glow"); flat, fake and the
  button without a painter draw no glow.
- `.glass()` and `.prominentGlass()` move identically.
- Text: title 17 regular.
- Reused by: bar capsules (recorded 1 + 16/w), search field (lift only,
  0.05 s after contact), alert platter (its own size: lift 4, threshold
  24000; 0.4 pt lean for a 120 pt drag with no fitted constant). The
  capsules and the platter share `touchDelay`.

## Disabled [device, light + dark, 2026-10-03]

- `.glass()`: the glass is UNCHANGED (body and rim pixel-identical: body
  31.7 dark / 244.6,244.6,250.1 light, same rim profile); the title and the
  image turn tertiaryLabel (dark 0x4CEBEBF5, light 0x4C3C3C43) (label textColor, image contentsMultiplyColor). Rendered
  peak: dark 249 -> 93 on the 32 body, light 13 -> 189 on 245.
- `.prominentGlass()`: the accent tint becomes systemGray4 (body dark
  59.7 gray = 0x3A3A3C within noise, light 210.3/210.3/214.3 = 0xD1D1D6;
  the enabled body is the tint itself, 0x0091FF dark / 0,134,251 light);
  the title turns tertiaryLabel too (peak dark 121, light 159).
- No opacity on the control. One frame, no animation, both ways.
- Touch on a disabled button: no reaction to a 0.8 s hold (no scale, no
  event, no animation) [device, testDisabledTouch; states.md].
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method and recapture in [states](states.md) (StatesUITests testDisabled, scenes x4dis / x4disbars / x4distab / x4disalert).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): `disabledForegroundColor` / `disabledTintColor`;
  glass untouched; a hold shows no reaction.

## Fixtures

Device `ios27-device/controls/button-glass-{44x44,60x44,120x44,200x44,
300x44,200x100}-hold800.jsonl`, `button-glass-120x44-drag-off-back`,
`button-glass-44x44-taps`, `button-prominent-120x44-hold800`;
`ios27-device/tracking/release-outside.jsonl` (lab scenario
`tracking-bounds`, button at 141,200 120x44) and `tracking/scroll-delay.jsonl`
(scenario `scroll-delay`, button at 141,300 in a scroll view). Simulator
`ios27/controls/button-*`. References
`references/dark/glass-{44x44,120x44}-{resting,pressed}.png`.

## Recapture

Scenes `gb<W>x<H>`, `gbp<W>x<H>` (prominent); `PROBE_TINT`. Device plan
`controls` / `recapcontrols` (flex rows only in button scenes).

## morph

`MorphGlassButton`, `MorphGlassButton.prominent(tint:)` (tint defaults to the
accent, `MorphThemeData.tint`, else `MorphGlassButtonAppearance.prominentColor`),
`.clear` and `.prominentClear` (the liquid tier's fitted clear material; the
press is the regular button's - UIKit's clear configurations carry style
behaviors (colors, material, corner style) but no press of their own [read
from UIKit, notes private]; flat stand-in `clearFillColor` is an
approximation) (`padding`, `minSize`, `menu`, `enabled`),
`MorphGlassButtonAppearance`; internal `MorphGlassButtonMotion`
(`reducedMotion`) (glass_button.dart) on `MorphFlexInteraction`
(flex_interaction.dart, `glows: true`). Tests: controls_test (lift by size
against the simulator hold800 captures; drag-off against simulator and
device), glass_button_device_replay_test (device onsets at the logged
stamps within the 14.6 ms delivery spread, medians within half a frame;
holds aligned to their onsets < 3e-4 rms; the first touch's setup
skipped), scroll_delay_replay_test (the same in a scroll view), flex_interaction_test, release_bounds_test (replays
release-outside.jsonl through the widget), disabled_test (replays
disabled.json), glass_button_variants_test (clear, prominent, glow white
levels), menu_source_test (button menus), controls_scroll_test (scroll
competition, behaviour only), controls_platform_test (keyboard, Reduce
Motion).

Rest: settles once every spring's remaining swing (`MorphSpringState.reach`)
is under `MorphRest` - 0.1 pt (0.3 device px at 3x, 0.26 at 2.625x), a scale
over its surface's extent, an opacity under half an 8-bit step - and snaps
onto its targets: invisible, NEAR. A finger held
still counts: the press sleeps once lift and glow are in place (0.45 s; it
ticked for as long as the finger stayed down) and wakes on the next move or
the lift. The shape snaps as soon as it is at rest, also while the glow
still fades (`MorphFlexInteraction.isGlowOnly`): from then on only the
glow changes, and the frames that follow reach the glass alone
(docs/glass.md "Touch glow"). NEAR, the same remainder as any settle: the
host frames of a released drag (control_goldens m/glass-button/press-drag)
show the resting picture three hashed frames (~140 ms) sooner.

## Not reproduced / open

- Reduce Motion: no read of the flag found in the flex interaction (Swift); morph keeps its approximation, device pass pending ([states](states.md#read-from-uikit-static-2026-10-14-notes-private)).
- Not measured: the default insets 20 x 11, `minSize` 44 x 44 and the
  22 pt glyph (glass_button.dart); release bounds below and left; a
  glass <-> prominent configuration switch; the selected state.

## API gaps

- Clear glass variants exist as constructors. Touch glow white levels
  [read from UIKit, notes private; ported in
  `MorphTouchGlowMotion.spotGainFor`]: regular dark 0.75 / light 0.4 (the
  measured spot gains 4.0 / 1.667 are `1 / (1 - white)`), clear glass 0.7 in
  both appearances (gain 3.33), tinted glass (`.prominent`,
  `.prominentClear`) `lerp(0.7, 0.25, L^1.25)` with L the tint's Rec. 709
  luminance times alpha. The rim on the device and the glow of tinted /
  clear buttons are not recorded: capture `clearGlass` /
  `prominentClearGlass` scenes to confirm.
- `buttonSize` presets and `cornerStyle` (morph: capsule only, padding).
- Subtitle, activity indicator, selection toggling, role.
- `menu` / `showsMenuAsPrimaryAction` exist (`MorphGlassButton.menu`);
  `preferredMenuElementOrder` and the menu-open event are not on the
  button. Ranked list: [api/buttons.md](api/buttons.md).
