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
appearance scale 0.2 + blur 10. Births and deaths follow ONE law (section
"the birth and death law"); a survivor that moves while a group of its side
grows out of a survivor waits 0.1 s. Same transition drives nav bar buttons
on push/pop (with the navigation timing below). Replay: capsules 0.96 pt
rms center, 1.6 width, 0.8 height. Groups without id continue the NEAREST
group without id of their side (`MorphBarCapsuleLayout.anonymous`); the
back button morphs out of the leading capsule.

## Spec - per-segment transitions [device, 2026-10-05, scene navseg]

Owner report: morph fused the leading group into the trailing one on a
push / pop (a back button pushed onto a page without leading items was
born on the trailing capsule's facing edge and flew across the bar).
UIKit never does: each side of a bar changes only with itself.

- Leading groups change only into leading groups, trailing into trailing. No capsule, element or glass ever
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

## Spec - the birth and death law [device, 2026-10-05, navseg set b]

Owner report: on a pop from the gallery's Navigation page ([plus more]
[1x] -> [1x]) the [plus more] capsule slid to the facing edge of [1x] and
stayed there as a fused nub until it settled - not what UIKit does, and
not what morph's toolbar did. Measured (scene navseg, `PROBE_SET=b`, pages
[1x]; [plus more] [1x]; [Show Preferences]; [heart] [Show Preferences];
toolbar sets D..J; fixtures navsegb-push-pop / -toolbar / -toolbar2,
CASDFElementLayer identities):

- WHO SURVIVES: a group continues the group of its side whose center lies
  nearest (no identity crosses a push): [plus more] [1x] -> [Show
  Preferences] keeps the INNER group's element (262.33 -> 299.17) and lets
  [1x] die; [1x] -> [plus more] [1x] keeps [1x]. Explicit ids still win in
  morph; groups without id pair by nearest center.
- BIRTH: a group with no counterpart grows out of the nearest survivor of
  its side - its own box FITTED INSIDE the survivor's box BEFORE the
  change (each axis at most the survivor's, placed as near its own place
  as fits), at 0.2. [heart] out of [Show Preferences]: flush to the
  facing end (234.33, 8.8 x 8.8; toolbar 224.33, 9.6); [reply share
  folder] out of [Show Preferences]: 284.17, 33.53 x 9.6; [heart] out of
  [compose]: 350, 9.6; toolbar-swap's [folder] out of [Filter]: 75.67, 9.6
  (the old facing-edge rule said 76).
- DEATH: the same into the survivor's box AFTER the change, so it vanishes
  inside it: [plus more] into [1x] -> 355, 12.4 x 8.8; [1x] inside [Show
  Preferences] -> its own center, 12.4 x 8.8; [heart] -> 234.33, 8.8.
- TOO LARGE: a group wider than its survivor. The navigation bar still
  grows it out of the survivor's box ([plus more] out of [1x]: 355, 12.4 x
  8.8; the nav scene's inner group out of [add more]: 336.33, 19.87 x
  8.8); the toolbar shows it IN PLACE in its second SDF layer ([reply share
  folder] beside [compose] or [heart], sets E / J, swollen 183.67 x 57.6,
  host 1) and lets it leave in place. The two bars differ, one law with
  the discriminator as data: `MorphBarTransitionSpec.oversizedInPlace`
  (toolbar true, navigation false).
- NO SURVIVOR on the side: in place (per-segment section).
- The host survivor swells as if its items changed (toolbar [compose] ->
  [heart] [compose]: 56.93 wide); a survivor nothing grew out of does not
  ([compose] beside an in-place group: no change at all).
- Replay (test/bar_survivor_test.dart): every birth and death box of the
  four fixtures (navsegb nav 3 + 3, toolbar 3 + 3 and 4 in place, nav scene
  1 + 1, toolbar-swap 1 + 1) within 0.1 pt of the device (test bound 0.6);
  the pages with the overflow group (page 4) are left out. Old replays
  unchanged except toolbar-swap center 0.947 -> 0.959 (device), 1.021 ->
  1.009 (sim).
- NOT REPRODUCED (timing): when the survivor keeps its box, UIKit holds
  the newborn small inside it and first swings the survivor toward it (up
  to 24 pt sideways and 4.5 pt away from the screen edge, both elements
  together) - the newborn starts growing 0.146 - 0.268 s after the call
  (free fits over five births) where morph starts it at the frame delay;
  where the survivor's box changes it grows at once (toolbar-swap 0.03 s).
  No law found yet - measure before tuning.
