# Bars - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIBarButtonItem`, `UIBarButtonItem.Badge`, `UIBarButtonItemGroup`, `UINavigationItem`,
`UINavigationBar`, `UIToolbar`, `UIViewController.toolbarItems`, `UIBarMinimization`; SwiftUI
`toolbar`, `ToolbarItem(placement:)`, `ToolbarItemGroup`, `ToolbarSpacer`, `DefaultToolbarItem`,
`sharedBackgroundVisibility`, `navigationTitle` / `navigationSubtitle`, `toolbarTitleDisplayMode`,
`toolbarRole`, `toolbarTitleMenu`, `toolbarVisibility`, `toolbarMinimizationBehavior`,
`visibilityPriority`. morph: `MorphBarButton`, `MorphBarButtonGroup`, `MorphBarStyle`,
`MorphBarMetrics`, `MorphBarMenuTuning`, `MorphBarMotion`, `MorphBarTransitionSpec`,
`MorphBarCapsuleFrame` / `MorphBarCapsuleLayout` / `MorphBarItemFrame` / `MorphBarItemLayout`,
`MorphNavigationBar`, `MorphNavigationBarMetrics`, `MorphLargeTitle`,
`MorphLargeTitleScrollPhysics`, `MorphToolbar`, `MorphToolbarMetrics`, plus the bar fields of
`MorphNavigationScaffold` / `MorphNavigationConfig`. Passport: [../bars.md](../bars.md),
[../navigation-pages.md](../navigation-pages.md).

Sources: iPhoneOS27.0.sdk `UIBarButtonItem.h`, `UIBarButtonItemBadge.h`, `UIBarButtonItemGroup.h`,
`UINavigationItem.h`, `UINavigationBar.h`, `UIToolbar.h`, `UIBarMinimization.h`,
`UIBarAppearance.h`, UIKit and SwiftUI `.swiftinterface`. LG = new with Liquid Glass (iOS 26/27).

## UIKit

### UIBarButtonItem

| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIBarButtonItem.init(title:/image:/primaryAction:/menu:)`, iOS 2+/14+ | item with text or image | `MorphBarButton(label:, icon:)` | icon is a Widget (stronger than UIImage); a button cannot carry both label and icon (UIKit `init(title:image:...)` shows image in bar, title in overflow) | keep |
| `.style` `.plain` / `.prominent` (prominent iOS 26, LG; `.done` deprecated -> `.prominent`) | tinted glass item | `MorphBarButtonGroup.prominent` (bool, per capsule) | UIKit sets style per item, morph per group; bool instead of enum | rename -> `MorphBarButtonGroup.style: MorphBarButtonStyle.plain/.prominent` (optional, see Breaking) |
| `.tintColor`, iOS 5+ | item color; on a prominent item tints the glass | none per item (`MorphBarStyle.prominentColor` / `foregroundColor` per bar) | no per-item / per-group tint | add `MorphBarButtonGroup.tintColor` (Color?) |
| `.isEnabled` (UIBarItem), iOS 2+ | disabled look, no action | `MorphBarButton.enabled` | - | keep |
| `.primaryAction` / target-action, iOS 14+ | tap action | `MorphBarButton.onPressed` | Flutter idiom | keep |
| `.menu`, iOS 14+ | menu; tap opens when no primary action, long press otherwise | `MorphBarButton.menu` (List<MorphMenuEntry>) | matches measured behaviour | keep |
| `.preferredMenuElementOrder`, iOS 16+ | menu row order | none on bar button (`MorphMenuOrder` exists for `MorphMenuButton`) | not forwarded | add `MorphBarButton.menuOrder` |
| `.changesSelectionAsPrimaryAction`, `.isSelected`, iOS 15+ | toggle / pull-down selection item | none | no selected look | add `MorphBarButton.selected` (bool) |
| `.isHidden`, iOS 16+ | hide without removing | none | declarative: omit the button | skip (omit from list; id keeps the morph) |
| `.width`, `.possibleTitles`, legacy | fixed item width | none (`MorphBarMetrics.minButtonWidth`) | - | skip (metrics cover it) |
| `.customView`, iOS 2+ | arbitrary view | `MorphBarButton.icon` (any Widget, sized `iconSize`) | label must be String | keep; consider `child` later |
| `.badge` / `UIBarButtonItem.Badge.count/.string/.indicator`, `foregroundColor`, `backgroundColor`, `font`, iOS 26 (LG) | badge on a bar item | none | missing; common (inbox, cart) | add `MorphBarButton.badge: MorphBarBadge?` with `.count(int)`, `.string(String)`, `.indicator()`, colors |
| `.hidesSharedBackground`, iOS 26 (LG) | item drawn without glass capsule | none | missing (title-like or avatar items) | add `MorphBarButtonGroup.hidesSharedBackground` (bool) |
| `.sharesBackground`, iOS 26 (LG) | item may not join neighbours' capsule | separate `MorphBarButtonGroup` | covered by grouping model | keep |
| `.identifier`, iOS 26 (LG) | matches items across transitions | `MorphBarButton.id` (required), `MorphBarButtonGroup.id` | morph requires id; UIKit heuristics when nil | keep (Dart `id`) |
| `UIBarButtonItem.flexibleSpace()` / `.flexibleSpace` system item, iOS 14+ | pushes items apart | `MorphToolbar.leading` / `.trailing` split | one flexible space only; no centered toolbar items | add `MorphToolbar.center` (List<MorphBarButtonGroup>) |
| `.fixedSpace(_:)`, `.fixedSpace()` (no width, iOS 26 LG), `UIBarButtonItemGroup.fixedSpace()` iOS 26 | split capsules | separate groups (`MorphBarMetrics.groupGap` 12) | covered | keep |
| `UIBarButtonItem.SystemItem` (`.done`, `.cancel`, `.add`, `.close`, `.search`, `.trash`, ...), iOS 2+ | localized title / SF symbol presets | none | apps pass label / icon | skip (no SF Symbols; app supplies icon); maybe later `MorphBarButton.close(...)` |
| `.visibilityPriority` (`.standard/.low/.high`), iOS 27 (LG) | which items survive when space is short | none | no overflow at all | add later with overflow (low) |
| `.isPaddingRemoved`, iOS 27 (LG) | no standard padding around item | none (`MorphBarMetrics.labelPadding/iconPadding` per bar) | - | skip (low) |
| `.menuRepresentation`, iOS 16+ | how item shows in overflow menu | none | needs overflow | skip until overflow |
| `.isSymbolAnimationEnabled`, `addSymbolEffect`, `setSymbolImage(_:contentTransition:)`, iOS 17+ | SF Symbol effects | none | no SF Symbols in Flutter | skip (app animates its icon Widget) |
| `creatingFixedGroup` / `creatingMovableGroup` / `creatingOptionalGroup`, iOS 16+ | customizable iPad toolbars | none | - | skip (iPad customization) |
| `UIBarButtonItem.back` look (system back item) | chevron + previous title | `MorphBarButton.back(label:)` | - | keep |

### UIBarButtonItemGroup

| UIKit API | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `init(barButtonItems:representativeItem:)`, iOS 9+ | items sharing one capsule | `MorphBarButtonGroup(buttons)` | - | keep |
| `.representativeItem`, `.isDisplayingRepresentativeItem` | collapsed form when space short | none | no compaction | skip (iPad / narrow; low) |
| `.isHidden`, iOS 16+ | hide group | none | omit group | skip (declarative) |
| `.alwaysAvailable`, iOS 16+ | never collapses into overflow | none | needs overflow | skip |
| `.menuRepresentation`, iOS 16+ | overflow form | none | needs overflow | skip |

### UINavigationItem

| UIKit API | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `.title`, iOS 2+ | inline / large title | `MorphNavigationScaffold.title`, `MorphNavigationConfig.title`, `MorphNavigationBar.title` | String only | keep |
| `.attributedTitle`, iOS 26 (LG) | styled title | none | - | skip (low; `titleView` covers custom looks) |
| `.titleView`, iOS 2+ | custom center view | none | missing (segmented control in bar is common) | add `MorphNavigationScaffold.titleView` / `MorphNavigationBar.titleView` (Widget?) |
| `.subtitle`, `.attributedSubtitle`, `.subtitleView`, iOS 26 (LG) | second line under inline title | none | missing, new LG pattern | add `subtitle` (String?) on scaffold, config, bar (needs device metrics) |
| `.largeTitle`, `.largeSubtitle`, `.largeAttributedSubtitle`, `.largeSubtitleView`, iOS 26 (LG) | text of the large title area distinct from inline | `MorphLargeTitle(title)`; no subtitle | no large subtitle; large text always = title | add `largeSubtitle`; `MorphLargeTitle(title, subtitle:)` |
| `.largeTitleDisplayMode` `.automatic/.always/.never/.inline` (inline iOS 17) | per-page large title | `MorphNavigationScaffold.largeTitle` (bool) | bool covers always/never only | rename -> `largeTitleDisplayMode: MorphLargeTitleDisplayMode` (Breaking) |
| `.prompt`, legacy | text above title | none | rarely used in LG | skip |
| `.backBarButtonItem`, legacy | custom back item of next page | none | - | skip (backButtonTitle + backButtonDisplayMode cover it) |
| `.backButtonTitle`, iOS 11+ | label of the NEXT page's back button | `MorphNavigationScaffold.backTitle`, `MorphNavigationConfig.backTitle` | same semantics, different name | rename -> `backButtonTitle` |
| `.backButtonDisplayMode` `.default/.generic/.minimal`, iOS 14+ | full title / "Back" / chevron only | none | missing; minimal is common in LG | add `backButtonDisplayMode: MorphBackButtonDisplayMode.standard/.generic/.minimal` |
| `.hidesBackButton`, `setHidesBackButton(_:animated:)` | hide back | implicit: non-null `leading` replaces back | no hide without replacing | add `hidesBackButton` |
| `.leftItemsSupplementBackButton`, iOS 5+ | leading items next to back | none (leading replaces back) | missing | covered by `leading` list + back (see leadingItemGroups) |
| `.backAction`, iOS 16+ | custom back action | Flutter `PopScope` (route `popGestureEnabled` honours it) | - | skip (Flutter idiom) |
| `.leftBarButtonItems` / `.rightBarButtonItems`, `set...(animated:)` | items per side | `leading` / `trailing` | animated always (ids drive it); `MorphNavigationBar.animate` exists | keep |
| `.leadingItemGroups` / `.trailingItemGroups`, iOS 16+ | groups per side | `leading` (ONE group?) / `trailing` (List) | leading is a single group, UIKit a list | reshape -> `leading: List<MorphBarButtonGroup>` (Breaking) |
| `.centerItemGroups`, iOS 16+ | center groups (browser/editor style) | none | - | skip for phones (low) |
| `.style` `.navigator/.browser/.editor`, iOS 16+ | title placement / center items | none | phone layout only navigator | skip (low; iPad) |
| `.customizationIdentifier`, iOS 16+ | user customization | none | - | skip (iPad) |
| `.pinnedTrailingGroup`, iOS 16+; SwiftUI `.topBarPinnedTrailing` iOS 27 (LG) | trailing group that never overflows | none | needs overflow | skip until overflow (low) |
| `.additionalOverflowItems`, `.overflowPresentationSource`, iOS 16+ | overflow "..." menu | none | missing overflow | add later `MorphNavigationBar` overflow (low/med) |
| `.titleMenuProvider`, iOS 16+ | menu under the title | none | missing | add `titleMenu: List<MorphMenuEntry>?` (reuse menu machinery) |
| `.renameDelegate`, `.documentProperties`, iOS 16+ | document rename / header | none | - | skip (document apps) |
| `.searchController`, `.preferredSearchBarPlacement` (`.automatic/.integrated/.stacked/.integratedCentered/.integratedButton`; integrated* iOS 26 LG), `.searchBarPlacement`, `.searchBarPlacementBarButtonItem` (iOS 26), `.searchBarPlacementAllowsToolbarIntegration` / `AllowsExternalIntegration` (iOS 26), `.hidesSearchBarWhenScrolling` | search in bars | `MorphSearchToolbar`, `MorphSearchField`, `MorphSearchTabBar` (bottom only) | no nav bar placements (stacked / integrated / button) | add `MorphNavigationScaffold.search` with `MorphSearchBarPlacement` (see search.md family) |
| `.standardAppearance` / `.scrollEdgeAppearance` / `.compactAppearance` / `.compactScrollEdgeAppearance` | bar background per state | `MorphBarStyle`, `MorphNavigationBar.edgeEffect` (`MorphScrollEdgeEffectStyle`), `scrolledUnder` | LG bars have no fill; scroll edge effect replaces appearances | keep |
| `.navigationBarMinimization` (`UIBarMinimization`: `minimizationBehavior` `.automatic/.never/.onScrollDown/.onScrollUp`, `safeAreaAdjustment`, `restorationBehavior` `.atScrollEdge`), iOS 27 (LG) | bar shrinks on scroll | none | missing, needs measurement | add `MorphNavigationScaffold.minimization` later (low/med, measure first) |

### UINavigationBar / UIToolbar / UIViewController

| UIKit API | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UINavigationBar.prefersLargeTitles`, iOS 11+ | stack-wide default for `.automatic` | none | per page only | add `MorphNavigationStack.prefersLargeTitles` with the display-mode enum |
| `UINavigationBar.items`, `pushItem/popItem`, `setItems(_:animated:)` | standalone bar stack | `MorphNavigationBar` (stateless input) + `MorphNavigationConfig` | declarative | keep |
| `UINavigationBar.tintColor` | bar tint | `MorphBarStyle.foregroundColor` / `prominentColor` | - | keep |
| `UIBarAppearance.overrideUserInterfaceStyle`, iOS 27 (LG) | force light/dark bar | `MorphBarStyle.light` / `.dark` passed as `style` | covered | keep |
| `UINavigationBar.preferredBehavioralStyle`, `currentNSToolbarSection` | Mac / Catalyst | - | - | skip |
| `UIToolbar.items`, `setItems(_:animated:)` | toolbar items | `MorphToolbar.leading` / `trailing` | always animated | keep |
| `UIViewController.toolbarItems`, `setToolbarItems(_:animated:)` | per-page toolbar | `MorphNavigationScaffold.toolbarLeading/toolbarTrailing`, `MorphNavigationConfig.toolbarLeading/toolbarTrailing` | two lists = one flexible space | keep (+ `toolbarCenter`, see ranked) |
| `UINavigationController.isToolbarHidden` / `setToolbarHidden(_:animated:)` | toolbar visibility | `MorphNavigationConfig.hasToolbar` (derived) | no explicit hide | keep (declarative) |

