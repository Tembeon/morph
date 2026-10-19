# Page control - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIPageControl`, `UIPageControlProgress`, `UIPageControlTimerProgress`; SwiftUI `TabView` +
`.tabViewStyle(.page(indexDisplayMode:))`, `.indexViewStyle(.page(backgroundDisplayMode:))`.
morph (public): `MorphPageControl`, `MorphPageControlBackgroundStyle`, `MorphPageControlAppearance`.
Internal: `MorphPageControlMotion`, `MorphPageControlTuning`. Passport: [../page-control.md](../page-control.md).

SDK 27.1 check: no iOS 26 / 27 / 27.1 API on `UIPageControl.h` or `UIPageControlProgress.h`; newest is
`progress` (iOS 17). Liquid Glass changed the look only.

## UIKit
| UIKit API (availability) | meaning | morph equivalent | status | proposal |
|---|---|---|---|---|
| `numberOfPages` (iOS 2) | page count | `count` | covered | - |
| `currentPage` (iOS 2) | current page, pinned to the range | `page` (clamped) | covered | - |
| `.valueChanged` | user stepped or scrubbed | `onChanged` | covered | - |
| `isEnabled` | disabled: looks the same | `onChanged == null` | covered | - |
| `hidesForSinglePage` (iOS 2) | hide with one page | none (one dot draws) | gap | `hidesForSinglePage = false` |
| `pageIndicatorTintColor` (iOS 6) | other dots | `MorphPageControlAppearance.pageIndicatorColor` | partial: only through a whole appearance, which drops the dark and high-contrast tables | widget-level `pageIndicatorColor` |
| `currentPageIndicatorTintColor` (iOS 6) | current dot | `MorphPageControlAppearance.currentPageIndicatorColor` | partial (same) | widget-level `currentPageIndicatorColor` |
| `backgroundStyle` (iOS 14) + `.automatic` / `.prominent` / `.minimal` | platter policy | `backgroundStyle`, `MorphPageControlBackgroundStyle` | covered (4) | - |
| `direction` (iOS 16) | layout direction | none | gap | `MorphPageControlDirection` |
| `.natural` | follow layout direction | follows `Directionality` | covered | - |
| `.leftToRight` / `.rightToLeft` / `.topToBottom` / `.bottomToTop` | forced or vertical | none | gap (4) | with `direction` |
| `interactionState` (iOS 14, readonly) | none / discrete / continuous | internal only | gap | expose only if a caller needs it |
| `allowsContinuousInteraction` (iOS 14) | scrub on / off | always on | gap | add the flag |
| `preferredIndicatorImage` (iOS 14) | custom dot | none | gap | `indicatorBuilder` |
| `indicatorImage(forPage:)` / `setIndicatorImage(_:forPage:)` (iOS 14) | per-page dot | none | gap | same builder |
| `preferredCurrentPageIndicatorImage` (iOS 16) | current-page image | none | gap | same builder (current flag) |
| `currentPageIndicatorImage(forPage:)` / setter (iOS 16) | per-page current image | none | gap | same builder |
| `sizeForNumberOfPages(_:)` (iOS 2) | size for a count | none | gap | static `MorphPageControl.sizeFor(int)` |
| `progress` (iOS 17) | a `UIPageControlProgress` | `progress` (`double?`) | partial: a value, no object or delegate | keep the value |
| `UIPageControlProgress.currentProgress` | 0..1 of the page | `progress` | covered | - |
| `progressVisible` + delegate visibility | show or hide | `progress == null` | covered | - |
| `UIPageControlTimerProgress(preferredDuration:)` (iOS 17) | auto-advance | none | gap | `MorphPageControlTimer` controller |
| `setDuration(_:forPage:)` / `duration(forPage:)` | per-page duration | none | gap | in the controller |
| `resetsToInitialPageAfterEnd` | loop | none | gap | in the controller |
| `isRunning` / `pauseTimer()` / `resumeTimer()` | run control | none | gap | in the controller |
| timer delegate `shouldAdvanceToPage`, `didChange` | veto, progress | none | gap | in the controller |
| `defersCurrentPageDisplay` / `updateCurrentPageDisplay` | deprecated iOS 14 | - | n/a | - |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | status | proposal |
|---|---|---|---|---|
| `TabView` + `.tabViewStyle(.page(indexDisplayMode:))` (iOS 14) | pager with dots | none (app wires `PageView` + `MorphPageControl`) | gap | optional `controller: PageController?` |
| `.indexViewStyle(.page(backgroundDisplayMode:))` | platter | `backgroundStyle` | same as UIKit row: `.interactive` = `automatic`, `.always` = `prominent`, `.never` = `minimal` | name the mapping in the dartdoc |

