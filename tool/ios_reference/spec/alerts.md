# Alerts and action sheets passport

Status: measured simulator (iPhone 18 Pro Max 440 x 956) + device
(springs, lift, lean; iPhone 16 Pro) + film; ported; replayed (alert_test,
disabled_test).

## Native

`UIAlertController` (`_UIAlertControllerPhoneTVMacView` = platter),
`_UIPopoverView` for an action sheet with a source.
Public API (SDK 27.1, unchanged from 27.0): `alertControllerWithTitle:message:preferredStyle:`
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
  below; labels as tall as a UILabel (20.33 / 18 at 3x, the line height
  rounded up to the pixel; `MorphLabelHeight`), so a title and a message
  make a 72 pt header [device view dumps x4disalert: title label 313 in
  a platter at 291, message 340.67, header scroll view to 363; row alert
  title 218 in 196, text field 280]; a lone title or message (3.67 below)
  has no capture; buttons 48 capsules (tertiarySystemFill) 16 inset, 8 apart;
  exactly two actions in a row with cancel FIRST, otherwise a column with
  cancel LAST; preferred = accent fill + white semibold; actions 17 medium;
  text field 290 x 48 capsule, 16.33 under the message, the buttons 20
  under it (4 + the 16 inset), so the row alert is 216 [dump-dis-alertrow:
  field cell 280-328, collection view to 332, first button at 348;
  test/alert_layout_replay_test.dart]; several fields sit 8 apart (no
  capture).
- Touch: lifts the WHOLE platter with the glass-button model at the
  alert's size (forSize: lift 4 -> 1.0125; 0.09 - 0.25 pt rms); a dragging
  finger stretches and shifts it by the same flex at that size (threshold
  24000) [device: 0.4 pt lean per 120 pt drag; replay at the touch stamps,
  the flex taking each touch up 26 ms later as the glass button's does,
  0.005 / 0.013 pt rms lean, 0.10 / 0.18 pt size, no fitted constant]; pressed button fill
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
- Content 240 wide, arrow 26 x 13 (UIKit's `arrowBase` / `arrowHeight`),
  radius 34; cancel omitted and run at once by a tap outside; the popover
  does NOT lift under a touch [device].
- One shape [read from UIKit, notes private; path dumps on the iOS 27
  simulator, 2026-10-20]: `_UIPopoverShapePathProviderIOS` draws content
  and arrow as one path, and `_UIPopoverGlassBackground` shades it as one
  glass, a SwiftUI glass of ONE SDF element built from that path. The arrow
  is the content's own glass: same tint, the rim runs around it, nothing
  runs across its base; the chrome's own shadow is off.
- Arrow: each side leaves the edge 18.5 from the arrow's center (base 26
  plus a 5.5 fillet) through a cubic whose controls sit on the edge 13
  from the center and which ends at (7.5, 6); straight to (2, 12); the tip
  one cubic with both controls at (0, 13), reaching 12.75. The same arrow
  on every edge (mirrored up, turned left and right; the frame grows 13
  on that side).
- Corners: continuous (Apple's three-cubic corner, 1.5287 r along each
  edge) of 34, less when the box with the arrow is too small (radius at
  most its shorter side / 2 / 1.5287: a one-action popover 240 x 80 has
  30.42). A corner next to the arrow ends at least 16 (half the base + 3)
  from the arrow's center: center 60 from the side, the corner reaches 44
  along the edge; 50, 34. UIKit pins an arrow whose center comes within 49
  of a side (offset past 71 on a 240 popover) into the corner, a shape
  morph's placement (48 clearance) never asks for.
- `morphPlacePopover`: candidates above, below, trailing, leading; centered
  on the source across, slid into 10 pt margins and the safe area, toward
  the source by at most the arrow length (overlaps a source by 3 pt rather
  than switching sides); skip a candidate whose arrow comes within 48 pt
  (radius + half arrow) of a corner; least total slide wins (15/15).
