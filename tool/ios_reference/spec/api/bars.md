# Bars - API parity (UIKit / SwiftUI iOS 27.1 vs morph)

Catalog families: `navigation-bar`, `toolbar`. Native: `UIBarButtonItem`, `UIBarButtonItem.Badge`,
`UIBarButtonItemGroup`, `UINavigationItem`, `UINavigationBar`, `UIToolbar`,
`UIViewController.toolbarItems`, `UIBarMinimization`; SwiftUI `toolbar`, `ToolbarItem(placement:)`,
`ToolbarItemGroup`, `ToolbarSpacer`, `DefaultToolbarItem`, `sharedBackgroundVisibility`,
`navigationTitle` / `navigationSubtitle`, `toolbarTitleDisplayMode`, `toolbarRole`,
`toolbarTitleMenu`, `toolbarVisibility`, `toolbarMinimizationBehavior`, `visibilityPriority`.

morph (`lib/morph.dart`): `MorphBarButton` (+ `.back`), `MorphBarButtonGroup`, `MorphBarButtonStyle`,
`MorphBadge`, `MorphBarAppearance`, `MorphNavigationBar`, `MorphLargeTitle`,
`MorphLargeTitleDisplayMode`, `MorphBackButtonDisplayMode`, `MorphNavigationBarHiding`,
`MorphToolbar`, and the bar fields of `MorphNavigationScaffold`, `MorphNavigationConfig`,
`MorphNavigationStack`. Internal (`@internal`, not for apps): `MorphBarMetrics`,
`MorphNavigationBarMetrics`, `MorphToolbarMetrics`, `MorphBarMenuTuning`, `MorphBarMotion`,
`MorphBarTransitionSpec`, the capsule and item layouts, `MorphNavigationTitleMotion`,
`MorphLargeTitleScrollPhysics`. Passports: [../bars.md](../bars.md),
[../navigation-pages.md](../navigation-pages.md). Scroll edge effect:
[scroll-edge-effect.md](scroll-edge-effect.md); search placements: [search.md](search.md).

Sources: iPhoneOS27.1.sdk UIKit headers (`UIBarButtonItem.h`, `UIBarButtonItemBadge.h`,
`UIBarButtonItemGroup.h`, `UINavigationItem.h`, `UINavigationBar.h`, `UIToolbar.h`,
`UIBarMinimization.h`, `UIBarAppearance.h`, `UIViewController.h`, `UIVerticalBarEdge.h`) and
SwiftUI `arm64e-apple-ios.swiftinterface`. LG = new with Liquid Glass (iOS 26/27). Status: covered
(same meaning), partial (narrower), gap. A row is one member or one overload family; n/a members
are listed below the tables, not counted.

## New in 27.1

27.1 adds the vertical bar: `UIBarButtonItem.axisBehavior` (`.horizontalOnly`,
`.verticalPreferred`), `UINavigationItem.verticalBarCompressionBehavior` (`.prefersBarItems`,
`.prefersTabBar`), `UIViewController.preferredVerticalBarBehavior`,
`childForPreferredVerticalBarBehavior`, `setNeedsUpdateOfVerticalBarConfiguration`,
`UITraitCollection.verticalBarEdge`; SwiftUI `axisBehavior(_:)`, `toolbarVerticalBehavior(_:)`,
`toolbarVerticalCompressionBehavior(_:)`. On hardware without a vertical bar the edge is
`.unspecified` and bars stay horizontal. morph has no vertical bar; the members are n/a until a
device with one is measured. Nothing else in these families changed between 27.0 and 27.1.

## UIKit - navigation bar family

### UIBarButtonItem

