# Tab bar - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UITabBarController` (+ `UITabBarControllerDelegate`), `UITab`, `UITabGroup`, `UISearchTab`,
`UITabAccessory`, `UITabBarItem`, `UITabBar`, `UITabBarController.Sidebar`; SwiftUI `TabView`, `Tab`,
`TabRole`, `TabSection`, `tabViewStyle`, `tabBarMinimizeBehavior`, `tabViewBottomAccessory`,
`TabViewBottomAccessoryPlacement`, `badge`, `tabViewSearchActivation`, `defaultVisibility`,
`customizationID`. morph: `MorphTabBar`, `MorphTabItem`, `MorphTabBarStyle`, `MorphSearchTabBar`,
`MorphLensMotion`, `MorphLensSlot`, `MorphLensTuning`, `MorphTouchGlowMotion`, `MorphWidgetsTheme.tabBar`,
`MorphTabBarMinimizeBehavior`, `MorphContentScroll`, `MorphContentScrollScope`, `MorphTabAccessoryEnvironment`,
`MorphScrollAway`, `MorphTabBarMinimizeMotion`, `MorphTabBarMinimizeTuning`.
Passports: [../tab-bar.md](../tab-bar.md), [../search-tab-bar.md](../search-tab-bar.md),
[../tab-bar-minimize.md](../tab-bar-minimize.md).

