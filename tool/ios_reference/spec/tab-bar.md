# Tab bar passport (lens, look, glow, slow lift)

Status: measured on device (lens, scrub, glow, look, colors); ported;
replayed (taps against simulator and device rows; scrubs, taps on the
selected tab and the glow against device rows). Shared machinery:
[lens-and-flex.md](lens-and-flex.md). Search tab:
[search-tab-bar.md](search-tab-bar.md).

## Native

`UITabBarController` + `UITab` / `UISearchTab` (iOS 18+ API), floating bar
`_UIBottomTabBarGroupView`, lens `_UILiquidLensView`, selection
`_UITabSelectionView`, glows in `_UIFlexInteractionGlowContainerView`
(`_UIFlexInteraction.BigGlow`, `.LittleGlow`).
Public API (SDK 27.1; full table in [api/tab-bar.md](api/tab-bar.md)):
`tabs`, `setTabs:animated:`, `selectedTab`,
`tabForIdentifier:`, `mode` (automatic / tabBar / tabSidebar), `sidebar`,
`tabBarMinimizeBehavior` (automatic / never / onScrollDown / onScrollUp),
`bottomAccessory` (`UITabAccessory`, animated), `prominentTabIdentifier`,
`setTabBarHidden:animated:`; UITab `title`, `subtitle`, `image`,
`badgeValue`, `identifier`, `hidden`, `hiddenByDefault`, `UITabGroup`;
UITabBar `tintColor`, `unselectedItemTintColor` (`leadingAccessoryView` /
`trailingAccessoryView` are tvOS only).

## Spec - motion

- Selects on touch-DOWN. Inside a Scrollable the WHOLE touch (feedback
  too) is held until owned: 0.15 s hold, slop along the bar where the list
  scrolls the other way, or the lift (UIKit delaysContentTouches); a
  floating bar outside a scrollable keeps contact selection.
- The lens starts `startDelay` 45 ms after the touch's time stamp
  [device, 79 taps, `tabbar*-taps/pairs/many/no-radio/radio-first`, lift
  start fitted to the lift progress: 39 - 57 ms, median 45.5]: UIKit
  delivers the touch 10 - 25 ms after its stamp, then sets up the lift
  on the main thread (the display link's next frame comes 26 - 39 ms
  after the one before instead of 8.3; 22 - 42 ms on a tap on the
  selected tab), and the lens moves from the frame after that.
  morph counts the delay from the stamp (spec README "Clocks"); the
  former 20 ms left the travel 5.4 - 24.5 pt rms early.
- Stays lifted while held; hang 0.215 s + 0.000274 s/px of travel; press
  delay 50 ms [device; the same lift setup, 42.5 - 55.5 ms over 8 taps on
  the selected tab].
- Scrub: finger travel since touch x `dragGain` 1.013 on follow spring
  0.271/0.803, rubber band (4.55, 0.95); release after `releaseDelay`
  30 ms, travel carries scrub velocity; release picks the tab nearest the
  finger [device]. Codename One's 0.196/0.903 and "remaining < 3.5 pt"
  rule are contradicted by our data.
- Whole bar swells by `chromeGrowth` 14.6 px about its center while
  pressed (chrome spring 0.356/0.593, lag 20 ms). On-screen scrub gain
  1.055 - 1.064 = dragGain x swell. The "lens drifts outward while held"
  is the swell.
- Tap on the selected item: lifts in place, lands no earlier than
  `pressHang` 0.25 s after the touch (or `releaseDelay` after a longer hold).
- Lens lift +16 x +16; flex presentation spring 0.5/0.73.

## Spec - geometry and look

- Bar 62 tall, pitch 86 for 2..4 tabs / 68 for 5, lens 94/98/77 wide;
  widened when a label needs it; labels follow text scale up to 1.25
  [layout, device]. 21 pt from side and bottom (402 pt screen).
- Titles 10 pt medium, selected semibold (wght 590).
- Selected tint: UIKit draws a selected-style copy of ALL items masked by
  the lens (regular content cut with destOut), so tint + semibold travel
  with the lens. Colors from vibrant matrices over the measured bar
  [layout + device]: dark selected (0.2148 g + 0.3778 b, +0.5686, +1) ->
  0x0397FF, unselected 0.3125 x + 0.9375 -> 250 (0xFAFAFA); light selected
  0x0082FC, unselected 0.3125 x - 0.25 -> 13 (0x0D0D0D).
- Resting platter (`_UITabSelectionView` colorMatrix over a 2 pt blur):
  dark 0.87 x - 0.07 (32 -> 10, 0xAF000000), light 1.13 x - 0.2 (250 -> 231,
  0x13000000).
