# Lists - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UITableView` (`.insetGrouped`), `UICollectionLayoutListConfiguration`, `UIListContentConfiguration`,
`UICellAccessory`, `UITableViewCell.AccessoryType`, `UIBackgroundConfiguration`, `UISwipeActionsConfiguration`
/ `UIContextualAction`, `UICellConfigurationState`; SwiftUI `List`, `Section`, `listStyle`, `LabeledContent`,
`swipeActions`, `listRow*` / `listSection*` modifiers. morph (public): `MorphListSection`,
`MorphSliverListSection`, `MorphListRow`, `MorphListAccessory`, `MorphListAppearance`, `MorphListBackground`.
Internal: `MorphListMetrics`, `MorphListRowHighlightMotion`. Passport: [../lists.md](../lists.md).

SDK 27.1 check: the UIKit list headers carry no iOS 26 / 27 / 27.1 API (newest: iOS 18
`headerConfiguration`, `footerConfiguration`, `listCellConfiguration`, `contentHuggingElements`, `alpha`,
`shadowProperties`). The UIKit Swift overlay adds `UITableView.SelectionDidChangeMessage` (iOS 26, a typed
notification). SwiftUI adds `listSectionMargins(_:_:)`, the `listRowInsets(_:_:)` edge form,
`sectionIndexLabel(_:)` and `listSectionIndexVisibility(_:)` (iOS 26), and in iOS 27
`swipeActions(edge:allowsFullSwipe:content:onPresentationChanged:)` and `swipeActionsContainer()`
(swipe actions outside `List`). Nothing new in 27.1.

Naming: option (b). `MorphListAppearance` is the look table (8 colors); a future variant enum takes
UIKit's noun, `MorphListStyle { insetGrouped, plain, grouped }` (`UITableView.Style`).

