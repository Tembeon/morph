# Progress and activity - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIProgressView`, `UIActivityIndicatorView`; SwiftUI `ProgressView(value:total:)`,
`ProgressView(timerInterval:countsDown:)`, `ProgressView()`, `progressViewStyle(.linear / .circular)`,
`Gauge`. morph (public): `MorphProgressView`, `MorphProgressViewStyle`, `MorphProgressViewAppearance`,
`MorphActivityIndicator`, `MorphActivityIndicatorSize`, `MorphActivityIndicatorAppearance`. Internal:
`MorphProgressMotion`, `MorphActivityIndicatorFrames`. Passports: [../progress-view.md](../progress-view.md),
[../activity-indicator.md](../activity-indicator.md).

SDK 27.1 check: no iOS 26 / 27 / 27.1 API on `UIProgressView.h`, `UIActivityIndicatorView.h` or the
SwiftUI `ProgressView` family; the public surface is iOS 2 - 16.

Naming: option (b). `MorphProgressViewStyle { standard, bar }` is UIKit's `UIProgressView.Style`
(`default` is a Dart keyword), `MorphProgressViewAppearance` the look table. Colors use Flutter's
vocabulary (`activeTrackColor` / `inactiveTrackColor`) with the UIKit name in the dartdoc.

## UIKit - progress view
| UIKit API (availability) | meaning | morph equivalent | status | proposal |
|---|---|---|---|---|
| `progress` (iOS 2) | 0..1 | `value` | covered | - |
| `setProgress(_:animated:)` (iOS 5) | animated change | `animated` (every change of `value`) | covered | - |
| `progressViewStyle` / `init(progressViewStyle:)` (iOS 2) | default / bar | `style` | covered | - |
| `.default` / `.bar` | cases | `MorphProgressViewStyle.standard` / `bar` | covered (2) | - |
| `progressTintColor` (iOS 5) | fill | `activeTrackColor` | covered | - |
| `trackTintColor` (iOS 5) | track | `inactiveTrackColor` | covered | - |
| `progressImage` / `trackImage` (iOS 5) | stretchable images | none | gap (2) | leave out (rare) |
| `observedProgress` (iOS 9) | binds an `NSProgress` | - | n/a | rebuild from a listenable |

## UIKit - activity indicator
| UIKit API (availability) | meaning | morph equivalent | status | proposal |
|---|---|---|---|---|
| `style` (iOS 13: `.medium` / `.large`) | size | `size`, `MorphActivityIndicatorSize.medium` / `large` | covered (3) | - |
| `.white` / `.whiteLarge` / `.gray` | deprecated iOS 13 | - | n/a | - |
| `color` (iOS 5) | spoke color | `color`, `MorphActivityIndicatorAppearance.color` | covered | - |
| `hidesWhenStopped` (iOS 2) | hide at stop | `hidesWhenStopped` | covered | - |
| `startAnimating()` / `stopAnimating()` (iOS 2) | run | `animating` (default true; UIKit starts stopped) | covered | - |
| `isAnimating` (iOS 2) | run state | `animating` | covered | - |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | status | proposal |
|---|---|---|---|---|
| `ProgressView(value:total:)` (iOS 14) | determinate, `total` scale | `MorphProgressView(value:)` | partial: no `total` | divide in the call |
| `ProgressView(...) { label } currentValueLabel: { }` (iOS 14) | title and value text | none | gap | `label` / `currentValueLabel` (measure the layout) |
| `ProgressView(timerInterval:countsDown:)` (iOS 16) | bar driven by a date range | none | gap | `MorphProgressView.timer` |
| `progressViewStyle(.linear / .circular / .automatic)` | bar or spinner | two widgets | partial: no determinate circular | leave out until measured |
| `ProgressView()` (iOS 14) | indeterminate spinner | `MorphActivityIndicator` | covered | - |
| `ProgressView("Loading")` circular with label | spinner over a caption | none | gap | `MorphActivityIndicator.label` |
| `.controlSize(.mini ... .extraLarge)` on a spinner | spinner size | `medium` (= regular) / `large` | partial | leave out until measured |
| `.tint(_:)` | fill / spinner color | `activeTrackColor` / `color` | same as UIKit rows | - |
| `Gauge` (iOS 16) | value in a range | - | n/a | not a Liquid Glass control |

