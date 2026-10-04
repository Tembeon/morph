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
- Choosing a sub row closes the whole stack toward the button. The close
  starts 0.015 s after the lift on a card row (before the action's 0.019),
  0.04 - 0.05 s after a lift outside (the container's first visible change
  lags both by the same 0.024 s: mm-sub-select vs mm-sub-tap).

Submenu film [film, 2026-10-04, light + dark; MenuAPIUITests.testMenuFilm,
PROBE_SPINNER=1, layer log off; morph side
example/integration_test/menu_submenu_video_test.dart; montages
`references/menu-api/film/` (native top, morph bottom; `*-before` = the
port of 4f810d3, `*-after` = now); numbers in
`test/fixtures/ios27-device/menu_api/film-sub.json`]:
- Layers: every list (root and each card) is its own glass element - a
  `_GlassGroupView` with a `UISDFBackdropView` and a `UISDFView`; an open
  card lives in a second `MagicMorphView`. The card is NOT an opaque fill:
  it blurs what lies under it (the dimmed list's edge spreads over ~27 pt,
  a destructive row shows as a red smear) and lifts it: over the list it
  opened from 57 on the 32 dark menu / 252 on the 249.5 light one, past
  that list's edge only the blur (34 / 248.5), over two lists 68 (each
  further list adds about half); a bright top rim (dark 65 - 83, light
  251 - 255) and a faint shadow outside (light list -5 levels 4 pt above).
- The card's header IS its row: it opens on the row (regular title, the
  chevron pointing at the trailing edge), turns bold and the chevron down
  while the card grows, and on the way back the title goes regular at once,
  the chevron turns back and the header lands on the row at full contrast;
  the card's other rows fade out while it is still over half its size;
  the platter shrinks to a pill around the row and fades (still at a
  quarter of its progress, gone about 0.45 s into the back, q ~ 0.007).
  The row itself never blinks.
- Growing: the card's rows read at full contrast while the card is still
  small (clipped by its edges, not faded).
- Close with a card open: the morph's menu element starts from the list
  UNDER the card (`R0/1/1/0` 242.5 square after one card, 235.2 after two,
  250 without), the open card's rows shrink with the drop at full contrast
  and without blur, centered on it, legible at a fifth of the size and gone
  near progress 0.2; the list under the card fades as in a plain close.
  A plain close is unchanged.
- Taps on the More row, a card header and a card row show no highlight
  pill on the device (frames during the touch).

Submenu bounds correction [device film + widget frames, 2026-10-04]:
- The first gallery More card appeared to jump right on hand-back: the
  selection column placed its source title at 79, but the header used 64.
  The last header-to-row frame moved 15.0 pt. Headers now inherit their
  source row's title/glyph columns and approach the parent's scaled columns
  on the card spring. LTR/RTL, first/deeper hand-backs sampled every 8.333 ms
  have a maximum horizontal step of 0.045 pt (gate 0.5); the centered
  whole-stack close has no horizontal center displacement.
- The vessel's rounded clip cut the full-width card rims and outside
  shadows. Cards now escape that clip and clip only their own rows and
  backdrop. The root list clips separately; its glass and fusion outline
  use `MorphMenuMotion.rootBlob`, shrinking about the top center to 0.97
  per open card. The open widths are 250, 242.5, 235.225 (and 228.16825 for
  the root under three cards). The root platter's width/height replay
  `mm-sub-tap` at 0.0137 pt RMS over 74 samples, with the native 62 pt
  system footer included in the comparison layout.
- Each card supplies glass beyond the union of the lists under it, while
  keeping those lists visible through the measured backdrop blur/tint.
  The material paints after that blur, so it reaches the card's own edge;
  its top rim and outside shadow remain independent of the vessel bounds.
- Closing cards have a separate window-space carrier, not the glass's
  0.49/0.80 drop and kick. Fits of `_UIContextMenuView` in `mm-sub-select`,
  `mm-sub-tap` and `mm-sub-deeper` give 0.3500/0.8500, shrinking from 250
  to 50 pt about the source button (width fit 0.010-0.016 pt RMS). The
  carrier starts 9-20 ms after the logical close, mean 15.1 ms. This removes
  the premature swell and misplaced content of the previous close.
  `card-container.json` preserves the fits and per-record presentation
  delays: replay of visible card window x/y/width/height is 0.041-0.055 pt
  RMS (previous carrier: 26-29 pt). Production uses the measured 15 ms
  mean; replay aligns each recording's presentation delay, not its spring.