- Lifted lens optics: magnification 0.16 (held item 1.218 vs rest, swollen
  bar's other items 1.052, so 1.158 on top of the bar); shrink 0.16, edges
  inside 0.890 of the swollen bar; rim fraction 0.75 (see glass-optics).

## Spec - touch glow [device, layers + film]

- BigGlow (bar-sized) vibrantColorMatrix rows sum to 1 with +0.05 offset
  (dark bar 32 -> 43, light 250 -> 255). LittleGlow (93 pt disc) gain 4.0
  dark / 1.667 light, no offset; on screen a Gaussian of 0.568 x diameter
  at 0.38 of layer strength (s 55.7 pt at 98 pt).
- Peaks = forSize(274 x 62) bigGlowOpacity 0.845, littleGlowOpacity 0.2845.
- Rise 0.1 s crit after 0.042 s (fit); hold while down; fall 0.5 s crit
  after 0.02 s with the spot growing x4. A move 50 pt from the landing (40
  never, 60 always) turns the spot x2 at half strength on the 0.5 s
  spring until the lift; spot follows the finger in unswollen coordinates.
- Rise rows jitter one 60 Hz frame (first tap after launch ~15 ms late).

## Spec - slow lift (documented, NOT modelled)

Lens view SIZE lags its liftProgress on some selections (held: a step on
~0.59/0.86; tap cut at bh ~+13 instead of +16). Deterministic and
positional on the iPhone 16 Pro: every change from/to the THIRD slot of a
4-tab bar (x 243.3), nothing else; 2-, 3-, 5-tab never (37 taps). Not a CA
animation. CN1's 393 pt 5-tab bar was slow on other slots: the rule is a
function of geometry not derivable from two widths.

## Disabled item [device, light + dark, 2026-10-03]

- `UITabBarItem.isEnabled = NO` draws NOTHING different: the bar is
  pixel-identical to the enabled bar (both rows of the selected-tint copy
  keep their colors); only `_UITabButton.enabled` turns false.
- Touch on a disabled item (dis-tab-touch, tap 83 ms + hold 0.8 s on the
  disabled third tab): NO selection and the lens never leaves the selected
  slot; the bar STILL swells (platter 360 -> 368 on the tap, -> 375 on the
  hold, back on release) and the resting lens breathes with it (98 -> 102
  wide); no glow rows. So a disabled item still feeds the bar's press
  swell but not the lens.
- Fixture `ios27-device/disabled/disabled.json`, shots `references/disabled/{dark,light}/`, method and recapture in [states](states.md) (StatesUITests testDisabled, scenes x4dis / x4disbars / x4distab / x4disalert).
- Ported 2026-10-03 (test/disabled_test.dart replays disabled.json): `MorphTabItem.enabled`, no dim (pixel-identical
  test); a touch on a disabled item swells the bar only
  (`MorphLensMotion.isSelectable`); a drag released over one returns to
  the selected slot (unmeasured).

## Fixtures

Device `ios27-device/lens/tabbar{2,3,4,5}-*` (taps, pairs, scrub mid /
pastleft / pastright, tap-selected, no-radio, radio-first, many);
`ios27-device/tabglow/tabbar3-glow-{dark,light,drags}.jsonl` (k=big,
k=little rows). Simulator `ios27/lens/tabbar*`. References
`references/dark/tabbar3-{resting,held-selected,held-other}.png`.
Behaviours: `recordings/device-behaviours`.

## Recapture

Scene `tabbar<N>` (N 2..5); env `PROBE_DARK`, `PROBE_TABLAYERS=1`,
`PROBE_TAB_ORDER`, `PROBE_TBITEMS`, `PROBE_LENS_ANIMS=1`. Device plans
`lens`, `recaplens`, `tablook`, `tabglowdrag`; ProbeUITests.testBehaviours.

## morph

`MorphTabBar`, `MorphTabItem`, `MorphTabBarAppearance` (tab_bar.dart),
`MorphLensTuning.tabBar`, `MorphTouchGlowMotion` + `MorphGlassGlow`
(glass_glow.dart), touch_listener.dart (`delaysInScrollable`). Tests:
lens_test (simulator taps `ios27/lens/tabbar*`, tab bar on the undeformed
frame only), lens_scrub_test (device scrubs and taps on the selected tab),
tab_bar_device_replay_test (79 device taps at their logged stamps: onset
median within half a frame of `startDelay`, every onset within the
14.6 ms delivery spread, size rms < 2.5 pt, median center rms < 1.5 pt;
aligned to each lift start: center < 1.5, size < 2.5; the slow lift
stays skipped), tab_bar_glow_test (rms bound 0.03 / 0.012), tab_bar_slow_lift_test (sorts
the device tap fixtures; native behaviour only, it does not run morph),
disabled_test, tab_bar_api_test, controls_scroll_test, glyph_policy_test,
glyph_scale_test.

Labels under the swell: the whole bar scales by `grow` (1 -> 1.04) under a
finger, and the lens's magnified copy sweeps through its magnification in
the ~10 frames of a lift; a label meeting a new screen scale per frame
strikes its glyphs again. Each label (both rows, outside and inside the
lens) sits in `MorphGlyphs` and the copy painter observes its scale
through the same `MorphGlyphTracker` (glyph_scale.dart,
`MorphGlyphPolicy`): exact at rest; snapped to the 64-per-octave grid
about the label's center while slow (at most 0.54 percent off its layout
size); from one raster while the swell moves fast; the copy, recorded
again every frame of a live lens, snaps to 32 or 16 per octave when fast
(at most 1.1 / 2.2 percent, NEAR). Layout, hit testing and semantics are
unchanged. History: the fixed 64 grid (Redmi 6A flat, audit A B B A,
raster p95 14.0 / 15.7 -> 11.9 / 12.1 ms) and the copy's fixed 16 grid
while lift < 0.99 (bd4c4a7) were the special cases the policy replaced.
Pixel 6a liquid tab-bar scene, A B B A, 5 runs a launch (tool/bench,
perf/2026-10-12-bench-abba2-*): frames striking glyphs 6.5 -> 2.9 percent,
atlas 0.33 -> 0.22 ms per frame and 3.8 -> 0.9 ms in frames over budget;
frames over budget and power within the run spread. Host pixels
(glyph_scale_test, exact vs policy, 120 frames): 46 differ, worst mean
0.06, 0.09 percent of pixels over 15; first and last frames identical.

