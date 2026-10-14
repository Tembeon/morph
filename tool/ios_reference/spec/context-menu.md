# Context menu passport (THE HOLD)

Status: measured on device (growth, commit, preview, spring, dim,
retract); ported; replayed (morph_context_menu_test).

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
- PREVIEW (preview.json, 20 presentations): open preview at
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

## Fixtures

`ios27-device/context_menu/{growth,holds,preview,morph,dim}.json`.

## Recapture

Scene `w2ctx` (Widgets2), `PROBE_CW` / `PROBE_CH` (preview size),
`PROBE_CY`, `PROBE_W2FILTERS=1`; Widgets2UITests testW2Ctx,
testW2CtxGrowth, testW2CtxCommit, testW2CtxDim, testW2CtxDimLook. Also
scene `menu` with `PROBE_CTX=1`.

## morph

`MorphContextMenuRegion`, `MorphSatellite` (morph_context_menu.dart);
engine flight on a transparent vessel surface spec; `scrimMotion`
(`MorphScrimMotion`) for the dim.

Per-frame work (lifecycle.md, 2026-10-14): the source, hidden once
takeoff settled, returns to its natural size at once (it sprang back for
a second, repainting itself and the page; identical: nothing shows it).
A flight closed before it settled hands back a source that shows, which
still springs. While the source grows under the finger or lands it is a
repaint boundary of its own (`MorphLiveApart`). The shuttle of every
flight is a repaint boundary. Host: hold 20 paints a frame to 2,
release 1.41 s to 0.37 s and 54 to 30 paints a frame. Still per frame:
the vessel follows the morph by layout (19 layouts: the engine's
shuttle chain).

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

morph's region is a separate machine: an engine flight on a transparent vessel whose
column (`above`, hero, `below`) the app fills with `MorphSatellite` widgets, moved by
layout (19 layouts a frame), with its own retract blob, its own live extents and its own
geometry. None of the button menu's card, rows, highlight, flex, slide-to-select, row
haptics, submenus, scrolling or keyboard handling is used. The hold (growth, commit,
haptic, lift), the preview lift and the dim are measured and stay.

Optimizations (ranked): (1) the unification below, which removes the layout-driven column
and gives the context menu every measured behaviour of the button menu; (2) the preview as a
composite-only layer (paint-time transform of the held child, no vessel layout per frame);
(3) the button menu's list (menu-button.md "Optimizations to adopt") then applies to both.

