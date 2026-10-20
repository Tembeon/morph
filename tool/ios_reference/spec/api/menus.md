# Menus - API parity (UIKit / SwiftUI iOS 27.1 vs morph)

Native: `UIMenu`, `UIMenuElement`, `UIMenuLeaf` (`UIAction`), `UIDeferredMenuElement`,
`UIMenuDisplayPreferences`, `UIButton.menu` / `showsMenuAsPrimaryAction` /
`changesSelectionAsPrimaryAction` / `preferredMenuElementOrder`, `UIBarButtonItem.menu`,
`UIContextMenuInteraction` (+ delegate), `UIContextMenuConfiguration`, `UITargetedPreview`,
`UIPreviewParameters`, `UIEditMenuInteraction`; SwiftUI `Menu`, `menuOrder`,
`menuActionDismissBehavior`, `menuStyle`, `menuIndicator`, `contextMenu(menuItems:preview:)`,
`ControlGroup`, `Picker` in menus, `Toggle`, `Section`, `Divider`.

SDK: iPhoneOS27.1.sdk. 27.1 changes nothing in these headers or in SwiftUI's menu API. The iOS 27
additions are `UIMenuElement.preferredImageVisibility`, `highlightStateUpdateHandler` and
`UIContextMenuConfiguration.allowsTypeSelect`.

morph (`lib/morph.dart`, names as in `test/api/public_api.txt`): `MorphMenuButton`,
`MorphMenuSource`, `MorphMenuTrigger`, `MorphMenuAppearance`, the entries (`MorphMenuEntry`:
`MorphMenuItem`, `MorphMenuSection`, `MorphSubmenu`, `MorphMenuDivider`, `MorphMenuDeferred`,
`MorphMenuWidget`), `MorphMenuState`, `MorphMenuIconVisibility`, `MorphMenuElementSize`,
`MorphMenuOrder`, `MorphContextMenuRegion`, `MorphSatellite`; menus also on
`MorphGlassButton(menu:)` and `MorphBarButton(menu:)`. Internal: motion, tuning and layout
(`MorphMenuMotion`, `MorphMenuTuning`, `MorphMenuLayout`, `MorphMenuMetrics`, ...), the sources'
`tuning` and `onOpen`, and the region's `onOpen`, `open(context)`, `tagId`, `overlay`,
`scrimMotion`. Passports: [../menu-api.md](../menu-api.md), [../menu-button.md](../menu-button.md),
[../context-menu.md](../context-menu.md).

