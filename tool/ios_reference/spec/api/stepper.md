# Stepper - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIStepper` (UIControl), SwiftUI `Stepper`. morph: `MorphStepper`, `MorphStepperStyle`
(`MorphWidgetsTheme.stepper`). Passport: [../stepper.md](../stepper.md).

SDK 27.0 adds NOTHING to `UIStepper.h` after iOS 6 (no iOS 26/27 API). SwiftUI `Stepper` has no iOS 26/27
additions (newest: `format:` initializers, iOS 16).

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `value` (iOS 5, double, clamped) | current value | `MorphStepper.value` | - | keep |
| `minimumValue` (default 0) / `maximumValue` (default 100) | range | `MorphStepper.min` (0) / `.max` (100) | same defaults; Flutter/SwiftUI-style names | keep |
| `stepValue` (default 1) | step | `MorphStepper.step` (1) | - | keep |
| `.valueChanged` event | value changed | `MorphStepper.onChanged` (`ValueChanged<double>?`) | - | keep |
| `isEnabled` (UIControl) | disabled; draws nothing different on iOS 27 | `onChanged: null` (pixel-identical, measured) | - | keep |
| `isContinuous` (default YES) | NO = one valueChanged when the hold ends | none (always continuous) | the app cannot defer an expensive update to the end of a hold | add `onChangeStart` / `onChangeEnd` instead (SwiftUI `onEditingChanged`); skip `isContinuous` |
| `autorepeat` (default YES) | press-and-hold repeats (0.5 s, measured) | always on (`MorphStepper.repeatInterval`) | cannot turn off | add `autorepeat` (bool, true); S |
| `wraps` (default NO) | max + step wraps to min and back | none (clamps) | missing; limit glyph dimming must not apply when wrapping (check on device) | add `wraps` (bool, false) |
| `tintColor` (UIView) | glyph tint (effect on the iOS 27 stepper not checked) | `MorphStepper.foregroundColor`, `MorphStepperStyle.foregroundColor` | - | keep |
| `setIncrementImage(_:for:)` / `setDecrementImage(_:for:)` (iOS 6) | custom plus/minus glyphs per state | none (drawn minus / plus) | missing | add `incrementIcon` / `decrementIcon` (Widget); low |
| `setBackgroundImage(_:for:)` / `setDividerImage(_:forLeftSegmentState:rightSegmentState:)` (iOS 6) | skin by images | `MorphStepperStyle.backgroundColor`, `.dividerColor`, `.dividerHeight` | images vs colors | skip images; colors cover the native look |
| `accessibilityIncrement` / `Decrement`, element labels | VoiceOver | two buttons `decrementLabel` / `incrementLabel` + `semanticValueFormatter` | - | keep |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Stepper(value:in:step:label:onEditingChanged:)` (iOS 13) | bounded value stepper + label row | `MorphStepper(value, min, max, step)` | no label row | skip (row layout is the app's / `MorphListRow`) |
| `onEditingChanged: (Bool) -> Void` (iOS 13) | begin / end of a press (incl. repeats) | none | same as UIKit `isContinuous` row | add `onChangeStart` / `onChangeEnd` |
| `Stepper(label:onIncrement:onDecrement:onEditingChanged:)` (iOS 13) | unbounded / custom stepping, nil disables a half | none (value-based only) | cannot step non-numeric things (e.g. dates, enum cases) or disable one half freely | add `MorphStepper.custom({onIncrement, onDecrement})` (VoidCallback?, null disables that half); med |
| `Stepper(value:step:format:label:)` (iOS 16) | value text formatted in the label | `semanticValueFormatter` (semantics only) | visible value text is the app's | keep |
| `.disabled(_:)` / `.controlSize(_:)` | disable / size | `onChanged: null` / fixed `MorphStepper.size` 94 x 32 | - | keep |

## Not relevant for Flutter
- `NSCoding`, `UIAppearance` proxies, per-`UIControlState` image variants.
- target-action plumbing; accessibility selectors (Semantics covers them).

## morph-only API
- `MorphStepper.backgroundColor` (widget-level fill override) - keep (UIKit uses background images).
- `MorphStepperStyle.limitForegroundColor`, `.pressedOverlay`, `.pressedReplacesFill`, `.dividerHeight` - keep
  (measured look).
- `MorphStepper.size`, `MorphStepper.repeatInterval` - keep (measured constants).
- `MorphStepper.decrementLabel` / `incrementLabel` default to English 'Decrement' / 'Increment' - flag: should
  come from a localization source (`WidgetsLocalizations` has no such strings; consider null = no default label
  plus a doc note, or an app-provided localization).

## Flutter convention
- Flutter has no Cupertino or Material stepper. morph's `value` / `onChanged` (null disables) / `min` / `max` /
  `step` match Flutter `Slider` naming (`min`/`max`) and SwiftUI (`in:` / `step:`); keep them.
- Same family convention as slider: add `onChangeStart` / `onChangeEnd` to both so a dev learns one pair.
- `semanticValueFormatter` (stepper) vs Material Slider's `semanticFormatterCallback`: pick ONE name for slider
  and stepper (`semanticFormatterCallback` is the Flutter one).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | begin/end of a press (`isContinuous = NO` / `onEditingChanged`) | med | S | `onChangeStart` / `onChangeEnd` |
| 2 | custom stepping (`onIncrement` / `onDecrement`) | med | S-M | `MorphStepper.custom` |
| 3 | `wraps` | low-med | S (+ device check of the limit glyph when wrapping) | add `wraps` |
| 4 | `autorepeat = NO` | low | S | add `autorepeat` |
| 5 | custom increment/decrement glyphs | low | S | `incrementIcon` / `decrementIcon` |
| 6 | English default semantic labels | low | S | localization hook |

## Breaking changes before 1.0
- `semanticValueFormatter` -> `semanticFormatterCallback` (Flutter Slider name), if the slider adds a formatter;
  otherwise none.
- Optional: `decrementLabel` / `incrementLabel` from non-null English defaults to nullable (localization); a
  behaviour change, decide before 1.0.
