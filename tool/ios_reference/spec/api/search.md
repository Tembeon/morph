# Search - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UISearchController` (+ delegate, `UISearchResultsUpdating`), `UISearchBar` (+ delegate),
`UISearchTextField`, `UISearchToken`, `UISearchSuggestion` / `UISearchSuggestionItem`,
`UINavigationItem` search placement members, `UISearchTab`; SwiftUI `searchable`, `SearchFieldPlacement`,
`searchToolbarBehavior`, `searchScopes`, `searchSuggestions`, `searchCompletion`, `onSubmit(of: .search)`,
`searchFocused`, `isSearching` / `dismissSearch`, searchable tokens, `searchPresentationToolbarBehavior`.
morph: `MorphSearchField`, `MorphSearchFieldStyle`, `MorphSearchToolbar`, `MorphSearchMotion`,
`MorphSearchTuning`, `MorphSearchTabBar`, `MorphWidgetsTheme.searchField`.
Passports: [../search.md](../search.md), [../search-tab-bar.md](../search-tab-bar.md).

Shape difference: UIKit search is a controller attached to a navigation item, which picks a placement
(bar / toolbar / tab). morph has three standalone widgets: a plain field, the iPhone bottom-toolbar
placement (`MorphSearchToolbar`) and the search tab (`MorphSearchTabBar`). Results, dimming and
suggestions are left to the app.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UISearchController.isActive` (iOS 8) | search presented; settable to start/stop | `MorphSearchToolbar.active` + `onActiveChanged`; `MorphSearchTabBar.active` + `onActiveChanged`; `MorphNavigationSearch.active` + `onActiveChanged` | - (2026-10-14: controlled `active` on the toolbar and the stacked search; parent changes are not reported back) | done |
| `UISearchControllerDelegate.willPresent/didPresent/willDismiss/didDismiss` (iOS 8) | lifecycle | `onActiveChanged(true/false)` (fires at start of the change) | no "did" (settled) phase | keep (add `onActiveSettled` only if asked) |
| `UISearchController.searchBar` / `UISearchBar.text` (legacy) | the query | `controller` (`TextEditingController`) on all three widgets | - | keep |
| `UISearchResultsUpdating.updateSearchResults(for:)`, `UISearchBarDelegate.searchBar(_:textDidChange:)` (legacy) | query changed | `MorphSearchField.onChanged`, `MorphSearchToolbar.onChanged`, `MorphSearchTabBar.onQueryChanged` | tab bar name differs | rename `MorphSearchTabBar.onQueryChanged -> onChanged` |
| `UISearchBarDelegate.searchBarSearchButtonClicked` (legacy) | Search key | `onSubmitted` on all three | - | keep |
| `UISearchBarDelegate.searchBarCancelButtonClicked` (legacy) | cancel/close | close button -> `onActiveChanged(false)` | - | keep |
| `UISearchBarDelegate.searchBarTextDidBeginEditing/EndEditing`, `searchBarShouldBeginEditing` (legacy) | focus | `focusNode` | - | keep (FocusNode idiom) |
| `UISearchBarDelegate.searchBar(_:shouldChangeTextInRanges:replacementText:)` (iOS 26) | filter edits | none | no `inputFormatters` | add `inputFormatters` (low) |
| `UISearchBar.placeholder` (legacy) | hint text | `placeholder` (default 'Search') | - | keep |
| `UISearchBar.prompt` (legacy) | line above a stacked bar | none | stacked placement only | skip until nav-bar placement exists |
| `UISearchBar.isEnabled` (iOS 16.4) / `UISearchTextField.isEnabled` | disabled field | `MorphSearchField.enabled` (measured flat fill, `MorphSearchFieldStyle.disabledFillColor`) | `MorphSearchToolbar` / `MorphSearchTabBar` have no `enabled` | add `enabled` to both (low) |
| `UISearchBar.showsCancelButton`, `setShowsCancelButton(_:animated:)`, `UISearchController.automaticallyShowsCancelButton` (iOS 13) | cancel button | close button, always shown while active | iOS 26+ glass uses a close (x) button | keep |
| `UISearchBar.showsBookmarkButton`, `showsSearchResultsButton`, `isSearchResultsButtonSelected` (legacy) | trailing buttons in the field | none | rarely used under Liquid Glass | skip |
| `UISearchBar.scopeButtonTitles`, `selectedScopeButtonIndex`, `showsScopeBar`, `setShowsScopeBar(_:animated:)` (legacy / iOS 13), delegate `selectedScopeButtonIndexDidChange` | scope bar under the field | none | missing, unmeasured | add `scopes` (`List<String>`) + `selectedScope` + `onScopeChanged` (reuse `MorphSegmentedControl`) |
| `UISearchController.scopeBarActivation` `.automatic/.manual/.onTextEntry/.onSearchActivation` (iOS 16) | when the scope bar appears | none | follows scope bar | add `MorphSearchScopeActivation.{automatic, onTextEntry, onSearchActivation}` (drop `manual`: controlled `showsScopeBar` covers it) |
| `UISearchBar.searchBarStyle` `.default/.prominent/.minimal` (iOS 7) | pre-glass backgrounds | `MorphSearchFieldStyle` | - | skip (legacy look) |
| `UISearchBar.lookToDictateEnabled` (iOS 17, mostly visionOS) | gaze dictation | none | - | skip |
| `UISearchBar.inputAccessoryView`, `inputAssistantItem` | keyboard accessories | none | Flutter has no input accessory view | skip |
| `UISearchTextField.tokens`, `insertToken`, `removeToken`, `tokenBackgroundColor`, `allowsDeletingTokens`, `allowsCopyingTokens`; `UISearchToken(icon:text:)`, `representedObject` (iOS 13) | token chips in the field | none | missing; needs a custom editable span | add `tokens` (`List<MorphSearchToken>`) + `onTokensChanged`, `MorphSearchFieldStyle.tokenColor` (later) |
| `UISearchController.searchSuggestions`, `UISearchTextField.searchSuggestions`, `UISearchSuggestionItem(localizedSuggestion:localizedDescription:iconImage:)`, `updateSearchResults(for:selecting:)` (iOS 16) | suggestion menu under the field | none | missing | add `suggestions` (`List<MorphMenuEntry>` or `MorphSearchSuggestion{title, subtitle, icon}`) + `onSuggestionSelected`, shown with the morph menu machinery |
| `UIPhotoSearchSuggestion` (`whoValues/whatValues/whereValues/whenValues`) (iOS 27, NEW) | Photos-style structured suggestion | none | domain-specific | skip |
| `UISearchController.ignoresSearchSuggestionsForSearchBarPlacementStacked` (iOS 16) | suggestions per placement | none | - | skip |
| `UISearchController.searchResultsController`, `showsSearchResultsController`, `automaticallyShowsSearchResultsController` (iOS 8 / 13) | results page over content | none | app swaps its body on `onActiveChanged` | skip (Flutter: widget tree) |
| `UISearchController.obscuresBackgroundDuringPresentation` (iOS 9.1) | dim content while active | none | app draws its own scrim | skip (or document recipe) |
| `UISearchController.hidesNavigationBarDuringPresentation` (legacy) | nav bar slides away (stacked) | `MorphNavigationSearch.hidesNavigationBarDuringPresentation` (default true; `MorphNavigationConfig.navigationBarHidden` carries it to a stack's shared bar) | toolbar placement keeps the nav bar (native hides it, sweep item 3) | done for stacked; toolbar pending the bars hook |
| `UISearchController.searchControllerObservedScrollView` | tvOS-only (header: unavailable on iOS) | none | - | skip |
| `UINavigationItem.searchController` (iOS 11) | attach search to a screen | `MorphNavigationScaffold.search` (`MorphNavigationSearch`, stacked placement) | stacked only; the toolbar placement is still a separate widget | done (stacked) |
| `UINavigationItem.preferredSearchBarPlacement` / `searchBarPlacement`, `UINavigationItemSearchBarPlacement.automatic/.integrated/.stacked/.integratedCentered/.integratedButton` (iOS 16; `integrated*` iOS 26, NEW; `.inline` deprecated -> `.integrated`) | where the field lives | `MorphSearchToolbar` = `.integrated` on iPhone with toolbar integration; `MorphNavigationSearch` = `.stacked` | no `.integratedButton`, no placement enum | add `MorphSearchPlacement` when a second nav-bar placement lands |
| `UINavigationItem.searchBarPlacementAllowsToolbarIntegration` (iOS 26, NEW) | iPhone: field may move into the bottom toolbar | implicit (`MorphSearchToolbar` always is the toolbar) | - | keep implicit; becomes a flag with the nav config |
| `UINavigationItem.searchBarPlacementAllowsExternalIntegration` (iOS 26, NEW) | split view moves the field | none | iPad split only | skip |
| `UINavigationItem.searchBarPlacementBarButtonItem` (iOS 26, NEW) | where the field sits among bar items | none (`MorphSearchToolbar.leading/trailing` put it between) | - | keep (leading/trailing is the Flutter shape) |
| `UINavigationItem.hidesSearchBarWhenScrolling` (iOS 11) | stacked bar collapses on scroll | none | stacked only | skip until stacked exists |
| `UISearchControllerDelegate.willChangeToSearchBarPlacement/didChangeFromSearchBarPlacement` (iOS 16) | placement change | none | - | skip |
| `UISearchTab.automaticallyActivatesSearch` (iOS 26, NEW) | search tab becomes the field | `MorphSearchTabBar` | see tab-bar.md | keep |
| `UIBarMinimization` / `UINavigationItem.navigationBarMinimization` (iOS 27, NEW; restoration `.atScrollEdge` auto-picked for `.integratedCentered`) | nav bar (and integrated field) minimise on scroll | none | bars family | skip here (bars) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `searchable(text:isPresented:placement:prompt:)` (iOS 15 / `isPresented` iOS 17) | attach search; `isPresented` = controlled active | `controller` + `MorphSearchTabBar.searching`; toolbar uncontrolled | same as UIKit `isActive` row; `prompt` = `placeholder` | add controlled `active` everywhere; keep `placeholder` |
| `SearchFieldPlacement.automatic/.toolbar/.toolbarPrincipal/.sidebar/.navigationBarDrawer(displayMode: .automatic/.always)` (iOS 15) | placements | `MorphSearchToolbar` ~ `.toolbar` on iOS 26+ | drawer = stacked | same as UIKit placement row; name the stacked case `stacked` (UIKit) not `navigationBarDrawer` |
| `searchToolbarBehavior(.automatic/.minimize)` (iOS 26, NEW) | toolbar field collapses to a button until tapped | none | ~ `UINavigationItemSearchBarPlacement.integratedButton` | add `MorphSearchToolbar.minimized` (or `behavior: MorphSearchToolbarBehavior.{automatic, minimize}`) after capture |
| `searchPresentationToolbarBehavior(.automatic/.avoidHidingContent)` (iOS 17.1) | keep toolbar/title visible while searching | none | nav integration | skip until nav config |
| `searchScopes(_:activation:scopes:)`, `SearchScopeActivation.automatic/.onTextEntry/.onSearchPresentation` (iOS 16; activation iOS 16.4) | scope bar | none | names: SwiftUI `onSearchPresentation` vs UIKit `onSearchActivation` | same as UIKit scope rows; prefer UIKit `onSearchActivation` (pairs with `active`) |
| `searchSuggestions(_:)` (iOS 16), `searchSuggestions(_:for: .menu/.content)`, `searchCompletion(_:)` (iOS 16+) | suggestions; completion fills the field | none | completion = tap fills text or token | same as UIKit suggestions row; `MorphSearchSuggestion.completion` |
| `searchable(text:tokens:suggestedTokens:...token:)`, `editableTokens` (iOS 16 / 17) | tokens | none | - | same as UIKit tokens row |
| `onSubmit(of: .search)` (iOS 15) | Search key | `onSubmitted` | - | keep |
| `searchFocused(_:)` (iOS 18) | focus binding | `focusNode` | - | keep |
| `EnvironmentValues.isSearching` (iOS 15) | descendants know search is active | none (app threads `onActiveChanged`) | results views deep in the tree cannot read it | add `MorphSearchScope.isActiveOf(context)` only with nav integration (low) |
| `EnvironmentValues.dismissSearch` (iOS 15) | end search from a descendant | none | same root gap as programmatic `isActive = false` | covered by controlled `active` |
| `searchDictationBehavior` (iOS 17, visionOS) | dictation | none | - | skip |
| `searchSelection(_:)` (iOS 26) | text selection binding | `controller.selection` | - | keep |

## Not relevant for Flutter
- `UISearchBar` background/scope/field images, icon images and position adjustments (`setImage(_:for:state:)`, `searchFieldBackgroundPositionAdjustment`, ...), `barStyle`, `barTintColor`, `isTranslucent`: appearance proxies of the pre-glass bar.
- `UISearchDisplayController`, `dimsBackgroundDuringPresentation`, `automaticallyShowsScopeBar`: deprecated.
- `UISearchContainerViewController`, `searchControllerObservedScrollView`: tvOS.
- `UISearchTextField` token geometry helpers (`positionOfTokenAtIndex`, `tokensInRange`, `textualRange`, `replaceTextualPortionOfRange`), token copy item providers: UITextInput plumbing.
- `UISearchController` NSCoding / nib initialisers; `UISearchControllerDelegate.presentSearchController` (custom presentation).

## morph-only API
- `MorphSearchField.clearLabel`, `semanticLabel`, `MorphSearchToolbar.closeLabel`, `MorphSearchTabBar.searchLabel/closeLabel` - semantics strings (UIKit localises internally); keep.
- `MorphSearchField.maxTextScale` (1.5), `autofocus` - keep.
- `MorphSearchFieldStyle.restingPlaceholderColor`, `cursorColor`, `clearColor`, `clearGlyphColor`, `disabledFillColor` - measured colours; keep.
- `MorphSearchToolbar.buttonStyle` (`MorphGlassButtonStyle`) - flag: `MorphToolbar` uses `style: MorphBarStyle`; align with the toolbar.
- `MorphSearchMotion`, `MorphSearchTuning` - pure motion and measured constants; keep.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | end/start search from code (`isActive`, `dismissSearch`) | high (selecting a result must close search) | S | done 2026-10-14 (`active` on the toolbar and `MorphNavigationSearch`) |
| 2 | search not integrated with `MorphNavigationStack` bars (`UINavigationItem.searchController`) | high (the iOS 26 way to add search) | M | stacked placement done 2026-10-14 (`MorphNavigationScaffold.search`); toolbar placement still standalone |
| 3 | suggestions (`searchSuggestions` / `searchCompletion`) | med | M (morph menu exists; capture native list) | add `suggestions` + `onSuggestionSelected` |
| 4 | scope bar (`scopeButtonTitles`, `scopeBarActivation`, `searchScopes`) | med | M (capture; reuse segmented control) | add `scopes`, `selectedScope`, `onScopeChanged`, `scopeActivation` |
| 5 | other placements: `integratedButton` / `searchToolbarBehavior(.minimize)`, pinned stacked | med | L (capture each) | stacked done; add `MorphSearchPlacement` with the next one |
| 6 | tokens | low-med | L (editable spans) | add later |
| 7 | `enabled` on toolbar / tab bar, `inputFormatters` | low | S | add |

## Breaking changes before 1.0
- `MorphSearchTabBar.searching` -> `active`, `onSearchingChanged` -> `onActiveChanged` (UIKit `isActive`; already the name in `MorphSearchToolbar`).
- `MorphSearchTabBar.onQueryChanged` -> `onChanged` (one name across `MorphSearchField`, `MorphSearchToolbar`, `MorphSearchTabBar`).
- `MorphSearchToolbar.leading` / `trailing`: `List<MorphBarButton>` -> `List<MorphBarButtonGroup>` (as `MorphToolbar` and `MorphNavigationConfig.toolbarLeading/Trailing`; UIKit `UIBarButtonItemGroup`), so search can be folded into the shared toolbar without a second shape. Coordinate with the `bar_items.dart` refactor.
- `MorphSearchToolbar.buttonStyle` (`MorphGlassButtonStyle`) -> `barStyle: MorphBarStyle` (as `MorphToolbar.style`), keep `style` for the field.
- Optional: `MorphSearchToolbar` -> uncontrolled default stays, but adding `active` makes it a controlled/uncontrolled pair (non-breaking if `active` is nullable).
