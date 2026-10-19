# Navigation - API parity (UIKit / SwiftUI iOS 27.1 vs morph)

Catalog families: `navigation-stack`, `zoom-transition`. Native: `UINavigationController`,
`UIViewController.navigationItem` / `.preferredTransition`, `UIViewController.Transition`
(`.zoom`, `.coverVertical`, `.crossDissolve`, `.flipHorizontal`, `.partialCurl`),
`UIZoomTransitionOptions`; SwiftUI `NavigationStack(path:)`, `navigationDestination`,
`navigationTransition(.automatic / .zoom(sourceID:in:) / .crossFade)`,
`matchedTransitionSource(id:in:)`, `NavigationSplitView`.

morph (`lib/morph.dart`): `MorphNavigationStack` (+ `.pages`), `MorphNavigationPage`,
`MorphNavigationRoute`, `MorphNavigationScaffold`, `MorphNavigationConfig`, `MorphSource`,
`MorphSourceLink`; sheet zoom `MorphSheetRoute(from:)` (sheets.md). Internal (`@internal`):
`MorphNavigationTuning`, `MorphNavigationPopMotion`, `MorphPushZoomMotion`, `MorphPushZoomTuning`,
`MorphZoomSource`, the predictive back registry. Passport:
[../navigation-pages.md](../navigation-pages.md) (bars: [../bars.md](../bars.md)).

Sources: iPhoneOS27.1.sdk `UINavigationController.h`, `UIViewController.h`,
`UIViewControllerTransition.h`, `UIZoomTransitionOptions.h`, SwiftUI
`arm64e-apple-ios.swiftinterface`. LG = new with Liquid Glass (iOS 26/27). Status: covered (same
meaning), partial (narrower), gap. A row is one member or one overload family; n/a members are
listed below the tables, not counted. 27.1 changes nothing in these families; the 27.1 vertical
bar (`preferredVerticalBarBehavior`) is listed in [bars.md](bars.md).

## How morph relates to Navigator 1 / 2 and go_router

- `MorphNavigationStack(home:)` and `MorphNavigationStack.pages(pages:, onDidRemovePage:)` own one
  nested `Navigator` and one shared navigation bar and toolbar over it. The bars follow the top
  `MorphNavigationScaffold`'s published `MorphNavigationConfig`.
- Imperative: `Navigator.of(context).push(MorphNavigationRoute(builder:, from:))`; `pop`,
  `popUntil`, `pushReplacement` are plain Navigator calls. Declarative: a list of
  `MorphNavigationPage(child:, from:)`, each creating a `MorphNavigationRoute`, so go_router or any
  Navigator 2 code can drive the inner stack.
- The stack sits under a `NavigatorPopHandler`: system back and an outer `maybePop` reach it.
  `PopScope` on a page blocks the edge and content swipes. Android predictive back drives the same
  interactive pop (an approximation: iOS has no predictive back).
- A zoom names its source with a `MorphSourceLink` attached by `MorphSource(link:, shape:)`.

## UIKit - navigation stack family

| UIKit API (availability) | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `UINavigationController(rootViewController:)` | stack with a root | `MorphNavigationStack(home:)` | covered | - |
| `pushViewController(_:animated:)` | push with a slide | `Navigator.push(MorphNavigationRoute(builder:))` | partial | no `animated: false` |
| `popViewController(animated:)`, `popToViewController`, `popToRootViewController` | pops | `Navigator.pop`, `popUntil` | covered | Navigator idiom |
| `viewControllers`, `setViewControllers(_:animated:)` | read / replace the stack | `MorphNavigationStack.pages`, `onDidRemovePage`, `MorphNavigationPage` | covered | - |
| `navigationBar`, `toolbar` | the managed bars | built into the stack; `appearance` | covered | not replaceable |
| `isNavigationBarHidden`, `setNavigationBarHidden(_:animated:)` | hide the nav bar | `MorphNavigationScaffold.navigationBarHidden`, `.setNavigationBarHidden` | covered | - |
| `interactivePopGestureRecognizer`, iOS 7 | edge swipe back | `MorphNavigationRoute` edge pop; `PopScope` blocks it | covered | release rule replayed; edge width 20 unmeasured |
| `interactiveContentPopGestureRecognizer`, iOS 26 (LG) | back swipe from the content | `MorphNavigationStack.contentPopGestureEnabled` (default on) | covered | 30 pt slop, 29 - 30 degree bracket [device] |
| `hidesBarsOnSwipe`, `hidesBarsOnTap`, `hidesBarsWhenKeyboardAppears`, `hidesBarsWhenVerticallyCompact` | auto-hiding bars | none | gap | low; iOS 27 minimization covers scrolling (bars.md) |
| `delegate` `willShow` / `didShow` | observe transitions | `MorphNavigationStack.observers` | covered | Flutter's observer contract |
| `UIViewController.hidesBottomBarWhenPushed` | hide the tab bar under a pushed page | none | gap | tab-bar composition |
| `UIViewController.navigationItem` | per-page bar config | `MorphNavigationScaffold` fields, `MorphNavigationConfig` | covered | bars.md |
| `UIViewController.preferredTransition`, iOS 18 | push / present transition | slide, or zoom with `from:` | partial | slide or zoom only |
| `UIViewController.Transition.crossDissolve`, iOS 18 | fade between pages | none (pages cross-fade only under Reduce Motion) | gap | expose the existing 0.5 s cross-fade |
| `restorationIdentifier` on the stack and its pages | state restoration | `MorphNavigationPage.restorationId` is accepted, but the inner `Navigator` has no `restorationScopeId` | gap | add `MorphNavigationStack.restorationScopeId` |

