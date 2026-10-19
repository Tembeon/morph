# Slider - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UISlider` (UIControl), `UISlider.TrackConfiguration` (+ `.Tick`), `UISlider.Style`; SwiftUI `Slider`,
`SliderTick`, `.sliderThumbVisibility(_:)`. morph: `MorphSlider`, `MorphSliderAppearance` (explicit, or from
`MorphThemeData.appearances`; the fill takes `MorphThemeData.tint`). The motion class `MorphSliderMotion`
is internal. Passport: [../slider.md](../slider.md).

Liquid Glass added public API here in iOS 26: `trackConfiguration`, `UISliderTrackConfiguration`, `UISliderTick`,
`sliderStyle` / `UISlider.Style`, SwiftUI `Slider(..., neutralValue:, enabledBounds:, currentValueLabel:,
ticks:/tick:)`, `SliderTick`, `.sliderThumbVisibility`. SDK 27.1 adds nothing (checked against iPhoneOS27.1.sdk
headers, the UIKit overlay and SwiftUI.swiftinterface). The header still says `setValue(_:animated:)` moves "at
fixed velocity"; the iOS 27 glass slider does not (slider.md).

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `value` (iOS 2, Float, pinned) | current value | `MorphSlider.value` | - | keep |
| `minimumValue` / `maximumValue` (iOS 2, 0 / 1) | range | `min` / `max` (0 / 1) | - | done |
| `setValue(_:animated:)` (iOS 2), no action | programmatic change | a new `value` jumps; with `animated` it springs (programmatic spring 0.4 / 0.8, read from UIKit) | the end overshoot does not stretch the track (clamped) | done |
| `isContinuous` (iOS 2, YES) | NO = one event at the end | `onChanged` + `onChangeEnd` | no flag | skip (use `onChangeEnd`) |
| `.touchDown` / `.valueChanged` / `.touchUpInside` / `.touchUpOutside` | begin / change / end | `onChangeStart` / `onChanged` / `onChangeEnd` | - | done |
| `isEnabled` (UIControl) | disabled | `onChanged: null`, `disabledOpacity` 0.5 | - | keep |
| `minimumTrackTintColor` (iOS 5) | fill | `activeTrackColor` (widget, appearance, theme tint) | - | done |
| `maximumTrackTintColor` (iOS 5) | track | `inactiveTrackColor` (widget, appearance) | - | done |
| `thumbTintColor` (iOS 5) | thumb | `MorphSliderAppearance.thumbColor` | no widget-level override | add `MorphSlider.thumbColor` |
| `minimumValueImage` / `maximumValueImage` (iOS 2) | images at the ends | none | missing; layout and motion unmeasured | `minimumValueLabel` / `maximumValueLabel` (Widget) after a capture |
| `setThumbImage(_:for:)`, `currentThumbImage` (iOS 2) | custom thumb | none | replaces the glass thumb | skip |
| `setMinimumTrackImage` / `setMaximumTrackImage` (iOS 2) | track skins | colors only | images vs colors | skip |
| `trackRect(forBounds:)`, `thumbRect(...)`, `*ValueImageRect(forBounds:)` | subclass hooks | - | - | n/a |
| `sliderStyle` `.thumbless` (iOS 26) | media scrubber | none | missing; look and touch unmeasured | `thumbVisible` after a capture |
| `TrackConfiguration(numberOfTicks:)` (iOS 26) | even stops, snapping | `MorphSlider.ticks` | - | keep (see breaking) |
| `TrackConfiguration(ticks:)` (iOS 26) | stops at any position | none | missing | `MorphSliderTrackConfiguration.ticks` |
| `Tick(position:title:image:)` (iOS 26) | tick title / image | none | look unmeasured | `MorphSliderTick(position, {title, icon})` |
| `allowsTickValuesOnly` (iOS 26, true) | snap or free | always snaps | NO is read from UIKit (slider.md), not ported | add with the configuration |
| `neutralValue` (iOS 26, 0) | fill origin | fill from the minimum | missing; look unmeasured | add with the configuration |
| `enabledRange` (Swift) / `minimumEnabledValue` / `maximumEnabledValue` (iOS 26) | reachable sub-range | none | missing; look unmeasured | add with the configuration |
| `accessibilityValue` / increment / decrement | VoiceOver | percent value, adjust by `keyboardStep` 0.1 or one stop | no formatter; step size has no source | add `semanticFormatterCallback`; measure the native step |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Slider(value:in:)`, `label:` (iOS 13) | range, label | `min` / `max`, `semanticLabel` | - | keep |
| `Slider(value:in:step:)` (iOS 13) | discrete values | `ticks` (always draws marks) | no snapping without marks; whether `step` alone draws marks on iOS 26+ is not checked | check, then decide |
| `onEditingChanged:` (iOS 13) | begin / end | `onChangeStart` / `onChangeEnd` | - | done |
| `minimumValueLabel:` / `maximumValueLabel:` (iOS 13) | end views | none | as the images row | as above |
| `currentValueLabel:` (iOS 26) | value view | none | where iOS draws it is not checked | skip until seen on a device |
| `neutralValue:` / `enabledBounds:` (iOS 26) | as TrackConfiguration | none | as the UIKit rows | one configuration class serves both |
| `ticks: { SliderTick(...) }` / `tick: (V) -> SliderTick?` (iOS 26) | declarative ticks | none | as the UIKit rows | `MorphSliderTrackConfiguration.ticks` |
| `SliderTick(_:)`, `SliderTick(_:_:)`, `SliderTick(_:label:)` (iOS 26) | tick with title or view | none | - | `MorphSliderTick` |
| `.sliderThumbVisibility(_:)` (iOS 26) | thumbless | none | - | `thumbVisible` |
| `.tint(_:)` | fill, inherited | `activeTrackColor`, `MorphThemeData.tint` | - | done |
| `.controlSize(_:)` | size | fixed `MorphSlider.height` 34 | effect not measured | measure first |

## Not relevant for Flutter
- `NSCoding`, `UIAppearance` proxies, `UIBehavioralStyle` (Mac idiom).
- Target-action plumbing, subclass rect hooks, `NSCopying` of the configuration.

## morph-only API
- `MorphSlider.height` (34), `MorphSlider.keyboardStep` (0.1): neither has a source.
- `MorphSlider.animated` (UIKit passes `animated` per call; morph takes it per widget).
- `MorphSliderAppearance.tickColor`, `.disabledOpacity` (measured), contrast tables (read, unrendered).

## Flutter convention
- `CupertinoSlider`: `value`, `onChanged`, `onChangeStart`, `onChangeEnd`, `min`, `max`, `divisions`,
  `activeColor`, `thumbColor`. Material `Slider` adds `inactiveColor`, `secondaryTrackValue`, `label`,
  `semanticFormatterCallback`, `focusNode`, `autofocus`.
- morph matches `value`, `onChanged`, `onChangeStart`, `onChangeEnd`, `min`, `max`, null-to-disable.
  `ticks` is UIKit's `numberOfTicks` (= Flutter `divisions` + 1).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | min/max value images | M | M meas. | `minimumValueLabel` / `maximumValueLabel` |
| 2 | iOS 26 track configuration: `neutralValue`, `enabledRange`, custom ticks + titles, `allowsTickValuesOnly = false` | M | L meas. | `MorphSliderTrackConfiguration` + `MorphSliderTick` |
| 3 | thumbless style | M | M-L meas. | `thumbVisible` |
| 4 | thumb hit slop 8 pt and VoiceOver step 0.1 have no source | M | S meas. | measure, then fix the numbers |
| 5 | widget-level `thumbColor` | L | S | add |
| 6 | `semanticFormatterCallback` | L | S | add (stepper already has the name) |

## Breaking changes before 1.0
- Done: `MorphSliderStyle` -> `MorphSliderAppearance`, `activeColor` / `trackColor` ->
  `activeTrackColor` / `inactiveTrackColor`, `min` / `max` / `onChangeStart` added, motion class internal.
- Open: `ticks` (int) -> `trackConfiguration: MorphSliderTrackConfiguration?`, or keep `ticks` as a
  shorthand next to it. Decide before 1.0.

## Behaviour fidelity
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | this page, SDK 27.1 | track configuration beyond even ticks, thumbless, value images |
| layout | replayed | test/controls_test.dart: fill end within 0.15 pt (ios27-device/controls slider-w300-video-dark, -w200-end-*-fill), tick centers and 8.5 pt offset exact (slider-ticks5-video-dark), thumb center at the ends | `MorphSlider.height` 34 no source; 200 pt width when unbounded |
| states | replayed | thumb lift and land (controls_test `_liftReplay`, slider-w300-hold800-thumb); disabled_test (disabled.json) | - |
| transitions | replayed | glide (6 glide files, rms < 2.2 pt), stretch and its return (`_stretchReplay`, 4 sim + 9 device files), stepped detent curve (fill / thumb rms < 1.85 / 1.55 pt), test/slider_set_value_test.dart (native fill samples inline, < 1 pt) | declared not reproduced: white release flash, animated overshoot into the stretch, stepped release overshoot past an outer stop |
| boundaries | replayed | no catch-up at the ends, finger lead within 0.2 - 6 pt (`_thumbReplay`), stretch rubber band (13, 0.74), far edge 0.357, squish | - |
| configuration | missing | ticks replayed; `min` / `max` mapping host-only (test/slider_range_test.dart) | `allowsTickValuesOnly = NO` read, not ported; neutral value, enabled range, custom ticks, thumbless |
| events | replayed | every recorded valueChanged during 17 device drags (`_sliderValues`, rms limits 0.05 - 1.7 pt); stepped stops exact | end and detent haptics mapped to Flutter feedback (approximation, haptics.dart:24-30) |
| input | unbacked | pan hysteresis 10 pt and waited begins replayed (test/support/slider_feed.dart); controls_scroll_test | `thumbSlop` 8 pt (slider_motion.dart:87) has no source; track tap fixtures (slider-w300-tap-track300, -drag-ontrack) not loaded by a test |
| mutation | unbacked | a parent value during a drag or glide waits for its end (slider.dart:167-170) | no native recording |
| accessibility | unbacked | Reduce Motion read (thumb never lifts), contrast fill read (states.md); test/accessibility_test.dart | percent value and `keyboardStep` 0.1 (slider.dart:211) have no source; stepped keyboard step unmeasured |
| optics | unbacked | glass path measured: film colors light / dark, platter white (slider.md Look), lifted thumb shrink 0 (glass-optics.md) | dark lifted thumb wash differs (declared); no-painter thumb shadow (slider.dart:615-618) and flat rim (small_lens.dart:42-47) have no source |
| platform | unbacked | controls_platform_test (RTL grows left, arrows) | RTL and keyboard not measured on iOS |
| performance | measured | Pixel 6a controls scene, tool/bench/baseline.json 2026-10-12: liquid UI / raster p95 10.2 / 12.0 ms, 589 mW; flat 8.7 / 7.0 ms, 441 mW | baseline predates 2026-10-19 API changes |
