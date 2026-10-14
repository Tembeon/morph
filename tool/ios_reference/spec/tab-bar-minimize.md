# Tab bar minimize and bottom accessory passport

Status: read from UIKit (iOS 27.0.1, iPhone 16 Pro cache; notes private);
ported; simulator film of the reverse scroll and the search tab circle
(2026-10-14); NOT yet recorded on the device. See also [tab-bar.md](tab-bar.md),
[search-tab-bar.md](search-tab-bar.md), API rows in
[api/tab-bar.md](api/tab-bar.md).

## Native

`UITabBarController.tabBarMinimizeBehavior` (automatic / never /
onScrollDown / onScrollUp), `bottomAccessory` (`UITabAccessory(contentView:)`,
`setBottomAccessory(_:animated:)`), the `tabAccessoryEnvironment` trait
(unspecified / none / regular / inline). The floating bar's visual provider
observes the tab's content scroll view through a scroll-away interaction
and drives the bar's morph target (expanded / minimized); the hint scale
goes on the bar's glass group container. Springs and thresholds come from
the tab bar's animation settings.

## Spec - trigger (read from UIKit)

- Only a user's scroll counts: the content dragging or decelerating. A
  programmatic scroll only records the offset.
- Direction: onScrollUp minimizes toward the content's start; every other
  behavior's interaction minimizes toward its end (automatic is resolved by
  the bar; morph resolves it to never, see below).
