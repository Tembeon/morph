# Tab bar minimize and bottom accessory passport

Status: read from UIKit (iOS 27.0.1, iPhone 16 Pro cache; notes private);
ported; NOT yet recorded on the device. See also [tab-bar.md](tab-bar.md),
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
- Not read: the reverse scroll in the middle of the content. The SDK
  header says the bar "expands when scrolling back up", but the negative
  accumulation never activates the interaction in the code read. morph:
  a drag of 64 pt in the expanding direction expands (APPROXIMATION).

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
  does not lift the circle (not measured).

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
- The minimized circle and the inline accessory of `MorphTabBar` are glass
  of one container (fusion spacing 4 pt, APPROXIMATION): they fuse only
  while the morph carries them closer than that. `MorphSearchTabBar` keeps
  them apart (its circles are separate glass, as for the search morph).

## Fixtures

None yet. Recapture: probe scene `w2search` with `PROBE_MINIMIZE=1`
(onScrollDown) on the device: film and layer rows of a drag that
minimizes, a drag back, a fling, a scroll to the top, a tap on the
circle, with and without an accessory.

## morph

`MorphTabBarMinimizeBehavior`, `MorphTabBar.minimizeBehavior` /
`bottomAccessory` / `contentScroll`, the same on `MorphSearchTabBar`;
`MorphContentScroll` (a `ScrollNotification` handler) and
`MorphContentScrollScope`; `MorphTabAccessoryEnvironment.of`. Motion:
`MorphScrollAway` (the interaction), `MorphTabBarMinimizeMotion` (hint +
morph), `MorphTabBarMinimizeTuning` (tab_bar_minimize.dart). Host:
`MorphTabBarChrome` (tab_bar_chrome.dart) wraps the bar's cached build; the
collapsing tabs are the search tab bar's (`MorphCollapsingTabs`,
tab_collapse.dart). Test: tab_bar_minimize_test; lifecycle scene
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
- `automatic` resolves to never (an iPhone tab bar that does not opt in);
  not read from UIKit.
- Reverse-scroll expansion rule (above).
- The accessory while searching (morph fades it), Reduce Motion.
- `setBottomAccessory(_:animated:)`'s insertion animation (morph: the
  accessory appears in one frame).
- `isTabBarHidden` animated and `prominentTabIdentifier`: not ported.
