# Lists - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UITableView` (`.insetGrouped`), `UICollectionLayoutListConfiguration`, `UIListContentConfiguration`,
`UICellAccessory`, `UIBackgroundConfiguration`, `UISwipeActionsConfiguration` / `UIContextualAction`,
`UICellConfigurationState`; SwiftUI `List`, `Section`, `listStyle`, `LabeledContent`, `swipeActions`,
`listRow*` / `listSection*` modifiers, `badge`, `onDelete` / `onMove`. morph: `MorphListSection`,
`MorphListRow`, `MorphListStyle`, `MorphListMetrics`. Passport: [../lists.md](../lists.md).

SDK 27.0 check: UIKit list headers carry no iOS 26 / 27 API (newest: iOS 18 `headerConfiguration`,
`footerConfiguration`, `listCellConfiguration`, `contentHuggingElements`, `alpha`, `shadowProperties`).
SwiftUI adds, with Liquid Glass: `listSectionMargins(_:_:)` (iOS 26), `listRowInsets(_:_:)` edge form
(iOS 26), `sectionIndexLabel(_:)` + `listSectionIndexVisibility(_:)` (iOS 26), and in iOS 27 a
non-generic `swipeActions(edge:allowsFullSwipe:content:)` overload plus `swipeActionsContainer()`
(swipe actions outside `List`).

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UITableView.Style.insetGrouped` (iOS 13) / `UICollectionLayoutListConfiguration.Appearance.insetGrouped` (iOS 14) | rounded inset cards | `MorphListSection` (only style) | none | keep |
| `.plain` / `.grouped` (iOS 2+ / 14) | edge-to-edge rows / full-width groups | none | missing | add `MorphListAppearance { plain, grouped, insetGrouped }` on the section (needs measurement) |
| `.sidebar` / `.sidebarPlain` (iOS 14) | iPad sidebar | none | - | skip (iPad sidebar out of scope) |
| `UICollectionLayoutListConfiguration.headerMode` / `footerMode` (iOS 14) | supplementary header / footer | `MorphListSection.header` / `footer` (String?) | String only | reshape -> Widget? (see Breaking) |
| `headerMode.firstItemInSection` (iOS 14) | outline parent row | none | - | skip (with outline disclosure) |
| `showsSeparators` (iOS 14) | separators on/off | none (always) | missing | add `MorphListSection.showsSeparators = true` |
| `separatorConfiguration` / `itemSeparatorHandler` (iOS 14.5) | color, insets, per-item visibility | `MorphListStyle.separatorColor` | no per-row visibility / inset | add `MorphListRow.showsSeparator` (null = auto) |
| `backgroundColor` (iOS 14) | list background | `MorphListStyle.backgroundColor` (color for the app's page) | not painted by the section | keep |
| `leading/trailingSwipeActionsConfigurationProvider` (iOS 14) | swipe actions per row | none | missing | add `MorphListRow.leadingActions` / `trailingActions` (`MorphSwipeActions`) |
| `UISwipeActionsConfiguration(actions:)`, `performsFirstActionWithFullSwipe` (iOS 11) | action set, full swipe | none | missing | add `MorphSwipeActions(actions, allowsFullSwipe: true)` (SwiftUI name) |
| `UIContextualAction(style:title:handler:)`, `.image`, `.backgroundColor` (iOS 11) | one action | none | missing | add `MorphSwipeAction(label, icon, style, backgroundColor, onPressed)` |
| `UIContextualAction.Style.normal` / `.destructive` (iOS 11) | gray vs red, destructive removes row | none | missing | add `MorphSwipeActionStyle.normal` / `destructive` |
| `headerTopPadding` (iOS 15) | space above header | `MorphListMetrics.headerTop` (const) | not settable | skip (measured constant) |
| `contentHuggingElements` (iOS 18) | header hugs content | none | - | skip |
| `UIListContentConfiguration.cell()` / `subtitleCell()` / `valueCell()` (iOS 14) | row layouts | `MorphListRow` (`subtitle` / `detail` select the layout) | one widget instead of three | keep |
| `.text` / `.attributedText` | primary text | `MorphListRow.title` (Widget) | Widget instead of String (Flutter `ListTile` idiom) | keep |
| `.secondaryText` | subtitle or value text | `MorphListRow.subtitle` / `detail` | split by role | keep |
| `.image`, `.imageProperties` (tint, cornerRadius, maximumSize, reservedLayoutSize) | leading symbol | `MorphListRow.leading`, `MorphListStyle.iconColor`, `MorphListMetrics.leadingIconSize` | no per-row size / reserved width | skip (Widget sizes itself) |
| `.textProperties` / `.secondaryTextProperties` (font, color, numberOfLines) | text styling | Widgets carry their style; defaults from `MorphTypography` | none | keep |
| `.directionalLayoutMargins` | row padding | `MorphListMetrics` constants | not per row | add `MorphListRow.padding` (EdgeInsetsDirectional?); low |
| `.prefersSideBySideTextAndSecondaryText` | value cell stacks when tight | not reproduced (detail wraps at half width) | behaviour gap (passport open) | add behaviour, no param; low |
| `.imageToTextPadding`, `.textToSecondaryText{Horizontal,Vertical}Padding` | spacing | `MorphListMetrics.leadingGap`, `gap` | constants | keep |
| `.alpha` (iOS 18) | content alpha | none | - | skip (Opacity) |
| `headerConfiguration()` / `footerConfiguration()` (iOS 18) | header / footer text | `header` / `footer` | none | keep |
| `prominentInsetGroupedHeaderConfiguration()` / `extraProminent...` (iOS 15) | larger headers | none | missing | add `MorphListSection.headerProminence` (`standard` / `increased`); low |
| `UICellAccessory.disclosureIndicator` (iOS 14) | chevron | `MorphListRow.chevron` | bool | reshape (see Breaking) |
| `UICellAccessory.checkmark` (iOS 14) | selected mark | none | missing | add (accessory enum) |
| `UICellAccessory.detail` (iOS 14) | info button | none | missing | add (accessory enum + callback); low |
| `UICellAccessory.label(text:)` (iOS 14) | trailing text | `MorphListRow.detail` | none | keep |
| `UICellAccessory.customView` (iOS 14) | any trailing view | `MorphListRow.trailing` | none | keep |
| `UICellAccessory.popUpMenu(_:)` (iOS 14) | trailing pop-up menu | none (app can put a `MorphMenuButton` in `trailing`) | no built-in | doc recipe; skip API |
| `UICellAccessory.outlineDisclosure` (iOS 14) | expand / collapse children | none | missing | add later (expandable rows); low-med |
| `.delete` / `.insert` / `.reorder` / `.multiselect` (iOS 14, `.whenEditing`) | edit mode accessories | none | missing | add with an edit mode (`MorphListSection.editing`); med, L |
| `UICellAccessory.DisplayedState` / `Placement` | when / where shown | none | - | skip until edit mode |
| `UIBackgroundConfiguration.listCellConfiguration()` (iOS 18) | cell fill + corner radius | `MorphListStyle.cellColor`, `MorphListMetrics.cornerRadius` | none | keep |
| `UIBackgroundConfiguration.backgroundColor` / `customView` / `visualEffect` / `cornerRadius` / `stroke*` / `shadowProperties` | per-cell background | none per row | missing | add `MorphListRow.backgroundColor` (SwiftUI `listRowBackground`); low-med |
| `UICellConfigurationState.isHighlighted` | pressed | `MorphListRow` (highlight on tap-down, `MorphListStyle.highlightColor`) | timing unmeasured | keep |
| `UICellConfigurationState.isSelected` | selected (sidebar, split views) | none | missing | add `MorphListRow.selected` (systemGray4, same as highlight) |
| `UICellConfigurationState.isDisabled` | disabled | `MorphListRow.enabled` | look unmeasured | keep |
| `isEditing` / `isSwiped` / `isExpanded` / `isReordering` | states | none | missing | with edit mode / swipe / outline |
| `UITableView.sectionIndexTitles(for:)` | A-Z index | none | missing | add later; low |
| diffable data source, cell reuse, `UICollectionViewCompositionalLayout.list` | data plumbing | sections are plain widgets | no lazy building inside a long section | add `MorphListSection.sliver` / builder form; high |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `List { Section(header:footer:) { } }` (iOS 13) | header / footer are Views | `header` / `footer` String? | String only | reshape -> Widget? |
| `Section(isExpanded:)` (iOS 17) | collapsible section | none | missing | low; skip for now |
| `listStyle(.insetGrouped / .grouped / .plain / .inset / .sidebar)` (iOS 13-14) | appearance | inset grouped only | same as UIKit appearance row | add `MorphListAppearance` |
| `LabeledContent(_:value:)` (iOS 16) | title + trailing value | `MorphListRow(title:, detail:)` | none | keep |
| `NavigationLink` in a List | chevron + push | `MorphListRow(chevron: true, onTap:)` | none | keep |
| `swipeActions(edge:allowsFullSwipe:content:)` (iOS 15; non-generic overload iOS 27) | swipe actions | none | missing | add (`allowsFullSwipe` name) |
| `swipeActionsContainer()` (iOS 27) NEW | swipe actions outside `List` | none | missing | design `MorphSwipeActions` as a standalone wrapper usable outside sections |
| `onDelete(perform:)` / `onMove(perform:)` / `deleteDisabled` / `moveDisabled` / `EditButton` (iOS 13) | delete / reorder | none | missing | add with edit mode (`onDelete`, `onReorder` callbacks) |
| `listRowBackground(_:)` (iOS 13) | row fill | none | missing | add `MorphListRow.backgroundColor` |
| `listRowSeparator(_:edges:)` / `listRowSeparatorTint` / `listSectionSeparator` (iOS 15) | separator control | `MorphListStyle.separatorColor` | per row missing | add `MorphListRow.showsSeparator` |
| `listRowInsets(_:)` (iOS 13), `listRowInsets(_:_:)` edges form (iOS 26) | row padding | none | missing | add `MorphListRow.padding`; low |
| `listSectionMargins(_:_:)` (iOS 26) NEW | card inset from the screen edges | `MorphListMetrics.sectionInset` (20, const) | not settable | add `MorphListSection.margin` (EdgeInsetsDirectional?); low |
| `listSectionSpacing(.default / .compact / CGFloat)` (iOS 17) | space between sections | fixed by header/footer metrics | not settable | add `MorphListSection.spacing`; low |
| `listRowSpacing(_:)` (iOS 15) | gaps between rows | none | - | skip |
| `sectionIndexLabel(_:)` / `listSectionIndexVisibility(_:)` (iOS 26) NEW | section index | none | missing | same as UIKit index row; low |
| `headerProminence(.increased)` (iOS 15) | large header | none | missing | add `headerProminence`; low |
| `badge(_:)` on rows (iOS 15) | trailing count | `MorphListRow.detail` | detail covers text | keep |
| `listItemTint(_:)` (iOS 14) | leading symbol tint | `MorphListStyle.iconColor` | none | keep |
| `List(selection:)` (iOS 13) | selection / multiselect | none | missing | with `selected` + edit mode |
| `scrollContentBackground(.hidden)` (iOS 16) | hide grouped background | `MorphListStyle.backgroundColor` is app-painted | none | keep |

## Not relevant for Flutter
- Cell reuse, `dequeueReusableCell`, diffable snapshots, `UICollectionView.CellRegistration` (Flutter builders).
- `UIContentView` / `UIListContentView` layout guides (`textLayoutGuide` etc.).
- `UIConfigurationColorTransformer` (Flutter computes colors in build).
- Mac Catalyst / iPad sidebar idioms (`accompaniedSidebarCellConfiguration`, `.sidebarPlain`).
- `listRowHoverEffect`, `listRowPlatterColor` (visionOS / pointer).
- Accessibility custom actions for swipe actions: Flutter `Semantics.customSemanticsActions` (implement with swipe).

## morph-only API
- `MorphListRow.child` (free content in the text area) - keep (UIKit uses a custom content configuration).
- `MorphListRow.leading` / `trailing` / `title` / `subtitle` naming from Flutter `ListTile` - keep.
- `MorphListRow.enabled` plus `onTap` null - keep (ListTile has both).
- `MorphListStyle` (8 colors), `MorphListMetrics` (measured constants) - keep.
- Section-wide glass stage for row accessories - internal behaviour, no API.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | swipe actions (`UIContextualAction`, `swipeActions`, full swipe; iOS 27 `swipeActionsContainer`) | high (mail, lists of items) | L (gesture + measured spring/reveal + glass buttons) | add `MorphSwipeActions` / `MorphSwipeAction` / `MorphSwipeActionStyle`, rows take `leadingActions` / `trailingActions` |
| 2 | long sections: lazy / sliver form | high (any data list) | M | add `MorphListSection.sliver` (builder + itemCount) |
| 3 | checkmark accessory + `selected` state | high (settings pickers) | S | accessory enum + `MorphListRow.selected` |
| 4 | plain / grouped appearances | med | M (two layouts to measure) | add `MorphListAppearance` |
| 5 | edit mode: delete / insert / reorder / multiselect | med | L | add `editing` + `onDelete` / `onReorder` |
| 6 | header / footer as Widgets | med | S | breaking reshape (below) |
| 7 | per-row background / separator visibility | low-med | S | add `backgroundColor`, `showsSeparator` |
| 8 | `listSectionMargins` (iOS 26), section spacing, row insets | low | S | add `margin`, `spacing`, `padding` |
| 9 | outline disclosure (expandable rows) | low-med | M | later |
| 10 | section index, header prominence, detail (info) accessory | low | S-M | later |

## Breaking changes before 1.0
- `MorphListSection.header` / `footer`: `String?` -> `Widget?` (SwiftUI `Section(header:footer:)` takes
  Views; Flutter idiom; allows a trailing "See All" button in a header). The section keeps applying the
  measured header / footer text style through `DefaultTextStyle`.
- `MorphListRow.chevron` (bool) -> `accessory: MorphListAccessory?` with UIKit case names
  (`disclosureIndicator`, `checkmark`, `detail`), so adding checkmark / info later is not another bool.
  `trailing` stays for custom views (UIKit `customView`).
- Reserve `MorphListAppearance { insetGrouped, ... }` (UIKit's own enum noun, so no clash with the
  `MorphListStyle` color table); add the parameter now with only `insetGrouped` if the others wait.
