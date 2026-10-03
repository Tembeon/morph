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
