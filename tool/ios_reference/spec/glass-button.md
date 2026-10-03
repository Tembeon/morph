# Glass button passport

Status: measured device + simulator; ported; device-identical.
Flex spec: [lens-and-flex.md](lens-and-flex.md).

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

- ONE degree of freedom: uniform scale 1 + lift / width; lift from
  `MorphFlexSpec.forSize` (16 px at height 44 -> 4 px at 160) [tuning].
- Press on the tracking spring, release on the scale spring (small buttons
  ring below 1, wide ones barely).
- Stays lifted for the whole touch, even far outside.
- Drag-off LEAN tx = d |d| / 10000 px plus a stretch along the drag;
  `onPressed` fires when the finger lifts within 70 px.
- Glow: overlay 1 - exp(-t / 0.023 s) on press, little glow at the touch
  point to 0.3; on release both fade and the little glow scales 1 -> 4 on
  0.5/1.0.
- `.glass()` and `.prominentGlass()` move identically.
- Text: title 17 regular.
- Reused by: bar capsules (recorded 1 + 16/w), search field (0.05 s after
  contact), alert platter (pull 0.25, stretch 0.6).

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
- Touch on a disabled button: capture prepared (testDisabledTouch), not run.
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method and recapture in [states](states.md) (StatesUITests testDisabled, scenes x4dis / x4disbars / x4distab / x4disalert).
- To port: drop the 0.35 dim; content color -> tertiaryLabel; prominent
  tint -> systemGray4 (light 0xD1D1D6 / dark 0x3A3A3C); glass untouched.

## Fixtures

Device `ios27-device/controls/button-glass-{44x44,60x44,120x44,200x44,
300x44,200x100}-hold800.jsonl`, `button-glass-120x44-drag-off-back`,
`button-glass-44x44-taps`, `button-prominent-120x44-hold800`. Simulator
`ios27/controls/button-*`. References
`references/dark/glass-{44x44,120x44}-{resting,pressed}.png`.

## Recapture

Scenes `gb<W>x<H>`, `gbp<W>x<H>` (prominent); `PROBE_TINT`. Device plan
`controls` / `recapcontrols` (flex rows only in button scenes).

## morph

`MorphGlassButton` (`tint`, `padding`, `minSize`), `MorphGlassButtonStyle`,
`MorphGlassButtonMotion` (`pull`, `stretch`, `reducedMotion`)
(glass_button.dart). Tests: controls_test.

## Not reproduced / open

- Reduce Motion unmeasured (plan in states.md).

## API gaps

- Clear glass variants (`clearGlass`, `prominentClearGlass`) as a style.
- `buttonSize` presets and `cornerStyle` (morph: capsule only, padding).
- Subtitle, image placement, activity indicator, selection toggling.
- `menu` / `showsMenuAsPrimaryAction` on an arbitrary glass button (morph
  has MorphMenuButton for the round 48 pt case only).