## UIKit - menu content and button menus
| UIKit API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIMenuElement.title` (13) | row text | `title` on item, submenu, section | none | keep |
| `UIMenuElement.subtitle` (15) | second line | `subtitle` on item and submenu | none | keep |
| `UIMenuElement.image` (13) | row image | `icon: Widget?` on item and submenu | none | keep |
| `preferredImageVisibility` (27) | show / hide the image | `MorphMenuItem.iconVisibility` | missing on `MorphSubmenu` (a `UIMenu` is an element too) | add to `MorphSubmenu` |
| `highlightStateUpdateHandler` (27) | row highlighted | `MorphMenuItem.onHighlightChanged` | none (timing unmeasured) | keep |
| `UIMenuLeaf.selectedImage` (17) | image while on | `MorphMenuItem.selectedIcon` | none | keep |
| attributes `.disabled` / `.destructive` / `.hidden` (13) | row look and presence | `enabled`, `destructive`, `hidden` on item and submenu | none | keep |
| attributes `.keepsMenuPresented` (16) | row keeps the menu | `MorphMenuItem.keepsMenuOpen` | none | keep |
| `state` `.off/.on/.mixed` (13) | check / dash | `MorphMenuItem.state` (`MorphMenuState`) | none | keep |
| `UIAction.identifier` (13) | stable identity | none on item or submenu | a live rebuild diffs by position | add `id` |
| `UIAction` handler (13) | action | `MorphMenuItem.onSelected` | none | keep |
| `UIMenuLeaf.presentationSourceItem` (16) | row as a popover source | none | gap | after a general popover exists |
| `UIMenu(title:subtitle:image:identifier:options:children:)` (13) | group | `MorphMenuSection` (inline) / `MorphSubmenu` (nested) | split into two types | keep |
| `UIMenu.Options.displayInline` (13) | inline group | `MorphMenuSection` | none | keep |
| `UIMenu.Options.destructive` (13) | red group | `MorphSubmenu.destructive` | missing on `MorphMenuSection` | add |
| `UIMenu.Options.singleSelection` (15) | radio group | `singleSelection` on section and submenu | none | keep |
| `UIMenu.Options.displayAsPalette` (17) | icon row | `MorphMenuSection.palette` | none | keep |
| `UIMenu.preferredElementSize` (16; `.automatic` 17) | small / medium / large cells | `elementSize` (`MorphMenuElementSize`) | none | keep |
| `displayPreferences.maximumNumberOfTitleLines` (17.4) | title line cap | `MorphMenuSection.maxTitleLines` | missing on `MorphSubmenu` and the root | add to submenu and sources |
| `UIDeferredMenuElement(provider:)` (14) | lazy rows, cached | `MorphMenuDeferred(load)` | none | keep |
| `.uncached` (15) | reload per opening | `MorphMenuDeferred(cache: false)` | none | keep |
| `UIDeferredMenuElement.identifier` (26) | identity of the element | `MorphMenuDeferred.id` | none | keep |
| `UIButton.menu` + `showsMenuAsPrimaryAction` (14) | tap opens the menu | `MorphMenuButton(menu:)`, `MorphMenuSource(menu:)`, `MorphGlassButton(menu:)` | none | keep |
| `UIButton` primary action + `menu` (14) | tap acts, hold opens | `MorphMenuSource(trigger: hold, onTap:)`, `MorphGlassButton(onPressed:, menu:)` | none | keep |
| `UIBarButtonItem.menu`, `(primaryAction:menu:)` (14 / 16) | bar item menu | `MorphBarButton(menu:)` (tap opens without `onPressed`) | none | keep |
| `UIButton.changesSelectionAsPrimaryAction` (15) | pop-up button | none | gap | `MorphPopUpButton<T>` |
| `preferredMenuElementOrder` (16) | `.automatic/.priority/.fixed` | `order` (`MorphMenuOrder`) on sources and region | none | keep |
| `UIControl.isContextMenuInteractionEnabled` (14) | menu on / off | `enabled` | none | keep |
| `contextMenuInteraction.dismissMenu()` on a control (14) | close from code | `MorphMenuSource.close(context)` (from the source, a row or the look the menu carries) | none | keep |
| control `willDisplayMenuFor` / `willEndFor` (14) | menu shows / ends | none public (`onOpen` is `@internal`) | gap | `onOpen` / `onClose: VoidCallback?` on sources |
| `updateVisibleMenu` (14) | change the open menu | rebuild with new `menu` | none | keep |
| `UIControl.menuAttachmentPointForConfiguration` (14) | attach point | none | gap | skip (low) |

## UIKit - context menu
| UIKit API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIContextMenuInteraction(delegate:)` + `configurationForMenuAtLocation` (13) | hold-to-open menu | `MorphContextMenuRegion(child:, menu:)` | none | keep |
| `UIContextMenuConfiguration` action provider (13) | the rows | `menu` | suggested actions n/a | keep |
| preview provider + `preferredContentSize` (13) | another view as the preview | `preview`, `previewSize` | none | keep |
| `highlightPreviewForItemWithIdentifier` / `dismissalPreviewForItemWithIdentifier` + `UITargetedPreview` / `UIPreviewTarget` (16) | which view lifts, where it returns | the region's `child` (or `replica`) | no sub-part lift, no return elsewhere | skip (low) |
| `UIPreviewParameters.visiblePath` / `shadowPath` / `backgroundColor` (13 / 14) | preview shape, shadow, fill | none: no preview platter | gap | measure the platter, then `previewShape` |
| `willPerformPreviewActionForMenu` + commit style `.dismiss` (13) | tap commits | `onPreviewTap` | commit animation unmeasured | keep |
| commit style `.pop` (13) | preview pops into its page | none | the app pushes its page | later |
| `willDisplayMenu` (13) | menu shows | `onHold` (hold door only) | `onOpen` is `@internal`; a secondary click is not reported | `onOpen: VoidCallback?` |
| `willEndFor` (13) | menu ends | `onClose` | none | keep |
| `updateVisibleMenuWithBlock` (14) | change the open menu | rebuild | none | keep |
| `dismissMenu` (13) | close from code | `MorphContextMenuRegion.close(context)` | none | keep |
| `preferredMenuElementOrder` (16) | order | `order` | none | keep |
| `allowsTypeSelect` (27) | type to select (hardware keyboard) | none | gap | later (low) |