## SwiftUI - navigation stack family

| SwiftUI API | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `NavigationStack(path:root:)`, iOS 16 | stack driven by data | `MorphNavigationStack.pages` | covered | - |
| `navigationDestination(for:)`, `(isPresented:)`, `(item:)`, iOS 16 / 17 | data -> page mapping | the app maps its data to `MorphNavigationPage`s | partial | no route table (`onGenerateRoute`) |
| `navigationTransition(.automatic)`, iOS 18 | default push | slide | covered | - |
| `navigationTransition(.crossFade)`, iOS 27.0 (LG) | fade between pages | none | gap | same as `.crossDissolve` |
| `NavigationSplitView`, iOS 16 | sidebar / content / detail | none | gap | low on phones |

## UIKit - zoom transition family

| UIKit API | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `Transition.zoom(options:sourceViewProvider:)`, iOS 18 | zoom out of a view | `MorphNavigationRoute(from:)`, `MorphNavigationPage(from:)` + `MorphSource(link:)`; sheets `MorphSheetRoute(from:)` | partial | the source resolves once at the push; UIKit asks the provider again during the transition's life, so a pop can return into another or a rebuilt cell (header example); morph dissolves when the first source is gone |
| `Transition.zoom(options:sourceBarButtonItemProvider:)`, iOS 26 (LG) | zoom out of a bar item | none | gap | let `MorphBarButton` carry a `MorphSourceLink` |
| `ZoomOptions.interactiveDismissShouldBegin` (location, velocity, `willBegin`) | veto a drag-to-dismiss | none (a `PopScope` veto returns the page after the drag) | gap | `zoomDismissShouldBegin` callback |
| `ZoomOptions.alignmentRectProvider` | zoom into a sub-rect of the page | none | gap | low |
| `ZoomOptions.dimmingColor` | dimming color | none (black 0.15, internal tuning) | gap | add `dimmingColor` |
| `ZoomOptions.dimmingVisualEffect` | blur instead of dimming | none | gap | blur cost on weak Android; flat fallback |
| `preferredTransition = .zoom` on a presented controller | full-screen modal zoom | none outside a navigation stack (a sheet zoom exists) | gap | a full-screen zoom route |

## SwiftUI - zoom transition family

| SwiftUI API | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `navigationTransition(.zoom(sourceID:in:))`, iOS 18 | zoom per destination | `MorphNavigationRoute(from:)` / `MorphNavigationPage(from:)` | covered | - |
| `matchedTransitionSource(id:in:)` on a View, iOS 18 | mark the source | `MorphSource(link:, shape:)` | covered | - |
| `matchedTransitionSource(id:in:configuration:)` (`background`, `clipShape`, `shadow`), iOS 18 | source look during the zoom | `MorphSource.shape` | partial | no background or shadow |
| `matchedTransitionSource(id:in:)` on `ToolbarContent`, iOS 26 (LG) | zoom out of a toolbar item | none | gap | same as `sourceBarButtonItemProvider` |

## Counts

| family | applicable | covered | partial | gap |
|---|---|---|---|---|
| navigation-stack | 20 | 11 | 3 | 6 |
| zoom-transition | 11 | 2 | 2 | 7 |

## Not relevant for Flutter (not counted)

