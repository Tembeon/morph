# Lifecycle passports - main-thread work per frame, native vs morph

Status: native from lab captures (iPhone 16 Pro, iOS 27.0.1, programmatic windows,
120 Hz rows; notes private); morph from the host recorder
`test/lifecycle_counts_test.dart` (flat and liquid tiers, 16 ms frames). The tables below
are the 2026-10-13 recording; the gaps closed since are in "Closed" with their new
numbers, which the recorder pins as ceilings (`_ceilings`: last active frame, median
builds and paints after the first frame).

## What is counted

Native, per display-link frame on the main thread: layer layouts, view and layer
creations, removals and deallocations, layer redraws (`display`) and render-server
animations added. Motion that the render server runs costs the main thread nothing.

morph, per frame (`builds/layouts/paints`, `+Nm` mounted, `-Nu` unmounted, `:gN` glass
render objects painted):

- builds: element builds (first build of a mounting element and every rebuild);
- layouts: `performLayout` calls (a layout skipped because nothing changed does not
  count);
- paints: render objects painted; a clean repaint boundary that is only composited again
  does not count.

Rerun: `LIFECYCLE_LOG=true flutter test test/lifecycle_counts_test.dart` (or
`LIFECYCLE_OUT=<file>`). Every scene drives the native window's programmatic trigger: the
parent sets the selection or value, a route is shown and dismissed through its API, a
scroll controller animates for 300 ms.

Caveats:

- Native rows are 120 Hz, morph rows 60 Hz (the Pixel 6a). Per-frame counts of continuous
  work are per frame of each device; durations are compared in ms.
- The native hook sees only animations added through the Objective-C entry point; lens,
  glass-shape and SwiftUI-hosted motion (segmented and tab bar lens, search field morphs,
  stepper) is driven through paths it does not see. Zero native animations never means no
  motion.
- Host tests have no Impeller: the liquid tier builds and lays out its real tree but paints
  the fallback, so `g` counts glass render objects painted, not shader passes.
- The scenes sit on a page of 13 striped boxes. When a control repaints without a repaint
  boundary of its own, the stripes repaint with it (`_RenderColoredBox 13` per frame in the
  class lists); that is the page cost an app pays too.

## Ranked gaps (expected Pixel 6a UI-time win)

Work after the setup frame = builds + layouts + paints summed over the motion, flat tier.

