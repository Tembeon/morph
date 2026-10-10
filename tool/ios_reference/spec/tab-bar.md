# Tab bar passport (lens, look, glow, slow lift)

Status: measured on device (lens, scrub, glow, look, colors); ported;
replayed. Shared machinery: [lens-and-flex.md](lens-and-flex.md). Search tab:
[search-tab-bar.md](search-tab-bar.md).

## Native

`UITabBarController` + `UITab` / `UISearchTab` (iOS 18+ API), floating bar
`_UIBottomTabBarGroupView`, lens `_UILiquidLensView`, selection
`_UITabSelectionView`, glows in `_UIFlexInteractionGlowContainerView`
(`_UIFlexInteraction.BigGlow`, `.LittleGlow`).
Public API (SDK 27.0): `tabs`, `setTabs:animated:`, `selectedTab`,
`tabForIdentifier:`, `mode` (automatic / tabBar / tabSidebar), `sidebar`,
`tabBarMinimizeBehavior` (automatic / never / onScrollDown / onScrollUp),
`bottomAccessory` (`UITabAccessory`, animated), `prominentTabIdentifier`,
`setTabBarHidden:animated:`; UITab `title`, `subtitle`, `image`,
`badgeValue`, `identifier`, `hidden`, `hiddenByDefault`, `UITabGroup`;
UITabBar `tintColor`, `leadingAccessoryView`, `trailingAccessoryView`.

## Spec - motion

- Selects on touch-DOWN. Inside a Scrollable the WHOLE touch (feedback
  too) is held until owned: 0.15 s hold, slop along the bar where the list
  scrolls the other way, or the lift (UIKit delaysContentTouches); a
  floating bar outside a scrollable keeps contact selection.
- Stays lifted while held; hang 0.215 s + 0.000274 s/px of travel; press
  delay 50 ms [device].
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

`MorphTabBar`, `MorphTabItem`, `MorphTabBarStyle` (tab_bar.dart),
`MorphLensTuning.tabBar`, `MorphTouchGlowMotion` + `MorphGlassGlow`
(glass_glow.dart), touch_listener.dart (`delaysInScrollable`). Tests:
lens_test (tab bar on the undeformed frame only), lens_scrub_test,
tab_bar_glow_test (rms bound 0.03 / 0.012), tab_bar_slow_lift_test,
controls_scroll_test, glyph_snap_test.

Labels under the swell: the whole bar scales by `grow` (1 -> 1.04) under a
finger, so every label met a new screen scale per frame and the glyph
cache struck it again. Each label (both rows, outside and inside the lens)
sits in `MorphGlyphSnap` (glyph_scale.dart), which paints it at the
`MorphGlyphScale` grid scale nearest its screen scale, about its own
center: at most 0.54 percent off its layout size, exact at rest; layout,
hit testing and semantics are unchanged. Redmi 6A (Skia, flat), audit
A B B A, 3 runs, tab-bar scene: raster p50 11.3 / 11.6 -> 10.2 / 10.3 ms,
p95 14.0 / 15.7 -> 11.9 / 12.1, p99 16.0 / 16.7 -> 13.2 / 12.9, frames
over budget 4 / 10 -> 1 / 0 (the scene had spent 8.3 ms a frame drawing
21 text blobs and 6.3 glyph-atlas uploads); the segmented and controls
scenes are unchanged within their spread.

## Not reproduced / open

- Slow lift (above). Bar-local glitch (deliberate).
- Tab bar deformation replay only on undeformed frames.
- Reduce Motion unmeasured (plan in states.md).

## API gaps

- Badges (`badgeValue`), subtitles, tab groups, hidden tabs.
- `tabBarMinimizeBehavior` (bar collapsing on scroll) - not measured; the probe can already set it (`w2search` scene, `PROBE_MINIMIZE=1` = onScrollDown).
- `bottomAccessory` (mini player above the bar) - not measured.
- `prominentTabIdentifier`, leading/trailing accessory views.
- Sidebar mode (iPad), `setTabBarHidden:animated:`.

## Implementation notes (moved from CLAUDE.md)

- Glow seam: `MorphGlassSurface.glow` (`MorphGlassGlow`: wash, center,
  radius, gain) and `MorphGlassPainter.buildGlow` (additive wash +
  colorDodge Gaussian, exact over gray; the default buildLayer, the flat
  bar and the renderer call it). The glows sit over the bar glass, under
  the tab content, riding the bar swell. Recapture: testTabLook /
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
