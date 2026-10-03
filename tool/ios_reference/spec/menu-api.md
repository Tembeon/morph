# Menu API passport (submenus, sections, palettes, sizes, selection, live content)

Status: API surface read from the iOS 27.0 SDK (UIKit headers + the SwiftUI
swiftinterface); layout, look and motion MEASURED on the iPhone 16 Pro
(iOS 27.0.1, light + dark, 2026-10-03); PORTED 2026-10-04
(menu_entries.dart, menu_layout.dart, menu_content.dart, menu.dart,
menu_motion.dart), replayed by test/menu_api_test.dart. Extends
[menu-button](menu-button.md) (the button-to-menu liquid morph, placement,
triggers); this page covers what lives INSIDE the menu.

## Native API surface (SDK 27.0)

UIKit (`UIMenu.h`, `UIMenuElement.h`, `UIMenuLeaf.h`, `UIAction.h`,
`UIDeferredMenuElement.h`, `UIMenuDisplayPreferences.h`,
`UIContextMenuConfiguration.h`, `UIButton.h`):

- `UIMenuElement`: `title`, `subtitle` (15), `image`,
  `preferredImageVisibility` automatic / visible / hidden (NEW 27),
  `highlightStateUpdateHandler(element, isHighlighted)` (NEW 27).
- `UIMenuLeaf` (UIAction, UICommand): `title`, `subtitle`, `image`,
  `selectedImage` (17), `discoverabilityTitle`, `attributes` = disabled /
  destructive / hidden / keepsMenuPresented (16), `state` = off / on /
  mixed, `repeatBehavior` (26, key commands), `sender`,
  `presentationSourceItem` (16), `performWithSender:target:`.
- `UIMenu`: `children`, `options` = displayInline / destructive /
  singleSelection (15) / displayAsPalette (17), `preferredElementSize` =
  small / medium / large / automatic (16/17), `selectedElements` (15),
  `displayPreferences.maximumNumberOfTitleLines` (17.4),
  `menuByReplacingChildren:`, identifiers (system menus).
- `UIDeferredMenuElement`: `elementWithProvider:` (cached),
  `elementWithUncachedProvider:` (15), `usingFocus(identifier:
  shouldCacheItems:)` (26), `Provider` (26).
- Presentation: `UIButton.menu`, `showsMenuAsPrimaryAction`,
  `changesSelectionAsPrimaryAction` (pop-up button), `preferredMenuElementOrder`
  automatic / priority / fixed (16); `UIContextMenuConfiguration`
  (`secondaryItemIdentifiers`, `badgeCount`, `preferredMenuElementOrder`,
  `allowsTypeSelect` NEW 27); `UIContextMenuInteraction.updateVisibleMenu`
  (the only way to change an open menu).
- NO custom-view element exists in UIKit 27: the element classes are
  UIMenu, UIAction, UICommand, UIDeferredMenuElement only.

SwiftUI (`Menu` content is converted to these elements): `Menu(content:
label:primaryAction:)`, `Section` (title = inline header), `Divider`,
`Button(role: .destructive / .cancel / .confirm / .close)`, `Label`, a
Button label of two `Text`s = title + subtitle, `Toggle` (checkmark row),
`Picker` with `.inline` (single-selection rows) / `.menu` (submenu) /
`.palette` (palette row), `ControlGroup` (+ `.controlGroupStyle(.palette /
.menu / .compactMenu)`), nested `Menu` (submenu), `ShareLink`,
`.menuOrder(.automatic / .priority / .fixed)`,
`.menuActionDismissBehavior(.automatic / .enabled / .disabled)`,
`.menuIndicator`, `.menuStyle`, `.controlSize` (element size). Measured on
the device: `Slider` and `Stepper` inside a Menu do NOT render as a slider
or stepper - each becomes a section header (its label, e.g. "Volume",
"Steps 2") over two medium cells Decrement / Increment (117 x 51.67).
So there is no official free-form content in iOS 27 menus.

