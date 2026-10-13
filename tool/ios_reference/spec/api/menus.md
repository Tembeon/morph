# Menus - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIMenu`, `UIMenuElement`, `UIMenuLeaf`, `UIAction`, `UIDeferredMenuElement`,
`UIMenuDisplayPreferences`, `UIButton.menu` / `showsMenuAsPrimaryAction` /
`changesSelectionAsPrimaryAction` / `preferredMenuElementOrder`, `UIContextMenuInteraction` (+ delegate),
`UIContextMenuConfiguration`, `UITargetedPreview`, `UIPreviewParameters`; SwiftUI `Menu`, `menuOrder`,
`menuActionDismissBehavior`, `menuStyle`, `menuIndicator`, `contextMenu(menuItems:preview:)`,
`contextMenu(forSelectionType:)`, `ControlGroup` / `controlGroupStyle`, `Picker` in menus, `Toggle`,
`Section`, `Divider`, `Label`. morph: `MorphMenuButton`, `MorphMenuSource`, `MorphMenuTrigger`,
`MorphMenuStyle`, `MorphMenuEntry` (`MorphMenuItem`, `MorphMenuSection`, `MorphSubmenu`,
`MorphMenuDivider`, `MorphMenuDeferred`, `MorphMenuWidget`), `MorphMenuState`,
`MorphMenuIconVisibility`, `MorphMenuElementSize`, `MorphMenuOrder`, `MorphContextMenuRegion`,
`MorphSatellite`, layout / motion classes (`MorphMenuLayout`, `MorphMenuMetrics`, `MorphMenuPlaced`,
`MorphMenuPlacedKind`, `MorphMenuTarget`, `MorphMenuTargetKind`, `MorphMenuMorphSpec`, `MorphMenuMotion`,
`MorphMenuBlob`, `MorphMenuCard`, `MorphMenuProgress`, `MorphMenuTuning`); menus also on
`MorphGlassButton.menu`, `MorphBarButton.menu`. No `showMorphMenu` in lib/foundation.dart (engine has
only `showMorph` + `MorphTargetSpec.popover`). Passports: [../menu-api.md](../menu-api.md),
[../menu-button.md](../menu-button.md), [../context-menu.md](../context-menu.md).

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIMenuElement.title` (iOS 13) | row text | `MorphMenuItem.title`, `MorphSubmenu.title`, `MorphMenuSection.title` | none | keep |
| `UIMenuElement.subtitle` (iOS 15) | second line | `MorphMenuItem.subtitle`, `MorphSubmenu.subtitle` | none | keep |
| `UIMenuElement.image` (iOS 13) | row image | `MorphMenuItem.icon` / `MorphSubmenu.icon` (`IconData?`) | only font glyphs; no image / avatar / custom widget | see breaking (`Widget?`) or add `iconBuilder` |
| `UIMenuElement.preferredImageVisibility .automatic/.visible/.hidden` (iOS 27, NEW) | show/hide row image | `MorphMenuItem.iconVisibility` (`MorphMenuIconVisibility`) | none on `MorphSubmenu` | keep; add to `MorphSubmenu` |
| `UIMenuElement.highlightStateUpdateHandler` (iOS 27, NEW) | row highlighted under the finger | `MorphMenuItem.onHighlightChanged` | none | keep |
| `UIMenuLeaf.selectedImage` (iOS 17) | image when `state == .on` | `MorphMenuItem.selectedIcon` | none | keep |
| `UIMenuLeaf.discoverabilityTitle` (iOS 13) | text for the keyboard-shortcut HUD / hint | none | | skip (use `Semantics`) |
| `UIMenuElement.Attributes.disabled` (iOS 13) | disabled row | `MorphMenuItem.enabled = false`, `MorphSubmenu.enabled` | none | keep |
| `.destructive` (iOS 13) | red row | `MorphMenuItem.destructive`, `MorphSubmenu.destructive` | none | keep |
| `.hidden` (iOS 13) | hidden row (kept for key commands) | `MorphMenuItem.hidden`, `MorphSubmenu.hidden` | none | keep |
| `.keepsMenuPresented` (iOS 16) | row does not close the menu | `MorphMenuItem.keepsMenuOpen` | none (Flutter "open") | keep |
| `UIMenuElement.State .off/.on/.mixed` (iOS 13) | checkmark / dash | `MorphMenuItem.state` (`MorphMenuState`) | none | keep |
| `UIAction.identifier` (iOS 13) | stable identity | none on `MorphMenuItem` (`MorphMenuWidget.id`, `MorphMenuDeferred.id` exist) | live updates diff by position | add `MorphMenuItem.id` (keys rows across `updateVisibleMenu`-style rebuilds) |
| `UIAction.handler` / `performWithSender` (iOS 13) | action | `MorphMenuItem.onSelected` | none | keep |
| `UIMenuLeaf.repeatBehavior` (iOS 26) | key-repeat for key commands | none | | skip (hardware keyboard commands) |
| `UIMenuLeaf.presentationSourceItem` (iOS 16) | the row as a source for a follow-up popover | none | | skip (low) |
| `UIMenu(title:subtitle:image:identifier:options:children:)` (iOS 13+) | group | `MorphMenuSection` (inline) / `MorphSubmenu` (nested) | `.displayInline` split into two types: idiomatic sealed hierarchy | keep |
| `UIMenu.Options.displayInline` (iOS 13) | inline section | `MorphMenuSection` | none | keep |
| `UIMenu.Options.destructive` (iOS 13) | red group | `MorphSubmenu.destructive` | missing on `MorphMenuSection` | add (low) |
| `UIMenu.Options.singleSelection` (iOS 15) | radio group | `MorphMenuSection.singleSelection`, `MorphSubmenu.singleSelection` | none | keep |
| `UIMenu.Options.displayAsPalette` (iOS 17) | horizontal icon row | `MorphMenuSection.palette` | none | keep |
| `UIMenu.preferredElementSize .small/.medium/.large/.automatic` (iOS 16/17) | row size | `elementSize` (`MorphMenuElementSize`, same case order) | none | keep |
| `UIMenu.selectedElements` (iOS 15) | which children are on | none | state lives in the app (`MorphMenuItem.state`) | skip (Flutter idiom) |
| `UIMenu.displayPreferences.maximumNumberOfTitleLines` (iOS 17.4) | title line cap | `MorphMenuSection.maxTitleLines` | missing on `MorphSubmenu` and on the root menu | add `maxTitleLines` to `MorphSubmenu` and the menu sources |
| `UIMenu.menuByReplacingChildren` (iOS 13) | copy with children | none | | skip (rebuild const lists) |
| `UIDeferredMenuElement(_:)` cached (iOS 14) | async rows with "Loading" | `MorphMenuDeferred(load, cache: true)` | none | keep |
| `UIDeferredMenuElement.uncached(_:)` (iOS 15) | reload every open | `MorphMenuDeferred(cache: false)` | none | keep |
| `UIDeferredMenuElement.identifier` (iOS 26) | identity of the deferred element | `MorphMenuDeferred.id` | none | keep |
| `UIDeferredMenuElement.usingFocus(identifier:shouldCacheItems:)` (iOS 26) | focus-system provided items | none | | skip (focus responder chain) |
| `UIButton.menu` + `showsMenuAsPrimaryAction = true` (iOS 14) | tap opens the menu | `MorphMenuButton(items:)`, `MorphMenuSource(trigger: MorphMenuTrigger.tap)`, `MorphGlassButton(menu:)`, `MorphBarButton(menu:)` | `items` vs `menu` naming split (see breaking) | keep concept |
| `UIButton.menu` + primary action (long-press menu) (iOS 14) | tap = action, hold = menu | `MorphMenuSource(trigger: MorphMenuTrigger.hold, onTap:)` | hold timing is the round button's (declared) | keep |
| `UIButton.changesSelectionAsPrimaryAction` (iOS 15) | pop-up button: title shows the chosen item | none | a common control ("Sort: Date") is missing | add `MorphPopUpButton<T>(value:, onChanged:, items:)` on `MorphMenuSource` with a single-selection section |
| `UIButton.preferredMenuElementOrder` / `UIContextMenuConfiguration.preferredMenuElementOrder` (iOS 16) | `.automatic/.priority/.fixed` | `MorphMenuSource.order` / `MorphMenuButton.order` (`MorphMenuOrder`) | none on `MorphContextMenuRegion` | keep; add to region with item rows |
| `UIControl.isContextMenuInteractionEnabled` (iOS 14) | menu on/off | `enabled` | none | keep |
| `UIContextMenuInteraction(delegate:)` + `configurationForMenuAtLocation` (iOS 13) | hold-to-open context menu with UIMenu rows | `MorphContextMenuRegion(child:, above:, below:)` with `MorphSatellite` widgets | NO UIMenu-row context menu: the app builds the rows itself | add `MorphContextMenuRegion.items: List<MorphMenuEntry>` drawing the measured menu card as the `below` satellite |
| `UIContextMenuConfiguration.previewProvider` (iOS 13) | a different view as the preview | none (the held `child` is the preview; `replica` is only an in-flight stand-in) | "peek" previews (a link, a photo larger than its thumbnail) | add `preview: WidgetBuilder?` |
| `previewForHighlightingMenu` / `previewForDismissingMenu` + `UITargetedPreview` (iOS 13/16) | which view lifts and where it returns | the region's `child` and its `MorphTag` | can not lift a sub-part or return elsewhere | skip (low) |
| `UIPreviewParameters.visiblePath` / `backgroundColor` / `shadowPath` (iOS 13/14) | preview shape and fill | none (child draws itself) | can not round a rectangular child while lifted | add `previewShape: ShapeBorder?` (low) |
| `willPerformPreviewActionForMenu` + `UIContextMenuInteractionCommitStyle .dismiss/.pop` (iOS 13) | tap the preview to commit (pop into it) | none | "peek and pop" missing | add `onPreviewTap` (+ commit into a page via `showMorphRoute`) |
| `willDisplayMenu` (iOS 13) | menu shows | `MorphContextMenuRegion.onOpen`, `MorphMenuSource.onOpen` (`ValueChanged<MorphFlight>`); region also `onHold` | none | keep |
| `willEndFor configuration` (iOS 13) | menu closes | none (only via the `MorphFlight` events) | | add `onClose: VoidCallback?` (S) |
| `updateVisibleMenu(_:)` (iOS 14) | change an open menu | rebuild with new `items` (the open menu follows the widget) | none | keep |
| `dismissMenu()` (iOS 14) | close programmatically | `MorphFlight.close()` from `onOpen` | indirect | add `MorphMenuSource.close(context)` beside the existing `MorphMenuSource.open(context)` |
| `menuAppearance .rich/.compact` (iOS 14) | modal with preview vs compact non-modal | rich = `MorphContextMenuRegion`; compact = `MorphMenuSource(trigger: hold)` | read-only in UIKit | skip |
| `UIContextMenuConfiguration.badgeCount` (iOS 16) | count badge on the lifted multi-item preview | none | | skip (multi-item drag/selection only) |
| `secondaryItemIdentifiers` (iOS 16) | multi-selection context menus | none | | skip (collection views) |
| `allowsTypeSelect` (iOS 27, NEW) | type-to-select in the open menu (hardware keyboard) | none | | add later (low; keyboard focus already exists) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Menu(content:label:)` (iOS 14) | button that opens a menu | `MorphMenuSource(child:, items:)` / `MorphMenuButton` | none | keep |
| `Menu(content:label:primaryAction:)` (iOS 15) | tap = action, hold = menu | `MorphMenuSource(trigger: hold, onTap:)` | none | keep |
| `menuOrder(.automatic/.priority/.fixed)` (iOS 16) | element order | `order: MorphMenuOrder` | none | keep |
| `menuActionDismissBehavior(.automatic/.enabled/.disabled)` (iOS 16.4) | rows close the menu or not | `dismissOnSelect: bool?` (null = automatic) | bool? instead of an enum | keep |
| `menuStyle(.button/.borderlessButton/...)` (iOS 14) | label look | `MorphMenuStyle` (colors, `buttonSize`) + `MorphMenuSource.look/shape/color` | concept differs (morph styles the menu, not the label) | keep |
| `menuIndicator(.visible/.hidden)` (iOS 15) | chevron on the label | none | pairs with the pop-up button | add with `MorphPopUpButton` |
| `contextMenu(menuItems:)` (iOS 13) | hold menu of rows | `MorphContextMenuRegion` (satellites only) | rows not built in | add `items:` (ranked gap 1) |
| `contextMenu(menuItems:preview:)` (iOS 16) | custom preview | none | | add `preview:` |
| `contextMenu(forSelectionType:menu:primaryAction:)` (iOS 16) | List/Table selection menus | none | | skip (no morph List selection model) |
| `Section(title)` / `Divider` (iOS 13) | inline group / separator | `MorphMenuSection(title:)` / `MorphMenuDivider` | none | keep |
| nested `Menu` (iOS 14) | submenu | `MorphSubmenu` | none | keep |
| `Toggle` in a menu (iOS 14) | checkmark row | `MorphMenuItem(state:)` | no bool convenience | keep (state + onSelected is enough) |
| `Picker` `.inline` / `.menu` / `.palette` (iOS 14/17) | radio rows / radio submenu / icon row | `MorphMenuSection(singleSelection:)` / `MorphSubmenu(singleSelection:)` / `MorphMenuSection(palette:)` | no typed value helper | optional `MorphMenuSection.picker<T>(value:, onChanged:, options:)` factory (low) |
| `ControlGroup` + `controlGroupStyle(.palette/.compactMenu/.menu)` (iOS 16/17) | small/medium cells, palette | `MorphMenuSection(elementSize: small/medium, palette:)` | none | keep |
| `Button(role: .destructive)` in a menu | red row | `MorphMenuItem.destructive` | none | keep |
| `Label(title, systemImage:)` / two-`Text` label (iOS 14/15) | title + icon / subtitle | `title`, `icon`, `subtitle` | none | keep |
| `Slider` / `Stepper` in a menu (measured: become Decrement/Increment medium cells under a header) | value control in a menu | `MorphMenuWidget` (free-form) | native has no free-form row | add `MorphMenuStepperRow` for parity (low, see menu-api.md) |
| `ShareLink` in a menu (iOS 16) | system share row | none | | skip (platform share sheet plugin) |

