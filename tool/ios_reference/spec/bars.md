# Bars passport (nav bar, toolbar, items, drift, back menu, container, edge effect, large title)

Status: measured device (programmatic night pass + finger recapture) and
simulator; ported; replayed (bar_motion_test, navigation_motion_test,
scroll_edge_effect_test, back_menu_test, bar_fusion_test). Pages and push
zoom: [navigation-pages.md](navigation-pages.md).

## Native

`UINavigationBar`, `UIToolbar`, `UINavigationItem`, `UIBarButtonItem`,
`UIBarButtonItemGroup`; glass capsules = `CASDFElementLayer`s of ONE
`CASDFLayer` (SwiftUI.SDFLayer host); title wrapper
`_UINavigationBarHostedViewWrapper`; edge effect `UIKit.ScrollEdgeEffectView`.
Tuning read live: SwiftUI `GlassContainerToolbarPTSettings`, `PocketSettings`,
`_UIFluidNavigationTransitionsSpec`, `_UINavigationBarTitleTransitionSpec`
(dump `test/fixtures/ios27-device/bars/tuning.txt`).
Public API (SDK 27.0) UINavigationItem: `title`, `subtitle`,
`attributedSubtitle`, `largeTitle`, `largeSubtitle`, `largeSubtitleView`,
`subtitleView`, `titleView`, `largeTitleDisplayMode` (automatic / always /
never / inline), `style` (navigator / browser / editor), `backButtonTitle`,
`backButtonDisplayMode`, `backAction`, `hidesBackButton`,
`leadingItemGroups`, `centerItemGroups`, `trailingItemGroups`,
`pinnedTrailingGroup`, `additionalOverflowItems`, `titleMenuProvider`,
`searchController` / `searchBarPlacement` / `preferredSearchBarPlacement`
(automatic, integrated, stacked, integratedCentered, integratedButton,
inline), `searchBarPlacementAllowsToolbarIntegration`.
UIBarButtonItem: `style` (plain / prominent), `menu`,
`preferredMenuElementOrder`, `hidden`, `sharesBackground`,
`hidesSharedBackground`, `identifier`, badge (`UIBarButtonItemBadge`),
`tintColor`, fixed / flexible space, groups (fixed / movable / optional).
UIScrollView `topEdgeEffect` etc. (`UIScrollEdgeEffect`, styles automatic /
soft / hard, `hidden`); `UIScrollEdgeElementContainerInteraction`.

## Spec - metrics [layout, device 402 pt]

- `MorphBarButtonGroup` = one glass capsule (adjacent items grouped);
  groups 12 apart.
- Navigation: capsule 44, button 36, pad 4, gap 16, label 12, icon 7.
  Toolbar: 48 / 38 / 5 / 14 / 11 / 8 (min 38).
- Toolbar 28 from the sides and screen bottom; nav bar 54 below the status
  bar; 16 side inset on 402 pt (20 on 440). Centered title kept 12 from
  the buttons.
- Press lifts the whole capsule on the glass-button model (1 + 16/w).
- Text: bar buttons 17 medium (prominent semibold), title 17 semibold,
  large title 34 bold.

## Spec - item transitions (`MorphBarMotion` = GlassContainerToolbarPTSettings) [tuning, delays fit]

frame 0.416/0.75 after 0.05 s; pulse up 0.292/0.5 to min(1.2, 1 + 16/len)
after 0.065 s; height back 0.416/0.584 +0.113; width 0.416/0.5 +0.142;
appearance scale 0.2 + blur 10. Births on the facing edge of a neighbour
OF THE SAME SIDE (segment, below); a survivor next to a newborn of its side
waits 0.1 s. Same transition drives nav bar buttons on push/pop (with the
navigation timing below). Replay: capsules 1.0 pt rms center,
1.6 width, 0.8 height. Groups without id are keyed by place from the bar's
EDGE (device morphs the outermost trailing capsule into the outermost one);
the back button morphs out of the leading capsule.

## Spec - per-segment transitions [device, 2026-10-05, scene navseg]