| UIKit API (availability) | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `init(title:/image:/primaryAction:/menu:)`, iOS 2+/14+/16+ | item with text or image | `MorphBarButton(id:, label:, icon:)` | partial | a button with both shows its label; which one UIKit shows in the bar is not measured |
| `style` `.plain` / `.prominent` (iOS 26, LG; `.done` deprecated) | tinted glass item | `MorphBarButtonGroup.style: MorphBarButtonStyle` | covered | per group; plain and prominent items cannot share a capsule |
| `tintColor` | item color; tints a prominent item's glass | `MorphTheme` tint -> `MorphBarAppearance.prominentColor` (per bar) | gap | add `MorphBarButtonGroup.tintColor` |
| `isEnabled` | disabled look, no action | `MorphBarButton.enabled` | covered | device colors replayed |
| `primaryAction`, target-action | tap action | `onPressed` | covered | - |
| `menu` | tap opens without a primary action, long press otherwise | `MorphBarButton.menu` | covered | timing measured (menu-button.md) |
| `preferredMenuElementOrder`, iOS 16 | menu row order | none (`MorphMenuOrder` exists on `MorphMenuButton`) | gap | add `MorphBarButton.menuOrder` |
| `changesSelectionAsPrimaryAction`, `isSelected`, iOS 15 | toggle item | none | gap | add `MorphBarButton.selected`; measure the look |
| `customView` | arbitrary view | `icon` (any Widget in the icon box) | partial | no free-size child |
| `badge` (`.count`, `.string`, `.indicator`), `Badge.foregroundColor` / `backgroundColor`, iOS 26 (LG) | badge on an item | `MorphBadge.count` / `.string` / `.indicator`, colors | covered | placement read from UIKit; static (no fade); count without locale grouping |
| `Badge.font`, iOS 26 | badge font | none | gap | low |
| `hidesSharedBackground`, iOS 26 (LG) | item without a glass capsule | none | gap | add `MorphBarButtonGroup.hidesSharedBackground` |
| `sharesBackground`, iOS 26 (LG) | item keeps its own capsule | separate `MorphBarButtonGroup` | covered | - |
| `identifier`, iOS 26 (LG) | matches items across transitions | `MorphBarButton.id` (required), `MorphBarButtonGroup.id` | covered | groups without id pair by nearest center, as measured |
| `SystemItem` (`.done`, `.close`, `.add`, `.search`, ...) | localized title / symbol presets | `MorphBarButton.back` only | gap | low; no SF Symbols |
| `visibilityPriority`, iOS 27.0 (LG) | which items survive when space is short | none | gap | needs overflow |
| `isPaddingRemoved`, iOS 27.0 (LG) | no standard padding | none | gap | low |
| `menuRepresentation`, iOS 16 | form in the overflow menu | none | gap | needs overflow |

### UIBarButtonItemGroup

| UIKit API | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `init(barButtonItems:representativeItem:)`, iOS 9 | items sharing one capsule | `MorphBarButtonGroup(buttons, id:, style:)` | partial | no representative (collapsed) item |
| `alwaysAvailable`, iOS 16 | never collapses into overflow | none | gap | needs overflow |

### UINavigationItem