Shape difference: UIKit's tab bar is owned by a container controller that also owns the pages
(`tabs`, `viewControllerProvider`). `MorphTabBar` is a bare control (items + index + callback); the
app owns the pages (IndexedStack or similar). That is the Flutter idiom (`NavigationBar`,
`CupertinoTabBar`) and stays. `MorphNavigationScaffold` / `MorphNavigationStack` do NOT host a tab bar.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UITabBarController.tabs` / `init(tabs:)` (iOS 18) | the tab list | `MorphTabBar.items` (`List<MorphTabItem>`) | 2..5 items only, no pages | keep |
| `UITabBarController.setTabs(_:animated:)` (iOS 18) | animated insert/remove | none (list swap re-creates the lens when the count changes) | no animated change of the tab set | skip (unmeasured, rare) |
| `UITabBarController.selectedTab` / `selectedIndex` (iOS 18 / legacy) | current tab | `MorphTabBar.selected` (int) | index, not identifier | keep (Flutter idiom; matches `MorphSegmentedControl.selected`) |
| `UITabBarController.tabForIdentifier(_:)`, `UITab.identifier` (iOS 18) | stable ids | none | not needed with index + app-owned list | skip (index idiom) |
| `UITabBarControllerDelegate.tabBarController(_:shouldSelectTab:)` (iOS 18) | veto a selection | `MorphTabBar.onChanged` + controlled `selected` (the lens reconciles back when the parent keeps the old index) | - | keep |
| `UITabBarControllerDelegate.tabBarController(_:didSelectTab:previousTab:)` (iOS 18) | selection notification, including a tap on the already selected tab | `MorphTabBar.onChanged` (only fires when the index changes) | no callback for a re-tap of the selected tab (UIKit apps scroll to top / pop to root) | add `MorphTabBar.onReselected` (`VoidCallback`/`ValueChanged<int>`) |
| `UITabBarController.mode` `.automatic/.tabBar/.tabSidebar` (iOS 18) | bar vs iPad sidebar | none | bar only | skip (see Sidebar below) |
| `UITabBarController.tabBarMinimizeBehavior` `.automatic/.never/.onScrollDown/.onScrollUp` (iOS 26, NEW) | bar collapses to the selected tab while scrolling | `MorphTabBar.minimizeBehavior` / `MorphSearchTabBar.minimizeBehavior` (`MorphTabBarMinimizeBehavior`), scrolls through `contentScroll` (`MorphContentScroll`) or `MorphContentScrollScope` (UIKit observes the content scroll view itself) | ported from UIKit's code, not yet recorded (tab-bar-minimize.md); `automatic` resolves to `never` | done |
| `UITabBarController.bottomAccessory` / `setBottomAccessory(_:animated:)`, `UITabAccessory(contentView:)` (iOS 26, NEW) | glass accessory above the bar (mini player), merges inline when minimized | `MorphTabBar.bottomAccessory` / `MorphSearchTabBar.bottomAccessory` (Widget) | geometry approximated, no insertion animation | done |
| `UITabAccessory.Environment` `.unspecified/.none/.regular/.inline`, `UITraitTabAccessoryEnvironment` (iOS 26, NEW) | accessory layout it is in | `MorphTabAccessoryEnvironment.{none, regular, inline}`, `MorphTabAccessoryEnvironment.of(context)` | UIKit case names (the SwiftUI `.expanded` is `regular`) | done |
| `UITabBarController.contentLayoutGuide` (iOS 26, NEW) | area content should avoid | none public (`MorphTabBarMetrics` is `@internal`) | app must hard-code 62 + 21 + safe area to pad lists | add `MorphTabBar.extentFor(...)` like `MorphToolbar.extentFor` |
| `UITabBarController.isTabBarHidden` / `setTabBarHidden(_:animated:)` (iOS 18) | hide the bar | none (app removes the widget, no motion) | no animated hide | add `MorphTabBar.hidden` (animated) - unmeasured |
| `UITabBarController.prominentTabIdentifier` / `setProminentTabIdentifier(_:animated:)` (iOS 27, NEW) | one tab drawn prominent | none | missing, look unmeasured | add `MorphTabItem.prominent` (bool) after capture |
| `UITabBarController.performBatchUpdates(_:)` (iOS 27, NEW) | batch tab mutations | none | declarative rebuild covers it | skip (Flutter rebuild is already batched) |
| `UITabBarController.compactTabIdentifiers`, `customizationIdentifier` (iOS 18) | which tabs show in compact / customization persistence | none | sidebar-era customization | skip (no sidebar) |
| `UITabBarController.customizableViewControllers`, `moreNavigationController` (legacy) | "More" tab, user reordering | none | max 5 items, no More | skip (legacy; the floating bar does not use More) |
| `UITab(title:image:identifier:viewControllerProvider:)` (iOS 18) | tab item | `MorphTabItem(icon:, label:)` | `title` vs `label`; `UIImage` vs `IconData` | keep `label` (Flutter `NavigationDestination.label`) |
| `UITab.image` (iOS 18) | glyph | `MorphTabItem.icon` (`IconData`) | IconData only: an app with SVG/asset icons cannot use the bar (the selected copy renders the glyph as text) | add a Widget icon path (`MorphTabItem.iconWidget`, tinted through `IconTheme`) |
| `UITab.selectedImage` (iOS 26.1, NEW) / `UITabBarItem.selectedImage` (iOS 7) | glyph inside the lens (e.g. filled symbol) | none | missing; common (SF Symbols `.fill` variants) | add `MorphTabItem.selectedIcon` (as `NavigationDestination.selectedIcon`) |
| `UITab.isEnabled` (iOS 18.4) / `UITabBarItem.isEnabled` (legacy) | disabled tab | `MorphTabItem.enabled` | measured: no visual change | keep |
| `UITab.badgeValue` (iOS 18) / `UITabBarItem.badgeValue` (legacy) | badge text | none | missing; very common | add `MorphTabItem.badge` (`String?`), look to capture |
| `UITabBarItem.badgeColor`, `setBadgeTextAttributes(_:for:)` (iOS 10) | badge look | none | follows badge | add `MorphTabBarStyle.badgeColor`, `badgeTextColor` |
| `UITab.subtitle` (iOS 18) | secondary text (sidebar) | none | sidebar only | skip (no sidebar) |
| `UITab.isHidden`, `hiddenByDefault`, `allowsHiding` (iOS 18) | user/app hiding | none | app filters `items` | skip (declarative list) |
| `UITab.preferredPlacement` `UITab.Placement` (iOS 18) | sidebar/bar placement | none | sidebar concept | skip |
| `UITab.userInfo`, `parent`, `viewController` (iOS 18) | plumbing | none | - | skip |
| `UITabGroup` (`children`, `selectedChild`, `displayOrder`, `sidebarAppearance`) (iOS 18; `isSidebarDestination` 26, `collapsedByDefault` 26.1) | nested tabs (sidebar sections) | none | sidebar concept | skip |
| `UISearchTab(viewControllerProvider:)` (iOS 18), `UISearchTab.identifier` (iOS 26.4) | search tab | `MorphSearchTabBar` (separate widget) | search tab is a different widget, not an item kind | keep (see Breaking changes for naming) |
| `UISearchTab.automaticallyActivatesSearch` (iOS 26, NEW) | tab turns into a field on selection (circle at trailing edge) | `MorphSearchTabBar` models only `true`; `false` = an ordinary `MorphTabItem` | documented in dartdoc | keep |
| `UITabBar.tintColor` / `unselectedItemTintColor` (iOS 5 / 10) | selected / unselected tint | `MorphTabBarStyle.selectedColor` / `color` | names differ | keep (style table; `selectedColor`/`color` is clear) |
| `UITabBar.leadingAccessoryView` / `trailingAccessoryView` | bar accessories | none | header: `API_UNAVAILABLE(ios)` (tvOS 13 only) - the passport's API list is wrong here | skip (not on iOS) |
| `UITabBar.itemPositioning`, `itemWidth`, `itemSpacing` (iOS 7) | layout tweaks | none (measured pitch, widened to the label) | - | skip (measured geometry is the spec) |
| `UITabBarItem.standardAppearance` / `UITabBarAppearance` (iOS 13) | per-item/bar appearance objects | `MorphTabBarStyle`, `MorphWidgetsTheme.tabBar` | - | keep (style + theme is the Flutter appearance proxy) |
| `UITabBarController.sidebar` / `UITabBarControllerSidebar` (iOS 18; `isAvailable`, `preferredPlacement` iOS 27) | iPad/Mac sidebar | none | not an iPhone Liquid Glass control | skip (separate family if ever: iPad split layouts) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `TabView(selection:content:)` with `Tab` (iOS 18) | same as UIKit `tabs` + `selectedTab` | `MorphTabBar.items` + `selected` | value-typed selection vs index | keep (index) |
| `Tab(_:systemImage:value:role:)` (iOS 18) | same as `UITab` | `MorphTabItem` | - | same as UIKit `UITab(...)` row |
| `TabRole.search` (iOS 18) | search tab | `MorphSearchTabBar` | - | same as UIKit `UISearchTab` row |
| `TabRole.prominent` (iOS 27, NEW) | prominent tab | none | - | same as UIKit `prominentTabIdentifier` row |
| `tabViewSearchActivation(.automatic/.searchTabSelection)` (iOS 26, NEW) | = `automaticallyActivatesSearch` | `MorphSearchTabBar` | - | same as UIKit row |
| `TabSection` (iOS 18), `sectionActions`, `defaultSectionExpansion` | sidebar sections | none | sidebar | skip |
| `tabViewStyle(.sidebarAdaptable / .tabBarOnly)` (iOS 18) | = `mode` | none | bar only | skip |
| `tabBarMinimizeBehavior(_:)` `TabBarMinimizeBehavior.automatic/onScrollDown/onScrollUp/never` (iOS 26, NEW) | = UIKit | `MorphTabBarMinimizeBehavior` | - | same as UIKit row |
| `toolbarMinimizationBehavior(_:for:)`, `toolbarMinimizationSafeAreaAdjustment`, `toolbarMinimizationRestoration` (iOS 27, NEW; UIKit `UIBarMinimization`, nav bar only) | generalised bar minimisation with safe-area reflow and restore-at-edge | none | iOS 27 extends minimisation to the nav bar (bars family) | the tab bar keeps UIKit's own `MorphTabBarMinimizeBehavior` (as `UITabBarController` does); `MorphScrollAway` is the shared interaction a nav bar minimization can reuse |
| `tabViewBottomAccessory(content:)` (iOS 26, NEW), `tabViewBottomAccessory(isEnabled:content:)` (iOS 26.1) | = `bottomAccessory` | `bottomAccessory` | - | same as UIKit row; `isEnabled` = null Widget in Flutter |
| `EnvironmentValues.tabViewBottomAccessoryPlacement` `.inline/.expanded` (iOS 26, NEW) | = `UITabAccessory.Environment` | `MorphTabAccessoryEnvironment.of(context)` | UIKit names kept (`regular` = `.expanded`) | done |
| `badge(_: Int / Text / String)` on Tab (iOS 18) | badge | none | count or text | same as UIKit `badgeValue` row (`String?`; app formats counts) |
| `TabContent.disabled(_:)` (iOS 18) | disabled tab | `MorphTabItem.enabled` | - | keep |
| `TabContent.hidden(_:)`, `defaultVisibility(_:for:)`, `customizationID`, `tabViewCustomization` (iOS 18) | user customisation / visibility | none | - | skip (declarative list) |
| `tabPlacement`, `defaultTabBarPlacement`, `TabBarPlacement`, `isTabViewSidebarAvailable` (iOS 27) | sidebar/ornament | none | - | skip |
| `tabViewSidebarHeader/Footer/BottomBar` (iOS 18) | sidebar chrome | none | - | skip |

## Not relevant for Flutter
- `UITabBarItem` system items (`UITabBarSystemItem`), `titlePositionAdjustment`, `backgroundImage`, `selectionIndicatorImage`, `shadowImage`, `barStyle`, `isTranslucent`: pre-glass appearance proxies.
- `UITabBar.beginCustomizingItems`, customizing delegate callbacks, "More" controller: legacy customisation sheet.
- Drag-and-drop on tabs (`operationForAcceptingItemsFromDropSession`), sidebar delegate (swipe actions, context menus, drag items): sidebar/iPad only.
- `UITab` popover/spring-loading/accessibility categories: Flutter `Semantics` (bar is `SemanticsRole.tabBar`, items `SemanticsRole.tab`).
- `tabBarControllerSupportedInterfaceOrientations`, animated transition delegate: app/Navigator business.
- NSCoding, Mac Catalyst idiom, tvOS/visionOS-only members.

## morph-only API
- `MorphTabBar.maxTextScale` (1.25, measured) - keep.
- `MorphTabBarStyle.barColor/shadowColor/platterColor/liftedLensColor/lensBorderColor/blurSigma` - renderer inputs, keep.
- `MorphLensMotion`, `MorphLensSlot`, `MorphLensTuning` (`.tabBar`, `.segmented`) - pure motion, shared with segmented control; keep.
- `MorphTouchGlowMotion` - keep.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | badge on a tab | high (most tab apps) | M (capture badge look on device) | add `MorphTabItem.badge` + `MorphTabBarStyle.badgeColor/badgeTextColor` |
| 2 | re-tap of the selected tab not reported | high (scroll to top / pop to root) | S | add `MorphTabBar.onReselected` (also on `MorphSearchTabBar`) |
| 3 | selected glyph variant | med-high | S | add `MorphTabItem.selectedIcon` |
| 4 | bar extent for content padding | med-high | S | add `MorphTabBar.extentFor(...)` (mirror `MorphToolbar.extentFor`) |
| 5 | non-IconData icons (SVG, images) | med | M (selected copy draws glyph as text) | add Widget icon path tinted via `IconTheme` |
| 6 | `tabBarMinimizeBehavior` | med (iOS 26 hallmark) | L (measure, scroll coupling) | done (0.8.0), recording pending |
| 7 | `bottomAccessory` + placement env | med (media apps) | L (measure, inline merge) | done (0.8.0), recording pending |
| 8 | animated hide | low-med | M | add `MorphTabBar.hidden` |
| 9 | prominent tab (iOS 27) | low (new, look unknown) | M | add `MorphTabItem.prominent` after capture |
| 10 | sidebar / groups / customisation | low on iPhone | L | skip |

## Breaking changes before 1.0
- `MorphSearchTabBar.searching` / `onSearchingChanged` -> `active` / `onActiveChanged` (UIKit `UISearchController.isActive`; matches `MorphSearchToolbar.onActiveChanged`). See search.md.
- `MorphSearchTabBar.onQueryChanged` -> `onChanged` (matches `MorphSearchField.onChanged`, `MorphSearchToolbar.onChanged`).
- Optional: `MorphTabItem.icon` stays `IconData`, but if a Widget path is added later as a second field it is non-breaking; making `icon` a Widget would be breaking - decide before 1.0.
- `MorphTabBar.selected` - keep (consistent with `MorphSegmentedControl.selected`); renaming the family to `selectedIndex` is possible but not recommended.