Owner report: morph fused the leading group into the trailing one on a
push / pop (a back button pushed onto a page without leading items was
born on the trailing capsule's facing edge and flew across the bar).
UIKit never does: each side of a bar changes only with itself.

- Leading groups change only into leading groups, trailing into trailing
  (by place from the edge, as before). No capsule, element or glass ever
  crosses the bar; the title is not glass and rides its page (exit shift
  -0.3 W on a push, +1 W on a pop, unchanged).
- A side that had no group (root page -> pushed page's back button; 0 -> 2
  trailing groups; a toolbar side filling) shows its groups IN PLACE: the
  group container (glass + items) stands at its final rect, scaled per axis
  by `pulseScaleFor(len)` = min(1.2, 1 + 16/len) (44 -> 52.8, 73.7 ->
  88.4, 103.7 x 44 -> 119.9 x 52.8), opacity 0, content blur 10, and
  settles to 1 / 1 / 0 on ONE progress p: the transition spring 0.416 /
  0.75 (free fits 0.394 - 0.410 / 0.75 - 0.77 over 16 groups, scale,
  opacity and blur identical). No 0.2 birth, no travel.
- A side left without groups (back button on a pop to the root, trailing
  group 1 -> 0, a toolbar side emptying) swells and fades IN PLACE: the
  same progress back to 0 (scale -> pulseScaleFor, opacity -> 0, blur
  -> 10).
- Such groups live in a SECOND SwiftUI SDF layer during the transition
  (`host` 1 in the fixture; a group leaving while another appears may stay
  in the first); at ~0.83 s UIKit folds every element back into one
  layer. morph: `MorphBarCapsuleFrame.apart`, drawn in a glass container
  of its own over the bar's (never fused with it), joined back when the
  progress rests.
- Delays from the call: navigation push / pop 0.058 s for in-place groups
  (0.050 - 0.063, 8 groups), 0.062 s for the frames of the capsules that
  morph (replay optimum 0.060 - 0.062; the toolbar's 0.05 leaves 0.45 pt
  center / 1.6 pt width rms) = `MorphBarTransitionSpec.navigation`.
  `setToolbarItems` filling / emptying a side: 0.020 - 0.044 s, replay
  optimum 0.026 - 0.030 -> `segmentDelay` 0.030 in `.standard`.
- Interactive pop (edge swipe): nothing in the bar moves while the finger
  drags (the back capsule has no counterpart; it does not drift or fade);
  on a commit the back group leaves in place 0.027 s after the lift's
  time stamp (one capture), on a cancel nothing happens.
- Replays (test/bar_segment_test.dart): nav push / pop capsules 0.21 pt
  rms center, 0.84 width, 0.58 height; in-place group scale 0.004, opacity
  0.021 rms; toolbar sides 0.0 / 0.13 / 0.13 pt, scale 0.020, opacity 0.099
  (one delay cannot follow the device's 24 ms call-to-start spread).
  Device check 2026-10-05: example/integration_test/navseg_video_test.dart
  (the same five pages, liquid tier) filmed next to the native run;
  recordings/device-navseg-20261005/sheet_0..7.png (native over morph,
  bar crops -0.05 .. 0.7 s from each page start): every group appears and
  leaves in place on its own side in both, morph about one film frame
  later; the inline title of a push arrives at once in morph and a few
  frames later natively (title timing, not part of this change).
  Regression: test/navigation_segments_test.dart (no glass layer ever
  fuses a leading capsule with a trailing one, the back button never
  crosses the middle - push, back tap, edge swipe).

## Spec - container spacing [layout, device + sim]

Every capsule of a nav bar (and of a toolbar) is an element of ONE SDF
layer, smoothness 12, constant through setItems, splits and merges.
Resting groups (12 apart) sit at the merge law's reach (never touch); a
split (UIKit keeps the trailing item's element, births the other at its own
center at 0.2 scale - morph keys by place, NOT changed) fuses while closer.
`MorphBarMetrics.containerSpacing` 12.

## Spec - edge-swipe drift [device fit, 4 swipes]

While a page is dragged, each capsule the destination bar also has (same
id) is drawn `barDrift` 0.5 x page progress toward its destination rect,
items riding the capsule center; pure function of the page (cancel leans
back); on commit the item transition starts from the leaning rects (device:
drift freezes at the lift). 0.49 at no lag, 0.50 at 1-2 ticks; 0.16 - 0.27
pt rms. The inner capsule without counterpart stays put.

## Spec - back menu [device holds, probe snback]

Release before 0.4 s = tap (0.25 / 0.35 popped, 0.45 did not); menu opens
0.595 s after the touch (0.584 - 0.609, 7 holds); a release in between
still opens it; a finger lifting ON the button after opening fires the
button and closes the menu (pops one, 4/4); moved off leaves it open. Rows
= back stack nearest first. Look = MorphMenuButton's liquid morph out of
the capsule [film]; after the latch the capsule rings out with both menu
shapes [film]. `MorphBarMenuTuning`.

An item whose menu is its primary action (`UIBarButtonItem(menu:)`, no
action; `MorphBarButton(menu:)` without `onPressed`) opens on a tap's
release and on a 0.22 s hold like the inline menu button, its tap 0.013 s
later [device, 2026-10-05]: see menu-button.md "Bar item menu as primary
action".

## Spec - inline title, large title, edge effect

- Inline title: crit 0.45 in / 0.7 out, +15 pt rise, blur 4; edge effect
  alpha crit 0.35; programmatic offsets switch at once (UIKit animates only
  with a finger). Title opacity replay <= 0.06 rms.
- Large title: device 10 pt slop; 25 pt scrolled snaps back, 30 under
  (threshold half the title, 26).
- Scroll edge effect is NOT a progressive blur: uniform variableBlur 1.5
  (soft) / 2 (hard) with a full mask; a "replay" of the background at 0.5
  (0.6 dark); soft: gradient from 0.34 (0.3407) of the band, band = bar +
  40; hard = thinFilm (saturation 1.25, +0.03 brightness, 1 px hairline 10
  percent). Automatic under a nav bar = hard; nothing under a floating
  toolbar.

## Disabled items [device, light + dark, 2026-10-03, scene x4disbars]

- Plain item (`UIBarButtonItem.isEnabled = NO`, nav bar and toolbar): the
  item tint becomes tertiaryLabel (dark 0x4CEBEBF5, light 0x4C3C3C43); the capsule glass is unchanged. Through the
  bar's color path the RENDERED content differs by kind:
  ICON (plus, share) dark peak 249 -> 83 on the 32 capsule, light 12 -> 167
  on 245; TEXT (Edit) dark 249 -> 47, light 13 -> 221 (text is far dimmer).
- Prominent item (`style .prominent`): the accent body becomes systemGray4
  (dark 59.8 gray, light 209.8/209.8/214.2), the glyph stays WHITE.
- A disabled item shares its capsule group with enabled ones like any item.
- One frame, no animation, both ways.
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method in [states](states.md).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): `MorphBarStyle.disabledIconColor` (0x55000000 /
  0x3CFFFFFF) and `disabledLabelColor` (0x19000000 / 0x12FFFFFF) render
  the measured peaks over the capsule; a prominent capsule whose items
  are all disabled takes `disabledProminentColor`, glyph white.

## Fixtures

Device `ios27-device/bars/`: navseg-push-pop, navseg-toolbar, navseg-edge
(per-segment transitions; rows `B` cls SDFElement with `bar` nav / tool and
`host` 0 / 1 = which SwiftUI SDF layer, cls group = the in-place group
container: sx, sy, a, blur; `evt` push / pop with from / to page,
setToolbarItems with set; touches in navseg-edge), toolbar-swap, push-pop,
scroll-edge.json,
title-drag-{collapse,partial20..45}, title-fling, item-hold,
pop-edge-{commit,cancel,slow25/30/35,flick-v400/v450,flickback,flickback3,
drift-*}, tuning.txt. Simulator `ios27/bars/`.

## Recapture

Scene `navseg` (Bars.swift, `NavSegPages`): five pages (0 Root large title,
no leading, [plus]; 1 Alpha back + [share]; 2 no title, Cancel instead of
back, [heart share]; 3 Gamma back only; 4 Delta large title, back, [Done]
[heart]); `PROBE_SEQ` (default push x4, pop x4; `tbA/tbB/tbC` set the root
toolbar; `none` for touches), `PROBE_GAP`. Launched with devicectl
(`-e '{"PROBE_SCENE":"navseg","PROBE_REC":...}'`, terminate the app before
pulling Documents - an open file pulls empty); touches:
BarsUITests.testNavSeg (tap pushes, edge swipes, back taps - the probe
crashed in CASDFGradientEffect dealloc on the first back tap on page 4,
a QuartzCore over-release under BarsRecorder; the auto run covers pops).
Raw: recordings/device-navseg-20261005 (films navseg-auto.mov,
navseg-touch.mov). Scene `nav` (Bars.swift): `PROBE_EDGE`, `PROBE_AUTO=scroll|toolbar|push|
pushpop|all`, `PROBE_LARGE=0`, `PROBE_ROWS`, `PROBE_DARK`. Device:
`PROBE_PLAN=bars` (BarsUITests.testBars). Scenes `snbars` (SDF sampler,
`PROBE_SPLIT`) and `snback` (`PROBE_STACK`), SheetNavUITests.testSNBack.

## morph

bar_items.dart (`MorphBarButton`, `.back`, `MorphBarButtonGroup`,
`MorphBarMetrics`, `MorphBarStyle`, `MorphBarItems`), bar_motion.dart,
toolbar.dart (`MorphToolbar`), navigation_bar.dart (`MorphNavigationBar`,
`MorphNavigationBarDrift`, `MorphLargeTitle`, `MorphLargeTitleScrollPhysics`,
`MorphNavigationTitleMotion`), navigation_stack.dart,
scroll_edge_effect.dart (`MorphScrollEdgeEffect`, ThemeData).

## Not reproduced / open

- Births and deaths WITHIN a side on a push (device push-pop.jsonl, list ->
  detail: the inner trailing group is born at the surviving trailing
  capsule's OLD center at 0.2 of THAT capsule's size and dies into its new
  center the same way) do not match the toolbar's facing-edge law morph
  uses (that replay leaves ~10 pt center rms); a split law fitted to it
  broke the toolbar replays (3.8 pt). Needs a capture that separates the
  two (navseg covers only sides that fill or empty).
- The edge-swipe commit's bar transition starts 0.027 s after the lift's
  time stamp on the device; morph starts it from the stack's setLayout at
  the commit with the navigation delays (not replayed).
- The stack's toolbar on a push uses the toolbar timing (`.standard`);
  a toolbar changing with a push is not measured.

- Large title's tall-bar inset bookkeeping (ours scrolls as content).
- Toolbar drift during an edge swipe (not measured).
- Split births keyed by place, not by UIKit's element identity.

## API gaps

- Subtitles / large subtitles, title menu (`titleMenuProvider`),
  `titleView`, `UINavigationItemStyle` browser / editor (center groups),
  `pinnedTrailingGroup`, overflow menu (`additionalOverflowItems`).
- `largeTitleDisplayMode` inline / never variants per page.
- Bar button badges; `hidesSharedBackground` (an item outside the capsule);
  `sharesBackground = false`; fixed / flexible spaces as API.
- Search bar integration placements in the nav bar / toolbar (morph has only
  the bottom search toolbar).
- `backButtonDisplayMode` (generic / minimal), `hidesBackButton`.

## Implementation notes (morph side, moved from CLAUDE.md)

- `MorphNavigationStack` keeps ONE bar + toolbar over its Navigator. The
  Navigator widget is built once (rebuilding it calls changedExternalState
  on every route and the pages' config publishing looped); scaffolds
  publish a signature-compared `MorphNavigationConfig`. A pushed screen
  publishes one frame after the push: the stack keeps showing the screen
  below until it does (or its first frame passes) - otherwise the bar
  flashed empty for a frame, its capsules died and were reborn and the
  toolbar remounted (the push did not morph).
- The Navigator sits under a NavigatorPopHandler: while the stack can pop,
  the ENCLOSING route is doNotPop, which turns off its Cupertino edge swipe
  / predictive back (popGestureEnabled) and routes system back and outer
  maybePop into the stack (the gallery's MaterialPageRoute used to win the
  edge swipe - its edge Listener sits above the page in hit-test order).
- The stack learns of an edge swipe from MorphNavigationRoute's edge
  gesture (start / settled), not from userGestureInProgress. Drift API:
  `MorphNavigationBarDrift`, `MorphBarMotion.setDrift`; on commit the next
  setLayout snaps the springs onto the leaning rects and the item
  transition starts from there.
- BACK MENU plumbing: built on the menu machinery through the internal
  MorphMenuHost / MorphMenuLayer / MorphMenuFlightProgress. The bar owns
  the gesture (hold clock in its MorphClock), the menu motion gets the
  capsule as its button (sourceHeight = capsule height), a vessel flight
  from the bar's own invisible MorphTag carries it, and the bar hides that
  capsule while the flight is airborne. RING-OUT [film, back-hold-away in
  the snback film]: UIKit's close lands as a wobbling union of the
  shrinking menu and the capsule, the capsule's top edge 3 pt off rest,
  settled ~0.2 s later; so after the latch the bar draws BOTH shapes of the
  menu motion on the capsule (surfaces of kinds button/menu, the glyph
  riding the button blob's center and scale) until the motion goes idle -
  pinned by back_menu_test (the glyph swings ~2 pt, then rests exactly).
- Container spacing reaches the painter as `buildLayer(spacing:)`; the
  fused outline of capsules within spacing - 0.5 is traced by the package
  (`morphGlassContainerOutline`, skin law, step 2) - see glass-renderer.md.
  The bar's own flat painter (no MorphGlass installed) draws the same
  groups and outline as the glass tiers (`morphGlassContainerGroups` +
  `morphGlassContainerOutline`), no trace of its own. GROUPING RULE (one
  rule for every tier, 2026-10-04): capsules group by geometry alone -
  any two within the container spacing fuse whatever their colors (a
  prominent capsule passing a plain one fuses with it) - and a fused body
  takes the color of its first capsule in drawing order, as the
  renderer's bodies take the tint of their first surface. Capsules under
  half a point either way are not drawn. Not measured: how UIKit tints an
  SDF element union of a prominent and a plain item.
- An id that comes back while its old capsule or item still leaves (a
  push-pop-push inside ~0.4 s, a toolbar flip-flop) REVIVES the leaving
  entry: it turns around from where it is on the same springs, so one id
  is one capsule / one button at all times. Not measured against UIKit.
- MorphNavigationConfig compares by value with callback identity: a
  screen rebuilt with new closures republishes them to the shared bar.
  The open back menu follows entry changes (a renamed screen below).
- Reduced motion (not recorded on UIKit yet): pages fade in place on the
  push spring instead of sliding.
- SEGMENTS: `morphLayoutBarGroups` tags every capsule with its side
  (`MorphBarCapsuleLayout.segment`); `MorphBarMotion` keys capsules by (id,
  segment), finds birth / death neighbours inside the segment only and
  turns a side that fills or empties into in-place groups
  (`MorphBarCapsuleFrame.apart`, opacity, per-axis swell; their items ride
  the group's scale, opacity and blur). MorphBarItems draws apart capsules
  through a second `buildLayer` placed under the content, so they never
  fuse with the bar's container; the default painter keys its content so
  a changing surface count never remounts the items.
- PRESENTATIONS ABOVE THE BARS: UIKit shows menus, context menus, alerts
  and sheets presented from a page above the navigation bar and toolbar.
  The stack installs a `MorphPresentationBoundary` around itself; every
  morph presenter without an explicit `overlay:` / `useRootNavigator:`
  uses the overlay / navigator around the outermost boundary
  (presentation_boundary_test).