| UIKit API | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `title` | inline / large title | `title` on scaffold, config, bar | covered | - |
| `attributedTitle`, iOS 26 (LG) | styled title | none | gap | low |
| `titleView` | custom center view | none | gap | add `titleView: Widget?`, placed by the measured title room rule |
| `subtitle`, iOS 26 (LG) | line under the inline title | `subtitle` on scaffold, config, bar | covered | fonts read from UIKit; line gap not read |
| `attributedSubtitle`, `subtitleView`, iOS 26 (LG) | styled / custom subtitle | none | gap | low |
| `largeTitle`, iOS 26 (LG) | large text distinct from `title` | none (the large title shows `title`) | gap | add `largeTitle: String?` |
| `largeSubtitle`, iOS 26 (LG) | line under the large title | `MorphNavigationScaffold.largeSubtitle`, `MorphLargeTitle(subtitle:)` | covered | layout read from UIKit, not recorded |
| `largeAttributedSubtitle`, `largeSubtitleView`, iOS 26 (LG) | styled / custom large subtitle | none | gap | low |
| `largeTitleDisplayMode` `.automatic` / `.always` / `.never` / `.inline` (iOS 17) | per-page large title | `MorphLargeTitleDisplayMode` automatic / always / never | partial | no `.inline` |
| `prompt` | text above the title | none | gap | low |
| `backBarButtonItem` | custom back item of the next page | none | gap | low |
| `backButtonTitle`, iOS 11 | label of the next page's back button | `backButtonTitle` | covered | - |
| `backButtonDisplayMode` `.default` / `.generic` / `.minimal`, iOS 14 | full title / "Back" / chevron | `MorphBackButtonDisplayMode` standard / generic / minimal | partial | `.default` shortening to "Back", then the chevron, when space runs out is not reproduced |
| `hidesBackButton`, `setHidesBackButton(_:animated:)` | hide back | `hidesBackButton` | covered | - |
| `leftItemsSupplementBackButton`, iOS 5 | leading items beside the back button | none: leading groups replace the back button | gap | add `leadingItemsSupplementBackButton` |
| `backAction`, iOS 16 | custom back action | back calls `maybePop`; `PopScope` on the page | covered | Flutter idiom |
| `leftBarButtonItems` / `rightBarButtonItems`, `leadingItemGroups` / `trailingItemGroups` (iOS 16) | items per side | `leading` / `trailing` (`List<MorphBarButtonGroup>`) | covered | changes always animate |
| `centerItemGroups`, `style` navigator / browser / editor, iOS 16 | centered groups, leading title | none | gap | low on phones |
| `pinnedTrailingGroup`, `additionalOverflowItems`, iOS 16 | overflow menu | none | gap | no overflow |
| `titleMenuProvider`, iOS 16 | menu from the title | none | gap | add `titleMenu: List<MorphMenuEntry>?` |
| `searchController`, `preferredSearchBarPlacement` (`.integrated`, `.integratedCentered`, `.integratedButton` iOS 26; `.stacked`) | search in the bars | `MorphNavigationScaffold.search` (`MorphNavigationSearch`, stacked), `MorphSearchToolbar` | partial | no integrated / button placement in the nav bar (search.md) |
| `hidesSearchBarWhenScrolling` | stacked field scrolls away | stacked field always scrolls away | partial | `false` (pinned field) not reproduced |
| `searchBarPlacementAllowsToolbarIntegration` / `AllowsExternalIntegration`, `searchBarPlacementBarButtonItem`, iOS 26 | where the integrated search may go | none | gap | search family |
| `standardAppearance` / `scrollEdgeAppearance` / `compactAppearance` / `compactScrollEdgeAppearance` | bar look per state | `MorphBarAppearance`, `edgeEffect` | covered | LG bars have no fill |
| `navigationBarMinimization` (`UIBarMinimization`: behavior, safeAreaAdjustment, restorationBehavior), iOS 27.0 (LG) | bar shrinks on scroll | none | gap | measure first |

### UINavigationBar

| UIKit API | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `prefersLargeTitles`, iOS 11 | stack default for `.automatic` | `MorphNavigationStack.prefersLargeTitles` | covered | - |
| `items`, `pushItem` / `popItem`, `setItems(_:animated:)` | standalone bar | `MorphNavigationBar` + `MorphNavigationConfig` | covered | declarative |
| `tintColor` | bar tint | `MorphBarAppearance.foregroundColor` / `prominentColor`, `MorphTheme` tint | covered | - |
| `titleTextAttributes`, `largeTitleTextAttributes` | title font and color | `MorphBarAppearance.titleColor` / `subtitleColor` | partial | colors only |
| `backIndicatorImage`, `backIndicatorTransitionMaskImage` | custom chevron | none | gap | low |
| `UIBarAppearance.overrideUserInterfaceStyle`, iOS 27.0 (LG) | force light / dark bar | `appearance: MorphBarAppearance.light` / `.dark` | covered | - |

## UIKit - toolbar family

