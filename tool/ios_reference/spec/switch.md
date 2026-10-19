# Switch passport

Status: measured device + simulator; ported; replayed (switch_test).
Knob = small lens: [lens-and-flex.md](lens-and-flex.md).

## Native

`UISwitch` (knob `_UILiquidLensView`). Public API (SDK 27.1): `on`,
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
- Release outside [device, 2026-10-13]: a tap dragged straight down off
  the switch toggles at every distance tried, up to 128.7 pt below its
  bottom edge (about 130 pt); a switch has no release bound. morph's
  release anywhere agrees.
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
8/15/50/100, left50, there-back, fling40, taps, tb-a1..a3);
`ios27-device/tracking/release-outside.jsonl` (lab scenario
`tracking-bounds`, switch at 176,420 51x31).
Simulator `ios27/controls/switch-*`. References
`references/dark/switch-{off,on,off-knob-held}.png`.

## Recapture

Scenes `sw`, `swOn` (control at y 400, knob off 210 / on 232 on the sim
440 pt screen). Device plans `controls`, `recapcontrols`, `dragtiming`.

## morph

`MorphSwitch`, `MorphSwitchAppearance`, internal `MorphSwitchMotion`
(switch.dart, switch_motion.dart), small_lens.dart. Tests: switch_test
(replays the simulator taps and the device captures: knob and lift),
flex_law_test, release_bounds_test (replays release-outside.jsonl),
disabled_test, accessibility_test, haptics_test, held_rest_test,
controls_platform_test, controls_scroll_test. No test replays the track
color springs or `colorDelay` (the simulator `switch-*-tap` rows carry
the track color).

Rest: settles once every spring's remaining swing (`MorphSpringState.reach`)
is under `MorphRest` - 0.1 pt (0.3 device px at 3x, 0.26 at 2.625x), a scale
over its surface's extent, an opacity under half an 8-bit step - and snaps
onto its targets: invisible, NEAR. A set value
settles in 0.83-0.94 s instead of 1.23 s. The switch is a repaint boundary:
its knob's frames repaint the switch, not the page around it.

## Not reproduced / open

- Reduce Motion read from UIKit (notes private): no lift, knob stays 37 x 24, a dragged knob is clamped without the rubber band; ported, device pass pending ([states](states.md#read-from-uikit-static-2026-10-14-notes-private)). Increase Contrast table and toggle haptic: states.md.
- On/Off Labels (iOS accessibility setting, `MediaQuery.onOffSwitchLabelsOf`
  in Flutter) is not drawn.
- `setOn:animated:` (programmatic) is not recorded; morph runs the tap
  springs.

## API gaps

- `UISwitchStyle.checkbox` (Mac idiom mostly) and `title`.
- `onImage` / `offImage`; `thumbTintColor` exists only as the appearance's `thumbColor`.
