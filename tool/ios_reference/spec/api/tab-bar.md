# Tab bar - API parity (UIKit / SwiftUI iOS 27.1 vs morph)

Native: `UITabBarController` (+ `UITabBarControllerDelegate`), `UITab`, `UITabGroup`, `UISearchTab`,
`UITabAccessory`, `UITabBarItem`, `UITabBar`, `UITabBarController.Sidebar`; SwiftUI `TabView`, `Tab`,
`TabRole`, `TabSection`, `tabViewStyle`, `tabBarMinimizeBehavior`, `tabViewBottomAccessory`,
`TabViewBottomAccessoryPlacement`, `badge`, `tabViewSearchActivation`, `defaultVisibility`,
`customizationID`. Headers: iPhoneOS27.1.sdk.

morph, public (test/api/public_api.txt): `MorphTabBar`, `MorphTabItem`, `MorphTabRole`, `MorphBadge`,
`MorphTabBarAppearance`, `MorphSearchTabBar`, `MorphTabBarMinimizeBehavior`, `MorphContentScroll`,
`MorphContentScrollScope`, `MorphTabAccessoryEnvironment`; theming through `MorphTheme` /
`MorphThemeData` (`tint`, `appearances`). Internal (lib/src, not exported): `MorphTabBarMetrics`,
`MorphLensMotion`, `MorphLensTuning.tabBar`, `MorphTouchGlowMotion`, `MorphScrollAway`,
`MorphTabBarMinimizeMotion`, `MorphTabBarMinimizeTuning`, `MorphTabBarChrome`,
`MorphTabBarGroupGeometry`.
Passports: [../tab-bar.md](../tab-bar.md), [../search-tab-bar.md](../search-tab-bar.md),
[../tab-bar-minimize.md](../tab-bar-minimize.md).
Catalog families: `tab-bar` (the bar, its items, the activating search tab's bar side) and
`tab-minimize-accessory` (minimizing, content scroll, bottom accessory). The search tab's field
presentation is graded in [search.md](search.md).

Shape difference: UIKit's tab bar is owned by a container controller that also owns the pages
(`tabs`, `viewControllerProvider`). `MorphTabBar` is a bare control (items + index + callback); the
app owns the pages (IndexedStack or similar). That is the Flutter idiom (`NavigationBar`,
`CupertinoTabBar`) and stays. `MorphNavigationScaffold` / `MorphNavigationStack` do not host a tab bar.

SDK 27.1: the only additions for this family are `UINavigationItem.verticalBarCompressionBehavior`
(`UIVerticalBarCompressionBehavior` automatic / prefersBarItems / prefersTabBar; automatic prefers
the tab bar on iOS) and SwiftUI `toolbarVerticalCompressionBehavior(_:)`
(`ToolbarVerticalCompressionBehavior` automatic / prefersToolbarItems / prefersTabBar): which bar
compresses first when the tab bar and bar items share the vertical bar. Every other member in
UITabBarController.h, UITab.h, UISearchTab.h, UITabAccessory.h and UIBarMinimization.h carries 26.x
or 27.0 availability. The `prominentTabIdentifier` header says that with no identifier set, a
`UISearchTab` with `automaticallyActivatesSearch` gets the prominent treatment by default: the
separate search circle `MorphSearchTabBar` draws is that default.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UITabBarController.tabs` / `init(tabs:)` (iOS 18) | the tab list | `MorphTabBar.items` (`List<MorphTabItem>`) | 2..5 items, no pages | keep |
| `UITabBarController.setTabs(_:animated:)` (iOS 18) | animated insert/remove | list swap; a count change re-creates the lens without motion | no animated change of the tab set | skip until measured (rare) |
| `UITabBarController.selectedTab` / `selectedIndex` (iOS 18 / legacy) | current tab | `MorphTabBar.selected` (int) | index, not identifier | keep (matches `MorphSegmentedControl`) |
| `UITabBarController.tabForIdentifier(_:)`, `UITab.identifier` (iOS 18) | stable ids | none | not needed with index + app-owned list | skip (index idiom) |
| `UITabBarControllerDelegate.tabBarController(_:shouldSelectTab:)` (iOS 18) | veto a selection | `onChanged` + controlled `selected` (the lens returns when the parent keeps the old index) | - | keep |
| `UITabBarControllerDelegate.tabBarController(_:didSelectTab:previousTab:)` (iOS 18) | selection, including a tap on the selected tab | `MorphTabBar.onChanged` + `onReselected` | `MorphSearchTabBar` has no `onReselected` | add `MorphSearchTabBar.onReselected` |
| `UITabBarController.mode` (iOS 18) | bar vs iPad sidebar | none | bar only | skip (sidebar) |
| `UITabBarController.tabBarMinimizeBehavior` (iOS 26) | bar collapses while scrolling | `MorphTabBar.minimizeBehavior`, `MorphSearchTabBar.minimizeBehavior` + `contentScroll` / `MorphContentScrollScope` | read from UIKit, no recording (fidelity below) | done |
| `UITabBarController.bottomAccessory`, `setBottomAccessory(_:animated:)`, `UITabAccessory(contentView:)` (iOS 26) | glass accessory above the bar | `bottomAccessory` (Widget) on both bars | geometry approximated; no insertion animation | done |
| `UITabAccessory.Environment`, `UITraitTabAccessoryEnvironment` (iOS 26) | where the accessory is laid out | `MorphTabAccessoryEnvironment.{none, regular, inline}` + `.of(context)` | UIKit case names (SwiftUI `.expanded` = `regular`) | done |
| `UITabBarController.contentLayoutGuide` (iOS 26) | area content should avoid | none (`MorphTabBarMetrics` is internal) | app hard-codes 62 + 21 + safe area | add `MorphTabBar.extentFor(...)` like `MorphToolbar.extentFor` |
| `UITabBarController.isTabBarHidden` / `setTabBarHidden(_:animated:)` (iOS 18) | hide the bar | none (app removes the widget, no motion) | no animated hide | add `MorphTabBar.hidden` after a capture |
| `UITabBarController.prominentTabIdentifier` / `setProminentTabIdentifier(_:animated:)` (iOS 27) | one tab drawn prominent | `MorphSearchTabBar` is the default prominent search tab | no prominent ordinary tab; look unmeasured | add `MorphTabItem.prominent` after a capture |
| `UITabBarController.performBatchUpdates(_:)` (iOS 27) | batch tab mutations | declarative rebuild | - | skip (a rebuild is already one update) |
| `UINavigationItem.verticalBarCompressionBehavior` (iOS 27.1) | which bar compresses first in the vertical bar | none | no vertical-bar layout in morph | measure the landscape bar first |
| `UITabBarController.compactTabIdentifiers`, `customizationIdentifier` (iOS 18) | compact filter, customization persistence | none | sidebar-era customization | skip |
| `UITab(title:image:identifier:viewControllerProvider:)` (iOS 18) | tab item | `MorphTabItem(icon:, label:)` | `title` vs `label`; `UIImage` vs `IconData` | keep `label` (Flutter `NavigationDestination.label`) |
| `UITab.image` (iOS 18) | glyph | `MorphTabItem.icon` (`IconData`) | IconData only: SVG / image icons cannot be used (the selected copy draws the glyph as text) | add a Widget icon path tinted through `IconTheme` |
| `UITab.selectedImage` (iOS 26.1) / `UITabBarItem.selectedImage` | glyph inside the lens | `MorphTabItem.selectedIcon` (`IconData`) | IconData only | done (follows the icon decision) |
| `UITab.isEnabled` (iOS 18.4) | disabled tab | `MorphTabItem.enabled` | measured: no visual change | keep |
| `UITab.badgeValue` (iOS 18) | badge text | `MorphTabItem.badge` (`MorphBadge.count` / `.string` / `.indicator`) | placement NEAR, top by eye | done |
| `UITabBarItem.badgeColor`, `setBadgeTextAttributes(_:for:)` (iOS 10) | badge look | `MorphBadge.backgroundColor` / `foregroundColor` | color only, no font attributes | keep |
| `UISearchTab(viewControllerProvider:)` (iOS 18), `UISearchTab.identifier` (iOS 26.4) | search tab | `MorphTabRole.search` / `MorphSearchTabBar` | identifier n/a | keep |
| `UISearchTab.automaticallyActivatesSearch` (iOS 26) | true: the tab turns into a field; false: an ordinary tab whose page stacks a field | true = `MorphSearchTabBar`; false = `MorphTabItem(role: MorphTabRole.search)` + `MorphNavigationScaffold(search:)` | - | done |
| `UITabBar.tintColor` / `unselectedItemTintColor` (iOS 5 / 10) | selected / unselected tint | `MorphTabBarAppearance.selectedColor` / `color`; `MorphThemeData.tint` sets `selectedColor` | names differ | keep |
| `UITabBar.itemPositioning`, `itemWidth`, `itemSpacing` (iOS 7) | layout tweaks | none (measured pitch, widened to the label) | - | skip (measured geometry is the spec) |
| `UITabBar.standardAppearance` / `UITabBarAppearance` (iOS 13) | appearance objects | `MorphTabBarAppearance`, `MorphThemeData.appearances` | color table, not per-state attributes | keep |
| `UITabBarController.sidebar` (iOS 18; `isAvailable`, `preferredPlacement` iOS 27) | iPad / Mac sidebar | none | not an iPhone control | skip |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `TabView(selection:content:)` with `Tab` (iOS 18) | tabs + selection | `MorphTabBar.items` + `selected` | value-typed selection vs index | keep (index) |
| `Tab(_:systemImage:value:role:)` (iOS 18) | tab item | `MorphTabItem` | - | as `UITab(...)` |
| `TabRole.search` (iOS 18) | search tab | `MorphTabRole.search` / `MorphSearchTabBar` | - | done |
| `TabRole.prominent` (iOS 27) | prominent tab | `MorphSearchTabBar` only (default prominent search tab) | no prominent ordinary tab | as `prominentTabIdentifier` |
| `tabViewSearchActivation(.automatic / .searchTabSelection)` (iOS 26) | = `automaticallyActivatesSearch` | `MorphSearchTabBar` | - | done |
| `badge(_: Int / Text / LocalizedStringKey)` on `Tab` (iOS 18) | badge | `MorphTabItem.badge` | - | done |
| `TabContent.disabled(_:)` (iOS 18) | disabled tab | `MorphTabItem.enabled` | - | keep |
| `toolbarVerticalCompressionBehavior(_:)` (iOS 27.1) | = `verticalBarCompressionBehavior` | none | - | as the UIKit row |
| `tabBarMinimizeBehavior(_:)`, `TabBarMinimizeBehavior` (iOS 26) | = UIKit | `MorphTabBarMinimizeBehavior` | - | done |
| `tabViewBottomAccessory(content:)` (iOS 26), `(isEnabled:content:)` (iOS 26.1) | = `bottomAccessory` | `bottomAccessory` (null = disabled) | - | done |
| `EnvironmentValues.tabViewBottomAccessoryPlacement` `.inline / .expanded` (iOS 26) | = `UITabAccessory.Environment` | `MorphTabAccessoryEnvironment.of(context)` | `regular` = `.expanded` | done |
| `toolbarMinimizationBehavior`, `toolbarMinimizationSafeAreaAdjustment`, `toolbarMinimizationRestoration` (iOS 27; UIKit `UIBarMinimization`) | navigation bar minimization; an integrated top tab bar follows it | none | bars family | the tab bar keeps `MorphTabBarMinimizeBehavior` as UIKit does |
| `TabSection`, `sectionActions`, `tabViewStyle`, `tabPlacement`, `TabBarPlacement`, `tabViewSidebar*` (iOS 18 / 27) | sidebar, ornament | none | - | skip |
| `TabContent.hidden(_:)`, `defaultVisibility`, `customizationID`, `tabViewCustomization` (iOS 18) | customization | none | - | skip (declarative list) |

## Not relevant for Flutter
- `UITabBarItem` system items, `titlePositionAdjustment`, `backgroundImage`, `selectionIndicatorImage`, `shadowImage`, `barStyle`, `isTranslucent`, `scrollEdgeAppearance`: pre-glass appearance proxies.
- Legacy `UITabBarItem` twins of `UITab` members (`badgeValue`, `isEnabled`, `title`, `image`): counted once, under `UITab`.
- `UITabBar.leadingAccessoryView` / `trailingAccessoryView`: `API_UNAVAILABLE(ios)` (tvOS only).
- `UITab.subtitle`, `isHidden`, `hiddenByDefault`, `allowsHiding`, `preferredPlacement`, `userInfo`, `parent`, `viewController`, `UITabGroup`: sidebar or plumbing.
- `UITabAccessory.Environment.unspecified`: Flutter reads `none` outside an accessory.
- `UITabBar.beginCustomizingItems`, customizing delegate callbacks, "More" controller; drag and drop on tabs; sidebar delegate.
- `UITab` popover, spring-loading and accessibility categories: Flutter `Semantics` (the bar is `SemanticsRole.tabBar`, items `SemanticsRole.tab`).
- `tabBarControllerSupportedInterfaceOrientations`, animated transition delegate, NSCoding, Mac Catalyst, tvOS / visionOS members.

## morph-only API
- `MorphTabBar.maxTextScale` (1.25, measured) - keep.
- `MorphTabBarAppearance.barColor / shadowColor / platterColor / liftedLensColor / lensBorderColor / blurSigma` - renderer inputs; only `platterColor`, `selectedColor` and `color` carry a measurement.

## API count
Per public member an app developer uses, UIKit and SwiftUI members separately, n/a rows excluded.
| family | applicable | covered | partial | gaps |
|---|---|---|---|---|
| tab-bar | 34 | 21 | 7 | 6 |
| tab-minimize-accessory | 18 | 16 | 2 | 0 |

tab-bar partial: `setTabs(_:animated:)`, `prominentTabIdentifier`, `TabRole.prominent`, `UITab.image`,
`selectedImage`, `setBadgeTextAttributes`, `standardAppearance`. Gaps: `isTabBarHidden`,
`setTabBarHidden(_:animated:)`, `contentLayoutGuide`, `setProminentTabIdentifier(_:animated:)`,
`verticalBarCompressionBehavior`, `toolbarVerticalCompressionBehavior`.
tab-minimize-accessory partial: `.automatic` (resolves to never, not read), `setBottomAccessory(_:animated:)`
(no insertion animation).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | bar extent for content padding (`contentLayoutGuide`) | med-high | S | `MorphTabBar.extentFor(...)` |
| 2 | non-IconData icons (SVG, images) | med | M (the selected copy draws the glyph as text) | Widget icon path tinted through `IconTheme` |
| 3 | `onReselected` on `MorphSearchTabBar` | med | S | add, same release rule as `MorphTabBar` |
| 4 | minimize and accessory have no recording | med | M meas. | device film + rows (`w2search`, `PROBE_MINIMIZE=1`), then fit |
| 5 | animated hide | low-med | M meas. | `MorphTabBar.hidden` |
| 6 | prominent ordinary tab (iOS 27) | low | M meas. | `MorphTabItem.prominent` |
| 7 | landscape vertical bar and its compression (iOS 27.1) | low on iPhone portrait apps | L meas. | capture the landscape bar first |
| 8 | sidebar, groups, customization | low on iPhone | L | skip |

Done since the last refresh: badges (`MorphTabItem.badge`, `MorphBadge`), `onReselected`, `selectedIcon`,
`minimizeBehavior`, `bottomAccessory`, `MorphTabAccessoryEnvironment`.

## Proposals before 1.0
- `MorphSearchTabBar.onQueryChanged` -> `onChanged` (matches `MorphSearchField.onChanged`, `MorphSearchToolbar.onChanged`, `MorphNavigationSearch.onChanged`). Open.
- Decide whether `MorphTabItem.icon` / `selectedIcon` stay `IconData` (a Widget path added later is non-breaking) or become Widgets (breaking). Open.
- `MorphTabBar.selected` - keep (consistent with `MorphSegmentedControl`).
- Done: `MorphSearchTabBar.searching` / `onSearchingChanged` -> `active` / `onActiveChanged`.

## Behaviour fidelity

Grades: replayed / measured / read / approx / unbacked / missing / n/a (shared audit brief). A grade
is the weakest important item of the dimension.

### tab-bar
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | 21 / 7 / 6 of 34 | tables above | see API count |
| layout | unbacked | bar 62, pitch 86 / 68, lens 94 / 98 / 77, 21 pt inset, 10 pt labels, text scale cap 1.25 [layout, device] in ../tab-bar.md "Spec - geometry and look"; `MorphTabBarMetrics` (lib/src/widgets/tab_bar.dart:322-371); test/controls_platform_test.dart "tabs widen for a long label" (no native comparison) | badge top 6 pt above the glyph by eye (lib/src/widgets/badge.dart:113-116); label widening padding 12 has no source (tab_bar.dart:345-346); badge leading edge NEAR (24 pt glyph box) |
| states | replayed | test/disabled_test.dart replays test/fixtures/ios27-device/disabled/disabled.json (unchanged look, swell without lens); selected / unselected tint from measured matrices | focus ring has no native twin |
| transitions | replayed | test/lens_test.dart replays test/fixtures/ios27/lens/tabbar{2,3,4,5}-taps-* (simulator, undeformed frame, center 1.5 pt, size 2.5 pt); test/lens_scrub_test.dart replays ios27-device/lens/tabbar{3,5}-scrub-* and -tap-selected (rms bounds per file); test/tab_bar_glow_test.dart replays ios27-device/tabglow/* (wash rms 0.03, spot rms 0.012) | device tap fixtures (ios27-device/lens/tabbar*-taps, -pairs, -many, -radio-*) are classified by test/tab_bar_slow_lift_test.dart, which never runs morph; slow lift not modelled (deliberate); lens deformation not compared on the tab bar; programmatic selection motion unrecorded |
| boundaries | replayed | rubber band past the end tabs: lens_scrub_test pastleft / pastright (device); geometry measured for 2..5 tabs | fewer than 2 or more than 5 items undefined (5-tab pitch used, tab_bar.dart:349) |
| configuration | read | badge metrics read from UIKit (`MorphBadgeMetrics`, badge.dart:85-117) and the iPhone 16 Pro badge capture (../tab-bar.md "API gaps"); `selectedIcon` inside the lens; `MorphTabRole.search` | badge motion and count changes unmeasured; prominent tab and Widget icons missing |
| events | read | `onChanged` on contact [device]; `onReselected` on release, read from UIKit (tab_bar.dart:552-567); test/tab_bar_api_test.dart | delay of the reselect after the lift not traced |
| input | replayed | drag gain, follow spring, release to the tab nearest the finger: lens_scrub_test; disabled touch swells the bar only: disabled_test; scroll ownership: test/controls_scroll_test.dart | 0.15 s ownership delay is UIScrollView's documented delay, never captured (lib/src/widgets/touch_listener.dart:10); second pointer and cancel unmeasured |
| mutation | missing | a count change re-creates the lens without motion (tab_bar.dart:440-455) | UIKit animates `setTabs(_:animated:)`, `setTabBarHidden(_:animated:)`, `setProminentTabIdentifier(_:animated:)`; none recorded or ported |
| accessibility | read | Reduce Motion read from UIKit: no lift, travel on 0.9 / 0.2 (test/accessibility_test.dart:113; ../states.md); tab bar / tab semantics and arrow keys (test/controls_platform_test.dart:127, 297); text scale cap 1.25 [device] | Reduce Motion device pass pending; Increase Contrast unread; VoiceOver not compared |
| optics | measured | tint and platter from vibrant matrices [layout + device]; glow peaks (test/spec_test.dart:116, tab_bar_glow_test); lifted lens optics in ../glass-optics.md; badge above the lens (iPhone 16 Pro capture) | flat-tier bar color, shadow, lifted lens fill and border unsourced (tab_bar.dart:212-219, 250-258, 889-893, 1043); no pixel test against references/dark/tabbar3-*.png |
| platform | missing | RTL mirror (controls_platform_test) | landscape layout (iOS 27.1 vertical bar) and iPad sidebar not implemented; RTL never captured natively |
| performance | measured | Pixel 6a flat tab bar raster p95 8.47 ms, 519 mW; liquid raster p95 17.32 ms (docs/performance.md section 6); glyph policy A B B A in ../tab-bar.md | liquid p95 above the 16.67 ms budget in the last listed run; no device figure after the aligned labels |

### tab-minimize-accessory
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | 16 / 2 / 0 of 18 | tables above | `automatic` resolution, accessory insertion animation |
| layout | approx | 48 pt circle 28 from side and bottom (read; search circle device still); accessory 48 tall, 8 pt spacing declared APPROXIMATION (lib/src/widgets/tab_bar_minimize.dart:103-125); test/tab_bar_minimize_test.dart:253 | accessory frame and inline spacing unmeasured |
| states | read | expanded / hinting / minimized, search circle split (../tab-bar-minimize.md, device stills 2026-10-14 / 15); tab_bar_minimize_test.dart:411, 565 | the hint is never recorded |
| transitions | approx | springs read from UIKit (tab_bar_minimize.dart:65-101); glass on the intermediate and content on the final spring is a declared APPROXIMATION; tab_bar_minimize_test checks the read constants | no fixture: every path and timing waits for a recording |
| boundaries | read | 0 / 64 / 96 pt, clamp 0.01, floor, far and near end, scroll to top (`MorphScrollAway`, tab_bar_minimize.dart:152-304; tab_bar_minimize_test.dart:35-127); reverse scroll in mid-content stays minimized [device, 150 pt] | other reverse distances and a reverse fling unmeasured |
| configuration | approx | `automatic` resolves to never (declared, tab_bar_minimize.dart:9-12); `onScrollUp` mirrors; with and without accessory; search role | `automatic` resolution not read |
| events | approx | circle tap expands, kept against the code read (declared, tab_bar_minimize.dart:490-497); selected search circle tap expands [device 2026-10-15]; accessory environment changes (tab_bar_minimize_test.dart:519) | general circle tap unrecorded; search circle tap while another tab is selected unmeasured |
| input | read | hold 0.22 s, 4 pt hysteresis, hand-off to the bar's scrub (tab_bar_minimize_test.dart:179-235, 338-410) | `MorphSearchTabBar` circle hold and scrub not ported |
| mutation | missing | a behavior change mid-way expands (tab_bar_minimize_test.dart:242) | `setBottomAccessory(_:animated:)` insertion (the accessory appears in one frame); the accessory fading while searching is unmeasured |
| accessibility | missing | minimized circle: no focus ring, semantics box spans both ends (declared NEAR, ../tab-bar-minimize.md) | UIKit's Reduce Motion springs for the interactive expansion (0.9 / 0.3, read) are not ported; no Reduce Motion path in tab_bar_chrome.dart |
| optics | approx | the accessory keeps its own glass capsule (test/tab_bar_accessory_glass_test.dart, every tier) | paths not filmed; flat capsule shadow blur 10, offset 4 unsourced (lib/src/widgets/tab_collapse.dart:616-617) |
| platform | unbacked | RTL mirror in `MorphTabBarGroupGeometry.of` (lib/src/widgets/tab_bar_chrome.dart:421-470) | RTL and landscape never captured |
| performance | unbacked | host counts only: test/lifecycle_counts_test.dart 'tabbar-minimize/*', perf scene `tab-bar-minimize` (../tab-bar-minimize.md) | no Pixel 6a frame time or energy |