## SwiftUI

| SwiftUI API | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `ToolbarItem(placement:)` `.topBarLeading/.topBarTrailing` (iOS 14), `.navigation/.primaryAction/.cancellationAction/.confirmationAction` | side of nav bar | `leading` / `trailing` | semantic placements map to sides | keep |
| `.principal`, `.title` / `.largeTitle` / `.subtitle` / `.largeSubtitle` (iOS 26 LG) | custom views in the title slots | none | same as UIKit `titleView` / subtitle rows | add (see UIKit titleView / subtitle) |
| `.bottomBar` (iOS 14), `.status` | toolbar; status = center | `toolbarLeading` / `toolbarTrailing` | no center | add `toolbarCenter` |
| `.topBarPinnedTrailing`, iOS 27 (LG) | same as UIKit `pinnedTrailingGroup` | none | - | skip until overflow |
| `.keyboard` | keyboard accessory bar | none | - | skip (separate widget) |
| `ToolbarItemGroup` | several items, one capsule | `MorphBarButtonGroup` | - | keep |
| `ToolbarSpacer(.fixed / .flexible, placement:)`, iOS 26 (LG) | split capsules / push apart | groups / leading-trailing split | flexible only once | keep; center list covers the rest |
| `ToolbarContent.sharedBackgroundVisibility(_:)`, iOS 26 (LG) | same as `hidesSharedBackground` | none | - | add (same row) |
| `.badge(_:)` on toolbar item content, iOS 26 | same as `UIBarButtonItem.badge` | none | - | add (same row) |
| `ToolbarContent.visibilityPriority(_:)` (`ToolbarItemVisibilityPriority`), iOS 27 (LG) | same as UIKit row | none | - | skip until overflow |
| `DefaultToolbarItem(kind: .search, placement:)`, `searchToolbarBehavior(.minimize)`, iOS 26 (LG) | search in toolbar, minimized to a button | `MorphSearchToolbar` | check minimize-to-button in search family | see search.md |
| `navigationTitle(_:)`, `navigationTitle(Binding<String>)` (renamable, iOS 16) | title | `title` | - | keep |
| `navigationSubtitle(_:)`, iOS 26 (LG) | same as UIKit `subtitle` | none | - | add |
| `toolbarTitleDisplayMode(.automatic/.large/.inlineLarge/.inline)`, iOS 17 | large title modes; inlineLarge = large title text sitting in the bar | `MorphNavigationScaffold.largeTitle` bool | see UIKit row | enum incl. `inlineLarge` only if measured |
| `toolbarRole(.automatic/.navigationStack/.browser/.editor)`, iOS 16 | same as `UINavigationItem.style` | none | - | skip (low) |
| `toolbarTitleMenu { }`, iOS 16 | same as `titleMenuProvider` | none | - | add `titleMenu` |
| `toolbarVisibility(_:for:)`, iOS 18; `navigationBarHidden` | hide nav bar / bottom bar | none for nav bar; toolbar implicit | cannot hide the stack's nav bar per page | add `MorphNavigationScaffold.navigationBarHidden` (low/med) |
| `toolbarBackgroundVisibility(_:for:)` iOS 18, `scrollEdgeEffectStyle(_:for:)` iOS 26 (LG) | bar background / edge effect | `edgeEffect: MorphScrollEdgeEffectStyle?` | - | keep |
| `toolbarForegroundStyle(_:for:)` | bar foreground color | `MorphBarStyle.foregroundColor` | - | keep |
| `toolbarMinimizationBehavior` / `toolbarMinimizationRestoration` / `toolbarMinimizationSafeAreaAdjustment`, iOS 27 (LG) | same as `UIBarMinimization` | none | - | same as UIKit row |
| `matchedTransitionSource(id:in:)` on `ToolbarContent`, iOS 26 (LG) | zoom from a toolbar item | none | see navigation.md (zoom from bar item) | add there |
| `toolbarItemHidden(_:)` | hide item | omit | declarative | skip |