- Device check: recordings/device-navsegb-20261005 (native navsegb-auto2
  next to morph navsegb-flutter = example/integration_test/
  navseg_video_test.dart with NAVSEG_SET=b), sheets navsegb_<k>_*.png;
  the gallery scenario before / after: gallery_pop1/pop2/push1.png
  (example/integration_test/gallery_navigation_video_test.dart).

## Spec - container spacing [layout, device + sim]

Every capsule of a nav bar (and of a toolbar) is an element of ONE SDF
layer, smoothness 12, constant through setItems, splits and merges.
Resting groups (12 apart) sit at the merge law's reach (never touch); a
split (the nearer group keeps its element, the other is born inside its
box at 0.2 - the birth law) fuses while closer.
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
- Cost (Pixel 6a, 2026-10-06): the band blurs a copy of the backdrop
  around it (grown by the kernel's reach), not the pass itself - a band
  along the screen edge made Impeller blur the whole pass at full
  resolution: 7.6 -> 2.8 ms GPU a scrolling frame, the same blur within
  1 - 2 channel steps (glass-renderer.md "Small blurs").

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

Device `ios27-device/bars/`: navsegb-push-pop, navsegb-toolbar,
navsegb-toolbar2 (set b, the birth law; same rows), navseg-push-pop,
navseg-toolbar, navseg-edge
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
[heart]); `PROBE_SET=b` swaps in NavSegPages.configureB (the birth law
pages), `PROBE_ROOTSCROLL=<pt>` scrolls the root once; `PROBE_SEQ`
(default push x4, pop x4; `tbA` .. `tbJ` set the root toolbar; `none` for
touches), `PROBE_GAP`. Set b runs 2026-10-05: `{"PROBE_SCENE":"navseg",
"PROBE_SET":"b","PROBE_ROOTSCROLL":"200"}` and `PROBE_SEQ=tbE,tbD,tbF,tbG,
tbF,tbD` / `tbH,tbD,tbF,tbI,tbF,tbD,tbJ,tbD`. Launched with devicectl
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

- The newborn's late start and the survivor's swing (birth law section).
- Overflow: a page whose items do not fit (navseg set b page 4) moves an
  item into an overflow group born in place; morph has no overflow.
- SCROLL EDGE EFFECT ON A PUSH / POP: UIKit's effect belongs to each
  page's scroll view and slides with its page (navsegb-auto2 rows: the
  root's band 188.6 -> 80.3 on a push = the page's 0.3 parallax, back on a
  pop); morph keeps one effect in the bar and fades it between the pages'
  states (crit 0.35). The fade now crossfades the blur itself
  (`MorphScrollEdgeEffect.opacity`); until 2026-10-05 an Opacity above the
  BackdropFilter made the blur read an empty backdrop, so the page showed
  sharp under the bar for the whole fade - the owner's "transparency under
  the back button" after a pop (edge_effect_fade_test).
- The edge-swipe commit's bar transition starts 0.027 s after the lift's
  time stamp on the device; morph starts it from the stack's setLayout at
  the commit with the navigation delays (not replayed).
- The stack's toolbar on a push uses the toolbar timing (`.standard`);
  a toolbar changing with a push is not measured.

- Large title's tall-bar inset bookkeeping (ours scrolls as content).
- Toolbar drift during an edge swipe (not measured).

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
  (`MorphBarCapsuleLayout.segment`) and marks groups without id
  `anonymous`; `MorphBarMotion` pairs capsules within the segment (ids,
  else nearest center), places births and deaths by the one law and
  turns a side without a survivor into in-place groups
  (`MorphBarCapsuleFrame.apart`, opacity, per-axis swell; their items ride
  the group's scale, opacity and blur). MorphBarItems draws apart capsules
  through a second `buildLayer` placed under the content, so they never
  fuse with the bar's container; the default painter keys its content so
  a changing surface count never remounts the items. A leaving capsule
  whose id a survivor took is renamed `MorphBarDepartedId` (MorphBarItems
  keeps its old tint for it).
- PRESENTATIONS ABOVE THE BARS: UIKit shows menus, context menus, alerts
  and sheets presented from a page above the navigation bar and toolbar.
  The stack installs a `MorphPresentationBoundary` around itself; every
  morph presenter without an explicit `overlay:` / `useRootNavigator:`
  uses the overlay / navigator around the outermost boundary
  (presentation_boundary_test).
