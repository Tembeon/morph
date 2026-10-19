# Sheets and presentations - API parity (UIKit / SwiftUI iOS 27.1 vs morph)

Native: `UISheetPresentationController` (+ `.Detent`, `.Detent.Identifier`, `.Placement`, delegate),
`UIPresentationController`, `UIAdaptivePresentationControllerDelegate`,
`UIViewController.modalPresentationStyle` / `modalTransitionStyle` / `isModalInPresentation` /
`preferredTransition`, `UIViewControllerTransition.zoom` + `UIZoomTransitionOptions`; SwiftUI `sheet`,
`fullScreenCover`, `presentationDetents`, `presentationDragIndicator`, `presentationBackgroundInteraction`,
`presentationCornerRadius`, `presentationContentInteraction`, `presentationSizing`,
`presentationPlacement`, `presentationBackground`, `interactiveDismissDisabled`,
`navigationTransition(.zoom)`. Catalog families: `sheet`, `presentation`.

morph (public, `lib/morph.dart`): `showMorphSheet`, `MorphSheetRoute`, `MorphSheet` (`of` / `maybeOf` /
`scrollControllerOf` / `detent` / `detents` / `animateTo`), `MorphSheetDetent` (`medium` / `large` /
`fraction` / `height` / `custom` / `fitted`, `resolve`), `MorphSheetAppearance`, `MorphSource` +
`MorphSourceLink` (zoom source). Internal (tests and example only): `MorphSheetMotion`,
`MorphSheetTuning`, `MorphZoomMotion`, `MorphZoomTuning`, `MorphMotionRouteMixin`. Passport:
[../sheets.md](../sheets.md).

SDK 27.1 adds nothing to the sheet, presentation-controller or zoom headers, nor to the SwiftUI
presentation modifiers. Its new UIViewController API (vertical bar behaviour, arrangements) belongs to
other families.

API count. sheet: 41 applicable, 19 covered, 9 partial, 13 gaps. presentation: 15 applicable, 6
covered, 3 partial, 6 gaps.