Aligned labels (2026-10-13): the atlas also keys a glyph by its x in
quarter device pixels, and the swell moves every label but the middle one
sideways, so the snapped frames still struck new keys at each quarter
pixel and the tail's live drift struck more (Pixel r5 d3dbebd: 3.0 - 5.5
percent strike frames flat, 11.6 - 19.2 liquid, UpdateAtlasBitmap 6 - 7
ms in frames over budget). The labels are `MorphGlyphs(aligned: true)`:
any motion of the scale snaps, down to the drift, and a snapped label is
shifted across so its origin lands on a whole device pixel (NEAR: at most
half a device pixel, a sixth of a point at 3x; the drift is drawn at most
0.54 percent off its size). The lens copy replays the content's recorded
paint, so it keys the replayed label at copy scale x the label's own
snap: the content source records each glyph drawing's transform
(`GlassContentSnapshot.glyphs`), and for an item whose label is aligned
the copy snaps the product, larger axis on its grid and the other at its
ratio to it snapped on the finest grid (the rim's middle strip grows one
axis only), and shifts the item so the label's origin lands on a whole
device pixel (NEAR: at most half a device pixel, per strip, and at most
0.54 percent off its exact aspect, while the lens is lifted). At rest
nothing moves: the bar draws as before. glyph_strikes_test replays the
atlas over three jittered bench runs, strike frames (keys new in runs 1 /
2 / 3): tap flat 16 (192 / 33 / 22) -> 4 (64 / 0 / 0), drag flat 39
(492 / 56 / 13) -> 6 (132 / 0 / 0), tap liquid 124 (1369 / 612 / 235)
-> 39 (510 / 28 / 26), drag liquid 161 (1783 / 559 / 223) -> 36 (553 /
34 / 0). Host pixels (control goldens at 1x, aligned vs not, re-recorded):
flat tap 6 frames differ, worst mean 0.04, 0.08 percent of pixels over
15; flat drag 22, 0.08 / 0.14; fake tap 17, 0.08 / 0.15; fake drag 24,
0.13 / 0.16.

Repaints (lifecycle.md, 2026-10-14): native redraws 3-4 labels once on a
selection change and moves the lens in the render server. Each label row
(outside and inside the lens) is a repaint boundary of its own while the
bar does not swell and no painter records the content for a lifted lens
(`morphGlassKeepsContentLive`: the flat tier, or a lens at rest); a lens
that travels then only moves the two clip paths, and the rows are
composited again. While the bar swells (the glyphs snap to the screen
scale at paint) or a lifted lens copies the content (the copy replays its
pictures), the rows paint into the bar as before. Pixels identical. Host
recorder, programmatic selection: 0/2/99 -> 0/2/17 builds/layouts/paints a
frame (flat), 0/2/102 -> 0/2/18 (liquid).

