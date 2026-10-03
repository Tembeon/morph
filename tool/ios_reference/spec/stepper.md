# Stepper passport

Status: measured on the SIMULATOR only; ported.

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

## Fixtures

`ios27/controls/stepper-{plus-tap,plus-hold2500,minus-press-slide}.jsonl`.

## Recapture

Scenes `st`, `st5`; device plan `controls` (not yet run for the stepper on
the device).

## morph

`MorphStepper`, `MorphStepperStyle` (stepper.dart); repeat on the motion
clock (timeDilation-aware). Tests: controls_test.

## Open

- Device confirmation of the repeat timing and overlay.
- Disabled opacity 0.35 unmeasured.

## API gaps

- `wraps`, `continuous = false` (value only at release), `autorepeat = false`.
- Custom increment/decrement images.
