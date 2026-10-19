# Adaptive bar brightness passport (bar glass and glyphs over light / dark content)

Status: DRAFT. Read from UIKit, SwiftUI and the glass material library
(iOS 27.0 simulator cache and the 27.0.1 device cache; notes private); NOT
measured; NOT ported. The device capture is specified in
[adaptive-brightness-capture.md](adaptive-brightness-capture.md). Related:
[bars.md](bars.md) (edge effect, bar glass groups), [tab-bar.md](tab-bar.md),
[glass-optics.md](glass-optics.md) (the luminance-conditioned tint model).

## Native

No public API: the behaviour is automatic and on by default (the owner sees
bars flip on iOS 27). What the reading found:

- The render server averages a tracked backdrop's luma, rounds it to 1/64
  and sends it to the app asynchronously (main thread); it samples on a
  quarter-second grid (next sample time rounded to 0.25 s).
- THE LIVE PATH is the glass material itself (the system glass material
  provider every bar capsule uses): each capsule reports the luma of its own
  backdrop, a per-bar aggregator combines them, and the material picks an
  adapted light or dark scheme with hysteresis. The glass face AND the
  glyphs on it resolve in that adapted scheme (the glyphs are the
  material's foreground), so they flip together, without any change of the
  views' user interface style (trait).
- A second path, the scroll pocket under each bar edge, can also flip the
  bars' style, but it is disabled on a stock install (a UIKit user default
  that is absent, read below). It is documented for completeness only.

## Spec - the glass material (live path, read from the binaries)

Input, per bar (glass group):

- Each capsule's backdrop luma is rounded to 1/32 and reported only when it
  changes.
- Aggregate: area-weighted mean over the bar's capsules (each capsule's
  bounds in the bar's coordinates); no capsules -> 0.5.
- Smoothing: an exponential moving average PER SAMPLE (not per frame):
  `s = 0.3 s + 0.7 raw` (the first sample after a reset is taken as is),
  then quantized `q = round(min(s, 1) x 32) / 32`. When `|s - raw| > 1/32`
  a one-shot 0.35 s settle timer is (re)armed; if no newer sample cancels
  it, it resets the average and takes `raw` directly. A system light / dark
  change resets the aggregator.

Decision (the material's state keeps the adapted scheme; until the first
luminance it shows the base scheme):

- The base scheme is the environment's (system appearance or an explicit
  scheme on the view). It picks one of two ranges: `light` when the base is
  light, `dark` when it is dark.
- With `L` the aggregated luminance and the range `[lo, hi]`: `L < lo` ->
  dark look; `L > hi` -> light look; `lo <= L <= hi` -> keep the previous
  adapted look.
- Default ranges (either set may be live; a glass-library setting picks it,
  not pinned in the reading):

  | set | light base `[lo, hi]` | dark base `[lo, hi]` |
  |---|---|---|
  | A | 0.20 ... 0.50 | 0.60 ... 0.90 |
  | B | 0.10 ... 0.30 | 0.70 ... 0.90 |

  So on a light system a bar turns dark only over content darker than 0.20
  (B: 0.10) and returns to light above 0.50 (B: 0.30); on a dark system it
  turns light only above 0.90 and returns to dark below 0.60 (B: 0.70).
  Both ranges can be overridden by two-number user defaults
  (`AdaptiveGlassHysteresisLightRangeArray`, `...DarkRangeArray`), and a
  view can set a custom range; one special glass kind uses 0.70 ... 0.75 in
  both. The upstream experiment's 0.5 +- 0.1 matches neither.
- Predicted timing (from the input chain, to be measured): a step to black
  under a light bar arrives within one 0.25 s grid step; the average jumps
  70 percent (1 -> 0.3, still above 0.20), and the settle timer takes the
  raw value 0.35 s later: about 0.6 s before the flip starts. A step to
  white under a dark bar crosses 0.50 after the first sample (0 -> 0.7):
  about 0.25 s. The look's own animation is not read.

## Spec - the scroll pocket (disabled on stock, read from the binaries)