## Not relevant for Flutter

- `UIBarItem` title text attributes / `setTitleTextAttributes`, `setBackgroundImage(...barMetrics:)`, position adjustments, `UIBarButtonItemAppearance`: legacy appearance proxies; `MorphBarStyle` + `MorphBarMetrics` replace them.
- `NSCoding` initializers, `UIBarPositioning`, `UINavigationBarDelegate` / `UIToolbarDelegate`: UIKit plumbing.
- `NSToolbar` bridging, `UINavigationBarNSToolbarSection`, `preferredBehavioralStyle`: Mac Catalyst only.
- `UIBarButtonItem.SystemItem.pageCurl`, `.writingTools`: legacy / system feature.
- `landscapeImagePhone`, `largeContentSizeImage`: Flutter Semantics and MediaQuery text scale cover accessibility; `MorphBarMetrics.maxTextScale` caps bar text.
- `UIBarButtonItemGroup` customization (movable / optional groups): iPad user customization.

## morph-only API

- `MorphBarMetrics` (`navigation`, `toolbar`), `MorphNavigationBarMetrics`, `MorphToolbarMetrics`: measured geometry - keep.
- `MorphBarStyle` (light / dark tables, disabled colors): keep (replaces appearances).
- `MorphBarMenuTuning` (`recognition`, `open`, `menu`): keep.
- `MorphBarMotion`, `MorphBarTransitionSpec`, `MorphBarCapsuleFrame`, `MorphBarCapsuleLayout`, `MorphBarItemFrame`, `MorphBarItemLayout`: pure motion and its frames - keep exported for custom painters/tests, but flag: an app developer never needs them; consider moving to `foundation`-level or an `advanced` export.
- `MorphLargeTitle` + `MorphLargeTitleScrollPhysics`: building blocks of the scaffold's large title - keep.
- `MorphNavigationBar.titleVisible`, `.scrolledUnder`, `.animate`, `.sideInset`: standalone-bar inputs - keep.
- `MorphNavigationBar.titleExitShift`, `MorphNavigationBar.drift`: stack internals on a public widget - flag (hide).
- `MorphToolbar.sideInset` / `bottomInset` / `keyboardInset`: keep.