- Each drag starts a fresh accumulation. Past an end of the content only
  motion further past it counts (a rubber band's return does not).
- Activation threshold 0 pt; active distance 64 pt. The content's
  scrollable range must be at least 1.5 x (threshold + active distance) =
  96 pt, else nothing happens.
- progress += scroll / 64, clamped to [0.01, 1] while it runs. At 1 the
  bar minimizes and the interaction rests until the next drag.
- End of a drag without deceleration, end of a deceleration: progress =
  floor(progress) (a scroll that stopped short returns to 0).
- Expand rules read: pushing further past the far end (the end the bar
  minimizes toward) while minimized; reaching the near end while the
  interaction runs, moving back; a scroll to the top (status bar).
- The reverse scroll in the middle of the content does NOT expand: the
  negative accumulation never activates the interaction in the code
  read, and on the iOS 27 simulator (scene `w2search`,
  `PROBE_MINIMIZE=1`, 2026-10-14 sweep) a 150 pt drag back up in the
  middle of the list, released and settled, left the bar minimized,
  although the SDK header says the bar "expands when scrolling back up".
  morph follows (until 2026-10-14 a 64 pt drag back expanded it, an
  approximation now dropped). A device capture at several distances and
  a long reverse fling is still due.

## Spec - motion (read from UIKit)

- Hint: while 0 < progress < 1 the glass group scales by
  1 - 0.05 x progress about its center, on the tracking spring (finger
  down: damping 0.8, response 0.1) or the progress spring (decelerating:
  0.8 / 0.5); at 0 or 1 it returns to 1 on the reset spring (0.8 / 0.3).
- Collapse: intermediate spring 0.72 / 0.36, final spring 0.76 / 0.42
  after 0.05 s. Expand: intermediate 0.72 / 0.30, final 0.72 / 0.36 after
  0.05 s. Which stage moves which part is not read: morph runs the glass
  on the intermediate spring and the content (labels fading, the selected
  glyph travelling to the circle's center) on the final one
  (APPROXIMATION).
- A tap on the minimized circle expands it (no selection); morph's tap
  does not lift the circle (not measured). Not what the code read says:
  UIKit's `expandsOnTap` is NO and a quick release only selects the
  circle's tab (nothing when it is the selected one). morph keeps the tap
  until a recording shows what iOS does.

## Spec - hold and scrub (read from UIKit)

- The minimized bar takes a finger through the tab bar's own selection
  gesture (it begins on contact) and an interactive expansion beside it.
- Held `minimumPressDuration` = 0.22 s without lifting, the interactive
  expansion expands the bar under the finger.
- A move of `expansionHysteresis` = 4 pt along the bar from where the
  finger went down expands it at once; the selection gesture applies the
  same 4 pt and moves the bar's morph target to expanded. From then the
  touch is the bar's selection drag (lens lifted on the first move, the
  tab under the finger highlighted) and its release selects that tab;
  the bar stays expanded.
- Lifted without having moved: the interactive expansion ends
  (`minimumActiveDuration` 0) and the bar collapses back; the release
  selects the circle's tab (nothing when it is the selected one).
- Springs: the interactive expansion runs on `expansionSpring` (damping
  0.5, response 0.4) and returns on `collapsedSpring` (0.75 / 0.4);
  Reduce Motion 0.9 / 0.3. Which views they move is not read: morph
  expands and collapses on the expand / collapse springs above
  (APPROXIMATION).
- morph: `MorphTabBarMinimizeMotion.pressDown / pressMove / pressUp /
  pressCancel` (hold on the motion's timeline, the clock dozes until it);
  `MorphTabBarChrome` follows the finger and, on the 4 pt move, hands it
  to the expanded bar's press (`MorphTabBar`'s lens drag, the same
  machinery, events mapped into the bar's box). The bar is hidden until
  the morph rests expanded, so the lens shows from then on (about 0.4 s);
  the tab bar selects on contact as the expanded bar does. The search tab
  bar's minimized circle is not ported (tap only).

## Spec - search tab [simulator, 2026-10-14]

Scene `w2search`, `PROBE_MINIMIZE=1` (Home, Library, a UISearchTab
without automatic activation, selected), sweep stills s1-s4
(`runs/native-sweep-20261014/runs/native-minimize/`, private):

- Minimized while the search tab is selected, the search tab is a circle
  of its own at the trailing side (the leading circle mirrored, 28 from
  the side and bottom), its magnifier tinted; the leading circle shows
  the last other tab (Home), untinted.
- A tap on the leading circle expanded the bar with Home selected (the
  page switched).
- morph: `MorphTabRole.search` on a `MorphTabItem`; the chrome's search
  circle grows from a bar-tall circle around the search tab's slot to
  `MorphTabBarGroupGeometry.searchCollapsed` on the collapse spring
  while its glyph fades in with the content (path APPROXIMATION, not
  filmed frame by frame); the inline accessory sits between the two
  circles. A tap on the search circle while another tab is selected
  selects the search tab and stays minimized (not measured); a tab
  circle tap selects the last other tab only while the search tab is
  selected (UIKit's selection gesture selects the circle's "weak" tab,
  read from UIKit, notes private).

## Spec - geometry

- Bar 62 pt, 21 pt from the sides and bottom (measured, tab-bar.md).
- Minimized bar: a 48 pt circle 7 pt inside the bar's leading and bottom
  edges, so 28 pt from the screen (UIKit's default layout record; the
  same circle the measured search tab collapses to). The search circle
  of a minimized search tab bar shrinks to the same 48 pt, mirrored.
- Accessory: 48 pt tall (APPROXIMATION), 8 pt above the bar (UIKit's
  layout record carries an 8 pt spacing; which space it is was not read),
  across the bar group (21 pt from the sides). Inline: between the
  minimized circle and the group's trailing side (or the search circle),
  8 pt apart, at the circle's height.
- The accessory is glass of its own on both bars, under the bar group
  (as iOS shows it: the accessory keeps its own capsule next to the
  circle). As one glass body they would fuse into one blob through most
  of the morph: their straight paths overlap from about 14 to 98 percent
  of it. They pass each other mid-morph, the bar's glass over the
  accessory's (paths APPROXIMATION, not recorded). While they stand apart
  `MorphTabBar` keeps both capsules as separate surfaces of one glass
  layer (one backdrop read); while they overlap the accessory draws its
  own glass and content under the bar's glass (the host builds again at
  each switch, twice a morph). Perf scene `tab-bar-minimize`: captures a
  frame 2.1 -> 2.4 (fake / liquid), builds 0.7 -> 0.9, paints 26.1 ->
  26.4.

## Fixtures

None yet. Recapture: probe scene `w2search` with `PROBE_MINIMIZE=1`
(onScrollDown) on the device: film and layer rows of a drag that
minimizes, a drag back, a fling, a scroll to the top, a tap on the
circle, with and without an accessory. Also: a quick tap on the circle
(does it expand?), a hold of 0.3 s lifted in place (collapses back?), a
hold that scrubs to another tab and lifts, a drag straight from the
circle, and the accessory's path past the shrinking bar (film).

## morph

`MorphTabBarMinimizeBehavior`, `MorphTabBar.minimizeBehavior` /
`bottomAccessory` / `contentScroll`, the same on `MorphSearchTabBar`;
`MorphContentScroll` (a `ScrollNotification` handler) and
`MorphContentScrollScope`; `MorphTabAccessoryEnvironment.of`. Motion:
`MorphScrollAway` (the interaction), `MorphTabBarMinimizeMotion` (hint +
morph), `MorphTabBarMinimizeTuning` (tab_bar_minimize.dart). Host:
`MorphTabBarChrome` (tab_bar_chrome.dart) wraps the bar's cached build; the
collapsing tabs are the search tab bar's (`MorphCollapsingTabs`,
tab_collapse.dart). Tests: tab_bar_minimize_test,
tab_bar_accessory_glass_test (every frame, every tier: the accessory's
glass is its own body, drawn under its content); lifecycle scene
`tabbar-minimize`; perf / glass frame scene `tab-bar-minimize`.