- A deeper card's endpoint uses its parent's 0.97 scale for the offset
  from that parent's top. The previous second-card top was 4.23 pt too low.
  Full opening/hand-back window-bounds replay is 0.837 pt (first), 0.584 pt
  (back), 0.643 pt (deeper), including per-record start alignment. The
  existing 0.395/0.86, 0.405/0.84 and 0.40/1.0 springs remain unchanged.
  Submenu taps do not flash the row pill seen in the previous film;
  held-button slides still highlight. A close reversed before or after
  the carrier starts keeps its position and velocity.
- The liquid renderer shaded the fused field but painted each primitive's
  exterior shadow above it. The source circle's shadow formed an interior
  rim, including a halo outside the blurred silhouette. Fused bodies now
  paint one shadow outside that silhouette and disable primitive shadows.
  The menu keeps the plain union's distance field when Gaussian radius
  returns to zero, rather than reverting to independent glass surfaces.
  `test/menu_glass_body_test.dart` fails twice before these corrections;
  it verifies a single silhouette shadow and continuous field ownership.
  The phone close film confirms the internal button circle is gone.
- Regression: `test/menu_card_bounds_test.dart` dumps rendered card rects
  per frame with `MENU_FRAME_DUMP=<directory>` (close, four LTR/RTL header
  hand-backs, 577 nested samples over three levels). It checks the 0.5 pt
  continuity limit, full scaled widths, absence of enclosing menu/vessel
  clips, and dark platter pixels past the root.
  `test/menu_api_test.dart` additionally dumps complete native window-bounds
  replays for opening, hand-back and three whole-stack closes. Invisible
  UIKit cleanup/reparenting frames are excluded from the visible-card gate.
- Phone-only verification was requested; no simulator was started. Native:
  `MenuAPIUITests.testMenuFilm`, light, spinner on. Ours:
  `menu_submenu_video_test.dart` with `VIDEO_LIGHT_ONLY=true` and the measured
  system-footer geometry, plus `menu_card_gallery_video_test.dart` on the
  actual gallery Options button. MorphRecorder runs with `open -g -W`;
  extraction preserves variable frame timestamps with `-fps_mode passthrough`.
  New stills and the close comparison are in `references/menu-api/film/`.


Submenu material correction [device rows + film, 2026-10-04]:
- The installed liquid renderer previously received only the root menu and
  its button. Submenus bypassed it with a manual backdrop blur, a base fill
  cut out at the parent bounds, and a blurred white tint. The hard cut and
  blurred parent edge produced a second rounded rectangle inside the card.
  Every submenu now calls the installed painter's buildSurface with its own
  SDF shape, an untinted regular material and a fresh BackdropGroup. Its
  refraction, complete contour and shadow use the same renderer as the root.
  glassTint defaults to transparent: the regular material supplies
  the native luminance lift, rather than receiving another opaque menu wash.
  submenuColor/RimColor/ShadowColor remain the no-renderer fallback.
  The root and button use the same neutral tint. Their former fallback
  wash was also supplied as shader tint, giving a dark root level34 rather
  than native32 and amplifying that error through nested materials. The
  glass seam now separates fallback color from optional renderer tint.
  The fused root body previously inherited optics from its first primitive,
  the unfrosted source button, so its backdrop blur was zero. With the
  fallback wash removed, the gallery exposed sharp buttons behind that
  menu. The active menu body now supplies the same measured 10 pt list
  blur to both primitives; resting buttons keep their own preset. A widget
  regression checks the shared root body's actual LiquidGlassLayer frost.
- The measured 10 pt card blur overrides the ordinary 2 pt regular preset
  through MorphGlassSurface.blurRadius. The local surface copy preserves it;
  dispersion and lighting remain the preset's. This blurs the parent rows
  and destructive color instead of transmitting a legible duplicate label.
- The dark side-edge profile also rejects the regular 60 pt sampling
  displacement: a median profile at x82-93.667, y310-320 pt over the native
  root SDF's x79.75 edge gives 5.766 gray-level RMS at 60 pt, versus 2.162
  with zero displacement and the measured 10 pt blur. A constrained joint
  fit of displacement and sigma settles at zero displacement (1.354 RMS
  with sigma12). cardDisplacement therefore uses zero for the unlifted
  submenu; its SDF material still supplies the contour and glint. The root
  and button retain their original optics. card-edge-profile.json preserves
  the samples and fit; the test replays them through the surface settings.