| # | family, trigger | native | morph (flat; liquid where different) | work after setup |
|---|---|---|---|---|
| 1 | tab bar, selection set by the parent | 1 frame: 16-17 layer layouts, 3-4 label redraws, content swap; 8-11 ms active | 41/3/116, then 0/2/99 every frame for 1.55-1.86 s (liquid 0/2/102) | ~9,700 |
| 2 | navigation push / pop | 1 heavy frame (88-115 layouts, 51-65 creations), then ~0 for ~0.5 s with 4-5 blips of 7-14 layouts | push 250/135/143+315m, then 6/5/75-97 every frame to 0.6 s and 0/3/58 to 1.26 s; pop the same | ~5,800 each |
| 3 | search tab: activate, resign, cancel | activate: 2 frames (11 and 145 layouts, 230 creations), then 0 | activate 79/75/65, then 21-26 layouts + 46-47 paints every frame for 0.96 s with 36-59-build bursts every ~5 frames (liquid 31-36 / 59-61, g4); resign 46-67 / 59-89 per frame for 0.54 s; cancel 21-25 / 41-45 for 0.45 s | ~7,200 + 4,900 + 1,900 |
| 4 | animated scroll under a bar (edge effect) | ~300 ms of 4-20 layouts per frame (scroll view, cells), then 0 | parity during the 300 ms (4-19 layouts, 22-62 paints), then a tail of 0/0/30 every frame for 0.5 s (scroll 300) to 1 s (scroll to top) after the scroll stopped | ~900-2,400 per scroll (tail only) |
| 5 | segmented, selection set by the parent | 1 frame: 7-11 layouts, 2 label redraws, 8-14 ms | 13/15/47, then 0/2/29 every frame for 1.63 s (liquid 0/2/10) | ~3,100 |
| 6 | context menu: hold, release, close | no programmatic window | hold: 20 paints per frame from the hold timer, lift frame 93/49/71+98m; release: 0/19/54 every frame for 1.4 s; close 69/18/62, then 19 layouts + 54-61 paints per frame for 0.65 s | ~6,600 |
| 7 | search toolbar: focus | 648 layouts in frame 1 (mostly the keyboard), then 25-27 layouts every frame for ~0.3 s (SwiftUI) | 28/1/53, 18 idle frames, then 32-55 layouts + 66-74 paints every frame for ~0.4 s, 22-23-build bursts | ~3,100 (native itself ~1,000) |
| 8 | sheet detent change | 1 heavy frame (135-232 layouts, 158-186 creations), 60-90 layouts in frame 2, 0 for the motion, 1 cleanup frame | 118/2/5 (the whole sheet content rebuilds), then 19-20 layouts + 27-33 paints every frame for 0.69 s (liquid 24-25 / 47-55, g2) | ~2,100 |
| 9 | menu (button menu) open / close | open: 1 frame of 150 layouts + 269 creations, 33 layouts in frame 2, then 0 with 1-3-layout blips, cleanup at ~0.95 s | open 60/33/22+74m, 5 idle frames, a second heavy frame 124/46/117+88m, then 10-11 layouts + 22-27 paints every frame to 0.93 s (liquid 15-16 / 31-37, g3); close: 10-11 layouts per frame, then 6/9 per frame for 0.55 s after the cleanup frame | ~2,000 + 1,400 |
| 10 | switch, value set by the parent | 0 layouts; 3 render-server animations added in one frame | 7/0/0, then 0/2/9 every frame for 1.23 s | ~840 |
| 11 | date picker: open / close, month or time set | month set while closed: 1 frame of 20 layouts; wheels set: 300 ms of 12-24 layouts per frame (main-thread scrolling) | open 125/93/44+157m and 44/113/0+144m, 7 idle frames, 194 paints, then 5 layouts + 14 paints per frame to 0.66 s; month set while open: 69/121/145 remounting 140 elements; wheel set: one jump frame remounting 90 elements | ~1,100 + 800 |
| 12 | alert / action sheet show, dismiss | show: 1 heavy frame (101 layouts, 157 creations), then 0; dismiss: 6 layouts, 0, cleanup frame | show 130/73/48+157m, 12/1/63, then 0/0/18 every frame to 0.51 s (liquid 23, g2); dismiss rebuilds 115 elements in frame 0, then 18 paints per frame | ~600 + 500 |
| 13 | glass button held (highlight) | 1 frame of 5 layouts | 12-16 paints every frame for as long as the finger stays down (still ticking after 2.6 s; liquid 17-21, g2), then 52 frames after the lift | unbounded |
| 14 | activity indicator spinning | 0 main-thread work (keyframe animation in the render server) | 2 paints every third frame (the 16-step quantized turn), a frame scheduled every 16 ms | 40 paints/s + 60 frames/s |
| 15 | flat tier, moving glass (merge scene) | 0 (render server) | the app's own animation costs 2 builds + 1 layout per frame; flat glass adds 18 paints per frame of which 13 are the page around it (liquid: 4 paints, g1) | ~650 page paints per 0.8 s move |

Parity or better (no work to do for frame time): stepper (1 frame, 12/0/13 vs 3 layouts),
page control (2 frames, 5 paints vs 33-37 frames of 1 native layout), slider set by the
parent (1-2 frames vs 0.55 s of 2 native layouts per frame), progress view (2 paints per
frame for 0.5-0.7 s vs 1 native frame), glass button enable / tint / title change (1 frame),
sheet present / dismiss (1 heavy frame, then 1 paint per frame), scroll jumps (1-2 frames).
The slider, page control and date picker wheels jump where the native control animates a
programmatic change: a fidelity gap, not a frame-time one.

