# Stepper - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIStepper` (UIControl; on iOS 27 it hosts a SwiftUI stepper), SwiftUI `Stepper`. morph:
`MorphStepper`, `MorphStepperAppearance` (explicit, or from `MorphThemeData.appearances`). Passport:
[../stepper.md](../stepper.md).

SDK 27.1 (iPhoneOS27.1.sdk): `UIStepper.h` declares nothing after iOS 6. SwiftUI `Stepper` adds nothing after
iOS 16 (`format:` initializers). 27.1 changes nothing here.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `value` (iOS 5, clamped) | current value | `MorphStepper.value` | - | keep |
| `minimumValue` (0) / `maximumValue` (100) | range | `min` (0) / `max` (100) | - | keep |
| `stepValue` (1) | step | `step` (1) | - | keep |
| `.valueChanged` | value changed | `onChanged` | - | keep |
| `isEnabled` (UIControl) | disabled; draws nothing different on iOS 27 | `onChanged: null` (pixel-identical, measured) | - | keep |
| `isContinuous` (YES) | NO = one event when the hold ends | always continuous | no deferred update | `onChangeStart` / `onChangeEnd` |
| `autorepeat` (YES) | hold repeats | always on (`MorphStepper.repeatInterval` 0.5 s) | cannot turn off | add `autorepeat` |
| `wraps` (NO) | max + step wraps to min | clamps | missing; limit glyph while wrapping unmeasured | add `wraps` after a capture |
| `tintColor` (UIView) | glyph tint (effect on iOS 27 not checked) | `foregroundColor` (widget, appearance) | `MorphThemeData.tint` not read | check on a device |
| `setIncrementImage` / `setDecrementImage` (iOS 6) | custom glyphs | none | missing | `incrementIcon` / `decrementIcon` (Widget) |
| `setBackgroundImage(_:for:)` (iOS 6) | fill skin | `backgroundColor` (widget, appearance) | colors only | keep |
| `setDividerImage(...)` (iOS 6) | divider skin | `dividerColor`, `dividerHeight` (appearance) | colors only | keep |
| `accessibilityIncrement` / `Decrement`, element labels | VoiceOver | two buttons `decrementLabel` / `incrementLabel` + `semanticFormatterCallback` | English default labels; native structure not recorded | localization hook |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Stepper(value:in:step:label:onEditingChanged:)` (iOS 13) | bounded stepper + label row | `MorphStepper(value, min, max, step)` | no label row | skip (row layout is the app's) |
| `onEditingChanged:` (iOS 13) | begin / end of a press | none | missing | `onChangeStart` / `onChangeEnd` |
| `Stepper(label:onIncrement:onDecrement:onEditingChanged:)` (iOS 13) | custom stepping, nil disables a half | none | cannot step non-numeric values | `MorphStepper.custom({onIncrement, onDecrement})` |
| `Stepper(value:step:format:label:)` (iOS 16) | formatted value text | `semanticFormatterCallback` (semantics only) | visible text is the app's | keep |
| `.disabled(_:)` | disable | `onChanged: null` | - | keep |
| `.controlSize(_:)` | size | fixed `MorphStepper.size` 94 x 32 | effect not measured | measure first |

## Not relevant for Flutter
- `NSCoding`, `UIAppearance` proxies, per-`UIControlState` image variants.
- Target-action plumbing and accessibility selectors (Semantics covers them).

## morph-only API
- `MorphStepper.backgroundColor` / `foregroundColor` (widget overrides).
- `MorphStepperAppearance.limitForegroundColor`, `.pressedOverlay`, `.pressedReplacesFill`, `.dividerHeight`
  (measured on the device).
- `MorphStepper.size`, `MorphStepper.repeatInterval` (measured; their dartdoc gives no source).
- No contrast tables (`lightHighContrast` / `darkHighContrast`), unlike the switch, slider and segmented control.

## Flutter convention
- Flutter has no Cupertino or Material stepper. `value`, `onChanged` (null disables), `min`, `max`, `step`
  match the slider and SwiftUI. `semanticFormatterCallback` is Material Slider's name.
- One begin / end pair across slider and stepper: the slider has `onChangeStart` / `onChangeEnd`, the stepper
  should take the same names.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | begin / end of a press (`isContinuous = NO`, `onEditingChanged`) | M | S | `onChangeStart` / `onChangeEnd` |
| 2 | custom stepping (`onIncrement` / `onDecrement`) | M | S-M | `MorphStepper.custom` |
| 3 | glyphs drawn 16 pt long; the device draws a 14 x 2 minus and a 13.33 plus | M | S | draw the measured glyphs |
| 4 | `wraps` | L-M | S meas. | add after a capture of the limit glyph |
| 5 | Increase Contrast colors | L-M | S meas. | capture, then tables |
| 6 | `autorepeat = NO` | L | S | add |
| 7 | custom glyph images | L | S | `incrementIcon` / `decrementIcon` |
| 8 | English default semantic labels | L | S | localization hook |

## Breaking changes before 1.0
- Done: `MorphStepperStyle` -> `MorphStepperAppearance`, `semanticValueFormatter` -> `semanticFormatterCallback`.
- Open: `decrementLabel` / `incrementLabel` from non-null English defaults to nullable (localized). Decide
  before 1.0.

## Behaviour fidelity
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | this page, SDK 27.1 | `wraps`, `autorepeat`, `isContinuous`, custom stepping, glyph images |
| layout | unbacked | 94 x 32 and divider 1 x 24 measured (stepper.md Device, controls manifest scene st5) | minus / plus drawn as 2 pt round-capped strokes 16 pt long (stepper.dart:530-540); device: 14 x 2 minus, 13.33 plus; no test compares geometry |
| states | measured | limit glyph color replayed from disabled.json (test/disabled_test.dart); pressed overlay and dark fill replacement checked against the measured constants | light pressed residual of 2 levels unexplained (declared) |
| transitions | measured | no motion; highlight on the first frame, gone after the lift (stepper.md Device) | test/controls_test.dart asserts the passport timings; ios27-device/controls/stepper-*.jsonl are not loaded by any test |
| boundaries | measured | clamps at min / max, repeat stops at the max, limit glyph dims (controls_test, disabled_test) | wrap missing |
| configuration | missing | - | `wraps`, `autorepeat = NO`, `isContinuous = NO` |
| events | measured | commit on release, repeats every 0.5 s without acceleration, no step on a release after repeats (controls_test against stepper.md numbers) | stepper-plus-hold2500.jsonl not replayed |
| input | measured | press-slide moves the highlight without a step, leaving the bounds cancels (controls_test, controls_scroll_test) | stepper-minus-press-slide.jsonl not replayed |
| mutation | unbacked | rejected steps restart from the parent value (test/other_controls_controlled_test.dart) | no native recording |
| accessibility | unbacked | two buttons with the value (controls_platform_test); no Reduce Motion read (no motion) | native VoiceOver structure unrecorded; English labels; no contrast tables |
| optics | measured | device fills, divider, pressed black 8 percent, light and dark (stepper.md Device), pixel-checked in disabled_test | glyph shapes (layout row) |
| platform | measured | minus stays left in RTL [sim] | arrow keys and Space / Enter have no iOS source |
| performance | unbacked | no motion; host counts pinned in test/lifecycle_counts_test.dart (scene stepper-touch) | not in any device bench scene |