- The neutral material still transmitted too much light across two dark
  layers: root 32, first 59, second 73, compared with native 32/57/68. A
  sequential face-transfer fit gives transmission gamma 1.0701; the rounded
  production value 1.07 replays both reference face levels within 1.5 gray
  levels in the transfer model. Phone verification gives 32/57/69; the
  second header keeps a one-gray-level residual. card-tone.json records
  the fitted transfer, baseline backdrop inference and actual phone values.
  The property changes transmitted luminance, retaining the same regular
  renderer material, emission, glints and contour.
- Whole-stack close transfers the cards' glass to the common morph field at
  closeKickDelay, 12 ms after the logical close. Native mm-sub-tap retains
  root rows at +7.588 ms, then makes their list alpha 0 and hides the original
  root glass at +15.551 ms. SDF match-bounds/position/radii/mesh animations
  start at +11.999 to +12.202 ms. The top card's list alpha stays 1 in its
  independently shrinking carrier. Our previous card material survived as
  a rectangular border inside the rounded blob, and parent rows blurred
  outside it. Both now hand off together; top rows keep their measured
  carrier and fade. Plain closes and submenu header hand-backs keep their
  existing ownership.
- card-material-handoff.json preserves these native rows and animations.
  menu_glass_body_test verifies the native ownership samples, separate
  backdrop groups at two levels, liquid shapes, 10 pt frost, preserved
  optical profile/dispersion, measured face transfer, surviving top rows and
  no independent closing card
  glass. The old implementation fails the renderer regression.
- Final phone evidence: submenu-material-open/close.png and .mp4, native
  above morph. The close silhouette width aligns at 1.474 pt RMS across 10
  captured native frames, without changing springs or geometry. The
  recording starts at a different media time, so film alignment is a clock
  offset fit. Material dark comparisons, gallery stacked-card screenshots,
  card frame dumps and the check summary accompany them in the film folder.
  This is a body-width comparison, not a claim of pixel-identical content.
  Light motion was captured at gamma1.06; the final gamma1.07 dark capture
  verifies the face calibration. Gamma affects only transmitted luminance,
  not the geometry, carrier or common closing body. Gallery screenshots
  record the 10 pt root blur and complete nested surfaces before this final
  dark-tone adjustment. The report records each capture's provenance.

Root scroll ownership correction [widget regression + phone, 2026-10-04]:
- Opening a submenu replaced the root ClipRect with ClipRRect. That
  remounted its Scrollable and reset a scrolled parent to zero (180 pt
  to zero in regression frame 10). The root keeps one ClipRRect subtree,
  with zero radius alone and the measured card radius while stacked.
- Parent input and scroll physics are disabled while any submenu card
  remains, including hand-back. Existing ballistic activity stops at
  the first stacked frame. A drag on the exposed parent cancels selection
  without moving the parent or turning that drag into a back tap; a tap
  beside the card retains the measured hand-back behavior.
- test/menu_scroll_test.dart checks offsets every 8.333 ms through opening
  and hand-back, two nested levels, parent drag/wheel input, stopping an
  existing ballistic activity and restoring scrolling after the final
  card returns. Before the fix, offset preservation and parent input
  locking both fail; the blocked parent drag moves 72.166 pt. No springs,
  layout metrics or submenu timing change.
- The gallery phone harness opens More and Move to after scrolling, drags
  the exposed parent at both levels and returns through both headers.
  All seven snapshots retain 311.159208 pt (span 0). Film, stills and
  offsets are in references/menu-api/film/submenu-scroll-*; required
  verification passes 1052 package tests, 11 example tests, analyze 0 and
  documentation 0 warnings/errors.

Parent tap correction [widget regression + phone, 2026-10-04]:
- The exposed parent's sole pan recognizer can win the gesture arena on
  touch-down without any drag movement. Cancelling menu selection in
  onPanStart therefore suppressed ordinary parent taps as if they were
  scrolls. Selection cancellation now runs onPanUpdate only; the stable
  scroll subtree, input lock and NeverScrollableScrollPhysics remain.
