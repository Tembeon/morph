# Adaptive bar brightness passport (bar glass and glyphs over light / dark content)

Status: DRAFT. Read from UIKit (iOS 27.0 simulator cache and the iPhone 16
Pro's 27.0.1 UIKitCore, SwiftUICore, QuartzCore; notes private); NOT
measured; NOT ported. The device capture is specified in
[adaptive-brightness-capture.md](adaptive-brightness-capture.md). Related:
[bars.md](bars.md) (edge effect, bar glass groups), [tab-bar.md](tab-bar.md),
[glass-optics.md](glass-optics.md) (the luminance-conditioned tint model).

## Native

No public API: the behaviour is automatic. What the reading found:

- Two separate luminance paths start at a `CABackdropLayer` with luma
  tracking. The render server averages the backdrop's luma, rounds it to
  1/64 and sends it to the app asynchronously (main thread, delegate
  callback); it samples on a quarter-second grid (next sample time rounded
  to 0.25 s), so a value is up to about 0.25 s old when it arrives.
- Path 1, the scroll pocket (`ScrollEdgeEffectView`'s pocket, one per
  edge): its blur backdrop tracks the luma of the filtered (blurred) band
  and turns it into a DISCRETE scheme with hysteresis, which UIKit forwards
  as a user interface style to the bars and bar items registered on that
  edge (and to the status bar). Glass and glyphs both resolve from that
  trait, so they flip together.
- Path 2, the glass material: every glass capsule of a bar (the capsules
  are SDF element layers of one SDF layer, bars.md) reports the luma of its
  own backdrop; a per-bar aggregator combines them and the result reaches
  the glass views as a smoothed, quantized luminance value. The floating
  tab bar's glass and its bottom pocket share one aggregator.
- UIKit only enables path 1 behind a feature flag (below). Which path the
  owner's phone actually shows, and whether path 2 ever makes a discrete
  flip, is the first thing the capture answers.

## Spec - path 1, the scroll pocket (read from UIKit)

- Gate: the pocket tracks luma only when the view has no fixed (overridden)
  user interface style AND the UIKit user default
  `CalistogaAllowLumaTracking` is true. When the key is absent the flag is
  false, so on a stock install the pocket does not track. The capture logs
  the key on the phone. An app-forced style (`overrideUserInterfaceStyle`,
  also the probe's `PROBE_DARK`) disables tracking.
- Input: the pocket's blur backdrop (filtered luma, whole band, render
  server cadence above). No smoothing in UIKit beyond the 1/64 rounding.
- Decision, with `L` the luma in [0, 1] and the current scheme `s`
  (initially the pocket's base scheme):
  - `s == dark`: becomes light when `L > 0.70`, else stays dark;
  - `s == light`: becomes dark when `L < 0.40`, else stays light.
  The band [0.40, 0.70] holds the current scheme. Asymmetric: a light
  scheme survives down to 0.40, a dark one up to 0.70. (The upstream
  experiment's 0.5 +- 0.1, i.e. 0.4 / 0.6, is hand-picked and has the upper
  edge wrong by 0.1.)
- Output: a per-edge style (top, bottom, leading, trailing) forwarded to
  the edge's pocket receivers: the bar, its items when they apply pocket
  traits, the status bar. A hidden (effectively hidden) pocket does not
  update. Under a floating toolbar or a tab bar the bottom edge effect is
  empty by default (bars.md); whether its pocket still tracks is open.
- Timing read: the status bar's style change uses duration 0.6 s, delay 0,
  UIKit curve 5 (UIKit's default `MPLumaChangeDuration`, overridable by a
  UIKit user default). Whether bars and items animate on the same 0.6 s is
  NOT read: the capture measures it.

## Spec - path 2, the glass aggregator (read from UIKit)

- Each glass capsule's backdrop luma is rounded to 1/32 and reported only
  when it changes.
- Aggregate: area-weighted mean over the bar's capsules (each capsule's
  bounds in the bar's host coordinates); no capsules -> 0.5.
- Smoothing: an exponential moving average PER SAMPLE (not per frame):
  `s = 0.3 s + 0.7 raw` (the first sample after a reset is taken as is),
  then quantized `q = round(min(s, 1) x 32) / 32`. When `|s - raw| > 1/32`
  a one-shot settle timer of 0.35 s is (re)armed; if no newer sample
  cancels it, it resets the average and takes `raw` directly. A system
  light / dark change resets the aggregator and reports "no value".
- Output: the quantized luminance goes to the bar's glass views (they lay
  out again and, inside an animation block, animate). How the glass turns
  it into its look is in SwiftUI's glass resolution and was NOT found:
  there is an adaptive glass option with a hysteresis range type (one
  closed range for light and one for dark, a default, a disabled and custom
  ranges), an initial and a fixed luminance, and an external luminance
  option; the default ranges live in the unread consumer. Glass buttons
  (every glass button configuration) and the context menu list explicitly
  turn adaptivity off; bars do not, so their glass is presumably adaptive.

## What the capture must still measure

1. Which path is live on the owner's 27.0.1 in light and in dark mode, and
   whether bar glass and glyphs change DISCRETELY at all (path 2 could be
   continuous only: morph's glass already conditions its tint on the
   backdrop luminance per pixel, glass-optics.md).
2. The flip luma in each direction, per bar (tab bar, toolbar, nav bar
   items), on grey steps (luma = grey for any weights) and on colours (the
   luma weights).
3. Latency from a content step to the flip's first frame, and the
   transition: duration, curve, glass vs glyph onset and length (together
   or not).
4. Which elements flip: tab bar glass, tab glyphs and labels, the selected
   lens, toolbar capsules and glyphs, nav bar items and title, search field
   (toolbar placement) and the search tab circle, status bar, home
   indicator.
5. The sampled region: what part of the screen a bar's decision reads
   (pocket band vs the capsules), and the statistic (area mean or not).
6. Behaviour while scrolling over alternating content (rate limit, missed
   flips, flicker).
7. Whether the base system appearance shifts the thresholds.

## morph design (proposal, not implemented)

Goal: the UIKit behaviour with one tiny luminance probe per bar band, no
full-screen readback, no frame-late glass, and nothing to do for the app.

- Bands: top (navigation bar and its items), bottom (tab bar, search tab
  bar, toolbar, bottom search field). One controller per band, owned by the
  band's chrome host (the screen's `MorphChromeBackdrop`, the tab bar
  chrome). UIKit decides per edge too.