- The pocket under a bar edge tracks luma only if the UIKit user default
  `CalistogaAllowLumaTracking` is true AND the view has no fixed style AND
  the edge effect's options prefer luma tracking. The default is read once;
  absent means false, and nothing registers it. The probe logs the key on
  the phone.
- When enabled: base dark -> light style when the pocket's (blurred) luma
  is above 0.70; base light -> dark style when it is below 0.40; the
  threshold follows the base (system or preferred) scheme, with no memory
  of the previous result. The style is forwarded to the edge's bars and
  items and to the status bar; the status bar animates it over 0.6 s.

## What the capture must still measure

1. Confirm the live path on 27.0.1: the bars flip with the scroll host and
   with a plain (static) host alike, and the views' style rows stay put.
2. Which range set is live: the flip luma on a light system going down
   (0.20 or 0.10) and up (0.50 or 0.30); on a dark system going up (0.90)
   and down (0.60 or 0.70). The hold tests inside the bands separate the
   sets.
3. The luma the material sees for a colour (render-server weights) and per
   bar mixes (area mean over capsules).
4. Latency and the look's transition: duration, curve, glass vs glyphs.
5. Which elements flip: tab bar glass, glyphs, labels, the selected lens,
   toolbar, navigation bar items and title, search field and search tab
   circle; whether the status bar follows (it would only with the pocket).
6. Behaviour while scrolling over alternating content.

## morph design (proposal, not implemented)

Goal: the native behaviour with one tiny luminance probe per bar, no
full-screen readback, no frame-late glass, nothing to do for the app.

- Bars: per glass group (tab bar, toolbar, navigation bar items, bottom
  search field), as the material decides per bar.
- Probe: when the content under the bar changed (the same layer signature
  test `GlassBackdropCache` uses; idle costs nothing), at most every 0.25 s
  like the render server, take the region under the bar's capsules from the
  content's repaint boundary as a tiny image (`OffsetLayer.toImage` at a
  pixel ratio that makes a capsule a few pixels, from the frame's existing
  layers, no repaint), read it back asynchronously, and average the luma
  per capsule in Dart, weighted by capsule area. Works the same for the
  flat and the liquid renderer.
- Decision: the measured chain: 1/32 quantization, the 0.7 per-sample
  average, the 0.35 s settle, then the range of the base scheme with the
  measured bounds (set A or B), keeping the previous look inside it.
- Transition: the bar's look becomes an animated value (0 light, 1 dark)
  on the measured duration and curve; glyph colours and the glass face
  (the appearance tables' light and dark entries) interpolate on it. Only
  colours and glass uniforms change: no relayout, no rebuild.
- No frame-late glass: the probe never gates the glass's own backdrop,
  which stays live every frame; only the look's target lags, as natively.
- Overrides: an explicit brightness on the bar (a `MorphTheme` above it)
  fixes the base scheme; a per-bar custom range mirrors the native one.

Pixel 6a budget (to verify, bench scenes `bars` and `tab-bar`, scrolling
content under the bars): idle 0; scrolling <= 4 probes per second per bar,
each <= 0.3 ms raster thread and <= 0.05 ms UI thread, the readback async
with no missed frame slot; average added frame time <= 0.1 ms at 60 Hz;
transition frames update colours and uniforms only; energy within the
bench's noise (admission as docs/performance.md).

Widgets it touches: `MorphTabBar`, `MorphSearchTabBar`, `MorphTabBarChrome`
(minimized circle, accessory), `MorphToolbar`, `MorphNavigationBar` and
`MorphBarItems` / `MorphBarButton`, `MorphSearchField` /
`MorphSearchToolbar` (bottom placement), `MorphChromeBackdrop` (the probe's
source), the theme (`morphBrightnessOf` gains a per-bar adapted look for the
bar subtree). The scroll edge effect and the status bar stay on the system
scheme, as on a stock phone.

## Fixtures

None yet: [adaptive-brightness-capture.md](adaptive-brightness-capture.md).

## Open questions

- Which default range set (A or B) is live, and which setting picks it.
- The look's transition (duration, curve) and glass / glyph sync.
- The render server's luma weights and the luma update interval (a 0.25 s
  grid seen; the interval value not proven).