| UIKit API | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `UIToolbar.items`, `setItems(_:animated:)` | toolbar items | `MorphToolbar(leading:, trailing:)` | covered | changes replay the measured `setToolbarItems` motion |
| `UIViewController.toolbarItems`, `setToolbarItems(_:animated:)` | per-page toolbar | `toolbarLeading` / `toolbarTrailing` on scaffold, config | partial | on a push UIKit swaps items (scale, blur, fade); morph morphs the shared toolbar instead (bars.md, not ported) |
| `UINavigationController.isToolbarHidden`, `setToolbarHidden(_:animated:)` | toolbar visibility | derived from non-empty lists (`MorphNavigationConfig.hasToolbar`) | covered | declarative |
| `UIBarButtonItem.flexibleSpace()` | pushes items apart | the leading / trailing split | partial | one flexible space; no centered items |
| `fixedSpace(_:)`, `fixedSpace()` (iOS 26), `UIBarButtonItemGroup.fixedSpace()` (iOS 26) | split capsules | separate groups | covered | - |
| `UIToolbar.standardAppearance` / `compactAppearance` / `scrollEdgeAppearance`, `tintColor` | toolbar look | `MorphToolbar.appearance` | covered | - |

## SwiftUI - navigation bar family

| SwiftUI API | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `navigationTitle(_:)` | title | `title` | covered | - |
| `navigationSubtitle(_:)`, iOS 26 (LG) | subtitle | `subtitle` | covered | - |
| `ToolbarItem(placement:)` `.topBarLeading` / `.topBarTrailing` / `.navigation` / `.primaryAction` / `.cancellationAction` / `.confirmationAction` | side of the nav bar | `leading` / `trailing` | covered | semantic placements map to sides |
| `.principal`, `.title`, `.largeTitle`, `.subtitle`, `.largeSubtitle` placements (iOS 26 for the last three) | custom views in the title slots | none | gap | same as `titleView` / `subtitleView` |
| `ToolbarItemGroup` | several items, one capsule | `MorphBarButtonGroup` | covered | - |
| `sharedBackgroundVisibility(_:)`, iOS 26 (LG) | same as `hidesSharedBackground` | none | gap | - |
| `.badge(_:)` on toolbar content, iOS 26 (LG) | same as `UIBarButtonItem.badge` | `MorphBarButton.badge` | covered | - |
| `.secondaryAction` placement, `visibilityPriority(_:)` (27.0), `.topBarPinnedTrailing` (27.0) | overflow and pinning | none | gap | needs overflow |
| `contentMarginsRemoved(_:)`, iOS 27.0 (LG) | same as `isPaddingRemoved` | none | gap | low |
| `toolbarTitleDisplayMode(.automatic / .large / .inlineLarge / .inline)`, iOS 17 | large title modes | `largeTitleDisplayMode` (`.inline` = `never`, `.large` = `always`) | partial | no `.inlineLarge` (UIKit `.inline`) |
| `toolbarRole(_:)`, iOS 16 | same as `UINavigationItem.style` | none | gap | low |
| `toolbarTitleMenu { }`, iOS 16 | same as `titleMenuProvider` | none | gap | - |
| `toolbarVisibility(_:for: .navigationBar)`, iOS 18 | hide the nav bar | `navigationBarHidden`, `MorphNavigationScaffold.setNavigationBarHidden` | covered | - |
| `toolbarBackgroundVisibility(_:for:)` iOS 18, `scrollEdgeEffectStyle(_:for:)` iOS 26 (LG) | bar background / edge effect | `edgeEffect: MorphScrollEdgeEffectStyle?` | covered | - |
| `toolbarForegroundStyle(_:for:)` | bar foreground color | `MorphBarAppearance.foregroundColor` | covered | - |
| `navigationBarBackButtonHidden(_:)` | hide back | `hidesBackButton` | covered | - |
| `toolbarMinimizationBehavior` / `Restoration` / `SafeAreaAdjustment`, iOS 27.0 (LG) | same as `UIBarMinimization` | none | gap | measure first |

## SwiftUI - toolbar family