## Ranked gaps

| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | Bar item badge (`UIBarButtonItem.badge`, iOS 26) | high | S/M | add `MorphBarButton.badge: MorphBarBadge?` (`.count`, `.string`, `.indicator`, colors); measure badge geometry on device |
| 2 | Subtitle / large subtitle (iOS 26) | high | M | add `subtitle`, `largeSubtitle` to scaffold, config, `MorphNavigationBar`, `MorphLargeTitle`; measure layout and title motion |
| 3 | `backButtonDisplayMode` (minimal / generic) + `hidesBackButton` | high | S | add `MorphBackButtonDisplayMode.standard/.generic/.minimal` and `hidesBackButton` on scaffold / config |
| 4 | `titleView` (custom center widget, e.g. segmented control) | med/high | M | add `titleView: Widget?`; title motion rides the same swap |
| 5 | Per-item tint and `hidesSharedBackground` | med | S/M | add `MorphBarButtonGroup.tintColor`, `MorphBarButtonGroup.hidesSharedBackground` |
| 6 | Multiple leading groups (leadingItemGroups) incl. back + items | med | M | `leading: List<MorphBarButtonGroup>`, back button prepended unless hidden |
| 7 | Centered toolbar items (flexible space both sides, `.status`) | med | M | add `MorphToolbar.center`, `toolbarCenter` |
| 8 | `largeTitleDisplayMode` enum + `prefersLargeTitles` | med | S | `MorphLargeTitleDisplayMode.automatic/.always/.never/.inline`, stack default |
| 9 | Title menu (`titleMenuProvider` / `toolbarTitleMenu`) | med | M | add `titleMenu: List<MorphMenuEntry>?` reusing the menu host |
| 10 | Search placements in the nav bar (integrated / stacked / button) | med | L | coordinate with search family |
| 11 | Selected / toggle bar item | low/med | S | add `MorphBarButton.selected` |
| 12 | Hide nav bar per page (`toolbarVisibility`) | low/med | M | add `navigationBarHidden` on scaffold / config |
| 13 | Bar minimization (iOS 27 `UIBarMinimization`) | low/med | L | measure first; add `minimization` later |
| 14 | Overflow / `visibilityPriority` / `pinnedTrailingGroup` / `additionalOverflowItems` | low | L | defer (narrow-width and iPad) |
| 15 | `preferredMenuElementOrder` on bar menus | low | S | add `MorphBarButton.menuOrder` |

