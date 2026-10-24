# Context menu passport (THE HOLD)

Status: measured on device (growth, commit, preview, spring, dim,
retract); ported; replayed (morph_context_menu_test, menu_context_motion_test).
Unified with the button menu (2026-10-14): one menu implementation.

## Native

`UIContextMenuInteraction` (+ delegate: configuration, previews
`UITargetedPreview`, willDisplay/willEnd, willPerformPreviewAction),
`UIContextMenuConfiguration` (`identifier`, previewProvider, actionProvider,
`badgeCount`, `preferredMenuElementOrder`), `menuAppearance` (rich /
compact), `preferredCommitStyle`, `dismissMenu`, `updateVisibleMenuWithBlock:`.
Internals: `_UIContextMenuView`, the morph container carrying it, the dim
= full-screen UIVisualEffectView.

## Spec

- Hold: UIKit opens at 0.78 s (device 0.768 - 0.797) = default
  `holdDuration` (`measuredHoldDuration`).
- GROWTH while held (fixture growth.json, 60x40 .. 300x200, 28 holds): hero
  scale 1 + growth(t) / longest side, t = hold clock from the touch;
  growth 0 until 0.184 s, 32 pt/s to 8 pt at 0.434, then 20 pt/s to 15 pt;
  absolute points on every size, along the long axis (80x160 grows in
  height). Early release snaps to rest next frame.
- COMMIT point `measuredCommitDuration` min(0.42 s, holdDuration): 0.400
  cancels, 0.433 opens, knee 0.434; past it a release opens the menu (and
  the child's tap does not fire).
- PREVIEW (preview.json, 20 presentations): unconstrained open preview at
  `measuredPreviewScale` = min(15 percent of long side, 26 pt) over the long
  side about the held view's center (60x40 -> 69x46, 300x200 -> 326x217.3;
  device-confirmed 138x92 and 326x217.3); resizes from the held size on ONE
  spring each way 0.284/0.81 (0.06 pt rms open, < 0.25 close).
- SPRING (morph.json, probe testW2CtxDim): preview resize AND menu blob
  growth/retract run on the same 0.284/0.81 spring both ways, launched
  together (within 4 ms; 0.4 - 0.6 percent rms of travel) =
  `measuredSpring` / `measuredMotion`. Open overshoots 1.3 - 1.9 percent;
  close dips -1.3 percent, crosses zero at 0.19 s; the residual undershoot
  plays on the source hero (300x200 dips 0.43 pt).
- Menu gap 16 pt from the lifted preview (`measuredMenuGap`).
- RETRACT: satellites unfold out of / retract into a blob at the held
  view's CENTER: 0.4 of the SHORTER side tall (300x200 -> 83x80, 80x160 ->
  32x32; uniform 0.4 exact for landscape <= 1.5:1) - `measuredRetractScale`.
- DIM (dim.json): black, alpha only, no blur filter; 0.2 light / 0.48 dark
  (`measuredDimOpacity`); opens on 0.32/0.80, closes on 0.35/0.85, 14.5 ms
  and 12.5 ms after the geometry (`measuredDim`, engine scrimMotion). The
  menu view's own alpha/scale model also closes on 0.35/0.85, and that
  fade is visible (simulator, see Not reproduced / open).

## Viewport fitting (simulator, 2026-10-24)

Eight native `UIContextMenuInteraction` holds in the existing `w2ctx` scene on
an iPhone 18 Pro simulator, iOS 27.0, 402 x 874 at 3x, with system insets 62/34.
Received XCUITest touches, resting presentation frames before the open screenshot,
source/environment hashes and screenshot attachments are retained in
`~/morph-re/2026-10-24-context-preview-fit/morph-preview-fit-native-*-001`. The compact replay fixture is
`test/fixtures/ios27-simulator/context_menu/preview_fit.json`; scenario hashes are
stored per case. These are simulator geometry observations, not physical-device
haptics, timing, optics or performance evidence.

- The measured lift is a preferred size, not an unconditional enlargement.
  The preview is uniformly fitted into the safe viewport with 16 pt margins:
  `min(1, availableWidth / preferredWidth, availableHeight / preferredHeight)`.
  A 390 x 220 source opens at 370 x 209, centered at x=201; a 350 x 220 source
  also caps at 370 wide. The 340 x 220 control opens at 366 wide, retaining the
  measured lift. Native alignment to the 3x pixel grid explains sub-point
  height/center rounding; replay tolerance is the existing resting 0.5 pt.
