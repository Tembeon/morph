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

- Disabled opacity 0.35 unmeasured; Reduce Motion unmeasured.

## API gaps

- Clear glass variants (`clearGlass`, `prominentClearGlass`) as a style.
- `buttonSize` presets and `cornerStyle` (morph: capsule only, padding).
- Subtitle, image placement, activity indicator, selection toggling.
- `menu` / `showsMenuAsPrimaryAction` on an arbitrary glass button (morph
  has MorphMenuButton for the round 48 pt case only).