## Not reproduced / open

- Slow lift (above). Bar-local glitch (deliberate).
- Tab bar deformation replay only on undeformed frames.
- Reduce Motion read from UIKit (notes private): no lift, selection on (0.9, 0.2) for taps and scrubs; ported, device pass pending ([states](states.md#read-from-uikit-static-2026-10-14-notes-private)). No haptics.

## API gaps

- Badges exist (`MorphTabItem.badge`, `MorphBadge`): the bar badge's
  metrics (see bars.md) [read from UIKit, notes private]. Placement: its
  leading edge 5 pt inside the image's trailing edge (ported against the
  24 pt glyph box - UIKit uses the symbol image's own frame, NEAR), its
  top 2 pt below the tab button's top (stacked style); the button frame
  relative to the glyph is not known, so morph keeps the badge top 6 pt
  above the glyph by eye - needs a device check. UIKit also keeps the
  badge inside the button bounds outset by a configuration margin (not
  read). `selectedImage` exists (`selectedIcon`, drawn inside the lens).
  Reselection (`onReselected`) fires on release: UIKit's floating tab bar
  decides a reselect of the highlighted item at the lift and fails it when
  the lift is outside [read from UIKit, notes private]; any delay after
  the lift is not traced.
  Subtitles, tab groups, hidden tabs.
  Badge under a held or dragged lens [iPhone 16 Pro, iOS 27.0.1,
  2026-10-14]: count and dot remain crisp circles above the lens.
  The number badge grows 18.33 -> 19.29 pt and the dot 18 -> 18.94 pt,
  matching the whole bar's 1.052 swell, without the lens's magnification
  or rim refraction. Morph draws one badge above the glass content,
  inside the bar's swell transform. Native capture: testTabBadges,
  `rec-followup-tab-badges` and held-number / held-dot attachments
  (raw data private). Placement remains NEAR as described above.
  The integrated Flutter release capture on the unobstructed iPhone,
  2026-10-15, confirms one crisp count/dot above the held and dragged
  lens, with the real liquid renderer. Four screenshots and the physical
  screen movie are retained privately; selection on contact/release and
  the explicit completion marker pass. Glyph-box placement remains NEAR.
- `tabBarMinimizeBehavior` and `bottomAccessory`: ported from UIKit's
  code, partly device-confirmed; passport [tab-bar-minimize.md](tab-bar-minimize.md)
  (the probe sets it: `w2search` scene, `PROBE_MINIMIZE=1` = onScrollDown).
- `prominentTabIdentifier` for an ordinary tab (with none set, UIKit
  makes the activating search tab prominent: `MorphSearchTabBar`).
- Sidebar mode (iPad), `setTabBarHidden:animated:`.

## Implementation notes (moved from CLAUDE.md)

- Glow seam: `MorphGlassSurface.glow` (`MorphGlassGlow`: wash, center,
  radius, gain). The liquid tier's final glass pass applies it to the bar
  glass (additive wash, then the color-dodge Gaussian, clamped at white;
  docs/glass.md "Touch glow"); the flat tier and the bar without a
  painter draw no glow. The glows sit over the bar glass, under the tab
  content, riding the bar swell. Recapture: testTabLook /
  testTabGlowDrag with `PROBE_TABLAYERS=1` (every layer of
  _UIBottomTabBarGroupView per frame).
- Selected tint in morph: two rows clipped along the lens outline each
  frame (the selected copy is RichText so `find.text` still finds one row).
- Bar-local glitch (UIKit artifact, deliberately not reproduced): one
  frame of bar-local coordinates fed into its own integrator at each lift
  after the first - a spurious drift/scale kick on the device, a vertical
  sag in the simulator.
- Slow lift evidence: lpp itself is normal and the sibling
  _UITabSelectionView keeps the normal size, so the lag is the lens view's
  own frame; CN1 measured the held step as 0.59/0.85. Not the item's icon or
  title (moved with PROBE_TAB_ORDER, the slot stays slow), not tap duration
  (33 ms .. 1 s), history, travel or display-link phase. The fall after a
  slow tap's unlift is not fitted either. Recordings
  tool/ios_reference/recordings/device-behaviours (testBehaviours;
  `PROBE_LENS_ANIMS` logs lens layer CAAnimations - none exist).
