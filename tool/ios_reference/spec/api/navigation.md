# Navigation - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UINavigationController`, `UIViewController.navigationItem` / `.preferredTransition`,
`UIViewController.Transition` (`.zoom`, `.coverVertical`, `.crossDissolve`, `.flipHorizontal`,
`.partialCurl`), `UIViewController.Transition.ZoomOptions` (`UIZoomTransitionOptions`); SwiftUI
`NavigationStack(path:)`, `NavigationPath`, `navigationDestination`, `NavigationLink`,
`navigationTransition(.automatic/.zoom(sourceID:in:)/.crossFade)`, `matchedTransitionSource(id:in:)`,
`navigationBarBackButtonHidden`, `toolbarVisibility`, `NavigationSplitView`. morph:
`MorphNavigationStack`, `MorphNavigationScaffold`, `MorphNavigationConfig`, `MorphNavigationRoute`,
`pushMorphZoom`, `MorphNavigationTransition`, `MorphNavigationTitleMotion`, `MorphPushZoomMotion`,
`MorphPushZoomTuning`, `MorphZoomMotion`, `MorphZoomTuning` (sheet zoom, `presentMorphSheet(from:)`),
engine `MorphPageRoute`, `showMorphRoute` (`lib/foundation.dart`). Passport:
[../navigation-pages.md](../navigation-pages.md) (bars: [../bars.md](../bars.md)).

Sources: iPhoneOS27.0.sdk `UINavigationController.h`, `UIViewController.h`,
`UIViewControllerTransition.h`, `UIZoomTransitionOptions.h`, UIKit and SwiftUI `.swiftinterface`.
LG = new with Liquid Glass (iOS 26/27).

## How morph relates to Navigator 1 / 2 and go_router

- `MorphNavigationStack(home:)` owns one nested `Navigator` (key and observers are read once) and
  one shared navigation bar + toolbar over it. Pages are pushed imperatively with
  `Navigator.of(context).push(MorphNavigationRoute(builder:))` or `pushMorphZoom`; the bars follow
  the top `MorphNavigationScaffold`'s published `MorphNavigationConfig`. `pop`, `popUntil`,
  `pushReplacement` etc. are plain Navigator 1 calls.
- No Navigator 2 surface: there is no `pages:` / `onDidRemovePage`, no `Page` subclass that creates a
  `MorphNavigationRoute`, so go_router / declarative deep links cannot drive the stack's inner
  navigator (a whole `MorphNavigationStack` can sit inside one GoRoute; its pages cannot be routes).
- The stack sits under a `NavigatorPopHandler`; system back and outer `maybePop` reach it.
  `PopScope` on a page blocks the edge swipe (`popGestureEnabled`).
- `MorphPageRoute` / `showMorphRoute` (engine) are a different thing: a morph flight from a
  `MorphTag` into an overlay page (container transform), any Navigator; not a nav-stack push.

## UIKit

| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UINavigationController(rootViewController:)`, iOS 2+ | stack with root | `MorphNavigationStack(home:)` | - | keep |
| `pushViewController(_:animated:)` | push with slide | `Navigator.push(MorphNavigationRoute(builder:))` | no `animated: false` | keep (Navigator); add `MorphNavigationRoute(animated:)` only if asked |
| `popViewController(animated:)`, `popToViewController`, `popToRootViewController` | pops | `Navigator.pop`, `popUntil` | - | keep (Navigator idiom) |
| `viewControllers`, `setViewControllers(_:animated:)` | read / replace the whole stack | none (imperative only) | no declarative stack | add Navigator 2: `MorphNavigationStack(pages:, onDidRemovePage:)` + `MorphNavigationPage` (see ranked #1) |
| `topViewController`, `visibleViewController` | queries | `ModalRoute.of`, `NavigatorObserver` | - | skip (Flutter idiom) |
| `navigationBar` / `toolbar` (managed bars) | the shared bars | built into `MorphNavigationStack` | not replaceable; style via `MorphBarStyle` | keep |
| `isNavigationBarHidden`, `setNavigationBarHidden(_:animated:)` | hide nav bar | `MorphNavigationScaffold.navigationBarHidden`, `MorphNavigationScaffold.setNavigationBarHidden(context, hidden:)` (motion of the search presentation, bars.md) | - | done |
| `isToolbarHidden`, `setToolbarHidden(_:animated:)` | toolbar visibility | derived from `toolbarLeading/toolbarTrailing` (`MorphNavigationConfig.hasToolbar`) | declarative | keep |
| `interactivePopGestureRecognizer`, iOS 7+ | edge swipe back | `MorphNavigationRoute` edge pop (`MorphNavigationTransition.edgeWidth` 20, `popDistance`, `popVelocity`) | no per-stack switch other than `PopScope` | keep; add `MorphNavigationStack.popGestureEnabled` if asked |
| `interactiveContentPopGestureRecognizer`, iOS 26 (LG) | back swipe from anywhere on the content | none (edge only) | missing; iOS 26 users expect it | add full-width content pop (default on, yields to horizontal scrollables); measure first |
| `hidesBarsOnSwipe`, `hidesBarsOnTap`, `hidesBarsWhenKeyboardAppears`, `hidesBarsWhenVerticallyCompact` | auto-hiding bars | none | iOS 27 replaces this with `UIBarMinimization` (bars.md) | skip (legacy); follow minimization |
| `delegate` `willShow/didShow`, custom animator / interaction controllers | observe / custom transitions | `MorphNavigationStack.observers` (`NavigatorObserver`) | no custom transition hook | keep |
| `UIViewController.hidesBottomBarWhenPushed` | hide tab bar under pushed page | none | belongs to tab bar / stack composition | add later (low; tab-bar family) |
| `UIViewController.navigationItem` | per-page bar config | `MorphNavigationScaffold` fields / `MorphNavigationConfig` | - | keep (see bars.md) |
| `UIViewController.preferredTransition`, iOS 18 | push / present transition | `MorphNavigationRoute.zoomSource` (push), `presentMorphSheet(from:)` (sheet) | only slide or zoom | reshape -> `MorphNavigationRoute(transition:)` (see Breaking) |
| `Transition.zoom(options:sourceViewProvider:)`, iOS 18 | zoom from a view | `pushMorphZoom(context, from: tagId, builder:)`, `MorphNavigationRoute(zoomSource:)`, `MorphPushZoomTuning` | source is a `MorphTag` id (static, not a provider) | keep; add provider form `from: Object Function()`-style only if needed |
| `Transition.zoom(options:sourceBarButtonItemProvider:)`, iOS 26 (LG) | zoom out of a bar button | none | missing | add: `MorphBarButton` exposes a tag id usable as `from` |
| `ZoomOptions.interactiveDismissShouldBegin`, iOS 18 | veto drag-to-dismiss (location, velocity, willBegin) | none (`MorphPushZoomTuning.dragAngle/dragSlop` fixed) | missing | add `zoomDismissShouldBegin: bool Function(MorphZoomDismissContext)?` |
| `ZoomOptions.alignmentRectProvider`, iOS 18 | zoom into a sub-rect of the destination | none | missing | add `alignmentRect: Rect Function(Size)?` (low/med) |
| `ZoomOptions.dimmingColor`, iOS 18 | dimming color | `MorphPushZoomTuning.dimmingOpacity` (black only) | no color | add `dimmingColor` (Color, default black 0.15) |
| `ZoomOptions.dimmingVisualEffect` (UIBlurEffect), iOS 18 | blur instead of dim | none | GPU cost on weak Android | skip (performance), or flat fallback |
| `Transition.coverVertical`, iOS 18 | modal slide up | `presentMorphSheet` | sheet, not full-screen cover | see sheets family |
| `Transition.crossDissolve`, iOS 18; SwiftUI `.crossFade` iOS 27 (LG) | fade between pages | none (reduced motion fades) | missing | add `MorphNavigationRouteTransition.crossFade` |
| `Transition.flipHorizontal`, `.partialCurl`, iOS 18 | legacy modal styles | none | - | skip (rare, not LG) |

## SwiftUI

| SwiftUI API | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `NavigationStack(path: Binding<NavigationPath / [T]>, root:)`, iOS 16 | declarative stack driven by data | none | same as UIKit `setViewControllers` row | add Navigator 2 pages API (ranked #1) |
| `navigationDestination(for:destination:)`, `(isPresented:)`, `(item:)` iOS 16/17 | data -> page mapping | Navigator `onGenerateRoute` not exposed | stack has no `onGenerateRoute` / named routes | add `MorphNavigationStack.onGenerateRoute` (cheap) or pages API |
| `NavigationLink(value:)` | push on tap | `Navigator.push` in `onPressed` | - | skip (Flutter idiom) |
| `navigationTransition(.automatic)` / `.zoom(sourceID:in:)` iOS 18 / `.crossFade` iOS 27 (LG) | per-destination transition | `MorphNavigationRoute(zoomSource:)`; no crossFade | name `MorphNavigationTransition` is taken by a tuning-constants class | rename constants, add transition value (Breaking) |
| `matchedTransitionSource(id:in:)` on View (iOS 18) and ToolbarContent (iOS 26 LG) | mark zoom source | `MorphTag(id:)` under `MorphScope` | no toolbar-item source | add bar-button source (same as UIKit row) |
| `navigationBarBackButtonHidden(_:)` | hide back | none | same as UIKit `hidesBackButton` | add (bars.md) |
| `toolbarVisibility(_:for:)`, iOS 18 | hide bars per page | `MorphNavigationScaffold.navigationBarHidden` | - | done |
| `navigationTitle` / `navigationSubtitle` | title | see bars.md | - | - |
| `NavigationSplitView`, iOS 16 | sidebar / content / detail columns | none | iPad / desktop layout; phones collapse to a stack | skip for 1.0 (low on phone; macOS desktop could use it later) |

## Not relevant for Flutter

- `initWithNavigationBarClass:toolbarClass:`, `NSCoding` initializers, `showViewController:sender:` (responder-chain dispatch).
- `UINavigationControllerDelegate` orientation callbacks: Flutter `SystemChrome`.
- `barHideOnSwipeGestureRecognizer` / `barHideOnTapGestureRecognizer`: gesture-recognizer objects; Flutter gestures are widgets.
- `UIViewControllerAnimatedTransitioning` / `UIViewControllerInteractiveTransitioning`: custom transitions are Flutter `PageRoute` subclasses.
- `UIZoomTransitionSourceViewProviderContext.sourceViewController/zoomedViewController`: controller graph; morph resolves the tag from `context`.

## morph-only API

- `MorphNavigationScaffold` (scroll view + bars + large title in one widget): keep (UIKit splits it across controller, item and scroll view).
- `MorphNavigationConfig` (value a page publishes to the shared bars): keep; it doubles as the standalone bar input.
- `MorphNavigationTransition` (static measured constants: `pushSpring`, `interactiveSpring`, `parallax`, `edgeWidth`, `popDistance`, `popVelocity`, `cancelVelocityScale`, `barDrift`): keep content, rename (Breaking).
- `MorphNavigationTitleMotion`, `MorphPushZoomMotion`, `MorphZoomMotion`: pure motion classes - keep (advanced).
- `MorphPushZoomTuning` / `MorphZoomTuning`: measured springs and drag rules - keep.
- `MorphPageRoute`, `showMorphRoute`: container-transform page from a tag (engine) - keep; document the difference from `pushMorphZoom` (one rides the nav stack's bars, the other is an overlay page).

## Ranked gaps

| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | Navigator 2 / go_router: no pages API, no `Page` for `MorphNavigationRoute`, no `onGenerateRoute` | high | M | add `MorphNavigationPage<T>` (creates `MorphNavigationRoute`, `zoomSource` optional), `MorphNavigationStack(pages:, onDidRemovePage:)` alternative to `home:`, plus `onGenerateRoute` |
| 2 | Full-width content back swipe (`interactiveContentPopGestureRecognizer`, iOS 26) | high | M | measure on device (thresholds, conflict with horizontal scrollers), then default on in `MorphNavigationRoute` |
| 3 | Zoom options: `dimmingColor`, `interactiveDismissShouldBegin` | med | S | add `dimmingColor` to `MorphPushZoomTuning`/`MorphZoomTuning` (or route), add `zoomDismissShouldBegin` callback on route / `pushMorphZoom` / `presentMorphSheet` |
| 4 | Zoom from a bar button (`sourceBarButtonItemProvider`, SwiftUI toolbar `matchedTransitionSource`, iOS 26) | med | M | each `MorphBarButton` registers a `MorphTag` under its id; `pushMorphZoom(from: barButtonId)` |
| 5 | Cross-fade navigation transition (`.crossDissolve` / SwiftUI `.crossFade` iOS 27) | med | S | `MorphNavigationRouteTransition.crossFade` (spring from the reduced-motion fade path; measure) |
| 6 | ~~Hide nav bar per page~~ done 2026-10-14: `navigationBarHidden`, `setNavigationBarHidden` | - | - | - |
| 7 | `alignmentRectProvider` | low | M | `alignmentRect` callback |
| 8 | `NavigationSplitView` | low (phone) | L | defer past 1.0 |
| 9 | `hidesBottomBarWhenPushed` with `MorphTabBar` | low | M | tab-bar family |

## Breaking changes before 1.0

- `MorphNavigationTransition` (constants) -> `MorphNavigationTuning` (or `MorphPushTuning`), freeing the name for a SwiftUI-like transition value: `MorphNavigationRoute(transition: MorphNavigationTransition.zoom(from: id))`, `.slide` (default, `.automatic`), `.crossFade`. `zoomSource` + `zoom` fold into it.
- `MorphNavigationRoute.zoomSource` vs `MorphSheetRoute(source:)` vs `pushMorphZoom(from:)` / `presentMorphSheet(from:)`: one name for the zoom source; use `from` everywhere (or fold into `transition`, above).
- `MorphNavigationStack(home:)` -> keep `home` but make it one of two constructors (`MorphNavigationStack(home:)` and `MorphNavigationStack.pages(pages:, onDidRemovePage:)`), so the Navigator 2 path is not a later breaking reshape.
- `MorphNavigationStack.backLabel` / `MorphNavigationScaffold.backLabel` -> `backButtonSemanticLabel` (listed in bars.md too).