Count: 33 applicable, 11 covered, 3 partial, 19 gaps.

## Not relevant for Flutter
- `UIAppearance` selectors (`MorphThemeData.appearances` carries a `MorphPageControlAppearance`), target-action, `NSCoding`, tvOS focus.
- Accessibility adjustable trait: Flutter `Semantics` (`semanticLabel`, `semanticValueFormatter`).

## morph-only API
- `semanticLabel`, `semanticValueFormatter` (default English "page n of count").
- `MorphPageControlAppearance.platterColor` / `platterIndicatorColor` (UIKit has no public platter color).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | `hidesForSinglePage` | M | S | add the flag |
| 2 | widget-level dot colors | M | S | two `Color?` parameters |
| 3 | many pages: dots that do not fit | M | M (measure first) | scroll and shrink the dots as UIKit does |
| 4 | custom indicator images | M | M | `indicatorBuilder` |
| 5 | timer progress | L-M | M (`ios27/page_control/pc-timer.jsonl` exists) | `MorphPageControlTimer` |
| 6 | `direction` incl. vertical | L-M | M | `MorphPageControlDirection` |
| 7 | link to a `PageController` | L-M | S-M | optional `controller` |
| 8 | `allowsContinuousInteraction`, `sizeForNumberOfPages` | L | S | add both |

## Breaking changes before 1.0
- Done: `indicatorColor` / `currentIndicatorColor` -> `pageIndicatorColor` / `currentPageIndicatorColor`;
  `background` -> `backgroundStyle` with `MorphPageControlBackgroundStyle`.
- `count` / `page`: kept (no change proposed).

## Behaviour fidelity
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | this page | `hidesForSinglePage`, dot colors on the widget, images, timer |
| layout | unbacked | dots, pitch, height [layout]; test/indicators_test.dart pins morph's own constants | UIKit's 5-page control view is 126 pt wide, morph's 108.35; the platter's width is not recorded and `padding` 14 has no source |
| states | replayed | disabled draws nothing different (`ios27-device/disabled/disabled.json`, test/disabled_test.dart); platter states replayed below | prominent / minimal platter look is a flat stand-in (optics) |
| transitions | unbacked | platter in / out replayed on device rows (`pc-hold`, `pc-scrub`, rms < 0.03); progress width spring and the fill fade replayed on sim rows (`pc-timer`, rms < 0.25 pt, fade rms < 0.02) | a page change without progress snaps ("instant, as UIKit's is") with no recording of the dots |
| boundaries | missing | empty and out-of-range counts (test/page_control_bounds_test.dart) | many pages (dots that do not fit) not implemented; a far scrub's irregular steps not reproduced |
| configuration | missing | backgroundStyle cases, progress on / off | `direction`, images, `allowsContinuousInteraction` |
| events | replayed | tap and scrub `valueChanged` sequences equal the recording (`pc-tap-right`, `pc-scrub`, device and sim) | - |
| input | replayed | tap halves step on the lift; scrub to the nearest dot with 1.5 pt hysteresis (measured) | `scrubSlop` 10 has no source; it only agrees with one scrub recording |
| mutation | unbacked | count change rebuilds the motion | count or page changes from code are not recorded |
| accessibility | read | haptic on a scrub step and Increase Contrast dots read from UIKit (notes private; states.md); no Reduce Motion read; adjustable semantics, arrow keys | English default value string |
| optics | approx | dot colors [layout, sim], high-contrast colors read from UIKit | the platter is a flat color on every renderer; the trade is not declared as NEAR / approximation |
| platform | missing | RTL runs the pages from the right (not measured) | vertical direction |
| performance | unbacked | host: a resting finger lets the ticker sleep (test/indicators_test.dart) | no device frame-time or energy run |