| SwiftUI API | meaning | morph equivalent | status | note / proposal |
|---|---|---|---|---|
| `.bottomBar` placement | toolbar items | `toolbarLeading` / `toolbarTrailing`, `MorphToolbar` | covered | - |
| `.status` placement | centered toolbar item | none | gap | add `MorphToolbar.center` |
| `ToolbarSpacer(.fixed / .flexible, placement:)`, iOS 26 (LG) | split capsules / push apart | groups; one leading / trailing split | partial | one flexible space only |
| `ToolbarItemGroup` in the bottom bar | one capsule | `MorphBarButtonGroup` | covered | - |
| `DefaultToolbarItem(kind: .search)`, `searchToolbarBehavior(.minimize)`, iOS 26 (LG) | search in the toolbar | `MorphSearchToolbar` | partial | search.md |
| `toolbarVisibility(_:for: .bottomBar)` | hide the toolbar | empty toolbar lists | covered | declarative |
| `.keyboard` placement | keyboard accessory bar | none | gap | low; a separate widget |
| `toolbarMinimizationBehavior(_:for: .bottomBar)`, iOS 27.0 (LG) | toolbar shrinks on scroll (UIKit exposes minimization only on `UINavigationItem`) | none | gap | measure first |

## Counts

| family | applicable | covered | partial | gap |
|---|---|---|---|---|
| navigation-bar | 68 | 28 | 9 | 31 |
| toolbar | 14 | 7 | 4 | 3 |

## Not relevant for Flutter (not counted)

- Legacy appearance: `UIBarItem` title text attributes, `setBackgroundImage(_:for:barMetrics:)`, position adjustments, `UIBarButtonItemAppearance`, `barStyle`, `isTranslucent`, `barTintColor`, `width`, `possibleTitles`; `MorphBarAppearance` replaces them.
- `NSCoding` initializers, `UIBarPositioning`, `UINavigationBarDelegate` / `UIToolbarDelegate`: UIKit plumbing.
- `NSToolbar` bridging, `preferredBehavioralStyle`, `currentNSToolbarSection`: Mac Catalyst.
- `SystemItem.pageCurl`, `.writingTools`: legacy / system feature.
- `isHidden` on items and groups, SwiftUI `toolbarItemHidden`: declarative, omit the button (its id keeps the morph).
- Symbol effects (`isSymbolAnimationEnabled`, `addSymbolEffect`, `setSymbolImage(_:contentTransition:)`): no SF Symbols; the app animates its icon widget.
- `landscapeImagePhone`, `largeContentSizeImage`: Flutter semantics and text scale; the Large Content Viewer is an accessibility gap (Behaviour fidelity).
- iPad customization: `creatingFixedGroup` / `creatingMovableGroup` / `creatingOptionalGroup`, `customizationIdentifier`.
- Document apps: `renameDelegate`, `documentProperties`, `navigationTitle(Binding<String>)` renaming.
- The iOS 27.1 vertical bar members (section above).

## morph-only API

- `MorphNavigationBar` standalone inputs `titleVisible`, `scrolledUnder`, `animate`, `sideInset`; `MorphNavigationBar.heightFor`: keep.
- `MorphLargeTitle` + `extentFor`: building block of the scaffold's large title; keep.
- `MorphToolbar.sideInset` / `bottomInset` / `keyboardInset`, `extent`, `extentFor`, `capsuleHeight`: keep. Their defaults name internal metrics classes an app cannot read.
- `MorphNavigationBarHiding` and `MorphNavigationConfig.barHiding`: the constructor is private, so an app can only pass one it got from the stack; flag (make `barHiding` internal).

## Ranked gaps