## Unification design (proposal, not implemented)

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
  onOpen: ..., onClose: ...,      // willDisplay / willEnd
  // kept: child, replica, holdDuration, lifts, enabled, opensOnSecondaryTap, tagId,
  // scrim and shadow settings, overlay, semanticLabel, onHold
)
MorphContextMenuRegion.open(context); MorphContextMenuRegion.close(context);
```

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
spec; `onOpen` keeps handing out the flight; new `preview`, `onPreviewTap`, `onClose`,
`order`, `dismissOnSelect`, `appearance`, `close`.

Tests and passports: morph_context_menu_test keeps every device group (morph.json,
preview.json, growth.json, holds.json, dim.json), re-targeted from the vessel column to
the controller's card and the preview layer, with the same tolerances; the satellite
live-column tests become accessory tests; new tests for slide-to-select, row haptics and
keyboard in the context menu (reuse menu_button_test helpers); context_menu_text_style_test
stays for the preview copies; lifecycle_counts_test gets the context release budget of the
button menu; haptics_test, accessibility_test (role menu), presentation_boundary_test,
glass_carry_test, controls_scroll_test, overlay_text_style_test, menu_host_test and the
gallery (example/lib/gallery/menu_page.dart, integration control_matrix,
backdrop_overlay_test) follow the API. Passports: this file ("Not reproduced": app-built
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

- Satellites are app-built columns, not UIMenu rows (no row styling
  measured for context menus specifically).
- The menu view's own fade IS visible [sim 2026-10-14, menu without a
  preview provider, dismissed with `dismissMenu`, layer tree and per-frame
  presentation read live]: `_UIContextMenuView` is a direct child of the
  container, not a portal source (the portals show the held source view,
  `hidesSourceLayer` on); on dismiss its opacity goes 1 -> 0 with its scale
  1 -> 0.195, the opacity fitting a 0.344 / 0.86 spring (rms 0.0025) = the
  0.35 / 0.85 model. Whether morph's satellites show the same fade is
  not checked here.

## API gaps

- `previewProvider` with a different preview view controller than the
  source (morph always previews the held child itself).
- Preview commit (`willPerformPreviewAction`, pop into the preview VC).
- `menuAppearance` compact vs rich, `badgeCount`, `updateVisibleMenu`.
- A UIMenu-driven action list (morph takes arbitrary satellite widgets).

## Implementation notes (morph side, moved from CLAUDE.md)

- Flight container: a TRANSPARENT VESSEL surface spec (color 0x00000000,
  elevation 0, clipBehavior none) - not `MorphTargetSpec.vessel`: the hero
  draws its own surface and flies as a MorphSharedElement with fade none;
  the vessel's contentAlignment is COMPUTED so the hero slot coincides
  with the flying hero at every spring value - A = heroOffset / (column
  size - hero size) per axis - so the satellites ride the hero as one rigid
  body and arrive WITH the surface. The hero stays put unless the column
  leaves the safe area (or the keyboard edge); then the whole column shifts
  (Telegram's shift).
- LIFT (`lifts`, replaced `pressGrow`): glass-button model, uniform scale
  by `MorphFlexSpec.forSize(size).liftScalePoints`, press on the tracking
  spring, release on the scale spring, on a SingleMotionController.
- Gesture: the State OWNS a TapGestureRecognizer (onTapDown lifts -
  deferred to the touch deadline inside a scrollable, so a scroll never
  flashes it; onSecondaryTapUp opens) and a LongPressGestureRecognizer
  (duration = the commit point, recreated on change - a RawGestureDetector
  cannot swap a constructor argument without remounting, and a remount
  re-registers the MorphTag mid-frame); fed from a raw Listener with
  deferToChild. The press transform sits ABOVE the tag so the flight takes
  off from the lifted pixels; the natural rect is measured from the
  region's own box above the transform. After the hold wins the press is
  FROZEN (a tap cancel must not start a second spring under a flight
  re-reading the transformed rect - the hero would shake), released once
  takeoff settles or the flight closes.
- Growth clock: a Ticker started on the pointer down (first frame after
  the touch is t = 0; shown only once the tap is down); past the commit a
  release opens the menu and a Timer opens it at holdDuration. The tap's
  cancel arrives BEFORE the winner's onLongPressStart, so _drop's verdict
  waits a microtask; pointer up / cancel on the raw Listener stops the
  clock (a swipe taken before the touch deadline never sends tap
  down/cancel).
- The marker for `MorphContextMenuRegion.open(context)` lives INSIDE the
  tag child so the shuttle's hero copies carry it (a "more" glyph in the
  open menu retargets instead of asserting).
- LIVE COLUMN: the hero slot and every content-sized satellite are
  measured by MorphContentMeasure; their extents spring on the flight's
  open motion on per-extent SingleMotionControllers on the REGION STATE's
  tickers (springs vsync'd by the flight's scope tripped its
  disposed-with-active-ticker assert, because flight.closed completes a
  microtask late), disposed with the flight or the State. Rect AND
  contentAlignment are read live: _MenuTarget extends MorphTargetSpec,
  overrides the alignment getter and hands the geometry as `repaint`, so
  frame, alignment and slots move in ONE frame; at value 1 the alignment
  offset vanishes whatever A is. Slots clip natural-size content while the
  extent catches up. A child or satellite change while open rebuilds the
  menu (didUpdateWidget -> flight.markNeedsBuild, deferred).
- TEXT STYLE: every copy of the hero (the shuttle's source replica, the
  menu slot, the flying layer) sits under the shuttle's Material, whose
  default text style (the theme's body) replaced the page's; a hero whose
  content fills its height overflowed its slot, sized from the source
  (1.6 pt on the gallery's list rows). The region wraps each copy in its
  own DefaultTextStyle (context_menu_text_style_test).
- `replica:` = source-side copy only (no snapshotGhost: without a live
  source marker the pair cannot form); `opensOnSecondaryTap` leaves the
  right click to an ancestor; onHold = the threshold (haptic moment),
  onOpen hands out the flight; the region does NOT abort its flight on
  dispose - a hero deleted from its own menu dissolves via the engine's
  source-lost path.
- PREVIEW port: the menu's hero slot is the LIFTED hero (slotWidth /
  slotHeight = natural extents x scale; the copy laid out at natural size
  inside OverflowBox + Transform.scale from the top left, so text never
  rewraps), placed about the launch rect's center; satellites stand `gap`
  off the lifted hero and the safe-area clamp sees the lifted column. The
  flight lerps the shared hero from the grown source to the lifted slot
  (60x40 shrinks 74.9 -> 69, 300x200 grows 314.9 -> 326) and home to
  natural.
- SPRING port: `measuredMotion` = MorphMotion.springs(measuredSpring both
  ways), default for the region (explicit motion > MorphTheme >
  measuredMotion) - no exemption needed. Container size and concentric
  radius extrapolate above 1 in the engine. _Retract uses that same
  morphFlightGeometry helper for the satellite's blob-to-slot rect, with
  no separate Rect.lerp overshoot formula or extra scale. The column lays
  content out at its natural size, so merely clamping _Retract would erase
  the satellite's size overshoot even as the outer container grows: the
  device replay's width/height peaks would become exactly 1.0. The menu
  rect's own size interpolation is applied once through the engine helper.
  The close's residual undershoot
  plays on the SOURCE hero (_followLanding: the press Transform adds
  min(value, 0) x (measuredPreviewScale - 1) while isLanding).
- DIM port: through the engine's scrim channel
  (`MorphContextMenuRegion.measuredDim` = MorphScrimMotion with the
  measured springs and delays, `measuredDimOpacity(brightness)` the
  ceiling; explicit maxScrimOpacity > MorphTheme > measured). Replay vs
  dim.json aligned at each side's geometry start: 0.0014 open / 0.0009
  close rms of alpha, light and dark.
- BLOB placement: where it is SEEN - the held view's center, found through
  the column's content alignment inside the vessel's value-0 rect, with the
  shuttle's 0.95 reveal scale divided out (`morphTargetRevealScale`,
  frame.dart); at the lifted slot's center a below satellite sat 15 pt low
  (300x200: 314.6 vs 300). Engine fix this needed: the shuttle's target
  anchor sits BELOW the reveal Transform.scale (target rects in layout
  space).
- Replays (morph_context_menu_test): device morph group (menu open/close
  and hero close under 1 percent of travel at the best start, normalized by
  the DEVICE endpoints - held center 300, device menu rect; hero vs
  preview.json under 0.12 pt open / 0.25 close); device preview group
  (s/m/t/l: open size and center exact, menu at the device rect, never
  back through natural size while open).
- Engine size-overshoot change (2026-10-04): menu center RMS as percent of
  device travel, before -> after: ctxd-m-1 open 0.473 -> 0.456, close
  0.680 -> 0.680; ctxd-l-1 open 0.487 -> 0.499, close 0.614 -> 0.614.
  Hero close remains 0.528 / 0.559 percent respectively. Menu size RMS is
  unchanged: width 0.659 / 1.069 percent, height 0.726 / 0.577 percent;
  the larger width error includes the blob-width gap below. Size peaks
  remain above 1, with no widget-specific overshoot formula.
- Not reproduced: the blob's WIDTH for a menu narrower than the lifted
  hero (300x200: device 83.2 x 80, ours 92 x 80 - our blob is 0.4 of the
  slot, the 250 pt menu centered in the 326 pt slot). The native preview
  ramps linearly from 0.2 s and pops at the commit (the growth law above
  is the measured replacement).

- Reduce Motion and haptics, read from UIKit (notes private): the held preview stays at scale 1 (ported), the presentation fades without the morph (device pass pending); the preview tap haptic at the hold, a selection haptic per row under a sliding finger. See states.md.