- Height uses the same safe viewport, independently of menu height. A 300 x 1000
  source fits to 224 x 746; a 390 x 1600 source fits to 182 x 746. Both preview
  frames span y=78..824. Ordinary 120 x 80 still opens at 138 x 92.
- Below/above placement and moving the pair are retained when their whole column
  fits. If it cannot, the preview reaches the safe top and the menu reaches the
  safe bottom, overlapping the preview instead of pushing either outside.
  A 300 x 700 source opens at 311.33 x 726, top=78; its 250 x 104 menu sits at
  y=720..824. The menu paints above the preview, confirmed by the screenshots.
- A matching Flutter simulator capture of the wide case receives the same
  XCUITest hold and confirms the 370-point centered preview visually:
  `~/morph-re/2026-10-24-context-preview-fit/morph-preview-fit-flutter-wide-001`.
  Its temporary target source is retained alongside the captures; native
  screenshots are the geometry oracle, not an optics-equivalence claim.
- The source's original rectangle is unchanged; closing returns to it. The
  fitted width/height, rather than the unconstrained lift, define the residual
  source scale past the close hand-off. Springs and hold timing are unchanged.

`MorphSatellite` continues reserving its declared room above the fitted preview;
this is its existing API contract, not a new native accessory measurement.
The preferred custom `previewSize` is constrained by the same viewport; native
preview-provider layout and commit semantics are not newly measured here.

## Fixtures

`ios27-device/context_menu/{growth,holds,preview,morph,dim}.json`.

## Recapture

Scene `w2ctx` (Widgets2), `PROBE_CW` / `PROBE_CH` (preview size),
`PROBE_CY`, `PROBE_W2FILTERS=1`; Widgets2UITests testW2Ctx,
testW2CtxGrowth, testW2CtxCommit, testW2CtxDim, testW2CtxDimLook. Also
scene `menu` with `PROBE_CTX=1`.

## morph

`MorphContextMenuRegion` (morph_context_menu.dart): the hold (growth,
commit, preview haptic, lift), then ONE vessel flight carrying the
preview, the accessory (`MorphSatellite`), the button menu's
`MorphMenuLayer` and the dim (`scrimMotion`, `MorphScrimMotion`). The
menu rows are `MorphMenuController` / `MorphMenuMotion` on
`MorphMenuTuning.context` (`MorphMenuMorphSpec.context`: 0.284 / 0.81
both ways, no kicks, no fusion) with a `MorphMenuAttachment` (blob 0.4
of the held view at its center, `blobSize`; placement 16 pt off the
lifted preview, `placeAttached`). The held finger is handed to the
controller after the hold (`MorphMenuController.holdOpen`); the
controller launches the region's flight through its `launch` hook.

Per-frame work (lifecycle.md, 2026-10-14): the source, hidden once
takeoff settled, returns to its natural size at once. While the source
grows under the finger or lands it is a repaint boundary of its own
(`MorphLiveApart`). The preview is a copy laid out once at the held
view's natural size inside a repaint boundary and moved by a paint-time
transform (NEAR: text resampled from one raster); the accessory is laid
out once and moved the same way; the vessel's dim sits in its own
repaint boundary. Host (flat / liquid, median per frame b/l/p): release
0/19/30 -> 0/1/23 / 0/4/28, close 0/0/21 (72 first builds) -> 0/1/21
/ 0/4/26: the button menu's budget (menu open-inline 0/1/22, 0/6/29).

Replays (fraction of travel, m / l, morph.json): menu open 0.43 / 0.46
(column: 0.46 / 0.50), close 0.78 / 0.77 (0.68 / 0.61; a spring released
from rest at its best start fits these frames at 0.76 / 0.75 only, the
column's extra frame of latency read better), width 0.73 / 0.36 (0.66 /
1.07: the blob is now 83.2 wide on 300 x 200 as on the device), height
0.80 / 0.39 (0.73 / 0.58). Preview open / close and dim replays
unchanged. The pure motion replays the same frames in
menu_context_motion_test.

## How UIKit renders it [simulator 2026-10-14 + device lifecycle runs]

