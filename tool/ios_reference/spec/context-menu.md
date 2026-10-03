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
  menu view's own alpha/scale model also closes on 0.35/0.85 (whether the
  portal shows that fade is unverified).

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

## Not reproduced / open

- Satellites are app-built columns, not UIMenu rows (no row styling
  measured for context menus specifically).
- Whether the menu view's own 0.35/0.85 fade is visible.

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
  measuredMotion) - no exemption needed. _Retract does not clamp above 1
  (the device menu overshoots its rect). The close's residual undershoot
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
- Not reproduced: the blob's WIDTH for a menu narrower than the lifted
  hero (300x200: device 83.2 x 80, ours 92 x 80 - our blob is 0.4 of the
  slot, the 250 pt menu centered in the 326 pt slot). The native preview
  ramps linearly from 0.2 s and pops at the commit (the growth law above
  is the measured replacement).