## UIKit - edit menu
morph has no edit menu. Its text inputs (`MorphSearchField`, alert text fields) build `EditableText`
without selection controls or a context menu builder, so a long press selects but shows no Copy /
Paste menu. Flutter's `SystemContextMenu` shows UIKit's own edit menu on iOS 16+; morph does not wire it.

| UIKit API (availability) | meaning | morph equivalent | gap | proposal |
|---|---|---|---|---|
| `UIEditMenuInteraction(delegate:)`, `presentEditMenu(with:)` (16) | show the edit menu at a point | none | gap | `SystemContextMenu` on iOS, a measured glass edit menu elsewhere |
| `UIEditMenuConfiguration(identifier:sourcePoint:)`, `preferredArrowDirection` (16) | anchor | none | gap | with the above |
| `dismissMenu`, `reloadVisibleMenu`, `updateVisibleMenuPosition(animated:)` (16) | control | none | gap | with the above |
| delegate `menuFor(_:suggestedActions:)`, `targetRect(for:)`, `willPresentMenu`, `willDismissMenu` (16) | rows, anchor, events | none | gap | with the above |
| `UITextView` / `UITextField` `editMenuForTextInRanges:suggestedActions:` (26) | customize the text edit menu | none | gap | `contextMenuBuilder` on morph text inputs |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Menu(content:label:)`, `Menu(_:systemImage:content:)` (14) | button that opens a menu | `MorphMenuSource`, `MorphMenuButton`, `MorphGlassButton(menu:)` | none | keep |
| `Menu(content:label:primaryAction:)` (15) | tap acts, hold opens | `MorphMenuSource(trigger: hold, onTap:)` | none | keep |
| `menuOrder` (16) | element order | `order` | none | keep |
| `menuActionDismissBehavior` (16.4) | rows close the menu or not | `dismissOnSelect: bool?` | `bool?` for the enum | keep |
| `menuStyle` (14) | label look | `MorphMenuSource.look/shape/color/rimColor`, `MorphMenuButton.size`, `MorphMenuAppearance` | no style enum | keep |
| `menuIndicator` (15) | chevron on the label | none | gap | with `MorphPopUpButton` |
| `contextMenu(menuItems:)` (13) | hold menu | `MorphContextMenuRegion(menu:)` | none | keep |
| `contextMenu(menuItems:preview:)` (16) | custom preview | `MorphContextMenuRegion(menu:, preview:)` | none | keep |
| `contextMenu(forSelectionType:menu:primaryAction:)` (16) | menus on a list selection | none | gap | after lists have selection |
| `Section` / `Divider` (13) | inline group / break | `MorphMenuSection(title:)` / `MorphMenuDivider` | none | keep |
| nested `Menu` (14) | submenu | `MorphSubmenu` | none | keep |
| `Toggle` in a menu (14) | check row | `MorphMenuItem(state:)` | no bool helper | keep |
| `Picker` `.inline` / `.menu` / `.palette` (14 / 17) | radio rows / submenu / icon row | `singleSelection` on section or submenu, `palette` | no typed value helper | optional `MorphMenuSection.picker<T>` |
| `paletteSelectionEffect` (17) | look of the selected palette cell | fixed platter | gap | later (low) |
| `ControlGroup` (15) + `controlGroupStyle` `.menu` / `.compactMenu` (16.4) / `.palette` (17) | cells, palette | `elementSize: small / medium`, `palette` | `.compactMenu` not mapped | keep |
| `Button(role: .destructive)` | red row | `destructive` | none | keep |
| `Label` / two-`Text` label (14 / 15) | title, image, subtitle | `title`, `icon`, `subtitle` | none | keep |
| `Slider` / `Stepper` in a menu (Decrement / Increment cells, measured) | value control | `MorphMenuWidget` (free-form) | no parity row | optional `MorphMenuStepperRow` |

## Not relevant for Flutter
- `UICommand`, `UIKeyCommand`, `UIMenuBuilder`, `UIMenuSystem`, `UIMainMenuSystem`, `UIContextMenuSystem` (26), `UIMenu.Identifier`: main-menu and key-command plumbing.
- `discoverabilityTitle`, `repeatBehavior` (26), `keyboardShortcut`: hardware key commands.
- `UIAction.sender`, target-action, `performWithSender:target:`, `captureTextFromCamera`: Dart closures; system Live Text.
- `UIMenu.selectedElements`, `menuByReplacingChildren`, `UIDeferredMenuElement.usingFocus`: entries are immutable lists; no responder chain.
- `badgeCount`, `secondaryItemIdentifiers`, suggested actions: multi-item drag and system-supplied rows.
- `menuAppearance` (read-only rich / compact; rich = region, compact = `MorphMenuSource(trigger: hold)`), `locationInView`, animators (`addAnimations`, `addCompletion`, `previewViewController`), NSCoding.
- `ShareLink`, `LocalizedStringKey` overloads, macOS menu styles, `contextMenu` on tab content and table rows.

## morph-only API
- `MorphMenuWidget`: free-form row (UIKit 27 has no custom-view element).
- `MorphContextMenuRegion.accessory` (`MorphSatellite`), `lifts`, `holdDuration`, `opensOnSecondaryTap`, `replica`, `maxScrimOpacity`, `scrimColor`, `onHold`.
- `MorphContextMenuRegion` public `measured*` statics (`measuredHoldDuration`, `measuredCommitDuration`, `measuredHoldGrowth`, `measuredHoldGrowthPoints`, `measuredPreviewScale`, `measuredLiftPoints`, `measuredLiftScale`, `measuredMenuGap`, `measuredRetractScale`, `measuredDimOpacity`).
- `MorphMenuSource.look`, `shape`, `color`, `rimColor`, `focusable`, `overlay`, static `open`; `MorphMenuItem.iconColor`; `MorphMenuButton.size`; `MorphMenuDeferred.loadingTitle`.

## Ranked gaps
Done since the last page: context menu rows, custom preview and preview tap (2026-10-14); `icon` /
`selectedIcon` as `Widget?`; `items` renamed `menu`; layout and motion types internal.

| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | Button menu motion has no replay: open spring, kicks, placement, early touch and reopen captures exist, the test was removed in 98237e58 | H | S | port the removed replays onto `MorphMenuMotion`, fixtures unchanged |
| 2 | Pop-up button (`changesSelectionAsPrimaryAction`, `menuIndicator`) | H | M | `MorphPopUpButton<T>` over `MorphMenuSource` |
| 3 | No edit menu on text inputs (`UIEditMenuInteraction`) | H | M meas. | `SystemContextMenu` on iOS; measure the glass edit menu for other platforms |
| 4 | No public open / close callbacks (`willDisplay`, `willEnd`); close from code on sources landed (`MorphMenuSource.close`, 2026-10-20) | M | S | `onOpen` / `onClose: VoidCallback?` on sources and region |
| 5 | Preview platter of the context menu (shadow; `UIPreviewParameters`) | M | M meas. | measure, then draw it; `previewShape` |
| 6 | Highlight as one sliding platter (UIKit 0.12 s spring, simulator) | M | S-M meas. | confirm at 120 Hz, then port |
| 7 | Stable row identity (`UIAction.identifier`) | L-M | S | `id` on item and submenu |
| 8 | `maxTitleLines` / `iconVisibility` / `destructive` at every level | L | S | add to submenu, sources, section |
| 9 | `.pop` commit | L | M meas. | later |
| 10 | `allowsTypeSelect` (27), `paletteSelectionEffect`, stepper parity row | L | S | later |

## Proposals before 1.0
- Done: `items` -> `menu` on every source; `icon` / `selectedIcon` are `Widget?`; layout and motion classes are internal.
- Open: public `onOpen` / `onClose` as `VoidCallback?`. The flight-typed `onOpen` became `@internal` on 2026-10-19 and left no public `willDisplay`.
- Open: the region's public `measured*` statics against the rule that tunings are internal. Keep `measuredHoldDuration` (default of `holdDuration`); make the rest `@internal` or document them as reference values.
- Open (API review): `test/api/public_api.txt` lists no fields that `MorphMenuSource` and `MorphMenuButton` inherit from the private `_MorphMenuSourceWidget` (`menu`, `appearance`, `overlay`, `semanticLabel`, `enabled`, `order`, `dismissOnSelect`); the API test sees them only through the constructors.
- Keep: `keepsMenuOpen` for `keepsMenuPresented`; `dismissOnSelect: bool?` for `MenuActionDismissBehavior`.

## Behaviour fidelity
Fixtures are under `test/fixtures/ios27-device/` unless named otherwise.

### menu (button menus and menu content)
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | read | SDK 27.1 tables above | 8 gaps, 7 partial |
| layout | measured | metrics replayed: `test/menu_api_test.dart` layout group vs `menu_api/layout.json`; submenu cards vs `mm-sub-*`; root placement captured in `menu/pos-*`, `bottom3`, `wide3`, `tl-items*`, `center-items*`, `ios27/menu/*` (menu-button.md "Spec - placement") | no test replays root placement (removed with menu_button_test); keyboard endpoints (menu-button.md "Keyboard changes after presentation") not replayed |
| states | unbacked | disabled button replayed (`test/disabled_test.dart` vs `disabled/disabled.json`); row colors measured (`layout.json`) | highlight fill has no source; the glow follows the glass glow model (menu-button.md, Spec - touch glow); no test compares row colors |
| transitions | measured | open / close springs read from UIKit (liquidMorph) and fitted (menu-button.md "Spec - progress"); close replayed with a submenu stack (menu_api_test "the menu glass closes with its container" vs `menu_api/glass-close.json`); submenu open / back / deeper replayed (`mm-sub-tap/back/deeper`, `card-container.json`); fusion replayed (`test/menu_fusion_test.dart` vs `menu/fusion.json`) | open spring and `tapOpenDelay`, driven kicks, content unfold, `center3-closemidopen`, `retap-midopen`, `reopen2-*`: not replayed |
| boundaries | unbacked | max height 520 replayed as a value (`layout.json`); scroll inside captured (`mm-tall-scroll.jsonl`, not replayed) | `maxTitleLines` heights (22 pt a line, declared not measured), Dynamic Type rows, submenu cards over the cap (cut, not scrolled) |
| configuration | unbacked | sections, palettes, small / medium cells, selection column replayed (menu_api_test rich1 / rich2) | `MorphMenuOrder.priority` = `automatic`, image visibility automatic = visible, large / automatic as rows, selection-only title start: unmeasured; device "Ask Siri" footer not reproduced (declared) |
| events | measured | action before close (`actionDelay` 0.016), kept-open action 0.02 (menu-api.md); card row action +0.019 replayed (menu_api_test vs `mm-sub-slide2`) | `onHighlightChanged` timing unmeasured; no public open / close callback |
| input | missing | flex under a finger replayed at 0.09 - 0.17 pt (`test/menu_drag_out_test.dart` vs `menu/drag-out*.jsonl`); hold lag vs the bar item replayed (`test/bar_menu_tap_test.dart` vs `menu/navbar-tap.json`); tap slop from glass-button.md | UIKit slides one highlight platter on a 0.12 s spring (simulator), morph jumps; the device shows no tap highlight on rows, morph does; early touch (`early-outside-*`) not replayed |
| mutation | unbacked | grow 0.565 / 0.84 and shrink 0.40 / 1.0 replayed (menu_api_test "live resize" vs `mm-resize.jsonl`) | deferred answer after a dismiss, empty answer (`test/menu_deferred_async_test.dart`) and a source removed under an open menu have no native capture |
| accessibility | missing | roles menu / menuItem, checked state, keyboard (`test/menu_entries_test.dart`, `test/menu_host_test.dart`) | Dynamic Type row heights neither measured nor implemented (rows stay 42 pt); VoiceOver unmeasured; Reduce Motion pass pending (states.md) |
| optics | unbacked | platter light / dark (menu-button.md "Platter color"); card tone, edge profile and material hand-off / copy replayed (`test/menu_glass_body_test.dart` vs `menu_api/card-tone.json`, `card-edge-profile.json`, `card-material-*.json`); silhouette vs film (menu_fusion_test) | card shadow fitted (`card-shadow-profile.json`, light only) but not replayed; root shadow (`menu.dart:37-38`), highlight and glow colors, glow size / opacity / fade (`lib/src/widgets/menu_motion.dart:72-74`): no source; light material too bright (glass-optics.md) |
| platform | unbacked | arrow keys, Enter, Esc; RTL mirroring (menu_api_test "right to left") | RTL, iPad and pointer presentations not captured; `loadingTitle` default is English |
| performance | measured | Pixel 6a menu frames and fusion served ahead (menu-button.md implementation notes, glass-renderer.md); host layout budget (`test/lifecycle_counts_test.dart`) | sliding highlight, composite-only frames (menu-button.md "Optimizations to adopt") |

### context-menu
| dimension | grade | evidence | open items |
|---|---|---|---|
| api | read | SDK 27.1 table above | 8 gaps, 1 partial |
| layout | unbacked | lift, 16 pt gap and blob replayed (`test/morph_context_menu_test.dart`, `test/menu_context_motion_test.dart` vs `context_menu/holds.json`, `growth.json`, `preview.json`, `morph.json`); menu above the preview captured (`holds.json` ctx-hold-bottom) | the shift when the menu fits on neither side and the 12 pt margin (`MorphMenuTuning.contextMargin`, declared not measured) are unbacked; ctx-hold-bottom is not replayed |
| states | replayed | dim 0.2 light / 0.48 dark (`dim.json`, 0.0014 / 0.0009 rms of alpha); open preview size (`preview.json`) | - |
| transitions | missing | morph 0.284 / 0.81 open and close (< 0.008 of travel), preview resize, dim springs and delays, hold growth replayed | `.pop` commit missing; `onPreviewTap` commit and the custom preview crossfade unmeasured (crossfade declared approximation) |
| boundaries | replayed | commit point 0.400 cancels / 0.433 opens (`holds.json`); growth on 60 x 40 to 300 x 200; preview scale knee | blob width cap measured at one menu height (208 pt) |
| configuration | unbacked | with and without a custom preview; accessory (morph-only, declared approximation) | entry order of a menu above the preview unmeasured |
| events | read | willDisplay at 0.768 - 0.797 s replayed (`holds.json`, `measuredHoldDuration`, 0.025 s); preview haptic at the hold read from UIKit (states.md) | willEnd timing captured, not replayed; no public willDisplay; `onHold` misses the secondary click |
| input | unbacked | hold, commit and early release replayed; slide-to-select is the button menu's (read from UIKit, simulator) | scroll cancelling a hold and the secondary click unmeasured |
| mutation | unbacked | morph behaviour tested (rebuilt rows, moving source, deleted hero) | no native capture of a source moved, resized or removed while open |
| accessibility | unbacked | Reduce Motion: preview held at scale 1 (read from UIKit, states.md); long-press semantics action | VoiceOver unmeasured; the Reduce Motion fade not recorded |
| optics | missing | dim alpha replayed | preview platter shadow missing; the preview is a copy without glass of its own (declared difference) |
| platform | unbacked | secondary click opens | pointer (compact) and iPad presentations unmeasured |
| performance | unbacked | host budget pinned (`lifecycle_counts_test` context-menu release and close) | no device frame-time or energy run |

### edit-menu
| dimension | grade | evidence | open items |
|---|---|---|---|
| all | missing | none | no native capture, no morph implementation; text inputs show no edit menu |

### Catalog obligations
| family / obligation | evidence | state |
|---|---|---|
| menu root-geometry | `menu/pos-*`, `bottom3`, `wide3`, `tl-items*`, `center-items*`, `ios27/menu/*`, `layout.json` | measured, not replayed |
| menu submenu-return | menu_api_test vs `mm-sub-tap/back/deeper`, `card-container.json`; `test/menu_scroll_test.dart` | replayed |
| menu disabled-hidden | `layout.json` (disabled, destructive, check, mixed), `disabled.json` | measured; disabled button replayed |
| menu deferred-update | `mm-resize.jsonl` replayed; `mm-deferred.jsonl` captured | replayed for grow / shrink; dismiss-before-answer and empty answer unbacked |
| menu hold-drag-release | `center3-hold700`, `center3-dragselect`, `drag-out*.jsonl` | flex replayed; hold and drag-select not replayed; highlight slide missing |
| menu overflow-scroll | `layout.json` max height, `mm-tall-scroll.jsonl` | max height replayed; long text and large type unbacked |
| menu rapid-reopen | `center3-closemidopen`, `retap-midopen`, `reopen2-*`, `early-outside-*` | measured, not replayed |
| menu system-content | device footer 62 pt (menu-button.md); lab `systemFooter` (`example/test/lab_test.dart`) | detected; not reproduced (declared) |
| context-menu preview-actions | region API | rows and custom preview covered; highlight / dismissal previews and suggested actions absent |
| context-menu preview-commit | none | `.pop` missing; dismiss commit unbacked |
| context-menu source-change | none | unbacked |
| context-menu presentation-geometry | `holds.json`, `growth.json`, `preview.json`, `morph.json` | replayed below the preview; above captured, not replayed; shift unbacked |
