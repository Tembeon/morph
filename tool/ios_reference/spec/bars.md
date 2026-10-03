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
appearance scale 0.2 + blur 10. Births on the neighbour's facing edge
where one exists; a survivor next to a newborn waits 0.1 s. Same transition
drives nav bar buttons on push/pop. Replay: capsules 1.0 pt rms center,
1.6 width, 0.8 height. Groups without id are keyed by place from the bar's
EDGE (device morphs the outermost trailing capsule into the outermost one);
the back button morphs out of the leading capsule.

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

Device `ios27-device/bars/`: toolbar-swap, push-pop, scroll-edge.json,
title-drag-{collapse,partial20..45}, title-fling, item-hold,
pop-edge-{commit,cancel,slow25/30/35,flick-v400/v450,flickback,flickback3,
drift-*}, tuning.txt. Simulator `ios27/bars/`.

## Recapture

Scene `nav` (Bars.swift): `PROBE_EDGE`, `PROBE_AUTO=scroll|toolbar|push|
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
  groups and outline per color (`morphGlassContainerGroups` +
  `morphGlassContainerOutline`), no trace of its own.