## Measured [device, light + dark]

Probe: `Sources/Menus.swift` (scene `x5menu`, PROBE_MENU sub / rich1 /
rich2 / tall / resize / deferred / swiftui), `UITests/MenuAPIUITests.swift`
(testMenuLook = open + deep dump + shot per menu and appearance;
testMenuMotion / testMenuMotion2 = gestures, dark, touch dumps). Numbers:
`test/fixtures/ios27-device/menu_api/layout.json`; rows: the jsonl files
there (manifest.json); shots `references/menu-api/` (cropped: origin at
50, 80 pt of the 402 x 874 screen, 3 px per pt).

Layout [layout, dumps]:
- Width 250; 10 pt top / bottom inset; row 42 pt (60 with a subtitle:
  title 17 pt, subtitle 13 pt 23 pt below the title's top).
- Columns from the menu's left edge: plain row image center 40, title at
  64 (158 wide); a menu with a selection column (any on / mixed state or
  singleSelection) puts the check center at 27.7, the image center at 55,
  the title at 79 (143 wide); an inline group without images starts its
  titles at 28 (194 wide). Check = `checkmark` 13.33 x 12.33, mixed =
  `minus` 12.67 x 3.67.
- Colors: title label at alpha 0.96 (dark white, light black); subtitle and
  section header secondaryLabel 0.6 (0xEBEBF5 / 0x3C3C43); disabled
  tertiaryLabel 0.298; destructive dark 0xFF4245, light 0xFF383C (image too).
- Section header (inline titled menu): 40.33 tall, 13 pt label 12 pt from its
  top, no visible line under it.
- Group separator between inline groups: a 21 pt gap with a 1 pt line inset
  24 pt from both menu edges (rendered dark 50 on the 32 platter, light 229
  on 249).
- Palette (`displayAsPalette`): one row of cells 42.67 x 54 (5 cells start
  18.33 pt in, 42.67 apart), 22 pt images, the selected cell on a rounded
  platter; SwiftUI's 3-cell palette uses 62.67 x 54.
- Small elements: icon-only cells 58.33 x 51.67, 8 pt from the edges (4 =
  234 wide). Medium: cells 78 x 77 (3 across from 8 pt), icon + 12 pt label
  44.67 pt down.
- Max height 520 pt (30 rows, and the SwiftUI menu): the content scrolls
  inside with an indicator; not bounded by the safe area.
- The system appends a separated "Ask Siri" footer row (62 pt incl. gap) to
  every menu on this device (known, menu-button.md).

Submenus [rows, fits]:
- STACKED CARDS, not a push: the submenu list grows out of its row (230 x 42
  at the row) to a full 250-wide card over the parent; the parent list
  scales to 0.97 (250 -> 242.5) and its rows fade to alpha 0.5; the menu
  view grows to cover both (h 250 -> 287.2). The card's top is a header
  (`_UIContextMenuSubmenuTitleView`, 250 x 62): the parent row's title in
  bold + a chevron down + separator.
- Open by tap: ONE spring 0.395 / 0.86 for every property, starting 0.076 s
  after the lift (rms 0.37 pt on the card height, 0.001 on the alpha).
- Second level: the same on 0.405 / 0.84 (0.04 s after the lift); the first
  card scales to 0.97^2, both parents at alpha 0.5.
- Back (tap the header): critically damped 0.40 / 1.0, 0.022 s after the lift.
- Hold-and-slide: a finger that holds the button (menu shown 0.25 s after
  the touch) and slides onto a submenu row opens it 0.525 s after ENTERING
  the row (0.523 / 0.527, two runs); sliding on to a sub row and lifting
  fires it 0.019 s after the lift.
- Choosing a sub row closes the whole stack toward the button (container
  0.355 / 0.84 fit on the view rows).

Live updates [rows + shots]:
- `keepsMenuPresented`: the handler runs 0.02 s after the lift and the menu
  stays, but UIKit does NOT redraw a checkmark / palette selection / state by
  itself (the singleSelection "Sort by" and the palette kept their old mark
  after taps) - the app updates through `updateVisibleMenu`.
- Content change while open (`updateVisibleMenu` add row, deferred elements
  arriving): the menu GROWS on 0.565 / 0.84 (0.07 s after the trigger, two
  sources agree); a removed row SHRINKS it on 0.40 / 1.0.
- Deferred (uncached) element: a "Loading..." row with a spinner (42 pt)
  until the provider answers.
- SwiftUI: a state-driven label updates in place while the menu stays open
  (`menuActionDismissBehavior(.disabled)`, Count 0 -> 2); a Toggle row
  dismisses.

## Proposed morph API (Dart, Morph* names)

```dart
sealed class MorphMenuEntry {}
class MorphMenuItem extends MorphMenuEntry      // UIAction / SwiftUI Button
  (title, {subtitle, icon, selectedIcon, iconVisibility, enabled = true,
   destructive = false, hidden = false, keepsMenuOpen = false,
   state = MorphMenuState.off /* on, mixed */, onSelected,
   onHighlightChanged});
class MorphMenuSection extends MorphMenuEntry    // UIMenu displayInline
  ({title, children, singleSelection = false,
    elementSize = MorphMenuElementSize.large /* small, medium, automatic */,
    palette = false, maxTitleLines});
class MorphSubmenu extends MorphMenuEntry        // UIMenu (nested)
  (title, {subtitle, icon, children, destructive, enabled, singleSelection,
   elementSize});
class MorphMenuDivider extends MorphMenuEntry;   // SwiftUI Divider
class MorphMenuDeferred extends MorphMenuEntry   // UIDeferredMenuElement
  (Future<List<MorphMenuEntry>> Function() load, {cache = true});
class MorphMenuWidget extends MorphMenuEntry     // FREE-FORM (no UIKit twin)
  (WidgetBuilder builder, {interactive = true, keepsMenuOpen = true});
```

- `MorphMenuButton(entries:, order: MorphMenuOrder.automatic / priority /
  fixed, dismissOnSelect, onOpen, controller)`; a
  `MorphMenuController.update(entries)` = `updateVisibleMenu` (resize on
  the measured springs); selection state comes from the app's state (as in
  SwiftUI): the menu rebuilds in place.