Lifecycle (host recorder, 2026-10-14): a drag that only hints builds and
lays out nothing (the hint is a transform). The collapse is laid out once,
as UIKit lays out its views once and animates them: the collapsing tabs
are laid out over both ends (the expanded bar and the circle) and follow
the morph by a live clip (which also bounds their touches), a live
translation of the selected glyph and the glass; the accessory's content
is laid out once at its end box and carried by a translation and a live
capsule clip; each part is a repaint boundary. Per frame of our bar group,
flat (liquid):

| step | before | after |
|---|---|---|
| minimize, morph frames | 14 layouts, ~27-31 paints (16 / 31-36) | 3 layouts, 12-21 paints (5 / 13-23) |
| expand | 11-20 layouts, 25-36 paints (16-26 / 29-43) | 0-7 layouts, 8-15 paints (5-9 / 10-17) |

The 3 layouts left are the glass host placing its surfaces (renderer);
the 4 more in the first half of the morph are the selected label
shrinking (`fontSize` x fade, laid out per frame as in the search morph).
Perf counts scene `tab-bar-minimize`: paints a frame 30.8 -> 23.3 flat,
36.8 -> 26.1 fake / liquid; pictures 3.3 -> 1.9 / 4.4 -> 3.0. Native:
minimize on scroll is 300 ms of 3 - 9 layouts a frame (lifecycle.md).

NEAR (declared): the accessory's content takes its end layout when the
morph starts (where its environment changes) and travels with the
capsule's center, clipped by it, instead of resizing with it; the
minimized circle has no keyboard focus ring and its semantics box spans
both ends. The search tab bar's accessory content follows the same way;
its collapsing tabs still follow by layout (shared with the search morph).

## Not reproduced / open

- Every motion fit above waits for a recording (springs are read, their
  assignment and the geometry partly are not).
- The quick tap on the minimized circle (expands in morph, not in the
  code read), the views the interactive expansion springs move, the
  search tab bar's hold.
- `automatic` resolves to never (an iPhone tab bar that does not opt in);
  not read from UIKit.
- Reverse-scroll: device distances (above); the search circle's tap and
  path (above).
- The accessory while searching (morph fades it), Reduce Motion.
- `setBottomAccessory(_:animated:)`'s insertion animation (morph: the
  accessory appears in one frame).
- `isTabBarHidden` animated and `prominentTabIdentifier`: not ported.