## UIKit - sheet
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UISheetPresentationController.detents` (iOS 15) | heights the sheet rests at | `showMorphSheet(detents:)`, `MorphSheetRoute.detents` | none; default `[large]` matches | keep |
| `Detent.medium()` (15) | half-height detent | `MorphSheetDetent.medium` (0.56 of the maximum) | none | keep |
| `Detent.large()` (15) | full height, docked | `MorphSheetDetent.large` | none | keep |
| `Detent.custom(identifier:resolver:)` (16) | height from a resolver given `maximumDetentValue` | `MorphSheetDetent.custom(resolver, identifier:)`; `.height(v)`, `.fraction(f)` | none (traits come from `MediaQuery`) | keep |
| `Detent.identifier`, `Detent.Identifier` (15/16) | name of a detent | `identifier:` on custom detents, value equality otherwise | none | keep |
| `Detent.resolvedValue(in:)` (16) | the detent's height | `MorphSheetDetent.resolve(maximum, fittedHeight:)` | none | keep |
| `UISheetPresentationControllerDetentInactive` (16) | a resolver turns its detent off | none | gap | skip (filter the list in Dart) |
| `Detent.backgroundEffect` (26.1) | per-detent background material | none (glass floating, fill docked) | gap | skip (low) |
| `selectedDetentIdentifier` get (15) | current detent | `MorphSheet.of(context).detent` inside; `onDetentChanged` outside | partial: the presenter cannot read it at will | add a controller only if apps ask |
| `selectedDetentIdentifier` set + `animateChanges(_:)` (15) | move to a detent, animated | `MorphSheet.of(context).animateTo(detent)` | partial: only from inside the sheet | same controller |
| `largestUndimmedDetentIdentifier` (15) | detents up to it do not dim; the page stays live | `largestUndimmedDetent` | none | keep |
| `prefersGrabberVisible` (15) | show the grabber | `grabberVisible` (default false, as UIKit) | none | keep |
| `preferredCornerRadius` (15) | corner radius, front of the stack only | none (top 38, measured) | gap | add `cornerRadius` |
| `prefersScrollingExpandsWhenScrolledToEdge` (15) | a scroll at its top expands the sheet first | `scrollingExpandsSheet` | none | keep |
| `prefersEdgeAttachedInCompactHeight` (15) | landscape phone: attach to the bottom edge | none | gap | measure landscape first |
| `widthFollowsPreferredContentSizeWhenEdgeAttached` (15) | content width when edge attached | none | gap | with edge attachment |
| `prefersPageSizing` (17) | page vs form width on wide screens | none | gap | `MorphSheetSizing` after an iPad measurement |
| `preferredPlacement` automatic / leading / center / trailing (27.0) | wide-screen placement | none | gap | with sizing |
| `sourceView` (15) | wide-screen sheet centered over a view | none (`from:` is the zoom source) | gap | with wide layouts |
| `invalidateDetents()` (16) | re-resolve custom detents | every relayout (size, keyboard) re-runs the resolvers | partial: no call after app state changes; the list is fixed per route | add `MorphSheet.invalidateDetents` / `setDetents` (low) |
| delegate `sheetPresentationControllerDidChangeSelectedDetentIdentifier` (15) | the user changed the detent | `onDetentChanged` | partial: morph also reports `animateTo`; the 27.1 header says UIKit does not call it for a programmatic change | decide before 1.0 (see breaking changes) |
| `preferredTransition = .zoom(options:sourceViewProvider:)` (18) | the sheet zooms out of a source | `showMorphSheet(from: MorphSourceLink)` + `MorphSource(link:)` | none | keep |
| `.zoom(options:sourceBarButtonItemProvider:)` (26) | zoom out of a bar button | none (bar buttons take no source link) | gap | `MorphBarButton` takes a `MorphSourceLink` (navigation.md) |
| `UIZoomTransitionOptions.interactiveDismissShouldBegin` (18) | veto the scrub | `dismissible: false` or a blocking `PopScope` stops the scrub | partial: no per-gesture veto with location and velocity | skip |
| `UIZoomTransitionOptions.alignmentRectProvider` (18) | part of the content the source aligns to | none | gap | skip (low) |
| `UIZoomTransitionOptions.dimmingColor` (18) | zoom dimming color | `MorphSheetAppearance.dimmingColor` | none | keep |
| `UIZoomTransitionOptions.dimmingVisualEffect` (18) | blurred dimming | none | gap | skip (low) |

## SwiftUI - sheet
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `sheet(isPresented:onDismiss:content:)`, `sheet(item:onDismiss:content:)` (iOS 13) | declarative sheet | `showMorphSheet` returning `Future<T?>` | none (Flutter presents imperatively) | keep |
| `presentationDetents(_:)` (16) | detents | `detents` | none | keep |
| `presentationDetents(_:selection:)` (16) | two-way detent binding | `onDetentChanged` out, `animateTo` in (inside only) | partial | as the UIKit rows |
| `PresentationDetent .medium/.large/.fraction/.height/.custom` (16) | detent kinds | `MorphSheetDetent`, same names | none | keep |
| `presentationDragIndicator(.automatic/.visible/.hidden)` (16) | grabber | `grabberVisible: bool` | partial: no `automatic` | keep the bool |
| `presentationBackgroundInteraction(.automatic/.disabled/.enabled(upThrough:))` (16.4) | use the page behind | `largestUndimmedDetent` | none | keep |
| `presentationCornerRadius` (16.4) | corner radius | none | gap | `cornerRadius` |
| `presentationContentInteraction(.automatic/.resizes/.scrolls)` (16.4) | a swipe resizes or scrolls first | `scrollingExpandsSheet` | none | keep |
| `presentationSizing(.automatic/.form/.page/.fitted)` (18) | size policy | `MorphSheetDetent.fitted` (height from content) | partial: phone heights only, no form or page width | with wide-screen sizing |
| `presentationPlacement` (27.0) | wide-screen placement | none | gap | with `preferredPlacement` |
| `presentationBackground(_:)`, `(alignment:content:)` (16.4) | custom background | `MorphSheetAppearance` colors | partial: no widget background | low |
| `interactiveDismissDisabled(_:)` (15) | block the swipe | `dismissible: false`, a blocking `PopScope` | none | keep |
| `navigationTransition(.zoom(sourceID:in:))` + `matchedTransitionSource` (18) | zoom from a source | `from:` + `MorphSource(link:)` | none | keep |
| `@Environment(\.dismiss)` (15) | close from inside | `Navigator.pop(context, result)` | none | keep |

## UIKit and SwiftUI - presentation
| API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `present(_:animated:completion:)` | present modally | `showMorphSheet` / `showMorphAlert` / `showMorphActionSheet`, `Navigator.push(MorphSheetRoute(...))` | none | keep |
| `dismiss(animated:completion:)` | dismiss | `Navigator.pop` | none | keep |
| `modalPresentationStyle .automatic / .pageSheet` (13 / 3.2) | sheet | `showMorphSheet` | none | keep |
| `modalPresentationStyle .formSheet` | centered card on wide screens | none | gap | with sizing |
| `modalPresentationStyle .fullScreen` | cover without drag | none (a zoomed `MorphNavigationRoute` is a push) | gap | `showMorphFullScreen`, cover-vertical slide measured first |
| `modalPresentationStyle .overFullScreen` (8) | cover over a live page | none | gap | same function, not opaque |
| `.currentContext` / `.overCurrentContext` / `definesPresentationContext` | present inside a container | `useRootNavigator: false` (nearest navigator); a `MorphNavigationStack` page presents above the stack's bars | partial: no "over current context" without a navigator | keep |
| `modalTransitionStyle`, `UIViewControllerTransition.coverVertical/crossDissolve/flipHorizontal/partialCurl` (18) | non-sheet transitions | none | gap | cover-vertical with the full-screen cover; skip the rest |
| `isModalInPresentation` (13) | block interactive dismissal | `dismissible: false`; a `PopScope` that cannot pop | none | keep |
| `presentationControllerShouldDismiss(_:)` (13) | veto per attempt | `PopScope.canPop`, read at the attempt | none | keep |
| `presentationControllerDidAttemptToDismiss(_:)` (13) | refused attempt | `onDismissAttempt` (sheets) | none | keep |
| `presentationControllerWillDismiss(_:)` (13) | dismissal starts | `PopScope.onPopInvokedWithResult`, `NavigatorObserver.didPop` | partial: no presenter-side hook on the call | low |
| `presentationControllerDidDismiss(_:)` (13) | dismissal finished | the returned `Future` | partial: it completes when the dismissal starts; UIKit calls this after it ends | document; `onDismissed` if asked |
| `UIPresentationController.backgroundEffect` (26.1) | background effect of a presentation | none | gap | skip (low) |
| SwiftUI `fullScreenCover(isPresented:/item:)` (14) | full screen | none | gap | `showMorphFullScreen` |

## Not relevant for Flutter
- `UIPresentationController` subclass hooks (`presentationTransitionWillBegin`, `containerViewWillLayoutSubviews`, `frameOfPresentedViewInContainerView`), `.custom` style and transitioning delegates: a Flutter route is the seam.
- `DetentResolutionContext.containerTraitCollection`: the resolver reads `MediaQuery`.
- `adaptivePresentationStyle(for:)`, `viewControllerForAdaptivePresentationStyle`, `willPresentWithAdaptiveStyle`: size-class adaptation; apps branch on `MediaQuery`.
- `presentingViewController` / `presentedViewController`: the navigator's route list.
- `modalPresentationCapturesStatusBarAppearance`: `SystemUiOverlayStyle`.
- `UIModalPresentationBlurOverFullScreen` (tvOS), `presentationPreventsAppTermination` (macOS), `dismissalConfirmationDialog` (unavailable on iOS), `overrideTraitCollection` (deprecated) / `traitOverrides`.

## morph-only API
- `useRootNavigator` (null: the presentation navigator, so a sheet from a `MorphNavigationStack` page covers its bars) and `semanticLabel`.
- `MorphSheet.scrollControllerOf`: Flutter needs an explicit controller where UIKit finds the scroll view.
- `MorphSheetDetent.fitted`: the content height as a detent; no UIKit detent, nearest is SwiftUI `presentationSizing(.fitted)`.
- `MorphSheetRoute`: the route itself, for `Navigator.push` and Navigator 2 pages.
- Android predictive back and Escape close the top sheet (predictive_back_test, sheet_escape_test).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | Full-screen cover (`.fullScreen`, `.overFullScreen`, `fullScreenCover`, cover-vertical) | med | M, measure first | `showMorphFullScreen` |
| 2 | `onDetentChanged` reports programmatic changes; UIKit does not | med | S | match UIKit or document the difference |
| 3 | `preferredCornerRadius` / `presentationCornerRadius` | med | S, measure the floating bottom and the stack rule first | add `cornerRadius` |
| 4 | Presenter-side detent read and set (`selectedDetentIdentifier`, `selection:` binding) | low-med | S | a sheet controller |
| 5 | Zoom from a bar button (`sourceBarButtonItemProvider`) | low-med | S-M | source link on `MorphBarButton` |
| 6 | Re-resolve or replace detents while open (`invalidateDetents`) | low | S | `MorphSheet.invalidateDetents` / `setDetents` |
| 7 | Wide-screen sizing and placement (`formSheet`, `prefersPageSizing`, `presentationSizing(.form/.page)`, `preferredPlacement`) | low (phones first) | L, measure first | `MorphSheetSizing` + `MorphSheetPlacement` |
| 8 | Landscape edge attachment (`prefersEdgeAttachedInCompactHeight`, `widthFollows...`) | low | M, measure first | add after landscape capture |
| 9 | `backgroundEffect` (26.1, detent and presentation), widget `presentationBackground`, `dimmingVisualEffect` | low | S | skip for now |

Done: `onDetentChanged`; `onDismissAttempt` with `PopScope` holding the drag, the tap and the zoom
scrub; `MorphSheetDetent.custom` and `.fitted`; `scrollingExpandsSheet`; `showMorphSheet` is the one
sheet entry point and returns a `Future` (the engine sheet flight is gone); `useRootNavigator` is
`bool?` on every presenter.

## Breaking changes before 1.0
- `onDetentChanged` semantics (owner decision): UIKit reports user-driven changes only, morph also
  reports `MorphSheet.animateTo`. Matching UIKit changes a public callback's behaviour.
- `useRootNavigator: null` means the root navigator for alerts and the presentation navigator for
  sheets. Both are documented; keep unless the owner wants one default.
- The source is `from: MorphSourceLink` on sheets and `anchor` / `anchorRect` on action sheets; see
  [alerts.md](alerts.md).

## Behaviour fidelity

### sheet
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | read | this page, 27.1 headers | 13 gaps, none high need |
| layout | replayed | passport "Spec - motion", "Spec - corners"; test/sheet_test.dart (edges vs `ios27{,-device}/sheet/*.jsonl`, < 2.5 pt rms); test/sheet_native_test.dart (corner 58.44 inline) | grabber geometry has no source (optics) |
| states | replayed | test/sheet_test.dart (dimming < 0.01 rms incl. sheet-undim); test/sheet_native_test.dart "background" (flip alphas inline, 0.035) | background flip and corners from the simulator; device confirms the flip point only |
| transitions | replayed | test/sheet_test.dart; test/sheet_zoom_test.dart (`ios27-device/zoom/zoom.json`, `scrub.json`) | 8 pt present drift; Reduce Motion (accessibility) |
| boundaries | replayed | test/sheet_native_test.dart (stretch 100 / 78, refused pull 200, device held samples); test/sheet_drag_test.dart (dismiss outcomes) | fd-1000 and lfd-800 sit on the decision boundary and are left out |
| configuration | replayed | test/sheet_test.dart (l, ml, sml, undim); test/sheet_widget_test.dart "keyboard and scrolling" (`scrollingExpandsSheet` false, inline) | custom and fitted detents ride the measured springs, no native twin for fitted |
| events | read | `dismissAttemptShare` 0.25 (read from UIKit, notes private); test/sheet_api_test.dart | no recording of the attempt callback; `onDetentChanged` fires on `animateTo`, UIKit's does not |
| input | measured | test/sheet_drag_test.dart (16 simulator + 26 device drags, outcomes exact, stretch < 0.0075 rms) | the replay feeds the device's 12 pt slop; the widget's vertical drag starts at Flutter's hit slop, kTouchSlop 18 pt unless the platform reports one (sheet.dart:783, 1071), and no widget test replays a drag start; second pointer unspecified; native immediate zoom dismissals |
| mutation | approx | test/sheet_widget_test.dart (keyboard rise 763.68 / 778 inline, sim + device) | keyboard motion on the sheet spring, UIKit's curve unmeasured (declared in the passport); three-detent keyboard choice assumed largest; detents fixed per route |
| accessibility | missing | test/sheet_widget_test.dart (named route) | Reduce Motion: UIKit reads it (notes private), effect unmeasured, morph ignores it; grabber accessibility action absent |
| optics | unbacked | passport "Spec - background", "Spec - corners" | grabber 60 x 4 at 8 pt (sheet_motion.dart:140, 143) and the flat floating color (sheet.dart:32, 63) have no source |
| platform | missing | test/sheet_widget_test.dart (RTL, dark) | 402 x 874 and 440 x 956 only; landscape, iPad sizing and placement unmeasured |
| performance | measured | tool/ios_reference/spec/lifecycle.md (rows 8, sheet drag); test/lifecycle_counts_test.dart; docs/performance.md (Pixel 6a 0.971 / 6.002 GPU Mcycles, iPhone raster p95 3.08) | content laid out every frame of a detent spring (native once) |

### presentation
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | this page | full-screen cover, form sheet, cover-vertical / cross-dissolve |
| layout | missing | - | stacked sheets: UIKit lays adjacent sheets out as a stack (27.1 `animateChanges` header); morph draws each sheet alone; unmeasured |
| states | unbacked | test/motion_route_lifecycle_test.dart | the route status follows the page's motion; no native recording of UIKit's transition phases |
| transitions | missing | - | no full-screen or cross-dissolve transition; sheet-over-sheet push-back unmeasured |
| boundaries | n/a | - | each presented family holds its own |
| configuration | unbacked | test/predictive_back_test.dart, test/motion_route_ownership_test.dart | a sheet from a stack page covers the bars, as UIKit documents; no capture |
| events | approx | sheets.md "API gaps"; test/sheet_api_test.dart, test/alert_return_test.dart | the Future completes when the dismissal starts (declared in `showMorphAlert`); no will-dismiss hook |
| input | unbacked | test/sheet_escape_test.dart, test/predictive_back_test.dart | Escape closes a dismissible sheet without a native source; predictive back has no iOS twin |
| mutation | unbacked | test/motion_route_ownership_test.dart, test/presentation_cycles_test.dart | covered and replaced routes follow Flutter's Navigator, not a native capture |
| accessibility | missing | - | Reduce Motion "prefer cross-fade" turns modal transitions into fades (notes private); morph ignores it |
| optics | missing | - | `backgroundEffect`, `dimmingVisualEffect`, stacked dimming |
| platform | missing | - | wide-screen styles (form sheet, page sizing) |
| performance | measured | tool/ios_reference/spec/lifecycle.md; test/presentation_cycles_test.dart (nothing left behind) | - |