## Not relevant for Flutter
- `UICommand`, `UIKeyCommand`, `UIMenuBuilder`, `UIMenu.Identifier` system menus, `UIMenuSystem`: main-menu / key-command plumbing of the responder chain.
- `UIAction.sender`, target-action, `performWithSender:target:`: Dart closures.
- `UIAction.captureTextFromCamera`: system Live Text action.
- NSCoding initialisers (`initWithCoder:`), `UIContextMenuInteractionAnimating.addAnimations/addCompletion`: UIKit animation plumbing (Futures/flights cover it).
- `UIContextMenuInteraction.locationInView:`: Flutter gesture details.
- `LocalizedStringKey` overloads, `menuStyle` macOS variants, `contextMenu` on `TabContent`/table rows.

## morph-only API
- `MorphMenuWidget` (free-form row, no UIKit twin since UIKit 27 has no custom-view element) - keep, declared extension.
- `MorphContextMenuRegion` satellites (`above` reactions capsule, `below`), `MorphSatellite`, `lifts`, `holdDuration`, `alignment`, `gap`, `margin`, `opensOnSecondaryTap`, `replica` - keep (message-bubble pattern beyond UIKit).
- `MorphMenuSource.look`, `shape`, `color`, `rimColor`, `focusable`, `MorphMenuItem.iconColor`, static `MorphMenuSource.open` - keep.
- `MorphMenuMotion`, `MorphMenuTuning`, `MorphMenuProgress`, `MorphMenuBlob`, `MorphMenuCard`, `MorphMenuMorphSpec` - pure measured motion, keep.
- `MorphMenuLayout`, `MorphMenuMetrics`, `MorphMenuPlaced`, `MorphMenuPlacedKind`, `MorphMenuTarget`, `MorphMenuTargetKind` - layout internals exported; no use in example/ or outside lib. FLAG: hide before 1.0 unless a consumer needs them.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | Context menu with standard rows (`UIContextMenuInteraction` + UIMenu, SwiftUI `contextMenu(menuItems:)`) | high | M | `MorphContextMenuRegion(items: List<MorphMenuEntry>, order:)` drawing the measured menu card (sections, submenus, deferred) as the below slot; satellites stay for custom blocks |
| 2 | Pop-up button (`changesSelectionAsPrimaryAction`, `menuIndicator`) | high | M | `MorphPopUpButton<T>` over `MorphMenuSource`: shows the selected title + chevron, single-selection rows |
| 3 | Row images beyond `IconData` (`UIMenuElement.image` any image) | med | S | `icon: Widget?` (breaking) or additive `iconBuilder` |
| 4 | Custom preview + commit (`previewProvider`, `willPerformPreviewAction`, `contextMenu(preview:)`) | med | M | `preview: WidgetBuilder?`, `onPreviewTap` (commit into a page via `showMorphRoute`) |
| 5 | Programmatic close + close callback (`dismissMenu`, `willEnd`) | med | S | `MorphMenuSource.close(context)`, `onClose` on sources and region |
| 6 | Stable row identity (`UIAction.identifier`) for live updates | low-med | S | `MorphMenuItem.id`, `MorphSubmenu.id` |
| 7 | `maxTitleLines` / `iconVisibility` / `destructive` on every UIMenu level | low | S | add to `MorphSubmenu`, root (sources), `MorphMenuSection.destructive` |
| 8 | `previewShape` (`UIPreviewParameters.visiblePath`) | low | S | add `previewShape: ShapeBorder?` |
| 9 | `allowsTypeSelect` (27) | low | S | later |
| 10 | Stepper/slider parity rows (`MorphMenuStepperRow`) | low | S | optional |

## Breaking changes before 1.0
- `MorphMenuButton.items` / `MorphMenuSource.items` vs `MorphGlassButton.menu` / `MorphBarButton.menu` (both `List<MorphMenuEntry>`): one concept, two names. Proposal: `items` -> `menu` everywhere (UIKit `UIButton.menu`, `UIBarButtonItem.menu`); `MorphMenuSection.children` / `MorphSubmenu.children` stay (`UIMenu.children`).
- `MorphMenuItem.icon` / `MorphSubmenu.icon` / `selectedIcon`: `IconData?` -> `Widget?` (Flutter `MenuItemButton.leadingIcon` idiom; images, avatars, tinted symbols). If kept as `IconData`, add `iconBuilder` instead and no break.
- Hide `MorphMenuLayout`, `MorphMenuMetrics`, `MorphMenuPlaced`, `MorphMenuPlacedKind`, `MorphMenuTarget`, `MorphMenuTargetKind` from `lib/widgets.dart` (internal layout; unused outside lib/ and test/).
- `MorphMenuItem.keepsMenuOpen` vs UIKit `keepsMenuPresented`: keep (Flutter word, documented mapping). `dismissOnSelect: bool?` vs SwiftUI `MenuActionDismissBehavior`: keep.
