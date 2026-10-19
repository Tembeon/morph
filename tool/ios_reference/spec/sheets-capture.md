# Sheet shape - capture protocol (iPhone 16 Pro and simulators)

For the coordinator's device run. [sheets.md](sheets.md) holds what is
measured; this plan measures what the sheet's one-outline work still
assumes: the corner radius during drags, the floating / docked switch and
its one odd frame, the zoom container's fill, other screen sizes, Reduce
Motion, a keyboard during a drag, a nested sheet and rotation. Follows
[README.md](README.md) (device lock, recording pipeline, clocks, fixture
conventions). Agents never touch the phone outside a lock session and
never change phone settings.

## Owner-only steps

- Light mode, Reduce Motion OFF, Reduce Transparency OFF, Developer >
  Enable UI Automation ON, phone unlocked on the cable, Auto-Lock long
  enough (about 25 minutes for passes A - F).
- Pass E only: Reduce Motion ON, then back OFF.
- Dark mode once for the reference shots of pass J.

## What the probe already records

Scene `w2sheet` (Sources/Widgets2.swift) writes a `V` row per tracked view
per frame with the presentation frame and, for a layer with
`cornerRadii`, the eight radii (`radii`: bl, br, tr, tl as x, y pairs;
the 2026-10-03 drag fixtures predate it and carry none). Keep
`PROBE_W2TRACK` including `DropShadow` so the clipping layer's radii come
with every row.

## Passes

A. Drag corners (device, about 6 min). Re-run `Widgets2UITests
   testW2Sheet` and `testW2SheetFlicks` unchanged, saving to
   `test/fixtures/ios27-device/sheet-drag-radii/`. Gives the bottom radius
   per frame of every drag, flick and settle: the drag law (passport:
   62 - q (1 - p), q the inset rounded up to a third of a point), the
   radius when a drag starts from the docked rest (0 at rest; a jump to
   about 62?), a settle's law from where the drag left it, and whether
   the stretch touches the radii.

B. Dock and undock, filmed (device, about 3 min). `PROBE_DETENTS=ml`,
   `PROBE_SCRIPT=present@1;large@2.5;medium@4;large@5.5;medium@7`, with
   MorphRecorder filming at the display rate and the page's stripes
   behind the sheet. Answers: (1) whether the frame that reads the sheet
   at y 0 at the end of every docking reaches the screen (a frame with
   the docked sheet's top at 0, over the status bar); (2) the drawn
   bottom corners through the undock (radius 54 (1 - p), from 0), for
   the comparison under a 62 pt continuous display mask applied in the
   analysis.

C. Interrupted changes (device, about 2 min). `PROBE_SCRIPT=present@1;
   large@2.5;medium@2.62;large@4;medium@4.72` (an undock that catches a
   docking at about a third, and one at the end). Gives the corner law of
   a reversal: from the presentation value, linear in the docking
   progress (assumed), or restarted.

D. Screen sizes (simulators: iPhone 17e, iPhone SE (3rd generation),
   iPhone 17 Pro Max; about 10 min). `Widgets2UITests testW2SheetPlan`
   with `PROBE_DETENTS` ml, m and l, plus `testW2Sheet`'s
   `sheet-drag-up-slow`. Per size: the maximum detent value, medium,
   floating inset, the radii floating and docked, the environment
   display radius (`settings` dump), the drag's docking end (shortfall),
   the stretch room. The SE has square display corners: what bottom
   radius a floating sheet takes there (morph assumes the reported 0
   minus the inset, clamped to 0).

E. Reduce Motion (device, owner turns it ON; about 3 min). The pass B
   script, one `sheet-drag-up-mid` and `sheet-zoom`. Whether the present
   still slides, whether docking still scales and turns its corners, and
   what the zoom becomes (a cross-dissolve?).

F. Keyboard during a drag (device, about 2 min). `PROBE_DETENTS=ml`,
   `PROBE_FIELD=1`, `PROBE_SCRIPT=kb@3.0;kbOff@6.0`, and a UITest path
   that grabs the sheet at 2.6 s and holds it 120 pt up until 5.0 s, then
   again from 5.6 s through the keyboard's fall. Gives how a raise or a
   fall during a drag moves the sheet and its corners (morph moves the
   detents and keeps the drag).

G. Nested sheet (device; needs a probe addition: `PROBE_NEST=1` puts a
   "Nested" button in `SheetContentScene` that presents a second
   `SheetContentScene` with `PROBE_NEST_DETENTS`, default `ml`). Script
   `present@1;nest@2.5;large@4;dismiss@5.5;dismiss@7`. Gives the parent's
   frame, radii and dimming while a child sheet presents over it, at
   medium and at large (UIKit stacks the parent?).

H. Rotation (device, about 2 min). Present at medium, then
   `XCUIDevice.shared.orientation = .landscapeLeft` at 2.5 s and back to
   portrait at 5 s, then large and rotate again. Gives the sheet's frame
   and radii in landscape (compact height, `prefersEdgeAttachedInCompactHeight`
   false) and through the rotation.

I. Zoom container (device film, about 2 min). `PROBE_ZOOM=1` with a
   bright content colour (`PROBE_STYLE=full`) and a dark page: open and
   close twice, and one scrub. Whether the zoom container is filled to its
   edges by the sheet (its glass or background) or the content is scaled
   to fit with an empty strip, and whether the container's corners and
   the sheet's own corners ever show as two outlines.

J. Reference shots (device, light and dark): the floating sheet at
   medium; a drag held at about 600 pt of value (docking 0.5, just before
   the background flips); the docked sheet. For the side-by-side check of
   the glass rim running round the 54 pt bottom corners against morph's
   host render (example/test/sheet_shape_host_test.dart).

## After the run

Fixtures go under `test/fixtures/ios27-device/` with a `manifest.json`
per family (rows, units, what each file is), films and shots under
`tool/ios_reference/recordings/` (gitignored) with the frames the
analysis cites copied into `tool/ios_reference/references/`. The passport
takes each answer with its source tag; a changed number updates the
tuning dartdoc in the same change.