- `MorphMenuWidget` is morph's extension for the owner's free-form rows
  (sliders, steppers, custom controls): laid out at the menu width minus the
  row insets, measured like any row (MorphContentMeasure), keepsMenuOpen by
  default; native has no equivalent, so its look is the app's, the motion is
  the menu's (resize on 0.565 / 0.84 grow, 0.40 / 1.0 shrink).
- The SwiftUI Slider / Stepper conversion (Decrement / Increment medium cells
  under a header) can be offered as `MorphMenuStepperRow` for native parity.

## To port (porting agent)

- [x] Entry model (sealed MorphMenuEntry: MorphMenuItem, MorphMenuSection,
      MorphSubmenu, MorphMenuDivider, MorphMenuDeferred, MorphMenuWidget);
      `MorphMenuItem` keeps title, icon, destructive, onSelected and adds
      iconColor (morph's, for palettes of colors). `MorphMenuButton.items`
      kept its name (passport proposed `entries`), plus `order` and
      `dismissOnSelect`. No `MorphMenuController`: the button is
      declarative, a rebuild with new entries is the update.
- [x] Layout table: `MorphMenuMetrics` / `MorphMenuLayout.build`, replayed
      against the rich1 / rich2 / sub / deferred dumps (positions to 0.02
      pt). Read from the dumps beyond this page: a header that opens a
      group starts at the group's top (no top inset at the menu top),
      rows follow it 38.33 below its top and cells 28.33; small / medium
      groups are followed by a 1 pt gap holding the hairline and a palette
      by nothing; the glyph column is per group (an imageless inline group
      starts titles at 28 next to a 64 group), the selection column
      menu-wide; headers start at 28, 43 with a selection column; the
      submenu chevron centers at 219; the card header is 62 with the rows
      10 below it.
- [x] Colors per appearance (MorphMenuStyle light / dark).
- [x] Submenus as stacked cards: springs, delays, 0.97 / 0.5, header back,
      dwell 0.525, sub action +0.019. The card's frame replays mm-sub-tap
      under 1 pt rms (progress under 0.01), the back and the deeper card
      under 1.5 / 2 pt. The card platter color is sampled (57 dark, 251
      light); the root list's own platter shrinking with the 0.97 (3.75 pt
      per side) is NOT drawn - morph's root is the menu glass, which keeps
      its width.