- `initWithNavigationBarClass:toolbarClass:`, `NSCoding` initializers, `showViewController:sender:`.
- `topViewController`, `visibleViewController`: `ModalRoute.of`, observers.
- Delegate orientation callbacks: `SystemChrome`.
- `barHideOnSwipeGestureRecognizer` / `barHideOnTapGestureRecognizer`: recognizer objects.
- `UIViewControllerAnimatedTransitioning` / `UIViewControllerInteractiveTransitioning`: custom transitions are `PageRoute` subclasses.
- `UIZoomTransitionSourceViewProviderContext.sourceViewController` / `zoomedViewController`: the controller graph.
- `NavigationLink(value:)`, `NavigationPath`: `Navigator.push`, Dart lists.
- `Transition.coverVertical`, `.flipHorizontal`, `.partialCurl`: modal presentation styles (sheets family; the last two legacy).
- `AnyNavigationTransition` (iOS 27.0): a type eraser.

## morph-only API

- `MorphNavigationScaffold`: scroll view, bars and large title in one widget (UIKit splits them across controller, item and scroll view); keep.
- `MorphNavigationConfig`: the value a page publishes to the shared bars, also the standalone bar input; keep.
- `MorphSource` / `MorphSourceLink`: one source naming for page zooms and sheet zooms; keep.

## Ranked gaps

| # | gap | kind | need | cost | proposal |
|---|---|---|---|---|---|
| 1 | State restoration: `MorphNavigationPage.restorationId` has no effect without a `restorationScopeId` on the inner Navigator | api | M-H | S | `MorphNavigationStack.restorationScopeId` |
| 2 | Interrupted transitions (a push during a push, a swipe during a push, a pop mid-zoom) follow no measurement | behaviour | M | M meas. | capture interruptions, then replay |
| 3 | Zoom source chosen again at the pop (provider semantics: another or a rebuilt cell) | behaviour | M | S-M | let the route take a source callback, or resolve the link again when the pop starts |
| 4 | Zoom options `dimmingColor`, `interactiveDismissShouldBegin` | api | M | S | route parameters |
| 5 | Zoom from a bar item (`sourceBarButtonItemProvider`, toolbar `matchedTransitionSource`) | api | M | M | `MorphBarButton.source: MorphSourceLink?` |
| 6 | Cross-fade transition (`.crossDissolve`, `.crossFade`) | api | M | S | a route option on the existing cross-fade (read from UIKit) |
| 7 | Push zoom on the Pixel 6a: no frame-time or energy record | perf | M | S | add a zoom scene to the navigation bench |
| 8 | Zoom under Reduce Motion: UIKit reads the flag (states.md), effect not decoded; morph zooms unchanged | a11y | M | S meas. | capture with Reduce Motion on |
| 9 | Full-screen modal zoom outside a stack | api | M | M | a full-screen zoom route |
| 10 | `hidesBottomBarWhenPushed` with `MorphTabBar` | api | L | M | tab-bar family |
| 11 | `alignmentRectProvider` | api | L | M | `alignmentRect` callback |
| 12 | Route table (`onGenerateRoute`) for `navigationDestination` users | api | L | S | optional `onGenerateRoute` |
| 13 | Edge width 20 pt has no measurement | behaviour | L | S meas. | read it from a device capture |
| 14 | `NavigationSplitView`, `hidesBarsOnSwipe` and friends, `animated: false` | api | L | S-L | after 1.0 |

## Breaking changes before 1.0

Done: `MorphNavigationStack.pages`, one source name `from:` (`MorphSourceLink`) on
`MorphNavigationRoute`, `MorphNavigationPage` and `MorphSheetRoute`, the tuning constants internal
(`MorphNavigationTuning`), `backButtonSemanticLabel`.

Open:
- If a cross-fade is added, fold `from:` into a transition value (`slide`, `zoom(from:)`, `crossFade`) before 1.0 so a third kind does not break callers.
- `MorphSourceLink`'s dartdoc says controls take a `source:` parameter; none does. Add `source:` where UIKit has a source (bar items first) or change the doc.

## Behaviour fidelity

### navigation-stack

