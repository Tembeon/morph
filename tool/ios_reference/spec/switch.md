# Switch passport

Status: measured device + simulator; ported; replayed (switch_test).
Knob = small lens: [lens-and-flex.md](lens-and-flex.md).

## Native

`UISwitch` (knob `_UILiquidLensView`). Public API (SDK 27.0): `on`,
`setOn:animated:`, `onTintColor`, `thumbTintColor`, `onImage`, `offImage`,
`title`, `style` / `preferredStyle` (`UISwitchStyle` automatic / checkbox /
sliding).

## Spec

- Geometry: track 63 x 28, knob 37 x 24, travel 22 [layout].
- Tap toggles on RELEASE; knob travel 0.30/~1.0 carrying velocity; track
  color on its own critically damped springs (toward on 0.68, toward off
  0.40) [fit].
- DRAG [device recapture]: commit when the knob TARGET reaches the far end,
  uncommit only when it returns to the starting end; color follows each
  change after `colorDelay` 90 ms; release keeps the committed state if the
  drag ever committed, else toggles like a tap; mid-travel decides nothing.
- Dead zone 5 px only for a drag that starts moving within `deadZoneWindow`
  0.1 s of the touch. Rubber band (12, 0.54).
- Knob lift/unlift/stretch: small lens (lift 0.27/0.625, min hang 0.22 s,
  unlift 0.40/1.0 + size 0.48/0.70).
- Look: track plain fill; lifted knob clear glass, shrink 0.25 (edges 0.755,
  track end inside at 0.869 with full rim) - glass-optics.
- Colors (morph defaults): active 0xFF34C759, track 0x29787880, knob white.

## Disabled [device, light + dark, 2026-10-03]

- `UISwitchModernVisualElement` at opacity 0.5 (track, knob and on-color
  together, off and on alike). Pixels exact: rms 0.07 / 0.05 of 8 bit
  against 0.5 enabled + 0.5 background.
- One frame, no animation, both ways.
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method and recapture in [states](states.md) (StatesUITests testDisabled, scenes x4dis / x4disbars / x4distab / x4disalert).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): one 0.5 layer over track and knob (pixel rule
  checked light + dark).

## Fixtures

Device `ios27-device/controls/switch-*` (off/on tap, hold800, drags right
8/15/50/100, left50, there-back, fling40, taps, tb-a1..a3).
Simulator `ios27/controls/switch-*`. References
`references/dark/switch-{off,on,off-knob-held}.png`.

## Recapture

Scenes `sw`, `swOn` (control at y 400, knob off 210 / on 232 on the sim
440 pt screen). Device plans `controls`, `recapcontrols`, `dragtiming`.

## morph

`MorphSwitch`, `MorphSwitchStyle`, `MorphSwitchMotion` (switch.dart,
switch_motion.dart), small_lens.dart. Tests: switch_test, controls_test,
controls_platform_test.

## Not reproduced / open

- Reduce Motion unmeasured (plan in states.md).

## API gaps

- `UISwitchStyle.checkbox` (Mac idiom mostly) and `title`.
- `onImage` / `offImage`; `thumbTintColor` exists only as style knobColor.