- Probe: when the content under the band changed (the same layer
  signature test `GlassBackdropCache` uses; idle costs nothing), at most
  every 0.25 s like the render server, take the band's backdrop region from
  the content's repaint boundary as a tiny image (`OffsetLayer.toImage`
  at a pixel ratio that makes the band about 32 x 4 px, from the frame's
  existing layers, no repaint) and read it back asynchronously; average
  the luma in Dart (128 pixels). Works the same for the flat and the liquid
  renderer (it reads the content, not the glass). No full-screen copy, no
  synchronous readback, never on the frame's critical path.
- Decision: the measured rule of the live path. If it is path 1: quantize
  to 1/64, hysteresis 0.40 / 0.70, initial = the platform brightness. If it
  is path 2: the area mean over the band's capsules, the 0.7 per-sample
  average, 1/32 quantization, the 0.35 s settle, then the measured ranges.
- Transition: the band's brightness becomes an animated value (0 light,
  1 dark) on the measured duration and curve (0.6 s until measured); the
  bar's glyph colours and its glass face (the appearance tables' light and
  dark entries) interpolate on it. During the transition only colours and
  glass uniforms change: no relayout, no rebuild of the bar tree.
- No frame-late glass: the probe never gates the glass's own backdrop,
  which stays live every frame. Only the brightness target lags, and UIKit
  lags more (0.25 s grid, async delivery, then the animation), so a
  decision one frame later than the content is invisible and native.
- Overrides: an explicit brightness on the bar (a `MorphTheme` above it)
  disables tracking, as UIKit's fixed style does. A per-band app override
  (UIKit has a private per-edge preferred style) only if an app needs it.
- Off switch: tracking follows the live path's default; if the capture
  shows the stock phone does not flip discretely, morph ships it off with
  an opt-in, not on.

Pixel 6a budget (to verify on the device, bench scenes `bars` and
`tab-bar`, scrolling content under the bars):

- Idle (nothing under a band changes): 0 probes, 0 cost.
- Scrolling: <= 4 probes per second per band; each <= 0.3 ms raster
  thread (a tiny offscreen render of the band's layers) and <= 0.05 ms UI
  thread; the readback async, adding no missed frame slot. Average added
  frame time <= 0.1 ms at 60 Hz.
- Transition frames (0.6 s per flip): uniform and colour updates only,
  within the bar's existing per-frame paint cost.
- Energy: no measurable increase in a sustained scroll (within the bench's
  noise); admission as docs/performance.md.

Widgets it touches: `MorphTabBar`, `MorphSearchTabBar`, `MorphTabBarChrome`
(minimized circle, accessory), `MorphToolbar`, `MorphNavigationBar` and
`MorphBarItems` / `MorphBarButton` (bar item glyphs and capsules),
`MorphSearchField` / `MorphSearchToolbar` (bottom placement),
`MorphScrollEdgeEffect` (its tint follows the band's scheme, as the pocket
does), `MorphChromeBackdrop` (the probe's source and the band key), the
theme (`morphBrightnessOf` gains a band-scoped brightness for the bar
subtree), and optionally the status bar style.

## Fixtures

None yet: [adaptive-brightness-capture.md](adaptive-brightness-capture.md).

## Open questions

- Which path is live on 27.0.1, and is the owner's visible flip discrete?
- The glass path's default hysteresis ranges (not found in the reading).
- The render server's luma weights and colour space, and the default luma
  update interval (a 0.25 s grid seen; the interval value not proven).
- Whether bars animate the style on the status bar's 0.6 s and curve.
- Whether the bottom pocket tracks under a tab bar / floating toolbar
  where its edge effect is empty.