| dimension | grade | evidence | open items |
|---|---|---|---|
| layout | measured | parallax 0.3 [tuning; device rows in `bars/push-pop.jsonl`]; card radius 62 [simulator film] or `displayCornerRadii` (navigation-pages.md "the card and the dim") | the card radius is a simulator fit; test/navigation_card_test.dart pins the constant only |
| states | replayed | dim alpha 0.1 x cover progress vs four device samples (test/navigation_card_test.dart) | samples are inlined in the test, not loaded from a fixture |
| transitions | unbacked | push / pop spring vs device rows within 1.5 pt (test/navigation_motion_test.dart, `bars/push-pop.jsonl`); release spring of 33 device releases within 0.2 pt (test/navigation_pop_motion_test.dart, test/fixtures/ios27-device/navigation/release-decision.json); slow first frame [device table] (test/navigation_first_frame_test.dart pins the rule); Reduce Motion cross-fade read from UIKit | interrupted transitions follow no measurement; first-frame table not replayed |
| boundaries | approx | pop threshold `min(187.5 / width, 0.5)` read from UIKit and replayed; content swipe 29 - 30 degree bracket (NEAR) and 30 pt slop [device] | edge width 20 pt unbacked (lib/src/widgets/navigation_motion.dart:168); scroll-view handoff measured only in the recorded strip cases |
| configuration | measured | content pop on by default [device]; `contentPopGestureEnabled`, `PopScope`, `prefersLargeTitles` (test/navigation_card_test.dart, test/navigation_api_test.dart) | - |
| events | n/a | `NavigatorObserver`, `onDidRemovePage` carry Flutter's contract (test/navigation_api_test.dart) | UIKit delegate order not compared |
| input | replayed | release prediction: speed, acceleration and outcome of 33 releases within 1e-5 (test/navigation_pop_motion_test.dart); held content releases through the widget (test/navigation_card_test.dart); angle gate | platform event delivery NEAR; fast coalesced inputs not reconstructed |
| mutation | unbacked | a page removed or pushed during a swipe, republished configs (test/navigation_stack_test.dart) | no native capture of changes mid-transition |
| accessibility | read | Reduce Motion: 0.5 s ease-in-out cross-fade, edge swipe keeps the slide, read from UIKit (states.md; test/navigation_stack_test.dart) | bar items snap where UIKit cross-fades the bar; the VoiceOver escape gesture is not checked |
| optics | measured | dim black 0.1 [device]; card corners [simulator film] | the card's edge on a dark page is not recorded |
| platform | missing | RTL slide and swipe mirror (code, no native capture); Android predictive back (test/predictive_back_test.dart, tool/audit/foundation-5.2-2026-10-19/predictive-back.md) | state restoration missing; predictive back is a declared approximation |
| performance | measured | Pixel 6a nested push / pop p95 within budget, energy recorded (docs/performance.md) | first-layout frames 1.2 - 1.3 percent over |

### zoom-transition

| dimension | grade | evidence | open items |
|---|---|---|---|
| layout | replayed | container edges of 5 transitions within 1.6 / 1.0 pt (test/push_zoom_test.dart, test/fixtures/ios27-device/push_zoom/push_zoom.json) | `alignmentRectProvider` missing |
| states | measured | dim black 0.15, shadow 0.36 / sigma 30 [film]; crossfade replayed within 0.12 | the shadow's fade follows the dimming by assumption (navigation-pages.md) |
| transitions | unbacked | open / close / return springs replayed (test/push_zoom_test.dart) | a pop mid-open turns around with its velocity (test only, no capture) |
| boundaries | unbacked | dismiss past 132.5 pt or 1050 pt/s, 30 degree drag gate, 13.5 pt slop [film brackets] | a lost source dissolves over half the remaining progress (lib/src/widgets/zoom_source.dart:98), no capture |
| configuration | missing | source shapes capsule / card / glass [film] | `dimmingColor`, `dimmingVisualEffect`, `interactiveDismissShouldBegin`, bar item sources |
| events | n/a | no callbacks beyond the route's | - |
| input | replayed | 10 drags, outcomes exact (test/push_zoom_test.dart) | fast flicks replay loose; the edge drag from x 2 at 9 pt rms |
| mutation | unbacked | source resolved once at the push (lib/src/widgets/navigation_stack.dart:940) | UIKit re-asks the provider at the pop |
| accessibility | unbacked | - | Reduce Motion effect on the zoom not decoded; morph zooms unchanged |
| optics | measured | corner radius from source to display by mean progress (0.6 pt off) [film] | shadow fade assumed |
| platform | approx | RTL mirrors the sideways drag (lib/src/widgets/push_zoom.dart:251); predictive back zooms the page home (test/predictive_back_test.dart) | no native RTL capture |
| performance | unbacked | - | no Pixel 6a frame-time or energy record for a push zoom |