Read from UIKit, notes private. Same capture as menu-button.md "How UIKit renders it"
(iOS 27.0 simulator, a 200 x 120 view with a context menu interaction, held 1.2 s, and
held 0.95 s then slid onto a row; device lifecycle-menu-005 for the counts).

- It IS the button menu. The context menu and the button menu are one implementation:
  the same menu view, list, rows, highlight platter, flex, hold-then-slide selection,
  liquid morph container and glass; a per-presentation style decides the differences
  (preview or none, attachment edge, background dim, stacked submenus). The button menu
  is the context menu without a preview.
- Hold. ~0.17 s after the touch the held view is mirrored into a preview platter (the
  original hidden) and the platter grows from the main thread every frame (1 layout a
  frame; device: 9 layouts + 11 creations at 0.17 s, then 1 a frame), its shadow fading
  in. The preview haptic plays at the commit point (~0.42 - 0.45 s).
- Open (at the hold, 0.78 s): the whole menu, morph container and both glass layers are
  built in one frame (device 202 layouts + 298 creations), then nothing per frame on the
  main thread: the motion is written from the background thread as for the button menu.
- Two morphs, two glass layers. The preview is its own morph (mirror of the held view,
  lifted to `measuredPreviewScale`: 200 x 120 -> 226 x 135.67) with its own glass layer
  (background at full resolution, its fill invisible); the menu grows out of a blob
  0.4 x the held view at its center (80 x 48) to 250 x 272, 16 pt below the lifted
  preview, on its own glass. Separate glass layers: the menu never fuses with the preview.
- Dim: a full-screen black layer whose opacity alone animates (0.2 light), also written
  from the background thread; the button menu keeps it at 0.
- The preview is not rasterized: it is a live mirror (no rasterized layer anywhere in the
  open tree); text in it is the held view's own bitmaps, scaled.
- Hold then slide: identical to the button menu (the highlight platter follows the
  finger, the release on a row fires its action ~10 - 20 ms after the lift, then the
  close).
- Close: the preview morphs back onto the held view (natural size at ~0.45 s), the menu
  retracts into the 0.4 blob, the dim fades, the views are removed after it.

### morph against it

Since the unification (below) the region is a trigger, a preview layer and an accessory
on top of the button menu, as UIKit's is: the card, rows, highlight, flex,
slide-to-select, row haptics, submenus, scrolling and keyboard are the button menu's.
Differences left: one glass layer per surface (no separate full-resolution backdrop for
the preview), the preview is a copy of the held view (UIKit: a live portal), and the
button menu's list optimizations (menu-button.md "Optimizations to adopt") apply to both.

## Unification design (implemented 2026-10-14, phases 1 - 5)

Implemented as designed, with these differences: one vessel flight carries the preview,
the accessory, the menu and the dim (the menu's controller launches it through a
`launch` hook), the preview is a composite-only copy from phase 3 on; the accessory is
centered on the preview and does not spring (a content-sized accessory grows upward at
once); a preview whose content changes while open keeps its open size; the keyboard does
not move an open context menu (placement is decided at the open, as for the button
menu). `previewSize` is morph's `preferredContentSize` for `preview:`.

That paragraph describes morph's implementation. Independent device endpoint evidence for UIButton.menu keyboard changes is recorded in menu-button.md (2026-10-18). The context-menu trigger/preview and close landing have not been measured under that protocol; button-menu observations are not context-menu parity.

One menu implementation - the `MorphMenuSource` path: `MorphMenuController` (gesture,
motion, content, flight), `MorphMenuMotion` / `MorphMenuTuning`, `MorphMenuLayer` (card,
rows, highlight, flex, submenu cards, scrolling, keyboard, semantics) - serves the
button, the bar item and the context menu. `MorphContextMenuRegion` becomes a trigger and
a preview layer on top of it.

API (mirrors `UIContextMenuInteraction` + `UIContextMenuConfiguration` and SwiftUI
`contextMenu(menuItems:preview:)`):