## Breaking changes before 1.0

- `MorphNavigationScaffold.largeTitle` (bool) -> `largeTitleDisplayMode: MorphLargeTitleDisplayMode` (UIKit `largeTitleDisplayMode`, SwiftUI `toolbarTitleDisplayMode`; room for `.inline` / `.automatic`).
- `MorphNavigationScaffold.backTitle`, `MorphNavigationConfig.backTitle` -> `backButtonTitle` (same semantics as `UINavigationItem.backButtonTitle`, set on the page below).
- `MorphNavigationStack.backLabel`, `MorphNavigationScaffold.backLabel` -> `backButtonSemanticLabel` (it is the spoken label, easily confused with `backTitle`).
- `MorphNavigationBar.leading`, `MorphNavigationScaffold.leading`, `MorphNavigationConfig.leading` (single `MorphBarButtonGroup?`) -> `List<MorphBarButtonGroup>` like `trailing` and `leadingItemGroups`; the back button no longer disappears when leading items exist (opt out via `hidesBackButton`).
- `MorphBarButtonGroup.prominent` (bool) -> `style: MorphBarButtonStyle.plain/.prominent` (mirror `UIBarButtonItem.Style`; optional, low value alone - do it together with `tintColor`).
- `MorphNavigationBar.drift` exposes `MorphNavigationBarDrift`, which `lib/widgets.dart` does not export (public parameter of an unexported type); hide `drift` and `titleExitShift` behind the stack (internal constructor or `@internal`) or export the type.