- [x] Whole-stack close: compared on the recordings - the
      `_UIContextMenuView` frames of a sub-row close (mm-sub-select) and of
      a plain row close (mm-palette, "Plain row") are identical frame by
      frame (w 247.94, 242.44, 234.38, ...): the "0.355 / 0.84" fit is the
      ordinary menu close seen on the container view, not a submenu
      spring. The stack closes on the measured morph close (0.49 / 0.80
      progress + kicks); no recapture needed.
- [x] keepsMenuOpen + live update: declarative; grow 0.565 / 0.84, shrink
      0.4 / 1.0. Delays refitted from the action (`evt`) rows: grow 0.045
      s after the action (the second add of mm-resize started about 0.02
      s earlier - display-link jitter), shrink 0.03.
- [x] Deferred entries (cached by `id` or the load function, uncached per
      opening; the loading row's glyph column counts as an image).
- [x] MorphMenuWidget free-form rows (measured post-frame, the first
      measurement snaps, later ones animate; touches on them are the
      widget's - no highlight, glow, lean or selection).
- [x] Max height 520 / safe area with scrolling and an indicator (also
      closes audit M3); a scrolling finger chooses nothing.
- [x] Replay tests (menu_api_test) and widget tests (menu_entries_test).
- [ ] Not ported: `maxTitleLines` heights (TextPainter estimate + 22 pt
      per line, unmeasured), `preferredImageVisibility` automatic vs
      visible (treated alike), large / automatic element sizes as rows,
      the "selection column without glyphs" title start (52, a guess),
      cell highlight shape (12 pt radius, a guess), the palette platter
      radius, `highlightStateUpdateHandler` timing, submenu cards that do
      not fit the cap (cut, not scrolled), the hold-and-slide card spring
      (uses the tap's), Dynamic Type row heights.

## Recapture

```sh
xcodebuild test-without-building ... -only-testing:ProbeUITests/MenuAPIUITests/testMenuLook   # TEST_RUNNER_PROBE_DARKS=1,0
xcodebuild test-without-building ... -only-testing:ProbeUITests/MenuAPIUITests/testMenuMotion2
xcrun devicectl device copy from --device <udid> --domain-type appDataContainer --domain-identifier dev.tembeon.morph.probe --source Documents --destination <dir>
```

Env: PROBE_MENU, PROBE_BY (button y), PROBE_DEFER (seconds), PROBE_DUMPS=1
(view-tree dumps after each touch-up, now named tree-<rec>-NNN.txt).
Geometry of the rows in the gestures comes from the dumps (row centers in
MenuAPIUITests); an XCUI query for "More" hits the ellipsis button itself
(its accessibility label), not the row.

## Open

- Hover-open dwell from two runs only. (The stack close question is
  settled: see the porting notes above.)
- Large / automatic element size, `maximumNumberOfTitleLines`,
  `preferredImageVisibility`, `highlightStateUpdateHandler`, menuOrder
  priority vs fixed with an upward menu: API read, not measured.
- Light motion not recorded (springs are appearance-independent elsewhere).
