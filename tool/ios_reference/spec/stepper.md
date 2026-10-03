# Stepper passport

Status: measured on the simulator and CONFIRMED on the device (2026-10-03,
light + dark); ported. Device colors differ from the morph style (see
Device).

## Native

`UIStepper`. Public API (SDK 27.0): `value`, `minimumValue` (0),
`maximumValue` (100), `stepValue` (1), `continuous` (YES), `autorepeat`
(YES), `wraps` (NO), background / divider / increment / decrement images
per state.

## Spec [sim]

- NO motion: the pressed half gets an instant 8 percent black overlay.
- Commit on release.
- Repeat: 0.5 s, then every 0.5 s, no acceleration.
- Sliding moves the highlight and the repeat to the other half; leaving the
  control cancels.
- Minus stays left in RTL.
- Track is a plain tertiary fill (not glass); morph style background
  0x1F767680, pressed overlay 0x14000000, divider 0x4C3C3C43.

## Disabled [device, light + dark, 2026-10-03]

- `isEnabled = NO` draws NOTHING different (pixel-identical, dump
  identical) on iOS 27.0.1.
- A half at its limit (value == minimumValue for minus, == maximumValue for
  plus) dims ITS glyph to tertiaryLabel (dark 0x4CEBEBF5, light 0x4C3C3C43) through the image's contentsMultiplyColor,
  fills unchanged - enabled or not.
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method and recapture in [states](states.md) (StatesUITests testDisabled, scenes x4dis / x4disbars / x4distab / x4disalert).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): no dim (pixel-identical test); the limit glyph
  is `MorphStepperStyle.limitForegroundColor` (pixel-checked).

## Device [iPhone 16 Pro, 2026-10-03, StatesUITests testStepperDevice]

Every simulator rule holds on the device:
- Highlight on the first frame after the touch (0.019 - 0.024 s), gone the
  frame after the lift. No motion of any kind.
- Commit on release: valueChanged 0.011 s after the touch-up.
- Repeat while held: 0.520, 1.021, 1.522, 2.023 s after the touch-down
  (0.5 s, then every 0.5 s, no acceleration; a 2.5 s hold = 4 steps).
- Press-slide: the held half keeps repeating while the finger stays in it;
  crossing the divider (x 201.7 vs divider 201) moves the highlight to the
  other half WITHOUT a step; leaving the control through its edge (x 248 =
  maxX, no slop) drops the highlight; the release outside changes nothing.
- Colors (SwiftUI DesignLibraryStepper layers, per half a masked fill):
  rest fill dark 0x14EBEBF5 (0.078) / light 0x163C3C43 (0.086); divider
  1 x 24 pt tertiaryLabel (0x4CEBEBF5 / 0x4C3C3C43); glyphs label color
  (minus = 14 x 2 image, plus = 13.33 shape).
- Pressed half: the layer rows show the half's fill replaced by black at
  0.08 (0x14000000) in both appearances. Rendered: dark = black (0,0,0 on
  black, the white fill is gone), light 206,206,212 on 242,242,247 (rest x
  0.912 - black 0.08 alone would give 223, so light keeps its rest fill
  under the black; 2 levels of 8 bit unexplained).
  Shots: `references/states/stepper-plus-pressed-{dark,light}.png`.
- Ported 2026-10-03: fill 0x163C3C43 / 0x14EBEBF5, divider 1 x 24
  tertiaryLabel, pressed black 8 percent replacing the fill in dark
  (`pressedReplacesFill`) and over it in light (pixel-checked).

## Fixtures

`ios27/controls/stepper-{plus-tap,plus-hold2500,minus-press-slide}.jsonl`
(simulator); `ios27-device/controls/stepper-{plus-tap,plus-hold2500,
minus-press-slide,pressed-dark,pressed-light}.jsonl` (device, same
gestures; the pressed-* files hold the plus half 1.2 s in a forced
appearance).

## Recapture

Scenes `st`, `st5`; device: `StatesUITests/testStepperDevice` (xcodebuild
test-without-building -only-testing:ProbeUITests/StatesUITests/testStepperDevice,
then devicectl copy Documents).

## morph

`MorphStepper`, `MorphStepperStyle` (stepper.dart); repeat on the motion
clock (timeDilation-aware). Tests: controls_test.

## Open

- Reduce Motion: nothing moves, nothing to measure (confirm in the pass).
- The 2-level light pressed residual.

## API gaps

- `wraps`, `continuous = false` (value only at release), `autorepeat = false`.
- Custom increment/decrement images.
