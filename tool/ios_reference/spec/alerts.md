# Alerts and action sheets passport

Status: measured simulator (iPhone 18 Pro Max 440 x 956) + device
(springs, lift, lean; iPhone 16 Pro) + film; ported; replayed (alert_test).

## Native

`UIAlertController` (`_UIAlertControllerPhoneTVMacView` = platter),
`_UIPopoverView` for an action sheet with a source.
Public API (SDK 27.0): `alertControllerWithTitle:message:preferredStyle:`
(alert / actionSheet), `addAction:` (`UIAlertAction` title, style
default / cancel / destructive, `enabled`, handler), `preferredAction`,
`addTextFieldWithConfigurationHandler:`, `textFields`, `severity`
(default / critical); `popoverPresentationController` (`sourceView`,
`sourceRect`, `sourceItem`, `permittedArrowDirections`,
`canOverlapSourceViewRect`, `passthroughViews`, `popoverLayoutMargins`).

## Spec - alert

- `MorphAlertMotion`: two DOFs on ONE spring CASpringAnimation 522.35/45.71
  = 0.2749/1.0 [tuning]: progress (alpha + 0.2 black dimming, both ways)
  and scale (snapped to 1.199 at present on device, 1.196 sim; heads to 1).
  A dismissal only fades. Scale 0.0005 rms, dimming 0.008 rms.
- Layout [layout]: 320 wide, radius 34, centered in the safe area +
  keyboard, text inset 30, header top 22; title 17 semibold (alone: 17
  regular), message 15 regular secondaryLabel, 7.33 between, 4.33 / 3.67
  below; buttons 48 capsules (tertiarySystemFill) 16 inset, 8 apart;
  exactly two actions in a row with cancel FIRST, otherwise a column with
  cancel LAST; preferred = accent fill + white semibold; actions 17 medium;
  text field 290 x 48 capsule.
- Touch: lifts the WHOLE platter with the glass-button model at the
  alert's size (forSize: lift 4 -> 1.0125; 0.09 - 0.25 pt rms); a dragging
  finger stretches and shifts it by the same flex at that size (threshold
  24000) [device: 0.4 pt lean per 120 pt drag; replay 0.017 / 0.042 pt rms
  lean, 0.09 / 0.19 pt size, no fitted constant]; pressed button fill
  drops to 0.4 of its alpha; finger may slide between buttons.
- A finger that drags an overflowing alert's content chooses nothing:
  the press cancels (highlight off, platter released) as soon as the
  content takes the drag, also when it is pinned against an edge and
  cannot move, as UIKit's scroll view cancels its content touches when
  its pan begins. No recording scrolls an alert; the
  rule is the menu rows' (menu.dart content scroll).
- Handlers run after the dismissal (UIKit ~0.45 s after the touch-up).
- Glass fades through `MorphGlassSurface.opacity` (no gray platter).

## Spec - action sheet popover

- With a source: glass popover, `MorphPopoverMotion` one progress: scale
  0.01 -> 1 about the arrow tip + alpha; present 331.9/29.15 = 0.345/0.80,
  dismiss 283.97/28.65 = 0.373/0.85 [tuning; 0.005 rms].
- Content 240 wide, arrow 28 x 13, radius 34; cancel omitted and run at
  once by a tap outside; the popover does NOT lift under a touch [device].
- `morphPlacePopover`: candidates above, below, trailing, leading; centered
  on the source across, slid into 10 pt margins and the safe area, toward
  the source by at most the arrow length (overlaps a source by 3 pt rather
  than switching sides); skip a candidate whose arrow comes within 48 pt
  (radius + half arrow) of a corner; least total slide wins (15/15).
- Without a source an iPhone action sheet IS an alert (cancel last).

## Disabled actions [device, light + dark, 2026-10-03, scene x4disalert]

- `UIAlertAction.isEnabled = NO`: the title turns tertiaryLabel (dark 0x4CEBEBF5, light 0x4C3C3C43) - a destructive
  action loses its red too; the action's fill (tertiarySystemFill)
  is unchanged; the action view's tintAdjustmentMode dims.
- A disabled PREFERRED action loses the accent fill (it shows the plain
  tertiarySystemFill) and keeps the semibold title (fw 0.3) in
  tertiaryLabel; enabling it brings the accent fill + white title back.