- A parent tap returns one card per tap, retaining the root scroll offset.
  A tap outside the stack dismisses the entire menu after a blocked parent
  drag too. Both installed-glass and painter widget paths exercise these
  gestures at two submenu levels in test/menu_scroll_test.dart.
- The phone gallery harness returns Move to and More by tapping the
  exposed root list, reopens both levels and dismisses the stack outside.
  Both parent-tap regressions fail before the callback correction (three
  cards remain where two are expected). On the phone, all seven offsets
  retain 311.159197 pt, span 0; the final outside tap leaves no menu cards.
  Film, stills and checks: references/menu-api/film/submenu-tap-*.
  Verification: 1056 package tests, 11 example tests, analyze 0 and
  documentation 0 warnings/errors.

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
      light); the root list's glass platter and fusion outline shrink
      with the 0.97 (3.75 pt per side), independently of the vessel.
- [x] Whole-stack close: the progress is the ordinary measured close
      (glass 0.49 / 0.80 + kicks; list carrier 0.35 / 0.85 from window
      frame fits). Fixed 2026-10-04 from film and full card window bounds:
      a card row closes after `submenuCloseDelay` 0.015 (was the root's
      0.04); the open card rides the drop outside the content blur, its
      rows fading to 0 at `cardCloseFadeEnd` 0.2; the glass hands off
      to the common morph field at the 12 ms close kick;
      the content is centered on the open card (`cardCloseCenter`: fully
      by progress 0.5, continuous at the close start) instead of keeping
      the frame's top on the shape's top.
- [x] Card look (2026-10-04, film + stills): each card uses the installed
      glass painter and its own backdrop group, with untinted regular
      material and the measured 10 pt frost. The complete rim, refraction
      and shadow come from the renderer; fallback colors apply only without
      a painter. See the material correction above.
- [x] Card hand-back (2026-10-04, film): the header rides the source row
      (`MorphMenuCard.contentTop`), the source row is hidden while its card
      shows, the header title crossfades regular / bold
      (`cardHeaderBoldStart` 0.15 / `cardHeaderBoldEnd` 0.35; back: within
      the first tenth), the chevron turns (`cardChevronTurn` 0.4 open,
      `cardChevronBack` 0.2 back), rows fade in by `cardRowsFadeIn` 0.25
      and out by `cardRowsFadeOut` 0.55 of the back's start, the platter
      at sqrt(q / `cardPlatterFade` 0.3), the card is dropped below
      `cardGone` 0.007. Replays: menu_api_test "submenu close and
      hand-back" (close delays vs mm-sub-select / mm-sub-tap, header lands
      on its row within 0.05 pt, never jumps) and "submenu card look"
      (tint over the measured menu levels within 1.5, the back pill's fade
      within 0.5 levels of the film).
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
      radius, `highlightStateUpdateHandler` timing, the device's missing
      tap highlight on menu rows (morph still highlights under the finger,
      except a card header), the header
      chevron's size (ours is the row chevron turned, a little larger), the
      chevron turn and bold switch (read by eye from film, not fitted),
      submenu cards that do
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

- Dark film: the screen recorder dropped most frames of the dark passes
  (even a second dark pass in one run came out compressed), so the dark
  motion was judged from the light film and the dark stills only.

- Hover-open dwell from two runs only. (The stack close question is
  settled: see the porting notes above.)
- Large / automatic element size, `maximumNumberOfTitleLines`,
  `preferredImageVisibility`, `highlightStateUpdateHandler`, menuOrder
  priority vs fixed with an upward menu: API read, not measured.
- Final submenu material films cover light opening/closing and dark nested
  cards. Variable capture timestamps leave about one film-frame uncertainty
  in comparing row phases; window-bounds replay remains the quantitative
  carrier check. Glyphs and the header chevron still differ from UIKit.

Shared laboratory audit [device film, 2026-10-04]:
- `lab/out/menu-phone-20261004-06`, shared `menu-return.json`: nine real
  gestures cover root/More/Deeper opening, both header returns, More
  reopening, outside dismissal and root reopening/dismissal. Source rows,
  films, assertions and hashes are summarized in
  `references/menu-api/lab/20261004/audit.json`; frame panels, regional
  profiles, two short films and detailed findings are beside it.