## Closed (2026-10-14)

morph tokens `builds/layouts/paints` per frame after the first, flat (liquid where
different); times are the last frame with any work.

| # | family, trigger | before | after | how |
|---|---|---|---|---|
| 1 | tab bar, selection set by the parent | 0/2/99 (liquid 0/2/102) to 1.55-1.86 s | 0/2/17 (liquid 0/2/18) to 1.33-1.46 s | label rows are repaint boundaries while the bar does not swell and no lens copies them; settle at visible rest |
| 2 | navigation push / pop | 6/5/75-97, tail 0/3/58 to 1.26 s | 2/5/38-47, tail 0/3/18 to 0.96 s | the route hands back its built transition; bars, inline titles and bar items are repaint boundaries; bar motion settles at visible rest |
| 5 | segmented, selection set by the parent | 0/2/29 (liquid 0/2/10) to 1.63 s | 0/2/8 (liquid 0/2/9) to 1.30 s | control and flat labels are repaint boundaries; settle at visible rest |
| 10 | switch, value set by the parent | 0/2/9 to 1.23 s | 0/2/9 to 0.83-0.94 s, the page no longer repaints with it | control is a repaint boundary; settle at visible rest |
| 13 | glass button held | 12-21 paints every frame while held (2.6 s+) | 16 paints a frame for the 0.45 s lift, then asleep until the finger moves or lifts | a held press settles |
| 14 | activity indicator | a frame scheduled for nothing between images (31 frames/s) | one frame per image (20 frames/s) | the doze wakes for the image's own frame |
| 4 | scroll edge tail (side effect) | 0/0/30 for 0.5-1 s | 0/0/1 | the edge effect's bar is a repaint boundary (nav stack bars) |

Rest thresholds (cross-cutting): every motion above settles once every spring's
remaining swing is under `MorphRest` (0.1 pt, 0.3 device px at 3x; scales over their
surface's extent; opacities under half an 8-bit step) and snaps onto its targets:
invisible, NEAR (lens-and-flex.md "Rest").

Still open: the 2 builds a frame of the navigation slide are the framework's own
route-scope builders; the bar items whose scale or presence changes repaint every frame
(their content under a live transform); the lens and the switch knob move by layout (2
layouts a frame: a live stack and its fill); gaps 3, 6-9, 11, 12, 15.

## Port suggestions, by gap

1. Tab bar. Every frame of the lens motion repaints all four tabs' glyphs and labels
   (per frame: 16 paragraphs, 10 rows, 8 glyph layers, 25 boxes). Keep the unselected and
   the selected-tint glyph rows in repaint boundaries (or retained pictures) and move only
   the lens and its clip, so a frame repaints the lens alone. Then check the rest
   threshold (below): the motion ticks 1.55-1.86 s.
2. Navigation. Two rebuilds per frame from listenable builders around the bar and one
   from the edge-pop region during the whole push (150 + 74 builds); move those listeners
   into render objects. The pages repaint 58-97 objects per frame while they translate
   (pointer listeners, semantics wrappers, glyph layers): put each page under a repaint
   boundary moved by a transform layer. After the 0.6 s transition a tail of 3 layouts +
   58 paints per frame runs to 1.26 s; find the spring that keeps it alive.
3. Search tab. The activation re-lays out 21-36 objects and repaints 46-61 every frame,
   and rebuilds the glass layers in bursts (62 glass-layer builds in 0.96 s). Build the
   field and the tabs once in the first frame, then push the morph into live render
   objects as transforms and clips; no build or layout in between.
4. Scroll edge effect. The 300 ms scroll itself is at parity; afterwards 30 paints per
   frame continue for 0.5-1 s with no layout, and the visible rows' wrappers are among the
   painted objects: the bar's fade shares a layer with the list. Give the edge effect its
   own repaint boundary (or drive it with an opacity layer) and settle it with the
   scroll.
5. Segmented. Same pattern as the tab bar at a smaller scale (4 labels and their wrappers
   repainted per frame, plus the page in the flat tier). Same remedy.
6. Context menu. 19 layouts per frame for the whole lift and settle: the shuttle and the
   satellites are moved by layout (stack, opacity, transform, constrained overflow boxes).
   Place them with paint-time transforms and offsets so a frame only composites.
7. Search toolbar focus. An 18-frame dead gap before the morph starts, then 32-55 layouts
   per frame. Native also lays out every frame here (~26), so the target is about half the
   current work and no idle gap.
8. Sheet detent. A detent change rebuilds the whole sheet content (118 elements) and
   re-lays it out every frame of the spring. Native lays the content out once at the start
   and animates the frame in the render server: lay out at the target detent once and
   move the sheet by translation and clip during the spring; rebuild nothing.
9. Menu. Build everything the menu needs in the first frame (today a second heavy frame
   follows 5 frames later), then drive the morph by paint-time transforms; the 10-16
   layouts per frame come from transform, opacity and clip boxes laid out per frame.
10. Switch. 2 layouts + 9 paints per frame for 1.23 s for a motion the native control
    gives to the render server. Repaint only the knob layer (a repaint boundary around the
    track) and settle at visible rest.
11. Date picker. Prebuild the calendar and the wheels in the setup frame (today two heavy
    frames, then 7 idle ones, then a 194-paint frame); key the day cells and wheel rows so
    a month or time change updates them instead of remounting 90-140 elements.
12. Alert. 18-23 paints per frame for 0.5 s: put the alert body under a repaint boundary
    below its live transform, so scale and opacity only update layers. Dismiss should not
    rebuild the alert (115 builds in its first frame).
13. Glass button held. A held press keeps a ticker alive (12-21 paints per frame) after
    the lift motion has settled; sleep once the press look is at rest and wake on the next
    pointer event.
14. Activity indicator. The paint is already quantized to the 16 steps of the native turn;
    schedule frames only at the step rate (a timer per 50 ms instead of a ticker), or
    raster-cache the spokes once and rotate them with a transform layer, so 2 of 3 frames
    are not scheduled at all.
15. Flat tier. A moving flat-glass surface dirties the page's layer (13 page paints per
    frame in the merge and segmented scenes; the liquid tier already isolates itself).
    Give the flat surface its own repaint boundary.

