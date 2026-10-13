# Sheets - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UISheetPresentationController` (+ `.Detent`, `.Detent.Identifier`, `.Placement`, delegate),
`UIViewController.modalPresentationStyle` / `isModalInPresentation` / `preferredTransition`,
`UIAdaptivePresentationControllerDelegate`, `UIPopoverPresentationController.adaptiveSheetPresentationController`,
`UIViewControllerTransition.zoom` + `UIZoomTransitionOptions`; SwiftUI `sheet`, `fullScreenCover`,
`presentationDetents`, `presentationDragIndicator`, `presentationBackgroundInteraction`,
`presentationCornerRadius`, `presentationContentInteraction`, `presentationCompactAdaptation`,
`presentationSizing`, `presentationPlacement`, `presentationBackground`, `interactiveDismissDisabled`,
`navigationTransition(.zoom)`. morph: `presentMorphSheet`, `MorphSheetRoute`, `MorphSheet`
(`of` / `maybeOf` / `scrollControllerOf` / `detent` / `detents` / `animateTo`), `MorphSheetStyle`,
`MorphSheetDetent`, `MorphSheetMotion`, `MorphSheetTuning`, `MorphZoomMotion`, `MorphZoomTuning`;
engine `showMorphSheet`, `showMorphDialog`, `showMorphRoute`, `MorphPageRoute`, `MorphTargetSpec`
(`.sheet` / `.dialog` / `.popover` / `.fullscreen` / `.measured` / `.vessel`). Passport: [../sheets.md](../sheets.md).

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UISheetPresentationController.detents` (iOS 15) | heights the sheet rests at | `presentMorphSheet(detents:)`, `MorphSheetRoute.detents` | none; default `[large]` matches | keep |
| `Detent.medium()` (iOS 15) | half-height detent | `MorphSheetDetent.medium` (0.56 of maximum, measured) | none | keep |
| `Detent.large()` (iOS 15) | full-height, docked | `MorphSheetDetent.large` | none | keep |
| `Detent.custom(identifier:resolver:)` (iOS 16) | height from a resolver given `maximumDetentValue` | `MorphSheetDetent.height(v)`, `.fraction(f)` | no resolver form (a height that depends on the maximum or on traits other than a fraction) | add `MorphSheetDetent.custom(double Function(double maximum))` |
| `Detent.Identifier` / `.identifier` (iOS 15/16) | name of a detent | `MorphSheetDetent` value equality (`==`) | identity is the value; two custom detents with equal value are one | keep (Dart value equality is the idiom) |
| `Detent.resolvedValue(in:)` (iOS 16) | the detent's height | `MorphSheetDetent.resolve(maximum)` | none | keep |
| `UISheetPresentationControllerDetentInactive` (iOS 16) | resolver returns "detent off" | none | can not disable a detent conditionally | skip (filter the list in Dart) |
| `Detent.backgroundEffect` (iOS 26.1, NEW) | per-detent background material | none (`MorphSheetStyle.floatingColor` / `dockedColor` by docking) | no per-detent look | skip (low need; floating/docked covers the system look) |
| `selectedDetentIdentifier` get (iOS 15) | current detent | `MorphSheet.of(context).detent` | readable only from inside the sheet | add `onDetentChanged` (see delegate row) |
| `selectedDetentIdentifier` set + `animateChanges(_:)` (iOS 15) | move to a detent animated | `MorphSheet.animateTo(detent)` | none | keep |
| `largestUndimmedDetentIdentifier` (iOS 15) | detents up to it do not dim, page stays live | `largestUndimmedDetent` | none | keep |
| `prefersGrabberVisible` (iOS 15) | show grabber | `grabberVisible` | none | keep |
| `preferredCornerRadius` (iOS 15) | corner radius of the sheet | none (`MorphSheetTuning.topRadius` 38 fixed) | not configurable | add `cornerRadius` to `presentMorphSheet` / `MorphSheetRoute` |
| `prefersScrollingExpandsWhenScrolledToEdge` (iOS 15) | scroll up expands sheet before scrolling | always on via `MorphSheet.scrollControllerOf` | can not turn it off | add `scrollingExpandsSheet = true` |
| `prefersEdgeAttachedInCompactHeight` (iOS 15) | landscape phone: attach to bottom edge | none | landscape layout not specified | add later with landscape measurement (low) |
| `widthFollowsPreferredContentSizeWhenEdgeAttached` (iOS 15) | width from content when edge attached | none | | skip until edge-attached lands |
| `prefersPageSizing` (iOS 17) | page vs form width on wide screens | none | wide-screen sizing absent | add with `MorphSheetSizing` (see SwiftUI `presentationSizing`) |
| `preferredPlacement` `.automatic/.leading/.center/.trailing` (iOS 27, NEW) | where a sheet sits on wide screens | none | | add `MorphSheetPlacement` enum together with wide-screen sizing (low) |
| `sourceView` (iOS 15) | anchor for wide-screen popover-like sheet | `from` (zoom source id) is a different concept | | skip until wide layouts |
| `invalidateDetents()` (iOS 16) | re-resolve custom detents | relayout re-resolves heights; `detents` list fixed for the route | can not swap the detent list while open | add `MorphSheet.setDetents(list)` (low) |
| `delegate.sheetPresentationControllerDidChangeSelectedDetentIdentifier` (iOS 15) | detent changed by the user | internal `MorphSheetMotion.onDetentChanged`, not public on the route | app outside the sheet can not observe the detent | add `onDetentChanged: ValueChanged<MorphSheetDetent>?` to `presentMorphSheet` |
| `UIViewController.isModalInPresentation` (iOS 13) | block interactive dismissal | `dismissible: false` | none (also blocks tap on dimming, as UIKit) | keep |
| `presentationControllerShouldDismiss` (iOS 13) | veto a swipe/tap dismissal at the moment | none (static `dismissible`, `PopScope` covers back only) | can not decide per attempt | add `shouldDismiss: bool Function()?` or honour `PopScope.canPop` for drag/tap too |
| `presentationControllerDidAttemptToDismiss` (iOS 13) | user tried while modal (show "discard?") | none | the common "unsaved changes" pattern is impossible | add `onDismissAttempt: VoidCallback?` (fires when `dismissible` false / veto) |
| `presentationControllerWillDismiss` / `DidDismiss` (iOS 13) | dismissal lifecycle | the returned `Future<T?>` completes; `Navigator` observers | no will-dismiss hook | keep (Future idiom); optional `onDismiss` low |
| `modalPresentationStyle .pageSheet` / `.automatic` (iOS 13) | sheet | `presentMorphSheet` | none | keep |
| `modalPresentationStyle .formSheet` (iOS 3.2; auto default since 18) | centered card on wide screens | none (phone geometry only) | wide-screen form sheet absent | add with sizing (`MorphSheetSizing.form`) |
| `modalPresentationStyle .fullScreen` / `.overFullScreen` (legacy) | cover the whole screen, no drag | engine `showMorphRoute(target: MorphTargetSpec.fullscreen())` (container transform), no cover-vertical slide | no UIKit cover-vertical full-screen presentation | add `presentMorphFullScreen` (slide up, `coverVertical`, measured) |
| `modalPresentationStyle .popover` + `UIPopoverPresentationController` (iOS 8) | content in an arrowed popover | engine `MorphTargetSpec.popover` (no arrow); action-sheet popover only in alerts | see [alerts.md](alerts.md) | see alerts |
| `UIPopoverPresentationController.adaptiveSheetPresentationController` (iOS 15) | the sheet a popover adapts to in compact width | none | | skip until a general popover exists |
| `preferredTransition = .zoom(options:sourceViewProvider:)` (iOS 18) | sheet zooms out of a source | `presentMorphSheet(from: tagId, zoom:)` | none | keep |
| `UIZoomTransitionOptions.interactiveDismissShouldBegin` (iOS 18) | veto the scrub-to-dismiss | none (scrub always) | | add with `shouldDismiss` (same hook) |
| `UIZoomTransitionOptions.alignmentRectProvider` (iOS 18) | part of the content the source aligns to | none | | skip (low) |
| `UIZoomTransitionOptions.dimmingColor` / `dimmingVisualEffect` (iOS 18) | dimming look | `MorphSheetStyle.dimmingColor` (no blur) | blur dimming absent | keep (blur dimming low) |
| `.coverVertical` / `.crossDissolve` / `.flipHorizontal` / `.partialCurl` (iOS 18) | other modal transitions | none (crossDissolve: engine `showMorph` fade variants) | | skip except coverVertical (full-screen row) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `sheet(isPresented:onDismiss:content:)`, `sheet(item:)` (iOS 13) | declarative presentation | imperative `presentMorphSheet` | Flutter idiom is imperative `show*`; fine | keep |
| `fullScreenCover(isPresented:/item:)` (iOS 14) | full screen | none (see UIKit `.fullScreen` row) | | add `presentMorphFullScreen` |
| `presentationDetents(_:selection:)` (iOS 16) | detents + two-way selection | `detents` + `MorphSheet.animateTo` | no binding from outside | add `onDetentChanged` (outbound) + a `MorphSheetController` (inbound) if needed |
| `PresentationDetent .medium/.large/.fraction/.height/.custom` (iOS 16) | detent kinds | `MorphSheetDetent.medium/.large/.fraction/.height` | names match SwiftUI; `.custom` missing | add `.custom` (same as UIKit custom row) |
| `presentationDragIndicator(.visible/.hidden/.automatic)` (iOS 16) | grabber | `grabberVisible: bool` | no `automatic` (SwiftUI shows it with >1 detent) | keep bool; document that UIKit default is hidden |
| `presentationBackgroundInteraction(.enabled(upThrough:))` (iOS 16.4) | interact with page behind | `largestUndimmedDetent` | same concept, UIKit name | keep |
| `presentationCornerRadius` (iOS 16.4) | corner radius | none | same as `preferredCornerRadius` | add `cornerRadius` |
| `presentationContentInteraction(.scrolls/.resizes/.automatic)` (iOS 16.4) | swipe on content scrolls or resizes first | fixed `.resizes` via `scrollControllerOf` | same as `prefersScrollingExpands...` | add `scrollingExpandsSheet` |
| `presentationCompactAdaptation` (iOS 16.4) | popover/sheet/fullScreenCover in compact | none | | skip (phone-only today) |
| `presentationSizing(.automatic/.form/.page/.fitted)` (iOS 18) | width/height policy; `.fitted` = height from content | none for the widget sheet; engine `showMorphSheet(fitContent:)` | a content-sized sheet is a common need (`.fitted`) | add `MorphSheetDetent.fitted` or `presentMorphSheet(fitContent:)` |
| `presentationPlacement(.automatic/.leading/.center/.trailing)` (iOS 27, NEW) | wide-screen placement | none | | add with UIKit `preferredPlacement` (low) |
| `presentationBackground(_ style:)` / `(alignment:content:)` (iOS 16.4) | custom background | `MorphSheetStyle` colors | no widget background | keep (style colors); widget background low |
| `interactiveDismissDisabled(_:)` (iOS 15) | block swipe dismissal | `dismissible: false` | none | keep |
| `navigationTransition(.zoom(sourceID:in:))` + `matchedTransitionSource` (iOS 18) | zoom from a source | `presentMorphSheet(from:)` + `MorphTag` | `MorphTag` id plays `matchedTransitionSource` | keep |
| `@Environment(\.dismiss)` (iOS 15) | close from inside | `Navigator.pop(context, result)` | none | keep |

## Not relevant for Flutter
- `UIPresentationController` subclassing hooks (`presentationTransitionWillBegin`, container view frames): the route is the Flutter seam.
- `UISheetPresentationControllerDetentResolutionContext.containerTraitCollection`: Flutter reads `MediaQuery` in the resolver.
- visionOS / tvOS / Mac Catalyst availability variants; `UIModalPresentationBlurOverFullScreen` (tvOS).
- `UIAdaptivePresentationControllerDelegate.adaptivePresentationStyle...`, `viewControllerForAdaptivePresentationStyle`: size-class adaptation, Flutter apps branch on `MediaQuery`.
- `modalPresentationStyle .currentContext / .overCurrentContext / .custom`: nested navigators and `useRootNavigator` cover it.
- `presentationPreventsAppTermination` (macOS scene behaviour).

## morph-only API
- `presentMorphSheet(useRootNavigator:)` and `semanticLabel`: Flutter routing and Semantics - keep.
- `MorphSheetMotion`, `MorphSheetTuning`, `MorphZoomMotion`, `MorphZoomTuning`: pure measured motion, usable without the widget - keep.
- `MorphSheet.scrollControllerOf`: Flutter needs an explicit controller where UIKit finds the scroll view - keep.
- Engine `showMorphSheet` / `showMorphDialog` / `showMorph` / `showMorphRoute` / `MorphTargetSpec`: container-transform flights, Material-themed (BottomSheetTheme / DialogTheme), no UIKit twin - keep, but see naming in breaking changes.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | Dismiss veto + attempted-dismiss callback (`presentationControllerShouldDismiss` / `DidAttemptToDismiss`, `interactiveDismissShouldBegin`) | high (unsaved-changes sheets) | M | add `onDismissAttempt` and honour `PopScope.canPop` (or `shouldDismiss`) for drag, tap on dimming and zoom scrub |
| 2 | Detent change observable from the presenter (`didChangeSelectedDetentIdentifier`, `presentationDetents(selection:)`) | high | S | add `onDetentChanged: ValueChanged<MorphSheetDetent>?` (motion already has the hook) |
| 3 | Content-fitted height (`presentationSizing(.fitted)`, custom resolver) | high | M | add `MorphSheetDetent.custom(resolver)` (S) and a fitted detent measured from content (M) |
| 4 | Full-screen cover (`.fullScreen`, `fullScreenCover`, `coverVertical`) | med | M | add `presentMorphFullScreen` with a measured cover-vertical slide |
| 5 | `preferredCornerRadius` / `presentationCornerRadius` | med | S | add `cornerRadius` |
| 6 | `prefersScrollingExpandsWhenScrolledToEdge = false` / `.scrolls` | med | S | add `scrollingExpandsSheet` |
| 7 | Replace detents while open (`invalidateDetents`, changing `detents` with `animateChanges`) | low | S | add `MorphSheet.setDetents` |
| 8 | Wide-screen sizing and placement (`formSheet`, `prefersPageSizing`, `presentationSizing(.form/.page)`, `preferredPlacement` 27) | low (phones first) | L | add `MorphSheetSizing` + `MorphSheetPlacement` after an iPad measurement |
| 9 | Landscape edge attachment (`prefersEdgeAttachedInCompactHeight`, `widthFollows...`) | low | M | measure landscape, then add |
| 10 | Per-detent `backgroundEffect` (26.1), widget `presentationBackground` | low | S | skip for now |

## Breaking changes before 1.0
- Name clash: engine `showMorphSheet` (returns `MorphFlight`, Material-themed container transform) vs widget `presentMorphSheet` (returns `Future<T?>`, the UIKit sheet). Flutter users expect `showXxx` -> `Future`. Proposal: rename `presentMorphSheet` -> `showMorphSheet` and the engine function `showMorphSheet` -> `showMorphSheetFlight` (same for `showMorphDialog` -> `showMorphDialogFlight` for symmetry), or at minimum cross-link them in dartdoc. Owner decision.
- `presentMorphSheet(from:)` (MorphTag id) vs `showMorphActionSheet(anchor:/anchorRect:)` (context/rect) name the source differently; see [alerts.md](alerts.md) for a unified `from` proposal.
- `useRootNavigator`: `presentMorphSheet` takes `bool?` (null = presentation navigator) while `showMorphAlert` / `showMorphActionSheet` take `bool = true`; align all to `bool?` with the presentation-navigator default.
- None of the existing parameter names need to change otherwise (`detents`, `initialDetent`, `largestUndimmedDetent`, `grabberVisible`, `dismissible` all map 1:1).