## UIKit
| UIKit API (availability) | meaning | morph equivalent | status | proposal |
|---|---|---|---|---|
| `.insetGrouped` (iOS 13 / 14) | rounded inset cards | `MorphListSection`, `MorphSliverListSection` | covered | - |
| `.plain` / `.grouped` | edge-to-edge rows, full-width groups | none | gap (2) | `MorphListStyle` (measure first) |
| `.sidebar` / `.sidebarPlain` | iPad sidebar | - | n/a | - |
| header / footer (`headerMode`, `headerConfiguration()`) | section labels | `header` / `footer` (`Widget?`) | covered (2) | - |
| `headerMode.firstItemInSection` | outline parent row | none | gap | with outline disclosure |
| `showsSeparators` (iOS 14) | separators on / off | always on | gap | `showsSeparators` |
| `separatorConfiguration` (iOS 14.5) | color, insets | `MorphListAppearance.separatorColor` | partial: color only | - |
| `itemSeparatorHandler` (iOS 14.5) | per-row visibility | none | gap | `MorphListRow.showsSeparator` |
| list `backgroundColor` | page behind the cards | `MorphListBackground`, `backgroundColor` | covered | - |
| `headerTopPadding` (iOS 15) | space above a header | fixed (measured) | gap (low) | - |
| `prominentInsetGroupedHeaderConfiguration()` / `extraProminent...` (iOS 15) | larger headers | none | gap | `headerProminence` |
| `leading/trailingSwipeActionsConfigurationProvider` (iOS 14) | swipe actions | none | gap | `MorphSwipeActions` (gap note; see swipe-actions family) |
| `UISwipeActionsConfiguration.performsFirstActionWithFullSwipe` | full swipe | none | gap | with swipe actions |
| `UIContextualAction` (style, title, image, backgroundColor, handler) | one action | none | gap | `MorphSwipeAction` |
| `cellConfiguration()` / `subtitleCellConfiguration()` / `valueCellConfiguration()` | row layouts | `MorphListRow` (`subtitle` / `detail` choose) | covered (3) | - |
| `text` / `attributedText` | primary text | `title` | covered | - |
| `secondaryText` | subtitle or value | `subtitle` / `detail` | covered | - |
| `image` | leading symbol | `leading` | covered | - |
| `imageProperties` (tint, size, reserved width) | symbol styling | `MorphListAppearance.iconColor` | partial: tint only | - |
| `textProperties` / `secondaryTextProperties` | text styling | the widgets' own styles | covered | - |
| `directionalLayoutMargins` | row padding | fixed (measured) | gap | `MorphListRow.padding` (low) |
| `prefersSideBySideTextAndSecondaryText` | value cell stacks when tight | detail wraps at half width | gap | stack as UIKit does (measure first) |
| `.disclosureIndicator` | chevron | `MorphListAccessory.disclosureIndicator` | covered | - |
| `.checkmark` | chosen option | `MorphListAccessory.checkmark` | covered | - |
| `.detailButton` / `UICellAccessory.detail` | info button | `MorphListAccessory.detailButton` + `onAccessoryTap` | covered | - |
| `.detailDisclosureButton` | info + chevron | `MorphListAccessory.detailDisclosureButton` | covered | - |
| `UICellAccessory.label(text:)` | trailing text | `detail` | covered | - |
| `UICellAccessory.customView` | any trailing view | `trailing` | covered | - |
| `UICellAccessory.popUpMenu(_:)` (iOS 16) | trailing pop-up menu | none (a `MorphMenuButton` in `trailing`) | gap | recipe in the dartdoc |
| `.outlineDisclosure` | expand / collapse | none | gap | expandable rows |
| `.delete` / `.insert` / `.reorder` / `.multiselect` | edit mode | none | gap (4) | edit mode |
| `listCellConfiguration()` background | cell fill, radius | `cellColor`, measured radius | covered | - |
| per-cell `backgroundColor` / `customView` | row fill | none | gap | `MorphListRow.backgroundColor` |
| `isHighlighted` | pressed | row highlight | covered | - |
| `isSelected` | persistent selection | checkmark marks `selected` semantics only | partial | `MorphListRow.selected` |
| `isDisabled` | disabled | `enabled` (look unchanged) | partial: look unmeasured | measure |
| `isEditing` / `isSwiped` / `isExpanded` / `isReordering` | states | none | gap | with edit mode, swipe, outline |
| `sectionIndexTitles(for:)` | A-Z index | none | gap | later |
| data source, lazy cells | long lists | `MorphSliverListSection` | covered | - |
| `accessoryButtonTappedForRowWith` | info tapped | `onAccessoryTap` | covered | - |
| `didSelectRowAt` | row tapped | `onTap` | covered | - |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | status | proposal |
|---|---|---|---|---|
| `List { Section(header:footer:) }` | sections with View labels | `MorphListSection(header:, footer:)` | same as UIKit rows | - |
| `listStyle(.insetGrouped / .grouped / .plain / .inset / .sidebar)` | appearance | inset grouped only | same as UIKit rows | `MorphListStyle` |
| `LabeledContent`, `badge(_:)` | title + value | `detail` | same as value cell | - |
| `NavigationLink` in a List | chevron + push | `accessory: .disclosureIndicator`, `onTap` | same | - |
| `swipeActions(edge:allowsFullSwipe:content:)` (iOS 15); `...onPresentationChanged:` (iOS 27) | swipe actions | none | same as UIKit swipe rows | - |
| `swipeActionsContainer()` (iOS 27) | swipe actions outside `List` | none | gap | design `MorphSwipeActions` as a standalone wrapper |
| `onDelete` / `onMove` / `EditButton`, `List(selection:)` | edit, selection | none | same as UIKit edit rows | - |
| `listRowBackground`, `listRowSeparator`, `listSectionSeparator` | row fill, separators | none | same as UIKit rows | - |
| `listRowInsets(_:)`, `listRowInsets(_:_:)` (iOS 26) | row padding | none | gap | `MorphListRow.padding` |
| `listSectionMargins(_:_:)` (iOS 26) | card inset from the edges | fixed 20 pt | gap | `MorphListSection.margin` |
| `listSectionSpacing(_:)` (iOS 17) | space between sections | fixed | gap | `spacing` |
| `sectionIndexLabel(_:)` / `listSectionIndexVisibility(_:)` (iOS 26) | section index | none | same as UIKit index row | - |
| `Section(isExpanded:)` (iOS 17) | collapsible section | none | gap | later |
| `headerProminence(_:)`, `listItemTint(_:)`, `scrollContentBackground(_:)` | header size, symbol tint, background | as UIKit rows | same | - |