- Without a source an iPhone action sheet IS an alert (cancel last).
- morph (popover_shape.dart, `MorphPopoverShape`): the same path on both
  tiers. Liquid shades it as one fused body from its distance field
  (`MorphGlassOutline` with a field, `MorphGlassMode.body`), as UIKit
  shades its SDF; flat fills it (with the flat shadow without a painter).
  One layout places the popover (`_RenderPopover`) and builds the platter
  from that placement's shape, so card, platter and arrow scale about the
  tip as one. The popover takes taps across content and arrow strip (the
  frame of UIKit's popover view; not measured): a tap on the arrow runs
  nothing.
- Why one outline with a field: it is UIKit's own structure and the
  package's general fused-body path. Rejected: an analytic arrow in the
  final shader (a special case in shared shaders); the arrow as a box
  fused by the container merge law (boxes make no 26 x 13 point); the
  arrow as a glass shape of its own (two bevels meet: the seam is the
  defect).
- NEAR, declared in `MorphPopoverShape`: the field is sampled every 2 pt,
  so the liquid tip rounds 0.2 pt short of the path (0.6 px at 3x;
  0.07 pt at 1 pt for four times the nodes); deeper than 32 pt above the
  arrow the field takes the nearest straight edge or fillet start (at
  most 1.2 pt off, where the glass reads only its sign); the curves are
  flattened within 0.03 pt. Corner normals turn by the renderer's optical
  corner as every fused body's do.
- Cost: present and dismiss frames shade a field body (a matte per
  frame) where the content alone was analytic; rest is a matte either way.
  The field is sampled once per placement (0.4 ms warm on the Mac) and the
  last two shapes keep theirs. Device frame time and energy: not measured
  yet.
- Host proof: example/test/popover_arrow_host_test.dart (four directions,
  a slid arrow, light and dark, liquid and flat, mid present, rest, mid
  dismiss): luma steps 0 - 0.7 across the arrow's edge, arrow vs content
  0 - 0.7 per channel; the arrow drawn apart stepped 20 - 88 and differed
  7 - 10. test/popover_shape_test.dart checks the path against the dumped
  points.

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

Device `ios27-device/alert/` (alert- and actionsheet-present-dismiss,
press, tap, slide, lean, ash-press, ash-tap-out; manifest.json).
Simulator `ios27/alert/` incl. placements.json (15 cases).
Film crops `references/alert-video/`.

## Recapture

Scene `x3alert` (Extras): `PROBE_ALERT=alert|sheet`, `PROBE_ACTIONS`,
`PROBE_ORDER`, `PROBE_PREFERRED`, `PROBE_TF`, `PROBE_NOTITLE`,
`PROBE_NOMSG`, `PROBE_BTN_X/Y` (source), `PROBE_DARK`, `PROBE_SCRIPT`
(show, dismiss, settings). ExtrasUITests testX3Alert, testX3Device,
testX3AlertVideo. Older scene `w2alert`.

## morph

Public (lib/morph.dart): alert.dart (`showMorphAlert`,
`showMorphActionSheet(anchor:/anchorRect:)`, `MorphAlertAction`,
`MorphAlertActionStyle`, `MorphAlertTextField`, `MorphAlertAppearance`).
Internal: alert.dart (`MorphAlertRoute`), alert_motion.dart
(`MorphAlertMotion`, `MorphAlertTuning`, `MorphPopoverMotion`,
`MorphPopoverTuning`, `MorphPopoverPlacement`,
`MorphPopoverArrowDirection`, `morphPlacePopover`).

Dismissal (lifecycle.md): the build that stops the card taking touches
hands back the card built before, so the card does not rebuild; host
recorder, dismiss frame 0: 115 -> 76 builds (100 -> 74 for an action
sheet), the rest the navigator's own pop. The 18-25 paints a frame of the
show and dismiss motions stay (the dimming and the card's fade repaint
the route; gap 12 in lifecycle.md): the card's glass and text must
repaint while the scale moves (the glyph policy reads the scale at
paint), and the text below the policy is a repaint boundary, so a frame
that only fades it keeps its pictures.

Rest (2026-10-14): the alert settles once the fade and the dimming swing
less than `MorphRest.opacity` and the scale less than
`MorphRest.scale(320)` (0.1 pt across the card), and lands on its
targets - NEAR, invisible. Show 0.51 -> 0.42 s, dismiss 0.43 -> 0.40 s.
Before, the scale stopped 1e-4 short of 1, so the resting card kept the
text the policy draws from its raster while the scale moves; it now rests
at exactly 1 and draws the text live (the "at rest exact" below now
holds). The alert cells of example/test/fixtures/control_goldens.json
were recorded again for this (frames 8-26 of 39). Popovers keep their
0.001 rest: a visible rest there (0.1 pt over the 240 pt sweep from
0.01) is stricter and would run longer.

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

- The action sheet popover's content rests 0.37 pt short of UIKit's
  208.33 (test/alert_layout_replay_test.dart, 5 captures, within 0.5):
  its header is 72 as the alert's (device tree w2alert), so UIKit adds
  0.33 below it that the alert (264 with three actions) does not have;
  the popover's 0.001 rest scale takes the other 0.04. Source unread.

- The source button's tint dimming while the popover is up.
- 0.7 s first popover present latency on the simulator.

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

- Reduce Motion and haptics, read from UIKit (notes private): the alert presents from scale 1 (fade only), a popover keeps its size; a finger sliding onto another action plays a selection haptic; Increase Contrast table. See states.md.
