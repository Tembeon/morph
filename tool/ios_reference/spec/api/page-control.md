# Page control - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIPageControl`, `UIPageControlProgress`, `UIPageControlTimerProgress`; SwiftUI
`TabView` + `.tabViewStyle(.page(indexDisplayMode:))`, `.indexViewStyle(.page(backgroundDisplayMode:))`.
morph: `MorphPageControl`, `MorphPageControlBackground`, `MorphPageControlMotion`, `MorphPageControlStyle`,
`MorphPageControlTuning`. Passport: [../page-control.md](../page-control.md).

SDK 27.0 check: no iOS 26 / 27 API on `UIPageControl*.h`; newest is `progress` (iOS 17). Liquid Glass
changed the look (platter) only.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIPageControl.numberOfPages` (iOS 2+) | page count | `MorphPageControl.count` | name only | keep (Dart-natural; dartdoc names UIKit) |
| `UIPageControl.currentPage` (iOS 2+) | current page | `MorphPageControl.page` | name only | keep |
| `.valueChanged` | user stepped / scrubbed | `MorphPageControl.onChanged` | null disables (look unchanged, as measured) | keep |
| `UIPageControl.hidesForSinglePage` (iOS 2+) | hide with one page | none (one dot draws) | missing | add `hidesForSinglePage = false` |
| `UIPageControl.pageIndicatorTintColor` (iOS 6) | dot color | `MorphPageControlStyle.indicatorColor` | no widget-level override (progress/activity have one) | add `MorphPageControl.pageIndicatorColor`; rename style field (see Breaking) |
| `UIPageControl.currentPageIndicatorTintColor` (iOS 6) | current dot color | `MorphPageControlStyle.currentIndicatorColor` | same | add `currentPageIndicatorColor` |
| `UIPageControl.backgroundStyle` (iOS 14) | platter policy | `MorphPageControl.background` | property name differs | rename -> `backgroundStyle` (optional, see Breaking) |
| `UIPageControl.BackgroundStyle.automatic` / `.prominent` / `.minimal` | cases | `MorphPageControlBackground.automatic` / `prominent` / `minimal` | none | keep |
| `UIPageControl.direction` (iOS 16) | natural / leftToRight / rightToLeft / topToBottom / bottomToTop | none (horizontal, follows `Directionality`) | no vertical, no forced direction | add `direction` (`MorphPageControlDirection`, UIKit cases) |
| `UIPageControl.allowsContinuousInteraction` (iOS 14) | scrub on/off | none (always on) | missing | add `allowsContinuousInteraction = true` |
| `UIPageControl.interactionState` (iOS 14, readonly) | none / discrete / continuous | `MorphPageControlMotion.isScrubbing` (motion object) | not on the widget | skip (rare; motion exposes it) |
| `UIPageControl.preferredIndicatorImage` (iOS 14) | custom dot for all pages | none | missing | add `indicatorBuilder` (Widget per page, current flag) |
| `UIPageControl.setIndicatorImage(_:forPage:)` / `indicatorImage(forPage:)` (iOS 14) | per-page dot (Weather location arrow) | none | missing | same builder |
| `UIPageControl.preferredCurrentPageIndicatorImage` / `setCurrentPageIndicatorImage(_:forPage:)` (iOS 16) | current-page image | none | missing | same builder (current flag) |
| `UIPageControl.sizeForNumberOfPages(_:)` (iOS 2+) | layout size | `MorphPageControlTuning` constants | no helper | add static `MorphPageControl.sizeFor(int count)` |
| `UIPageControl.progress` (iOS 17) | `UIPageControlProgress` | `MorphPageControl.progress` (double?) | value only | keep |
| `UIPageControlProgress.currentProgress` (iOS 17) | 0..1 of current page | `MorphPageControl.progress` | none | keep |
| `UIPageControlProgress.progressVisible` / delegate `initialProgressForPage`, `visibilityDidChange` | visibility policy | `progress == null` | app-driven | skip |
| `UIPageControlTimerProgress(preferredDuration:)` (iOS 17) | auto-advance timer | none | missing | add `MorphPageControlTimer` (controller: `duration`, `durationForPage`, `resetsToInitialPageAfterEnd`, `isRunning`, `pause()`, `resume()`, `shouldAdvanceToPage`) |
| `UIPageControlTimerProgress.setDuration(_:forPage:)` / `durationForPage` | per-page duration | none | missing | in the timer controller |
| `UIPageControlTimerProgress.resetsToInitialPageAfterEnd` / `running` / `pauseTimer` / `resumeTimer` | loop and control | none | missing | in the timer controller |
| `defersCurrentPageDisplay` / `updateCurrentPageDisplay` | deprecated | - | - | skip (deprecated) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `TabView` + `.tabViewStyle(.page)` (iOS 14) | pager with built-in dots | none (app wires `PageView` + `MorphPageControl`) | no linked pager | add optional `controller: PageController?` on `MorphPageControl` (page follows the scroll, taps animate the pager); low-med |
| `PageTabViewStyle.IndexDisplayMode.automatic / .always / .never` | show dots | app decides | - | skip (widget presence) |
| `PageIndexViewStyle.BackgroundDisplayMode.automatic / .interactive / .always / .never` (iOS 14) | platter | `MorphPageControlBackground` | SwiftUI `.interactive` = UIKit `.automatic`, `.always` = `.prominent`, `.never` = `.minimal` | keep UIKit names; note the mapping in dartdoc |

## Not relevant for Flutter
- `UIAppearance` selectors on the tint colors (theme / `MorphWidgetsTheme` covers it).
- Target-action, `NSCoding`, tvOS focus behaviour.
- Accessibility adjustable trait: Flutter `Semantics` (morph: `semanticLabel`, `semanticValueFormatter`).

## morph-only API
- `MorphPageControl.semanticLabel`, `semanticValueFormatter` - keep (Semantics idiom).
- `MorphPageControlStyle.platterColor`, `platterIndicatorColor` - keep (UIKit has no public platter color).
- `MorphPageControlMotion`, `MorphPageControlTuning` - keep (measured motion).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | `hidesForSinglePage` | med (dynamic page counts) | S | add bool |
| 2 | widget-level dot colors (`pageIndicatorTintColor`, `currentPageIndicatorTintColor`) | med (dots over photos / onboarding) | S | add two `Color?` params |
| 3 | custom indicator images per page / current page | med (Weather-style location dot, onboarding icons) | M | add `indicatorBuilder` |
| 4 | timer progress (`UIPageControlTimerProgress`) | low-med (stories, carousels) | M (pc-timer fixture exists) | add `MorphPageControlTimer` |
| 5 | `direction` incl. vertical | low-med (vertical pagers) | M (layout + scrub axis) | add `MorphPageControlDirection` |
| 6 | link to a `PageController` | low-med (convenience) | S-M | add optional `controller` |
| 7 | `allowsContinuousInteraction` | low | S | add bool |
| 8 | `sizeForNumberOfPages` | low | S | add static helper |

## Breaking changes before 1.0
- `MorphPageControlStyle.indicatorColor` / `currentIndicatorColor` -> `pageIndicatorColor` /
  `currentPageIndicatorColor` (UIKit's property names minus `Tint`), matching the widget-level overrides to add.
- Optional: `MorphPageControl.background` -> `backgroundStyle` and `MorphPageControlBackground` ->
  `MorphPageControlBackgroundStyle` (UIKit property and enum name). Cheap now; decide with the family-wide
  `*Style` = color-table convention (the enum would then end in `Style` without being a color table).
- `count` / `page`: keep (no change proposed).