| # | gap | kind | need | cost | proposal |
|---|---|---|---|---|---|
| 1 | Overflow when items do not fit (`visibilityPriority`, `pinnedTrailingGroup`, `additionalOverflowItems`, `.secondaryAction`); groups overlap today | behaviour | M | L meas. | overflow group born in place (bars.md, navseg set b page 4), then the API |
| 2 | `titleView` / `.principal` | api | M-H | M | `titleView: Widget?` on scaffold, config, bar |
| 3 | Back title shortening (`.default` mode: title, "Back", chevron) | behaviour | M | S-M meas. | measure the widths, then shorten in `_leadingOf` |
| 4 | Side inset 20 on a 440 point screen (measured, morph keeps 16) | look | M | S | width-dependent default |
| 5 | Bar under Reduce Motion: UIKit cross-fades it with the pages (states.md), morph snaps the items | a11y | M | S | fade the bar on the cross-fade progress |
| 6 | Title menu (`titleMenuProvider`, `toolbarTitleMenu`) | api | M | M | `titleMenu: List<MorphMenuEntry>?` over the bar menu machinery |
| 7 | Per-item tint and `hidesSharedBackground` / `sharedBackgroundVisibility` | api | M | S-M | `MorphBarButtonGroup.tintColor`, `.hidesSharedBackground` |
| 8 | Back button beside leading items (`leftItemsSupplementBackButton`) | api | M | S | `leadingItemsSupplementBackButton` |
| 9 | Toolbar item swap on a push (measured on the simulator, not ported) | behaviour | M | M | port the scale / blur / fade swap for toolbars that change with the page |
| 10 | Bar minimization (`UIBarMinimization`, iOS 27) | api | M | L meas. | measure, then `minimization` on scaffold |
| 11 | Centered toolbar items (`.status`, flexible spaces on both sides) | api | M | M | `MorphToolbar.center`, `toolbarCenter` |
| 12 | Large Content Viewer for bar items at accessibility text sizes (bars cap text at 1.25) | a11y | M | M meas. | measure UIKit, then a long-press HUD |
| 13 | Search placements in the nav bar (integrated, button) | api | M | L | search family |
| 14 | `largeTitleDisplayMode.inline` / `.inlineLarge` | api | L-M | S meas. | add after a capture |
| 15 | Selected / toggle bar item | api | L-M | S meas. | `MorphBarButton.selected` |
| 16 | Badge motion (fade in / out, follows the bar's update) | look | L-M | S meas. | measure, then animate on the bar spring |
| 17 | `preferredMenuElementOrder` on bar menus | api | L | S | `MorphBarButton.menuOrder` |
| 18 | `largeTitle` text, attributed / view subtitles, `prompt`, `backBarButtonItem` | api | L | S-M | add `largeTitle` first |
| 19 | Translation kick and bridge layer of `GlassContainerToolbarPTSettings` (read, unported) | behaviour | L-M | M | replay against navsegb births once ported |

## Breaking changes before 1.0

Done: `largeTitleDisplayMode` enum, `backButtonTitle`, `backButtonSemanticLabel`, `leading` as a
list, `MorphBarButtonGroup.style`, `MorphNavigationBar.drift` / `titleExitShift` internal.

Open:
- `MorphNavigationConfig.barHiding` and `MorphNavigationBarHiding` -> `@internal` (apps cannot construct one).
- `leading` replacing the back button: keep, and add `leadingItemsSupplementBackButton` before apps depend on the replace-only rule.

## Behaviour fidelity

### navigation-bar

| dimension | grade | evidence | open items |
|---|---|---|---|
| layout | read | metrics [layout, device] bars.md "Spec - metrics"; title room replayed within 0.5 pt (test/navigation_title_layout_test.dart, test/fixtures/ios27-device/navigation/title-room.json); large title snap (test/navigation_motion_test.dart, `title-drag-partial*`) | subtitle fonts, large subtitle layout and badge placement read from UIKit, not recorded; `largeSubtitleHeight` formula unchecked; title drop threshold unmeasured; side inset 20 on 440 pt not applied |
| states | replayed | disabled colors vs device peaks (test/disabled_test.dart, test/fixtures/ios27-device/disabled/disabled.json); held capsule lift (test/navigation_motion_test.dart, `bars/item-hold.jsonl`) | selected state has no API; how UIKit tints a fused prominent + plain capsule is unmeasured |
| transitions | approx | push / pop per side and births replayed (test/bar_segment_test.dart, test/bar_survivor_test.dart, `bars/navseg*`, `navsegb*`); drift (test/navigation_motion_test.dart, `pop-edge-drift-*`); inline title and edge effect fades (`title-*`, simulator and device) | scroll edge effect fades in the bar where UIKit slides it with each page (declared); newborn's late start not reproduced; the `translationKick` (kickFactor 6) and `bridgeLayer` springs in test/fixtures/ios27-device/bars/tuning.txt are read by no morph class (inference: the kick is the survivor's swing bars.md lists as not reproduced); `transition.delayFactor` 0.33 is replaced by fitted delays; the inline title's fade duration does not scale with scroll speed (`titleTransition` maxScrollVelocity / min- and maxDurationFactor in tuning.txt; morph uses the two fitted springs); edge-swipe commit bar delay 0.027 s not replayed; bar hiding during search is a simulator fit of a bar without items (APPROXIMATION in `MorphNavigationBarHiding`) |
| boundaries | missing | too-large groups (`oversizedInPlace`, replayed); title truncation and drop (title-room.json) | no overflow: items that do not fit overlap; back title never shortens |
| configuration | read | `largeTitleDisplayMode.automatic` resolution, back display modes, prominent style follow the SDK header semantics (test/navigation_api_test.dart); edge effect styles vs device layers (test/scroll_edge_effect_test.dart) | combinations not recorded |
| events | measured | bar menu tap / hold timing [device] (menu-button.md "Bar item menu as primary action"); back menu recognition 0.4 s, open 0.595 s (bars.md "Spec - back menu") | test/back_menu_test.dart pins the constants, no replay |
| input | measured | press lift replayed (`item-hold.jsonl`); back menu hold outcomes [device, 7 holds]; second pointer (test/bar_items_test.dart) | back menu timing not replayed |
| mutation | unbacked | object lifecycle per change (bars.md "Spec - object lifecycle"; test/bar_lifecycle_test.dart) | an id that returns while leaving revives its capsule (lib/src/widgets/bar_motion.dart:538), not measured against UIKit |
| accessibility | missing | semantics and back menu long press (test/navigation_bar_test.dart, test/back_menu_test.dart); RTL mirror | Large Content Viewer missing; text scale cap 1.25 borrowed from the tab bar (lib/src/widgets/bar_items.dart:301); bar snaps under Reduce Motion where UIKit cross-fades it; Increase Contrast for bars unmeasured |
| optics | approx | edge effect filters vs device layers (test/scroll_edge_effect_test.dart, `bars/scroll-edge.json`); capsule glass from the renderer (glass-optics.md) | flat-tier edge effect and the half-resolution raise are declared NEAR; flat capsule shadow 6 and rim 0.5 not measured (lib/src/widgets/bar_items.dart:2565, 2571) |
| platform | missing | RTL (test/navigation_bar_test.dart); Android glyph raster (bars.md "Android rendering cost") | 440 pt side inset; landscape (compact height) bar unmeasured; RTL not recorded natively |
| performance | measured | Pixel 6a nested push / pop / enter p95 within 16.67 ms, energy per variant (docs/performance.md, tool/ios_reference/perf/2026-10-13-bench-nav-tip) | a new page's first layout over budget 1.2 - 1.3 percent |