```dart
MorphContextMenuRegion(
  menu: <MorphMenuEntry>[...],   // menuItems / actionProvider; the shared entries
  preview: (context) => ...,      // preview: / previewProvider; null previews child
  accessory: MorphSatellite(...), // morph-only: the slot above (reactions capsule)
  order: MorphMenuOrder.automatic,// preferredMenuElementOrder
  dismissOnSelect: null,          // menuActionDismissBehavior
  appearance: ...,                // MorphMenuAppearance
  onPreviewTap: ...,              // willPerformPreviewAction (commit)
  onClose: ...,                   // willEnd
  // kept: child, replica, previewSize, holdDuration, lifts, enabled,
  // opensOnSecondaryTap, maxScrimOpacity, scrimColor, semanticLabel, onHold
)
MorphContextMenuRegion.close(context);
```

Since 2026-10-19 `onOpen` (willDisplay, hands out the flight),
`MorphContextMenuRegion.open(context)`, `tagId`, `overlay` and `scrimMotion`
are `@internal`: the public API has no willDisplay callback and no open
from code.

How it works:
- The region keeps its gesture (hold growth, commit point, preview haptic, secondary click,
  `open`), the preview lift and the dim. At the hold it opens a `MorphMenuController`
  whose source is the preview's blob (0.4 of the held view at its center) instead of a
  button, with a context morph spec (`MorphMenuMorphSpec.context`: the measured
  0.284 / 0.81 spring both ways, no button kicks, no fusion with the preview).
- Placement: the controller's layout, attached 16 pt below the lifted preview (above
  when it does not fit, entries reversed as for an upward button menu), the preview and
  menu shifting together to stay in the safe area (today's column shift).
- After the hold the region hands the pointer to the controller's `menuPointerMove` /
  `menuPointerUp`, as `MorphBarButton` does: hold, slide onto a row, release to choose,
  with the row haptic and the highlight of the button menu. A release on the preview
  without moving keeps the menu open.
- `accessory` rides the preview (UIKit's accessory views) on the preview's morph; the
  rows are always the shared menu card. A free-form block below the preview becomes a
  `MorphMenuWidget` entry.
- A menu without a preview is `MorphMenuSource(trigger: MorphMenuTrigger.hold)`, as in
  UIKit (`menuAppearance` compact).

Code that goes away (morph_context_menu.dart): `_MenuColumn`, `_Retract`, `_MenuTarget`,
`_LiveExtent`, `_MenuGeometry` (the column, its content-alignment formula, the per-extent
springs, the satellite measurement), the `below` satellite and the transparent-vessel
column flight - roughly lines 914 - 1495 of 1507, plus the satellite paths of the region
state. Kept: the gesture and growth (`_MotionHoldRecognizer`, growth clock, commit),
`measured*` constants, the dim (`measuredDim`), the preview lift and its text-style copies.

Public API migration (before the first release, so a break with CHANGELOG notes, no
deprecation): `below: MorphSatellite(...)` -> `menu: [MorphMenuItem(...)]` (free-form
content -> `MorphMenuWidget`); `above:` -> `accessory:`; `width` -> the menu's own width
(`MorphMenuTuning.menuWidth`); `gap` and `alignment` -> the menu layout (16 pt,
attachment edge); `margin` -> the menu's safe-area rules; `motion` -> the context morph
spec; `onOpen` keeps handing out the flight (`@internal` since 2026-10-19); new
`preview`, `onPreviewTap`, `onClose`, `order`, `dismissOnSelect`, `appearance`, `close`.

Tests and passports: morph_context_menu_test keeps every device group (morph.json,
preview.json, growth.json, holds.json, dim.json), re-targeted from the vessel column to
the controller's card and the preview layer, with the same tolerances; the satellite
live-column tests become accessory tests; new tests for slide-to-select, row haptics and
keyboard in the context menu; context_menu_text_style_test
stays for the preview copies; lifecycle_counts_test gets the context release budget of the
button menu; haptics_test, accessibility_test (role menu),
glass_carry_test, controls_scroll_test, overlay_text_style_test, menu_host_test and the
gallery (example/lib/gallery/menu_page.dart, example/test/control_matrix_test.dart)
follow the API (menu_button_test, presentation_boundary_test and
backdrop_overlay_test were removed in 98237e58). Passports: this file ("Not reproduced": app-built
satellites goes), menu-api.md and api/menus.md (the `UIContextMenuInteraction`,
`previewProvider` and `contextMenu(menuItems:preview:)` gaps close), docs/widgets.md.

Phases: (1) `MorphMenuMorphSpec.context` and a blob source in `MorphMenuMotion`, replayed
against morph.json at today's error; (2) `menu:` on the region through
`MorphMenuController`, the preview still on today's engine flight, pointer hand-off after
the hold; (3) `accessory`, removal of the column code, API break, test and passport
moves; (4) the preview as a composite-only layer (closes the 19 layouts a frame); (5)
`preview:` builder and `onPreviewTap`. Each phase: the replays at their current errors,
lifecycle counts no worse, device parity run and the owner's eye on the iPhone for (2)
and (4).

## Not reproduced / open

- The accessory's unfold (opacity and 0.4 -> 1 scale from the preview's
  top edge) and the custom preview's crossfade are not measured.
- The menu's own close fade (0.35 / 0.85, below) is the button menu's
  content fade here.
- The menu view's own fade IS visible [sim 2026-10-14, menu without a
  preview provider, dismissed with `dismissMenu`, layer tree and per-frame
  presentation read live]: `_UIContextMenuView` is a direct child of the
  container, not a portal source (the portals show the held source view,
  `hidesSourceLayer` on); on dismiss its opacity goes 1 -> 0 with its scale
  1 -> 0.195, the opacity fitting a 0.344 / 0.86 spring (rms 0.0025) = the
  0.35 / 0.85 model. Whether morph's satellites show the same fade is
  not checked here.

