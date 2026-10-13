# Progress and activity - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIProgressView`, `UIActivityIndicatorView`; SwiftUI `ProgressView(value:total:)`,
`ProgressView(timerInterval:countsDown:)`, `ProgressView()`, `progressViewStyle(.linear / .circular)`,
`Gauge`. morph: `MorphProgressView`, `MorphProgressViewStyle`, `MorphProgressStyle`, `MorphProgressMotion`,
`MorphActivityIndicator`, `MorphActivityIndicatorFrames`, `MorphActivityIndicatorSize`,
`MorphActivityIndicatorStyle`. Passports: [../progress-view.md](../progress-view.md),
[../activity-indicator.md](../activity-indicator.md).

SDK 27.0 check: no iOS 26 / 27 API on `UIProgressView.h` or `UIActivityIndicatorView.h`; the
public surface is legacy (iOS 2 - 13).

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIProgressView.progress` (iOS 2+) | 0..1 | `MorphProgressView.value` | name (SwiftUI says `value`) | keep |
| `UIProgressView.setProgress(_:animated:)` (iOS 5) | animated change | `MorphProgressView.animated` (applies to every change of `value`) | per-call vs per-widget | keep (declarative idiom) |
| `UIProgressView.progressViewStyle` / `init(progressViewStyle:)` (iOS 2+) | default / bar | `MorphProgressView.viewStyle` | name; `default` is a Dart keyword | keep cases; reshape name (see Breaking) |
| `UIProgressView.Style.default` / `.bar` | cases | `MorphProgressViewStyle.standard` / `bar` | `standard` for `default` (keyword) | keep |
| `UIProgressView.progressTintColor` (iOS 5) | fill color | `MorphProgressView.progressColor`, `MorphProgressStyle.progressColor` | none | keep |
| `UIProgressView.trackTintColor` (iOS 5) | track color | `MorphProgressView.trackColor`, `MorphProgressStyle.trackColor` | none | keep |
| `UIProgressView.progressImage` / `trackImage` (iOS 5) | stretchable images | none | missing | skip (rare; app can draw its own bar) |
| `UIProgressView.observedProgress` (iOS 9) | binds an `NSProgress` | none | - | skip (Flutter: rebuild from a `ValueListenable` / stream) |
| `UIActivityIndicatorView.style` (iOS 13: `.medium` / `.large`) | size | `MorphActivityIndicator.size` (`MorphActivityIndicatorSize.medium` / `large`) | enum named `Size` (morph `*Style` = colors) | keep |
| `UIActivityIndicatorView.Style.white` / `.whiteLarge` / `.gray` | deprecated iOS 13 | - | - | skip (deprecated) |
| `UIActivityIndicatorView.color` (iOS 5) | spoke color | `MorphActivityIndicator.color`, `MorphActivityIndicatorStyle.color` | none | keep |
| `UIActivityIndicatorView.hidesWhenStopped` (iOS 2+) | hide at stop | `MorphActivityIndicator.hidesWhenStopped` | default true both | keep |
| `startAnimating()` / `stopAnimating()` / `isAnimating` (iOS 2+) | run state | `MorphActivityIndicator.animating` | declarative bool; default true (UIKit starts stopped) | keep (Flutter idiom; `CupertinoActivityIndicator.animating` is the same) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `ProgressView(value:total:)` (iOS 14) | determinate, `total` scale | `MorphProgressView(value:)` | no `total` | skip (divide in the call) |
| `ProgressView(value:) { label } currentValueLabel: { }` (iOS 14) | title above, value text below the bar | none | no labels | add `label` / `currentValueLabel` Widgets (layout needs measuring); low |
| `ProgressView(timerInterval:countsDown:)` (iOS 16) | bar driven by a date range | none | missing | add `MorphProgressView.timer(interval, countsDown: true)`; low |
| `ProgressView()` / `value: nil` (iOS 14) | indeterminate -> spinner | `MorphActivityIndicator` | separate widget | keep (document the mapping) |
| `progressViewStyle(.linear / .circular / .automatic)` (iOS 14) | bar vs spinner | `MorphProgressView` vs `MorphActivityIndicator` | determinate circular not provided | skip until measured on iOS 27 |
| `ProgressView` + `.controlSize(.mini / .small / .regular / .large / .extraLarge)` | spinner size | `MorphActivityIndicatorSize.medium` (= regular) / `large` | mini / small / extraLarge missing | skip (unmeasured; UIKit has two) |
| `ProgressView("Loading")` circular with label (iOS 14) | spinner over a caption | none | missing | add `MorphActivityIndicator.label` Widget; low |
| `.tint(_:)` | fill / spinner color | `progressColor` / `color` | none | keep |
| `Gauge(value:in:)` + `gaugeStyle(.linearCapacity / .accessoryCircular ...)` (iOS 16) | value in range, min/max labels | none | out of scope (widget / Lock Screen look) | skip (not a Liquid Glass control) |

## Not relevant for Flutter
- `UIAppearance` selectors (`progressTintColor`, `color`), `NSCoding`, `initWithFrame:`.
- `NSProgress` cancellation / pausing plumbing behind `observedProgress`.
- Accessibility value / updates frequent trait: Flutter `Semantics` (morph: percent value, `semanticLabel`).

## morph-only API
- `MorphProgressStyle`, `MorphActivityIndicatorStyle` light / dark tables - keep (package convention).
- `MorphProgressMotion` (additive linear motion), `MorphActivityIndicatorFrames`, `MorphActivityIndicator.metrics`,
  `MorphProgressView.standardHeight` / `barHeight` - keep (measured).
- `MorphActivityIndicator.semanticLabel = 'In progress'` (English default) - keep, but note it is the
  only non-null English default string among these widgets; consider `String?` with a localizable default.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | spinner caption (`ProgressView("Loading")`) | med (loading states) | S (needs one layout measurement) | add `MorphActivityIndicator.label` |
| 2 | bar labels (`label`, `currentValueLabel`) | low-med (downloads) | S-M | add to `MorphProgressView` |
| 3 | timer-driven bar (`ProgressView(timerInterval:countsDown:)`) | low | S | add named constructor |
| 4 | track / progress images | low | M | skip |
| 5 | extra spinner sizes (SwiftUI `controlSize`) | low | S (unmeasured) | skip until measured |

## Breaking changes before 1.0
- `MorphProgressView.viewStyle` + `MorphProgressViewStyle` (shape enum) next to `MorphProgressStyle`
  (color table) is the one place where morph's `*Style` means UIKit's style enum; the two names differ by
  one word and read alike. Proposal: `MorphProgressViewStyle` -> `MorphProgressViewVariant` and
  `viewStyle` -> `variant`, matching the presentation-enum word chosen for the date picker
  (`MorphDatePickerVariant`). Coordinator decides the word across families; activity keeps `MorphActivityIndicatorSize`.
- `MorphActivityIndicator.semanticLabel` `String = 'In progress'` -> `String?` (null = default from
  localizations). Low priority.