### toolbar

| dimension | grade | evidence | open items |
|---|---|---|---|
| layout | replayed | 28 pt insets [tuning + device]; capsule rects replayed (test/bar_motion_test.dart, `bars/toolbar-swap.jsonl`) | compact height insets (tuning 24 / 38) not applied |
| states | replayed | disabled toolbar items (test/disabled_test.dart) | - |
| transitions | missing | `setToolbarItems` replayed (test/bar_motion_test.dart, test/bar_segment_test.dart `navseg-toolbar`, test/bar_survivor_test.dart `navsegb-toolbar*`) | the item swap with a push is not ported |
| boundaries | missing | oversized group in place (replayed) | no overflow |
| configuration | replayed | sides filling / emptying in place (test/bar_segment_test.dart) | - |
| events | measured | shared with bar items | - |
| input | measured | items stay put during an edge swipe [sim] (bars.md "Not reproduced / open") | not on the device |
| mutation | unbacked | flip-flop test (test/bar_items_test.dart) | revive rule as for the nav bar |
| accessibility | missing | as navigation-bar | as navigation-bar |
| optics | approx | no edge effect under a floating toolbar, as UIKit (bars.md); renderer glass | as navigation-bar |
| platform | missing | keyboard inset 8 (tuning `phoneKeyboard`) | compact height layout |
| performance | measured | toolbar morph in example/lib/perf/navigation_stage_bench.dart (docs/performance.md) | - |
