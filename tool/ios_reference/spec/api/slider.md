# Slider - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UISlider` (UIControl), `UISlider.TrackConfiguration` (+ `.Tick`), `UISlider.Style`; SwiftUI `Slider`,
`SliderTick`, `.sliderThumbVisibility(_:)`. morph: `MorphSlider`, `MorphSliderStyle`, `MorphSliderMotion`
(`MorphWidgetsTheme.slider`). Passport: [../slider.md](../slider.md).

This family is where Liquid Glass ADDED public API: `UISlider.trackConfiguration`, `UISliderTrackConfiguration`,
`UISliderTick`, `UISlider.sliderStyle` / `UISlider.Style` (all iOS 26), SwiftUI `Slider(..., neutralValue:,
enabledBounds:, currentValueLabel:, ticks:/tick:)`, `SliderTick`, `.sliderThumbVisibility` (all iOS 26).
Nothing new in iOS 27.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `value` (iOS 2+, Float, pinned to min/max) | current value | `MorphSlider.value` (double, 0..1) | - | keep |
| `minimumValue` / `maximumValue` (iOS 2+, default 0 / 1) | range | none (fixed 0..1) | app must map; Flutter `Slider`/`CupertinoSlider` take `min`/`max` | add `min` / `max` (default 0 / 1; same names as `MorphStepper`) |
| `setValue(_:animated:)` (iOS 2+), fixed velocity, no action | programmatic change | a new `value` from the parent: thumb JUMPS (`MorphSliderMotion.setValue`) | no animated path; native fixed-velocity animation unmeasured | skip until measured; low |
| `isContinuous` (iOS 2+, default YES) | NO = valueChanged only at the end of tracking | `onChanged` (continuous) + `onChangeEnd` | covered by Flutter idiom | skip (use `onChangeEnd`) |
| `.touchDown` / `.valueChanged` / `.touchUpInside` + `.touchUpOutside` events | begin / change / end tracking | `onChanged`, `onChangeEnd`; no begin | no start callback | add `onChangeStart` (Flutter Slider/CupertinoSlider; SwiftUI `onEditingChanged(true)`) |
| `isEnabled` (UIControl) | disabled | `onChanged: null` -> `MorphSliderStyle.disabledOpacity` 0.5 | - | keep |
| `minimumTrackTintColor` (iOS 5) | fill below value | `MorphSlider.activeColor`, `MorphSliderStyle.activeColor` | - | keep (Flutter name) |
| `maximumTrackTintColor` (iOS 5) | track above value | `MorphSlider.trackColor`, `MorphSliderStyle.trackColor` | Material `Slider` calls it `inactiveColor` | rename -> `inactiveColor` (optional; see breaking) |
| `thumbTintColor` (iOS 5) | thumb color | `MorphSliderStyle.thumbColor` only | no widget-level override | add `MorphSlider.thumbColor` (CupertinoSlider/Material name) |
| `minimumValueImage` / `maximumValueImage` (iOS 2+) | images at the track ends (speaker off / max) | none | missing; layout (gap, size) unmeasured | add `minimumValueLabel` / `maximumValueLabel` (Widget, SwiftUI names) |
| `setThumbImage(_:for:)`, `setMinimumTrackImage`, `setMaximumTrackImage`, `current*Image` (iOS 2+) | skin by images per state | none | - | skip (replaces the glass thumb; a custom thumb is not this control) |
| `trackRect(forBounds:)`, `thumbRect(forBounds:trackRect:value:)`, `min/maxValueImageRect(forBounds:)` (iOS 2+) | subclass layout hooks | `MorphSliderMotion` (track inset, thumb size constants) | - | skip (subclass hooks; pure motion object exposes geometry) |
| `sliderStyle`, `UISlider.Style` `.default` / `.thumbless` (iOS 26, NEW) | thumbless media-scrubber slider | none | missing; thumbless look/motion unmeasured | add `MorphSlider.thumbVisible` (bool, true) - avoids clashing with the look class `MorphSliderStyle` |
| `trackConfiguration` (`UISlider.TrackConfiguration?`, iOS 26, NEW) | ticks, snapping, neutral value, enabled range | `MorphSlider.ticks` (int) only | only even ticks, always snapping | add `MorphSliderTrackConfiguration` (rows below) |
| `TrackConfiguration(numberOfTicks:)` / `configurationWithNumberOfTicks:` (iOS 26) | evenly spaced ticks | `MorphSlider.ticks` | - | keep concept, move into the configuration |
| `TrackConfiguration(ticks: [Tick])` / `configurationWithTicks:` (iOS 26) | ticks at arbitrary positions | none | missing | add `MorphSliderTrackConfiguration.ticks` (`List<MorphSliderTick>`) |
| `Tick(position:title:image:)` / `UISliderTick` (iOS 26) | tick at a value, optional title/image | none | rendering of tick title/image unmeasured | add `MorphSliderTick(position, {title, icon})` (icon as Widget) |
| `allowsTickValuesOnly` (iOS 26, default true) | snap to ticks or allow any value | none (always snaps when `ticks >= 2`) | missing | add `allowsTickValuesOnly` (default true) |
| `neutralValue` (iOS 26, default 0) | fill grows from this value (e.g. -1..1 balance) | none (fill from minimum) | missing; fill drawing from a neutral point unmeasured | add `neutralValue` |
| `enabledRange` (Swift, `ClosedRange<Float>`) / `minimumEnabledValue` / `maximumEnabledValue` (ObjC) (iOS 26) | sub-range the thumb may reach | none | missing; disabled-part look unmeasured | add `enabledRange` (record `(double, double)` or two doubles; Swift name) |
| `accessibilityValue` / increment / decrement | VoiceOver adjust | `semanticLabel`, adjust actions by `keyboardStep` (or one stop) | no value formatter | add `semanticFormatterCallback` (Material Slider name) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Slider(value:in:step:onEditingChanged:)` (iOS 13) | range + continuous step | `ticks` (even stops) | `step` without tick marks is not expressible; Flutter `divisions` | covered by `numberOfTicks` / `allowsTickValuesOnly`; skip `step` |
| `onEditingChanged: (Bool) -> Void` (iOS 13) | begin / end editing | `onChangeEnd` only | same as UIKit events row | add `onChangeStart` |
| `minimumValueLabel:` / `maximumValueLabel:` (iOS 13) | views at the ends | none | same as UIKit images row | add `minimumValueLabel` / `maximumValueLabel` |
| `label:` (iOS 13) | accessibility / macOS label | `semanticLabel` | - | keep |
| `currentValueLabel:` (iOS 26, NEW) | view showing the current value (where it renders on iOS not checked) | none | unmeasured | skip until seen on device |
| `neutralValue:` / `enabledBounds:` (iOS 26, NEW) | same as TrackConfiguration | none | same as UIKit rows | add (one config class serves both) |
| `ticks: { SliderTick(...) }` / `tick: (V) -> SliderTick?` (iOS 26, NEW) | declarative ticks; per-step tick builder | none | same as UIKit ticks rows | `MorphSliderTrackConfiguration.ticks` |
| `SliderTick(_ value:)`, `SliderTick(_ title:, _ value:)`, `SliderTick(_:label:)` (iOS 26, NEW) | tick with title or view label | none | - | `MorphSliderTick(position, {title, icon})` |
| `.sliderThumbVisibility(_ Visibility)` (iOS 26, NEW) | hide the thumb (= `UISlider.Style.thumbless`) | none | - | `thumbVisible` |
| `.tint(_:)` / `.disabled(_:)` / `.controlSize(_:)` | fill color / disable / size | `activeColor` / `onChanged: null` / fixed `MorphSlider.height` 34 | - | keep |

## Not relevant for Flutter
- `NSCoding`, `UIAppearance` proxies, `UIBehavioralStyle` (Mac idiom).
- target-action plumbing; subclass rect hooks; per-state image skinning (see row).
- `NSCopying` of the configuration (Dart value class covers it).

## morph-only API
- `MorphSlider.height` (34), `MorphSlider.keyboardStep` (0.1) - keep.
- `MorphSliderStyle.tickColor`, `.disabledOpacity` - keep (measured look).
- `MorphSliderMotion` (pure motion; `panSlop`, `glideCoast`, `glideDecay`, `fillRamp`, `tickHold`, ...) - keep.

## Flutter convention
- `CupertinoSlider`: `value`, `onChanged`, `onChangeStart`, `onChangeEnd`, `min` (0), `max` (1), `divisions`,
  `activeColor`, `thumbColor`. Material `Slider` adds `inactiveColor`, `secondaryTrackValue`, `label`,
  `semanticFormatterCallback`, `focusNode`, `autofocus`.
- morph matches `value` / `onChanged` / `onChangeEnd` / `activeColor` / null-to-disable, but lacks
  `onChangeStart`, `min`/`max`, `thumbColor`; `trackColor` is neither Flutter's (`inactiveColor`) nor UIKit's
  (`maximumTrackTintColor`). `ticks` (UIKit `numberOfTicks`) vs Flutter `divisions` (= ticks - 1): keep the UIKit
  concept (ticks are drawn marks on iOS 26), document the off-by-one against `divisions`.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | `min` / `max` range | high | S (map at the widget edge; motion stays 0..1) | add `min`, `max` |
| 2 | `onChangeStart` | high | S | add `onChangeStart` |
| 3 | min/max value images (speaker icons) | med | M (layout gap/size need a capture) | `minimumValueLabel` / `maximumValueLabel` |
| 4 | iOS 26 track configuration: `neutralValue`, `enabledRange`, custom tick positions + titles, `allowsTickValuesOnly = false` | med | L (each look unmeasured: neutral fill, disabled range, tick labels) | `MorphSliderTrackConfiguration` + `MorphSliderTick` |
| 5 | thumbless style (iOS 26) | med (media players) | M-L (look + touch model unmeasured) | `thumbVisible` |
| 6 | widget-level `thumbColor` | low | S | add |
| 7 | `semanticFormatterCallback` | low | S | add (stepper has `semanticValueFormatter`; unify the name) |

## Breaking changes before 1.0
- `MorphSlider.ticks` (int) -> `trackConfiguration: MorphSliderTrackConfiguration?` with
  `MorphSliderTrackConfiguration.numberOfTicks(n)` and `(ticks: [...])`, `allowsTickValuesOnly`, `neutralValue`,
  `enabledRange` - one home for the iOS 26 API instead of growing flat parameters. (Alternative if a short form
  matters: keep `ticks` and add the class later; decide before 1.0, not after.)
- `MorphSlider.trackColor` / `MorphSliderStyle.trackColor` -> `inactiveColor` (Material Slider name; UIKit
  `maximumTrackTintColor`). Optional, low priority; only if the switch renames land too, for one vocabulary.