Count, progress (UIKit + SwiftUI-only): 13 applicable, 7 covered, 2 partial, 4 gaps.
Count, activity indicator (UIKit + SwiftUI-only): 10 applicable, 8 covered, 1 partial, 1 gap.

## Not relevant for Flutter
- `UIAppearance` selectors (`MorphThemeData.appearances`), `NSCoding`, `initWithFrame:`.
- `NSProgress` cancellation and pausing behind `observedProgress`.
- Accessibility traits: Flutter `Semantics` (percent value on the bar, `semanticLabel` on both).

## morph-only API
- Light / dark appearance tables (progress also has high-contrast tables).
- `MorphActivityIndicator.metrics`, `MorphProgressView.standardHeight` / `barHeight`.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | spinner caption (`ProgressView("Loading")`) | M | S (measure the layout) | `MorphActivityIndicator.label` |
| 2 | spinner label localizable: "In progress" is a hard-coded English default | M | S | read it from `MorphLocalizations` |
| 3 | bar labels (`label`, `currentValueLabel`) | L-M | S-M | add to `MorphProgressView` |
| 4 | timer-driven bar | L | S | named constructor |
| 5 | track / progress images | L | M | leave out |
| 6 | extra spinner sizes | L | S (unmeasured) | leave out until measured |

## Breaking changes before 1.0
- Done: `viewStyle` -> `style`; the look table is `MorphProgressViewAppearance`; colors are
  `activeTrackColor` / `inactiveTrackColor`; `MorphActivityIndicator.semanticLabel` is `String?`.
- Open: the null `semanticLabel` still announces English "In progress"; move the default into `MorphLocalizations`.

## Behaviour fidelity - progress view
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | read | this page | labels, timer (low need) |
| layout | measured | heights 4 / 2.67 in `ios27-device/progress/*.jsonl` (ids 1 - 8) | no test compares the heights with the rows |
| states | unbacked | empty bar hides its fill (replayed) | the bar style draws no track: not recorded |
| transitions | replayed | test/indicators_test.dart replays `progress2`, `progress3` (sim and device) and `progress-additive` (device), the standard and the bar style: width rms < 0.6 pt, opacity rms < 0.02 | - |
| boundaries | replayed | the 8 pt minimum fill and the 0.2 s minimum fade are inside the replays | - |
| configuration | measured | bar style runs the same timing [device] | bar look unrecorded |
| events | n/a | no events | - |
| input | n/a | no input | - |
| mutation | replayed | a retarget mid-change adds on top (`progress-additive`) | - |
| accessibility | unbacked | percent value; Increase Contrast tables read from UIKit (notes private) | under Reduce Motion morph drops the animation; no UIKit read or recording backs it |
| optics | measured | colors [sim, device confirmed]; fill opacity ramp replayed | - |
| platform | unbacked | RTL fills from the right | not recorded |
| performance | unbacked | - | no device frame-time or energy run |

## Behaviour fidelity - activity indicator
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | this page | caption |
| layout | unbacked | boxes 20 / 37 in `ios27-device/progress/activity-startstop.jsonl` | spoke width and inner / outer radii (`MorphActivityIndicator.metrics`) have no source |
| states | replayed | stop / start / hide are cuts; a restart turns on from the image the stop left (images 0, 10, 4) [device rows `activity-startstop`, read from UIKit]; test/indicators_test.dart replays the three starts | the stopped image with `hidesWhenStopped` false is inferred, not recorded |
| transitions | measured | 16 images per 0.8 s [tuning]; head and tail strengths from simulator pixels | test/indicators_test.dart checks the constants, not pixels |
| boundaries | n/a | - | - |
| configuration | measured | two sizes, color override | - |
| events | n/a | - | - |
| input | n/a | - | - |
| mutation | measured | every start restarts at image 0 [device] | not replayed |
| accessibility | missing | label while spinning | no Increase Contrast table; "keeps turning under Reduce Motion, as UIKit's does" has no source; English default label |
| optics | measured | light color [tuning], dark color from device pixels (test/disabled_test.dart pins the constant) | spokes are drawn round-capped lines, not UIKit's images |
| platform | n/a | - | - |
| performance | unbacked | host: one frame per image, 20 a second (test/indicators_test.dart) | no device run; UIKit spends no main-thread frame |