- Rendered title peak: dark 111 on the 60 fill, light 121 on 198.
- One frame, no animation, both ways (rows: column alert Enabled /
  Disabled / Delete / Cancel; row alert Cancel + disabled preferred OK with
  a text field).
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method in [states](states.md).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): `MorphAlertAppearance.disabledLabelColor`; a disabled
  preferred action takes `buttonColor` and keeps w600.

## Fixtures

Device `ios27-device/alert/` (present-dismiss, press, tap, slide, lean,
ash-press, ash-tap-out). Simulator `ios27/alert/` incl. placements.json.
Film crops `references/alert-video/`.

## Recapture

Scene `x3alert` (Extras): `PROBE_ALERT=alert|sheet`, `PROBE_ACTIONS`,
`PROBE_ORDER`, `PROBE_PREFERRED`, `PROBE_TF`, `PROBE_NOTITLE`,
`PROBE_NOMSG`, `PROBE_BTN_X/Y` (source), `PROBE_DARK`, `PROBE_SCRIPT`
(show, dismiss, settings). ExtrasUITests testX3Alert, testX3Device,
testX3AlertVideo. Older scene `w2alert`.

## morph

alert.dart (`showMorphAlert`, `showMorphActionSheet(anchor:/anchorRect:)`,
`MorphAlertRoute`, `MorphAlertAction`, `MorphAlertActionStyle`,
`MorphAlertTextField`, `MorphAlertAppearance`), alert_motion.dart
(`MorphAlertMotion`, `MorphAlertTuning`, `MorphPopoverMotion`,
`MorphPopoverTuning`, `morphPlacePopover`).

Dismissal (lifecycle.md): the build that stops the card taking touches
hands back the card built before, so the card does not rebuild; host
recorder, dismiss frame 0: 115 -> 76 builds (100 -> 74 for an action
sheet), the rest the navigator's own pop. The 18-25 paints a frame of the
show and dismiss motions stay (the dimming and the card's fade repaint
the route; gap 12 in lifecycle.md).

Performance trade (2026-10-13, declared in `showMorphAlert`): the card's
content (text, buttons, fields) is a `MorphGlyphs.faded` card. While its
scale moves (present 1.199 -> 1, the lift, a popover's 0.01 -> 1) it is
drawn from one raster, mipmapped - NEAR (resampled, at most 9 percent
magnified); at rest exact - IDENTICAL; the fade is the drawing's own
opacity layer - IDENTICAL (exact-mode frame hashes of every matrix cell
unchanged) - except while it draws from its raster, where the fade is the
alpha of the one image draw, without an offscreen pass - NEAR: at most 1
of 255 per channel (see date-picker.md). Host, exact vs policy every frame (glyph_scale_test): 110
frames, 55 off live, worst mean 0.07 per channel, 0.07 percent of pixels
over 15. Glyph strike frames over three bench runs (glyph_strikes_test,
Impeller's atlas keys replayed): 67 -> 3; three rasters a run (two
scales and the highlighted button). Pixel matrix before:
m/alert/open-close 18.9 percent strike frames, 6.8 - 7.1 ms
UpdateAtlasBitmap in frames over budget (bench-matrix-night).

## Not reproduced / open

- The source button's tint dimming while the popover is up.
- 0.7 s first popover present latency on the simulator.
- The popover arrow in the glass painter (always drawn flat).

## API gaps

- `severity = .critical`.
- `permittedArrowDirections`, `passthroughViews`, `canOverlapSourceViewRect`.
- A general popover presentation (any content in a popover) - morph only
  has the action sheet popover.
- Text fields take onChanged, autofocus, autocorrect, suggestions,
  capitalization, input formatters and a semantic label; an action's
  enablement follows `MorphAlertAction.enabledListenable` live (its look
  changes in one frame, as the measured disabled look; whether UIKit
  animates the change is not measured). Text field clear button, return
  key type and text content type are missing.

## Implementation notes (morph side, moved from CLAUDE.md)

- `showMorphAlert` / `showMorphActionSheet` push a `MorphAlertRoute` (the
  sheet's PopupRoute pattern: zero transition, the motion finalizes the
  pop).
- The alert's and the popover's glass fade through
  `MorphGlassSurface.opacity` and the content through its own Opacity ABOVE
  the glass - an Opacity above the glass read an empty backdrop (a gray
  platter while fading). Filmed against UIKit on the device,
  references/alert-video/ (native top, ours bottom).
