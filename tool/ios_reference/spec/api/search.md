# Search - API parity (UIKit / SwiftUI iOS 27.1 vs morph)

Native: `UISearchController` (+ delegate, `UISearchResultsUpdating`), `UISearchBar` (+ delegate),
`UISearchTextField`, `UISearchToken`, `UISearchSuggestion` / `UISearchSuggestionItem`,
`UINavigationItem` search placement members, `UISearchTab`; SwiftUI `searchable`, `SearchFieldPlacement`,
`searchToolbarBehavior`, `searchScopes`, `searchSuggestions`, `searchCompletion`, `onSubmit(of: .search)`,
`searchFocused`, `isSearching` / `dismissSearch`, searchable tokens, `searchPresentationToolbarBehavior`.
Headers: iPhoneOS27.1.sdk. 27.1 adds nothing to the search headers; the newest members are
`UISearchBarDelegate.searchBar(_:shouldChangeTextInRanges:replacementText:)` (iOS 26) and
`UIPhotoSearchSuggestion` (iOS 27).

morph, public (test/api/public_api.txt): `MorphSearchField`, `MorphSearchFieldAppearance`,
`MorphSearchToolbar`, `MorphNavigationSearch` (on `MorphNavigationScaffold.search`), `MorphSearchTabBar`;
strings from `MorphLocalizations` (`searchPlaceholder`, `searchLabel`, `closeLabel`); theming through
`MorphThemeData.appearances`. Internal: `MorphSearchMotion`, `MorphSearchTuning`, `morphSearchBarLayout`,
`morphSearchTabLayout`.
Passports: [../search.md](../search.md), [../search-tab-bar.md](../search-tab-bar.md).
Catalog family: `search` (the field, the bottom toolbar, the stacked field and the search tab's field
presentation; the search tab's bar side is graded in [tab-bar.md](tab-bar.md)).

Shape difference: UIKit search is a controller attached to a navigation item, which picks a placement
(bar / toolbar / tab). morph has standalone widgets: a plain field, the iPhone bottom-toolbar placement
(`MorphSearchToolbar`), the stacked field of a scaffold page (`MorphNavigationSearch`) and the search tab
(`MorphSearchTabBar`). Results, dimming and suggestions are left to the app.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UISearchController.isActive` (iOS 8) | search presented; settable | `active` + `onActiveChanged` on `MorphSearchToolbar`, `MorphNavigationSearch`, `MorphSearchTabBar` | parent changes are not reported back | done |
| `UISearchControllerDelegate.willPresent/didPresent/willDismiss/didDismiss` (iOS 8) | lifecycle | `onActiveChanged(true / false)` at the start of the change | no settled (did) phase | add `onActiveSettled` only if asked |
| `UISearchController.searchBar` / `UISearchBar.text` | the query | `controller` (`TextEditingController`) on every widget | - | keep |
| `UISearchResultsUpdating.updateSearchResults(for:)`, `UISearchBarDelegate.searchBar(_:textDidChange:)` | query changed | `onChanged` on field, toolbar, stacked; `MorphSearchTabBar.onQueryChanged` | tab bar name differs | rename to `onChanged` |
| `UISearchBarDelegate.searchBarSearchButtonClicked` | Search key | `onSubmitted` everywhere | - | keep |
| `UISearchBarDelegate.searchBarCancelButtonClicked` | cancel / close | close button -> `onActiveChanged(false)` | - | keep |
| `UISearchBarDelegate.searchBarTextDidBeginEditing / EndEditing`, `searchBarShouldBeginEditing` | focus | `focusNode` | no veto of the focus | keep (FocusNode idiom) |
| `UISearchBarDelegate.searchBar(_:shouldChangeTextInRanges:replacementText:)` (iOS 26) | filter edits | none | no `inputFormatters` | add `inputFormatters` (low) |
| `UISearchBar.placeholder` | hint text | `placeholder` (default `MorphLocalizations.searchPlaceholder`) | - | keep |
| `UISearchBar.prompt` | line above a stacked bar | none | stacked only | add on `MorphNavigationSearch` (low) |
| `UISearchBar.isEnabled` (iOS 16.4) | disabled field | `MorphSearchField.enabled` (measured flat fill, `MorphSearchFieldAppearance.disabledFillColor`) | no `enabled` on `MorphSearchToolbar`, `MorphNavigationSearch`, `MorphSearchTabBar` | add (low) |
| `UISearchBar.searchTextField` (iOS 13) | the field itself | `MorphSearchField` | a separate widget; the placements do not expose theirs | keep |
| `UISearchBar.showsCancelButton`, `UISearchController.automaticallyShowsCancelButton` | cancel button | close button, always shown while active | glass uses a close (x) button | keep |
| `UISearchBar.showsBookmarkButton`, `showsSearchResultsButton`, `isSearchResultsButtonSelected` + delegate clicks | trailing buttons in the field | none | rare under Liquid Glass | skip |
| `UISearchBar.scopeButtonTitles`, `selectedScopeButtonIndex`, `showsScopeBar`, `setShowsScopeBar(_:animated:)`, delegate `selectedScopeButtonIndexDidChange` | scope bar | none | unmeasured | `scopes` + `selectedScope` + `onScopeChanged` over `MorphSegmentedControl` |
| `UISearchController.scopeBarActivation` (iOS 16) | when the scope bar appears | none | follows the scope bar | `MorphSearchScopeActivation.{automatic, onTextEntry, onSearchActivation}` |
| `UISearchTextField.tokens`, `insertToken`, `removeToken`, `tokenBackgroundColor`, `allowsDeletingTokens`, `allowsCopyingTokens`; `UISearchToken(icon:text:)`, `representedObject` (iOS 13) | token chips | none | needs an editable span | `tokens` + `onTokensChanged` (later) |
| `UISearchController.searchSuggestions`, `UISearchTextField.searchSuggestions`, `UISearchSuggestionItem`, `updateSearchResults(for:selecting:)` (iOS 16) | suggestion menu | none | unmeasured | `suggestions` + `onSuggestionSelected` over the menu machinery |
| `UISearchController.ignoresSearchSuggestionsForSearchBarPlacementStacked` (iOS 16) | suggestions per placement | none | follows suggestions | with suggestions |
| `UISearchController.obscuresBackgroundDuringPresentation` (iOS 9.1) | dim content while active | none | app draws its own scrim | skip (recipe) |
| `UISearchController.hidesNavigationBarDuringPresentation` | nav bar leaves while searching | `MorphNavigationSearch` / `MorphSearchToolbar.hidesNavigationBarDuringPresentation` (default true) | device timing pending | done |
| `UISearchController.searchBarPlacement` (iOS 16, read-only) | the placement in effect | none | each widget is one placement | with a placement enum |
| `UINavigationItem.searchController` (iOS 11) | attach search to a screen | `MorphNavigationScaffold.search` (`MorphNavigationSearch`, stacked) | stacked only | done (stacked) |
| `UINavigationItem.preferredSearchBarPlacement`, `.automatic / .stacked / .integrated / .integratedCentered / .integratedButton` (iOS 16; `integrated*` iOS 26) | where the field lives | stacked = `MorphNavigationSearch`; integrated on iPhone with toolbar integration = `MorphSearchToolbar` | no inline nav-bar field, no `integratedCentered`, no `integratedButton`, no placement enum | `MorphSearchPlacement` with the next placement |
| `UINavigationItem.searchBarPlacementAllowsToolbarIntegration` (iOS 26) | iPhone: field may move into the bottom toolbar | implicit (`MorphSearchToolbar` is the toolbar) | - | flag with the placement enum |
| `UINavigationItem.searchBarPlacementBarButtonItem` (iOS 26) | the field among bar items | `MorphSearchToolbar.leading` / `trailing` (`List<MorphBarButtonGroup>`) | each group holds exactly one button | keep |
| `UINavigationItem.hidesSearchBarWhenScrolling` (iOS 11) | stacked field collapses on scroll | stacked field scrolls away (UIKit's default) | no pinned field | add `false` with the pinned look |
| `UISearchTab.automaticallyActivatesSearch` (iOS 26) | search tab becomes the field | `MorphSearchTabBar` | see tab-bar.md | keep |
| `UIBarMinimization` / `UINavigationItem.navigationBarMinimization` (iOS 27) | nav bar minimizes on scroll | none | bars family | skip here |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `searchable(text:placement:prompt:)` (iOS 15), `searchable(text:isPresented:placement:prompt:)` (iOS 17) | attach search; `isPresented` = controlled active | `controller` + `active` / `onActiveChanged`; `prompt` = `placeholder` | placements limited | keep |
| `SearchFieldPlacement.automatic / .toolbar / .toolbarPrincipal / .navigationBarDrawer(displayMode:)` (iOS 15) | placements | `.toolbar` ~ `MorphSearchToolbar`; `.navigationBarDrawer(.automatic)` ~ `MorphNavigationSearch` | no `.toolbarPrincipal`, no `.always` drawer | name the stacked case `stacked` (UIKit) |
| `searchToolbarBehavior(.automatic / .minimize)` (iOS 26) | toolbar field collapses to a button | none | ~ `.integratedButton` | `MorphSearchToolbar.behavior` after a capture |
| `searchPresentationToolbarBehavior(.automatic / .avoidHidingContent)` (iOS 17.1) | keep the title visible while searching | none (`hidesNavigationBarDuringPresentation: false` is the closest) | no title-keeping presentation | document the mapping |
| `searchScopes(_:scopes:)`, `searchScopes(_:activation:_:)`, `SearchScopeActivation` (iOS 16 / 16.4) | scope bar | none | SwiftUI `onSearchPresentation` vs UIKit `onSearchActivation` | as the UIKit scope rows |
| `searchSuggestions(_:)`, `searchSuggestions(_:for:)`, `searchCompletion(_:)`, `searchSuggestionsPlacement` (iOS 16) | suggestions | none | - | as the UIKit suggestions row |
| `searchable(text:tokens:...)`, `searchable(text:editableTokens:...)` (iOS 16 / 17) | tokens | none | - | as the UIKit tokens row |
| `onSubmit(of: .search)` (iOS 15) | Search key | `onSubmitted` | - | keep |
| `searchFocused(_:)` (iOS 18) | focus binding | `focusNode` | - | keep |
| `EnvironmentValues.isSearching` (iOS 15) | descendants know search is active | none | results deep in the tree cannot read it | add with nav integration (low) |
| `EnvironmentValues.dismissSearch` (iOS 15) | end search from a descendant | controlled `active` from the owner | no descendant action | covered by `active` |
| `searchSelection(_:)` (iOS 26) | text selection binding | `controller.selection` | - | keep |
| `searchDictationBehavior` (iOS 17, visionOS) | dictation | none | - | skip |

## Not relevant for Flutter
- `UISearchBar` background, scope, field and icon images, position adjustments, `searchBarStyle`, `barStyle`, `barTintColor`, `isTranslucent`: pre-glass appearance proxies.
- `UISearchController.searchResultsController`, `showsSearchResultsController`, `automaticallyShowsSearchResultsController`: results are the widget tree.
- `UISearchControllerDelegate.presentSearchController`, `willChangeToSearchBarPlacement` / `didChangeFromSearchBarPlacement`, `UINavigationItem.searchBarPlacementAllowsExternalIntegration`: custom presentation, iPad.
- `UISearchDisplayController`, `dimsBackgroundDuringPresentation`, `automaticallyShowsScopeBar`: deprecated.
- `UISearchContainerViewController`, `searchControllerObservedScrollView`: tvOS.
- `UISearchTextField` token geometry helpers, token copy item providers, `inputAccessoryView`, `inputAssistantItem`, `lookToDictateEnabled`, `UIPhotoSearchSuggestion` (Photos-specific).
- NSCoding and nib initialisers.

## morph-only API
- `MorphSearchField.clearLabel`, `semanticLabel`, `MorphSearchToolbar.closeLabel`, `MorphSearchTabBar.searchLabel` / `closeLabel`, `MorphNavigationSearch.closeLabel` - semantics strings; keep.
- `MorphSearchField.maxTextScale` (1.5, no source), `autofocus`, `height`, `glass` - keep; source the scale cap.
- `MorphSearchFieldAppearance.restingPlaceholderColor`, `cursorColor`, `clearColor`, `clearGlyphColor`, `disabledFillColor`, `stackedFillColor` - measured; `capsuleColor` / `rimColor` / `shadowColor` are the flat stand-in, unsourced.
- `MorphSearchToolbar.buttonAppearance` (`MorphGlassButtonAppearance`) - `MorphToolbar` takes `appearance: MorphBarAppearance`; align.

## API count
Per public member an app developer uses, UIKit and SwiftUI members separately, n/a rows excluded.
| family | applicable | covered | partial | gaps |
|---|---|---|---|---|
| search | 75 | 18 | 13 | 44 |

Covered: `isActive`, `willPresent`, `willDismiss`, `searchResultsUpdater`, `hidesNavigationBarDuringPresentation`,
`text`, `placeholder`, delegate `textDidChange` / `searchButtonClicked` / `cancelButtonClicked` /
`textDidBeginEditing` / `textDidEndEditing`, `searchController`, placement `.stacked`, `SearchFieldPlacement.toolbar`,
`onSubmit(of: .search)`, `searchFocused`, `searchSelection`. Partial: `isEnabled`, `searchTextField`,
`preferredSearchBarPlacement`, `.automatic`, `.integrated`, `searchBarPlacementAllowsToolbarIntegration`,
`searchBarPlacementBarButtonItem`, `hidesSearchBarWhenScrolling`, both `searchable` forms,
`SearchFieldPlacement.automatic`, `.navigationBarDrawer`, `dismissSearch`. Gaps: scope bar (8 members),
tokens (10), suggestions (8), bookmark / results buttons (5), `didPresent`, `didDismiss`,
`obscuresBackgroundDuringPresentation`, `searchBarPlacement`, `prompt`, `shouldBeginEditing`,
`shouldChangeTextInRanges`, `.integratedCentered`, `.integratedButton`, `.toolbarPrincipal`,
`searchToolbarBehavior`, `searchPresentationToolbarBehavior`, `isSearching`.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | suggestions (`searchSuggestions` / `searchCompletion`) | med | M (menu exists; capture the native list) | `suggestions` + `onSuggestionSelected` |
| 2 | scope bar (`scopeButtonTitles`, `scopeBarActivation`, `searchScopes`) | med | M meas. | `scopes`, `selectedScope`, `onScopeChanged`, `scopeActivation` |
| 3 | other placements: `integratedButton` / `searchToolbarBehavior(.minimize)`, inline nav-bar field, pinned stacked | med | L meas. | `MorphSearchPlacement` with the next one |
| 4 | toolbar placement inside `MorphNavigationScaffold` (today a standalone widget) | med | M | a toolbar case of `MorphNavigationSearch` |
| 5 | tokens | low-med | L | later |
| 6 | `enabled` on toolbar / stacked / tab bar, `inputFormatters`, `prompt` | low | S | add |

Done since the last refresh: controlled `active` on the toolbar, the stacked field and the tab bar; stacked
placement on `MorphNavigationScaffold.search`.

## Proposals before 1.0
- `MorphSearchTabBar.onQueryChanged` -> `onChanged` (one name across `MorphSearchField`, `MorphSearchToolbar`, `MorphNavigationSearch`, `MorphSearchTabBar`). Open.
- `MorphSearchToolbar.buttonAppearance` (`MorphGlassButtonAppearance`) -> `MorphBarAppearance` as `MorphToolbar.appearance`, so the toolbar placement folds into the shared toolbar. Open.
- Done: `MorphSearchTabBar.searching` -> `active`; `MorphSearchToolbar.leading` / `trailing` -> `List<MorphBarButtonGroup>` (one button per group); `MorphSearchToolbar.active` nullable (controlled / uncontrolled).

## Behaviour fidelity

Grades: replayed / measured / read / approx / unbacked / missing / n/a (shared audit brief). A grade is
the weakest important item of the dimension.

| dimension | grade | evidence | open items |
|---|---|---|---|
| api | 18 / 13 / 44 of 75 | tables above | see API count |
| layout | measured | field metrics [layout + film] and toolbar rest / focused geometry (../search.md); test/search_test.dart:951-968 asserts the device positions; tab search geometry (search_test.dart:1075-1088); stacked field from simulator film (`MorphSearchTuning.stacked*`, lib/src/widgets/search_motion.dart:147-175) | stacked geometry simulator only; unsourced: clear button lead 8 (lib/src/widgets/search_field.dart:469), text button padding 11 (search_field.dart:1282), placeholder end 8 (lib/src/widgets/search_tab_bar.dart:925), line height 1.2 (search_field.dart:375); focused toolbar field 27 pt lower than native (no prediction bar) |
| states | replayed | disabled flat fill: test/disabled_test.dart replays test/fixtures/ios27-device/disabled/disabled.json; resting vs focused placeholder colors [device] | no `enabled` on the placements; dark stacked fill unmeasured |
| transitions | approx | toolbar focus / close / cancel replayed on simulator and device rows (search_test.dart:75-205, 357-425; rms < 2 pt over ~300 pt); tab search glass morph replayed against the simulator film (search_test.dart:1090-1138, rms < 3 pt); tab focus rise and fall replayed on device rows (search_test.dart:466-581) | stacked presentation: simulator film fit only, glass switch at p = 0.5 and the close slide are declared approximations, test/search_stacked_test.dart loads no fixture; the tab morph test fits its start time, so the tap-to-morph latency is not compared; UIKit's close button two-frame lag not modelled |
| boundaries | measured | tab morph reversal and ignored taps (films tm-*, ../search-tab-bar.md); `keyboardWaitLimit` 0.3 s declared guard (search_motion.dart:36-39) | an empty query submits (Flutter engine); test/fixtures/ios27/search/search-close.jsonl recorded, never replayed |
| configuration | missing | toolbar (`MorphSearchToolbar`), stacked (`MorphNavigationSearch`), tab (`MorphSearchTabBar`) | integrated, integratedCentered, integratedButton / `.minimize`, pinned stacked; scopes, tokens, suggestions |
| events | measured | `onActiveChanged` at the start of the change; `willPresentSearchController` 0.085 s after the lift [device] (search_motion.dart:115-120) | no settled callback; parent changes of `active` not reported |
| input | replayed | touch lift 0.05 s after contact: search_test replays search-hold / search-tap (device, rms < 0.4; search_test.dart:357-463); a held touch focuses on the lift (film) | a drag on the field unmeasured (lifts without stretch) |
| mutation | measured | `transitionDelay` 0.067 s from `isActive = false` [device] (search_motion.dart:22-27) | text or controller changes during a transition unmeasured |
| accessibility | unbacked | semantics labels and close / clear buttons; Reduce Motion keeps the transition and drops the lift (declared approximation, search_motion.dart:322-324) | `MorphSearchField.maxTextScale` 1.5 (search_field.dart:262) and the toolbar labels' 1.25 cap (search_field.dart:965) have no source; Increase Contrast fills unread; Reduce Motion unmeasured |
| optics | measured | disabled and stacked light fills [device / simulator]; magnifier, clear and close glyph geometry [layout + film] (search_motion.dart:74-101); film crops references/search-video/ | flat stand-in capsule / rim / shadow colors unsourced (search_field.dart:26-28); magnifier grows 1.15 x during the tab morph, unsourced (search_tab_bar.dart:908-911) |
| platform | measured | keyboard timing on the iPhone 16 Pro (`keyboardLag`, `tabKeyboardLag`); engine limits recorded in ../search.md (prediction bar, `enablesReturnKeyAutomatically`) | RTL never captured natively |
| performance | unbacked | toolbar stage on the Pixel 6a: raster p95 -1.0 ms, GPU -8 percent (../glass-renderer.md "Package stages"); host counts test/lifecycle_counts_test.dart 'search/*', 'search-bar/*' | no device frame time or energy for the tab search morph or the stacked presentation |