Count (UIKit + SwiftUI-only members): 52 applicable, 22 covered, 4 partial, 26 gaps.

## Not relevant for Flutter
- Cell reuse, diffable snapshots, `CellRegistration`, `UIContentView` layout guides, `UIConfigurationColorTransformer`.
- Mac Catalyst / iPad sidebar idioms, `listRowHoverEffect`, `listRowPlatterColor` (visionOS / pointer).
- `UITableView.SelectionDidChangeMessage` (rows keep no selection).
- Text and image spacing constants (`imageToTextPadding`, `textToSecondaryText*Padding`): measured, fixed.

## morph-only API
- `MorphListRow.child` (free content in the text area), `ListTile`-style slot names (`leading`, `trailing`, `title`, `subtitle`).
- `MorphListBackground`: follows a floating sheet's background (clear at the medium detent, grouped gray at the large one).
- Section-wide glass stage for row accessories (behaviour, no API).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | swipe actions (incl. iOS 27 `swipeActionsContainer`) | H | L (measure first) | `MorphSwipeActions` / `MorphSwipeAction` |
| 2 | persistent `selected` state | H | S | `MorphListRow.selected` (systemGray4) |
| 3 | plain / grouped styles | M | M (measure first) | `MorphListStyle` |
| 4 | edit mode: delete / insert / reorder / multiselect | M | L | `editing`, `onDelete`, `onReorder` |
| 5 | localizable "More info" label; Increase Contrast table | M | S | `MorphLocalizations`, high-contrast appearances |
| 6 | per-row background and separator visibility | L-M | S | `backgroundColor`, `showsSeparator` |
| 7 | `listSectionMargins`, section spacing, row insets | L | S | `margin`, `spacing`, `padding` |
| 8 | outline disclosure, section index, header prominence | L | S-M | later |

## Breaking changes before 1.0
- Done: `header` / `footer` are `Widget?`; `chevron` -> `accessory: MorphListAccessory?` with
  `UITableViewCell.AccessoryType` case names; sliver form `MorphSliverListSection`; the look table is `MorphListAppearance`.
- Open: reserve `MorphListStyle { insetGrouped }` and a `style` parameter on both sections now, so
  plain and grouped arrive without a reshape.

## Behaviour fidelity
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | this page | swipe actions, selection, plain / grouped |
| layout | approx | passport "Spec - geometry" (sim tree, `ios27/list/list-tree-*.txt`); test/list_test.dart asserts the native positions (text 36, symbol text 76, symbol center 48, switch end 362, detail end 366) | value cell does not stack (declared); simulator only, 402 pt only; the tree fixture is not loaded by a test |
| states | unbacked | highlight color systemGray4 [layout] | disabled row keeps its look: unmeasured (declared); no persistent selection |
| transitions | measured | highlight after the 0.15 s touch delay, cancel at once, 0.5 s deselect fade (read from UIKit and the layer; sim rows); test/highlight_motion_test.dart checks the constants | the sim highlight rows are not fixtures; keyboard focus highlight unmeasured |
| boundaries | approx | sliver section builds rows in view (test/list_api_test.dart) | detail wraps at half the row width (declared); long titles and Dynamic Type unmeasured |
| configuration | missing | inset grouped only | plain, grouped |
| events | measured | `onTap` on release, `onAccessoryTap` (UIKit didSelect after the highlight, sim) | not replayed |
| input | measured | touch delay only inside a scrollable, scroll cancels the highlight [sim] | not replayed |
| mutation | missing | rows rebuild | UIKit animates row insertion and deletion; morph does not |
| accessibility | missing | button / selected semantics, focus | no Increase Contrast table; English "More info"; Dynamic Type unmeasured |
| optics | approx | colors light / dark [layout, sim] | checkmark and info glyphs drawn by eye; chevron a fitted polyline (both declared) |
| platform | unbacked | sheet background follows the detent [sim] | RTL mirrors without a recording; card inset 20 pt on every width |
| performance | measured | passport "Repaint boundary" (glass audit harness, Redmi 6A and Moto g86, A B B A) | no Pixel 6a run |