- The initial lab adapter omitted this phone's automatic 62 pt Ask Siri
  footer. A declared systemFooter and an accessibility assertion now verify
  its presence. The ordinary Flutter group gap makes the adapter footer
  63 pt/root 209 pt versus native 62/208 pt: a recorded 1 pt harness
  discrepancy, not production physics. The footer glyph is a declared
  placeholder. Earlier pilot root-height differences must not be fitted
  as physics. Parent widths confirm the 0.97 and 0.97 squared scales.
- Final acquisition is EVIDENCE, with no fidelity gates: 851 global film
  pairs, every paired gesture window above 80% coverage, accepted/decoded
  counts 1800/1684, zero encoder drops and received-path RMS 0.192450 pt.
  Global timing retains runner drift; explicitly separate inspection
  windows align recorded downs without fitting response delay or duration.
- Matching material remains open. Settled More left-rim MAE is 12.021
  encoded RGB levels, shadow MAE 8.223 and face MAE 1.849. Native's attached
  contour is clearer; Flutter exposes the parent's rounded boundary inside
  the child. These are registered image diagnostics, not isolated optical
  transfer coefficients. The supplied liquid tier initialized successfully.
- Repeated opening crosses the diagnostic 100 pt bright-body width between
  125.531 and 142.200 ms after native up, versus 83.815 to 117.083 ms on
  Flutter. More's outside close crosses below 100 pt between 200.293 and
  250.301 ms on native, versus 167.819 to 185.263 ms on Flutter. During
  close, Flutter rows extend beyond the bright body earlier. These intervals
  retain film gaps and display/postFrame phase uncertainty; they are not
  new production delay constants or SDF contour fits.
- [ ] Match the lab adapter's system-footer height and glyph before using
  whole-root residuals as calibration evidence.
- [ ] Calibrate opening phase, closing rows/material ownership, attached
  contour and shadow against these shared films. Previous body-width fits
  and passing widget regressions do not certify full pixel/frame fidelity.
  Row-container bounds and clips must not be promoted as glass contours.

Painter scope and copied card material [macOS diagnostic + phone stills, 2026-10-05]:
- ROOT CAUSE of the lab's missing rim: the lab adapter installs MorphGlass
  inside MaterialApp's home, below the Navigator. The menu vessel lives in
  the navigator's overlay, so MorphGlass.maybeOf returned null there and
  the menu silently drew the no-renderer fallback: flat platter, no
  contour or glint, and the fallback card's rounded cutout (the "parent
  boundary inside the child"). Only the source button was liquid. The
  Flutter side of lab runs menu-phone-20261004-01..07 and
  menu-rim-diagnostic-02 therefore measured the FALLBACK, not the
  renderer; their rim/shadow/face residuals and close panels are void as
  renderer evidence. Gallery films (GalleryApp installs the painter above
  the navigator) were not affected.
- Proof: a macOS profile diagnostic built zero LiquidGlassLayers for the
  open root and card; isolated surfaces (button, frosted menu, field body,
  blur 0 and 10) all drew the 0.75 pt dark contour. The data-pass blending
  hypothesis is disproved: Flutter GPU passes inherit impeller's
  ColorAttachmentDescriptor, blending_enabled = false by default
  (engine/src/flutter/impeller/core/formats.h and lib/gpu/render_pass.cc at
  revision d3b14c8769, Flutter 3.47.2).
- Fix: MorphMenuHost.menuGlass resolves the painter from the source's
  context; the menu layer installs it and cards use it. Regression:
  menu_glass_body_test "a menu in the navigator overlay draws with its
  button painter" (fails before the fix).
- Closing cards keep their own liquid body: the native carrier keeps a
  matched copy of the card material (copied key-fill CASDFLayer 175, local
  250 x 208, radii 32) whose opacity is (window width - 50) / 200 of the
  0.35/0.85 carrier; card-material-copy.json (mm-sub-tap, 35 frames,
  source hash) replays at < 0.015 RMS. This supersedes the 12 ms hand-off
  to the common morph field described above.
- Card shadow: encoded-SDR straight side/bottom profiles on #F2F2F7,
  excluding 3 pt at the contour, fit a Gaussian half-plane alpha 0.1188,
  sigma 16.546 pt, offset 8.109 pt at 0.273 gray RMS; production 30/255,
  blur radius 28, offset 8 replays the holdout at 0.288 RMS
  (card-shadow-profile.json). Light only; the dark shadow keeps its old
  unmeasured color with the same geometry.