Cross-cutting: rest thresholds. Lens and switch springs settle at 0.01 pt with 0.1 pt/s
and scales at 1e-4 with 1e-3/s, so the tickers run 1.2-1.9 s after a selection change
while the visible motion is far shorter. A threshold tied to visibility (a fraction of a
device pixel) ends the tail early; measure how many frames it cuts before adopting it,
and declare it as a near trade if any pixel moves.

## Per family

Native and morph per window; morph tokens are `builds/layouts/paints` per 16 ms frame.

| family | native window | morph |
|---|---|---|
| segmented | selection: 1 frame, 7-11 layouts, 2 label redraws, 0 creations | 13/15/47, then 0/2/29 x 101 (liquid 0/2/10) |
| tab bar | selection: 1 frame, 16-17 layouts, 3-4 redraws, content swap (1 creation, 2 removals); minimize on scroll: 300 ms of 3-9 layouts per frame (no morph counterpart) | 41/3/116, then 0/2/99 x 96-115 |
| switch | animated: 3 animations, 0 layouts; plain: nothing | 7/0/0, then 0/2/9 x 76 |
| slider | animated set: 2 layouts per frame for 0.55 s; plain: 1 frame of 2 | 11/5/31, 0/0/13 (no animation) |
| stepper | value: 1 frame of 3 layouts; enable: nothing | value 12/0/13; enable 13/0/0 |
| glass button | state / title: 1 frame of 5-7 layouts; style change: 2 frames, 14-17 layouts, 14-26 creations, 21 animations | 13/1/15 (title 13/18/31); held: 12-16 paints per frame until lifted |
| merge (container) | animated move: 1 animation, 0 layouts for 1.5 s; jump: nothing | app animation 2/1/18 per frame (liquid 2/1/4 g1); jump 6/1/18 |
| menu | open: 150 layouts + 269 creations in frame 1, then blips, cleanup at 0.95 s; close: 60 layouts + 70 creations, cleanup at 1.19 s | open 60/33/22, second heavy frame 124/46/117, then 0/10-11/22-27 to 0.93 s; close 0/10-11/14-25, cleanup frame 24/9/53 -151u, then 0/6/9 to 0.96 s |
| context menu | (no window) | hold 0/0/20 per frame, lift 93/49/71; release 0/19/54 x 88; close 69/18/62 then 0/19/54-61 |
| sheet | present: 160 layouts + 262 creations in frame 2, then 0; detent: heavy frame, 60-90 layouts in frame 2, 0, cleanup; dismiss: 27 layouts, 0, cleanup removes 124 | present 185/90/98+229m, 13/8/7, then 0/0/1; detent 118/2/5, then 0/19-20/27-33 x 42; dismiss 58/1/5, then 0/0/1 |
| alert | show: 101 layouts + 157 creations, then 0; dismiss: 6 layouts, 0, cleanup removes 67; action sheet the same shape | show 130/73/48, 12/1/63, then 0/0/18 to 0.51 s; dismiss 115/1/25, then 0/0/18, cleanup -157u at 0.43 s |
| search (tab) | activate: 2 frames (11, 145 layouts); keystroke: 1-3 frames of 3-18 layouts; resign: 36 + 12 layouts, cleanup; cancel: 76 layouts, then 0 | activate 79/75/65, then 0/21-26/46-47 with build bursts x 59; keystroke 1 frame 16-18/16-25/57-61; resign 59/2/73, then 1-2/46-67/59-89 x 33; cancel 50/13/32, then 0/21-25/41-45 x 27 |
| search (toolbar) | focus: 648 layouts (keyboard), then 25-27 per frame for 0.3 s; resign and cancel: 14-26 layouts per frame for ~0.3 s | focus 28/1/53, 18 idle, then 1-2/32-55/66-74 x 25; resign: 1 frame 22/1/53 |
| scroll edge | animated scroll: 300 ms of 4-20 layouts per frame, cells created as they appear; jump: 1 frame | animated: 300 ms of 0-24/4-24/22-62, then 0/0/30 for 0.5-1 s; jump: 2 frames (90/69/54+143m, 14/10/32) |
| page control | page: 1 animation + 1 layout per frame for 0.3 s; count: 1 frame | page: 5/0/0, 0/0/5; count: 5/8/21 |
| progress | animated: 1 frame, 4 layouts, 4 animations; plain: 1 frame | animated: 3/0/2, then 0/0/2 to 0.53-0.72 s; plain: 3/0/2 |
| activity indicator | spinning: nothing; start: 4 animations in one frame; stop: nothing | spinning: 0/0/2 every third frame, a frame scheduled every 16 ms; start/stop 3/0/0-2 |
| date picker | month set closed: 1 frame of 13-20 layouts; wheels set: 300 ms of 12-24 layouts per frame, 2-3 label redraws per frame; compact open/close: capture invalid, recapture | set closed 16/16/42; open 125/93/44 + 44/113/0, 7 idle, then 0/5/14 to 0.66 s; month set open 69/121/145 (+140m -143u); wheel set 74/76/110 (+90m -90u); close 142/2/14, then 0/5/14 to 0.56 s |
| navigation | push (same items): 1 heavy frame, then ~0 with 4-5 blips over ~0.5 s; changing items: 21-30 layouts per frame | push 250/135/143, 65/50/80, then 6/5/75-97 to 0.6 s, 0/3/58 to 1.26 s; pop 116/50/76, then 6/3-5/78-92, the same tail |

## Open

- Native date picker compact open and close need a recapture (the window stalled).
- Native context menu has no programmatic window; only the button menu is measured.
- The morph counts are host counts. The device check of a change is still frame time and
  energy on the Pixel 6a (docs/performance.md); these tables say where to look.