## API gaps

- `menuAppearance` compact vs rich, `badgeCount`; `previewProvider`'s
  commit style `.pop` (the app pushes its page from `onPreviewTap`).
- Closed by the unification: `menu:` rows, `preview:` (+ `previewSize`),
  `onPreviewTap`, `onClose`, `close(context)`, `order`,
  `dismissOnSelect`, `appearance`; `updateVisibleMenu` is a rebuild with
  new entries.
- Open again since 2026-10-19: `willDisplayMenu` (`onOpen` is
  `@internal`; `onHold` covers the hold door only) and opening from code
  (`open(context)` is `@internal`).
- Not implemented: the preview platter (its shadow fading in, above;
  shape and fill through `UIPreviewParameters`), highlight / dismissal previews
  (`UITargetedPreview` of another view), `allowsTypeSelect` (27).
  Full table: [api/menus](api/menus.md).

## Implementation notes (morph side)

- Gesture: the State OWNS a TapGestureRecognizer (onTapDown lifts -
  deferred to the touch deadline inside a scrollable, so a scroll never
  flashes it; onSecondaryTapUp opens) and a long press advanced by the
  hold ticker, fed from a raw Listener with deferToChild; a third arena
  member keeps a held press from a scrollable. The press transform sits
  ABOVE the tag so the flight takes off from the lifted pixels; the
  natural rect is measured from the region's own box above the
  transform. After the hold wins the press is FROZEN, released once
  takeoff settles or the flight closes. The same Listener routes the
  held finger's moves and release to the menu controller.
- Growth clock: a Ticker started on the pointer down; past the commit a
  release opens the menu and the ticker opens it at holdDuration. The
  tap's cancel arrives BEFORE the winner's onLongPressStart, so the
  drop's verdict waits a microtask.
- The marker for `open(context)` / `close(context)` lives inside the
  tag child and in every overlay copy (preview, accessory, menu rows).
- TEXT STYLE: every overlay copy of the held view sits under the
  shuttle's Material; the region wraps it in the source's own text style
  (`sourceThemes.wrapText`, context_menu_text_style_test).
- PREVIEW: `_PreviewLayer` lays the copy out at the held view's natural
  size at the overlay origin and transforms it onto
  `Rect.lerp(sourceRect, preview, value)` (the grown source on the open,
  the natural one on the close; overshoot included). The close's residual
  undershoot plays on the SOURCE (`_followLanding`: the press transform
  adds min(value, 0) x (fittedPreview / source - 1) per axis while landing).
- DIM: the engine's scrim channel (`measuredDim`, `measuredDimOpacity`);
  replay vs dim.json 0.0014 open / 0.0009 close rms of alpha.
- The region does NOT abort its flight on dispose: a held view deleted
  from its own menu dissolves via the engine's source-lost path.

- Reduce Motion and haptics, read from UIKit (notes private): the held preview stays at scale 1 (ported), the presentation fades without the morph (device pass pending); the preview tap haptic at the hold, a selection haptic per row under a sliding finger. See states.md.