- Phone stills, lab/out/menu-phone-20261005-09 (--no-film: the recorder
  found no iPhone screen capture device; stills only, no film, no close
  phase evidence), settled More, encoded RGB MAE vs run 06: submenu left
  rim 10.994 (12.021), p95 56.8, edge RMS 25.8 - both sides now have the
  dark line (native 184/143, ours 196/153, ours 1 device px outward);
  submenu shadow 2.697 (8.223); face 1.588 (1.849); parent rim 11.128
  (11.140, ours 2 px outward). The rim MAE is now a sub-pixel placement
  residual, not a missing contour.
- [ ] Native shows a bright 1 px line inside the contour on the card's
  sides (249 - 253 over a 244 face); ours shows none there (glint only
  along the light axis) and the face is ~2 levels darker.
- [x] Root rows and card headers sat 34.7 pt right of native in lab runs
  since the lab footer gained an icon (b67cb75): the footer's glyph row
  shared the root group, and the glyph column is per group (36 pt =
  titleStart 64 - plainTitleStart 28), so the root rows took the column.
  Natively the footer is its own group, separated by 20 pt instead of an
  inline group's 21. The library rule matches the dumps; the lab adapter
  now draws the footer as two free-form rows (20 pt hairline + 42 pt
  glyph and title at the column positions), so the root keeps 208 pt and
  its rows keep 28 (example/test/lab_test.dart). The footer row is not a
  menu target: it neither highlights nor selects.
- [ ] Close phase: a macOS slow-motion burst shows the root morph blob and
  the retained card copy as two bodies; native shows two bodies at +0.10 s
  and one body by +0.13 s. Needs a phone film once the screen capture
  device is available.

Close timing and one closing body [device element fits + phone film, 2026-10-05]:
- Film run lab/out/menu-phone-20261005-10 (c4d14a7's parent af03154, valid
  acquisition: EVIDENCE, every gesture window >= 0.815 coverage) showed
  our close body 15-27 ms ahead of native in BOTH outside closes, so the
  kept card copy stuck out below a too-small morph body (two bodies until
  +0.19 s; native is one body from about +0.13 s).
- Cause: the menu glass close started at the container's logical close.
  Native glass element widths after the last release (glass-close.json:
  mm-sub-tap/back/deeper/open-light outside, mm-sub-select card row)
  replay the unchanged close spring at 0.16-0.39 pt RMS when the close
  starts 0.050-0.0595 s (outside) and 0.031 s (card row) after release,
  each within 1.5 ms of that record's container fit (card-container.json
  start_after_lift). Nine plain dismissals solved by the menu replay start
  0.046-0.074 s, mean 0.0605. So the container and the glass start
  together: dismissDelay 0.04 -> 0.059 (mean of 13), submenuCloseDelay
  0.015 -> 0.031, cardContainerDelay 0.015 -> 0 (c4d14a7). Regression:
  menu_api_test "the menu glass closes with its container".
- Film run lab/out/menu-phone-20261005-11 (c4d14a7, EVIDENCE, coverage
  0.815-0.947): More's outside close now shows two bodies at +0.09/+0.10 s
  and ONE body with the card rows inside from +0.167 s, like native.
  Contour-width residual over 0-0.30 s after release (Flutter - native):
  close-submenu RMS 10.8 pt, mean -7.4; close-root RMS 13.6, mean -11.0
  (run 10: larger lead). Early frames agree within 2 pt (+0.083: 236 vs
  235; +0.100: 205 vs 203); from +0.117 to +0.18 s ours stays 15-20 pt
  narrower. Open/More/Deeper/back steps: contour width RMS 0.4-1.0 pt
  (opening phases are noisy for this estimator). Settled More stills:
  submenu rim MAE 5.100 (run 09: 10.994), shadow 2.945, face 1.574,
  parent rim 6.711 (11.128).
- [ ] Late close: native visible body 15-20 pt wider than ours at
  +0.12..+0.18 s although the element widths replay at < 0.4 pt; suspect
  the visible silhouette vs element bounds (blurred SDF union) - measure.
- [ ] At +0.09 s native still shows the root rows blurred under the card;
  ours has faded them. The kept card copy's own contour is faintly
  visible inside our body at +0.167 s; native shows none.
- [ ] Opening: native glass element starts 0.07-0.15 s after the tap's
  release (mm-sub-tap 0.150, mm-sub-palette 0.120; plain replays median
  0.082) versus tapOpenDelay 0.05; not changed here.
