# Glass optics passport (magnification, shrink rim, platters, colors, frost)

Status: measured on the device (dark reference PNGs, layer filters, film);
implemented in the package renderer (`MorphGlassRenderer`); LIGHT reference
set pending.

## Native

`UIGlassEffect` (style regular / clear, `interactive`, `tintColor`),
`UIGlassContainerEffect` (`spacing`), SwiftUI `.glassEffect` /
`GlassEffectContainer`; lens `_UILiquidLensView`; filters
vibrantColorMatrix, colorMatrix, variableBlur, gaussianBlur (inputs
readable via KVC on public CALayer filter key paths, `PROBE_W2FILTERS=1`).
Refraction values `MorphGlassOptics.small/large` = UIKit's lens optics
[tuning].

## Which surfaces are glass (audit vs dark UIKit references)

Glass: bars and bar capsules, glass buttons, menus, popovers, date picker
overlay, alerts, floating sheets, search capsule. PLAIN fills (`glass`
false): segmented / switch / slider tracks, stepper. Lens / knob / thumb:
opaque platter at rest, CLEAR glass only while lifted (shows the track at
its own brightness - no wash, no tint).

## Lifted lens optics [device references, glyph scale by correlation, edges at sub-pixel crossings]

| control | magnification | native edges inside | renderer shrink | rim | gallery on device |
|---------|---------------|---------------------|-----------------|-----|-------------------|
| tab bar | 0.16 (held item 1.218 vs rest; 1.158 over the swollen bar 1.052) | 0.890 of swollen bar | 0.16 | 0.75 | 0.891 |
| segmented | 0 (label 0.996) | 0.8125 | 0.20 | 1 | 0.815 |
| switch knob | 0 | 0.755 | 0.25 | 1 | 0.762 |
| slider thumb | 0 | 1.000 | 0 | - | - |

- UIKit minifies by DEPTH below the rim, fading toward the middle (rim depth
  27 px: 9 px, 37 px: 7 px, 47 px: 0) - why the thin slider track is
  untouched. Rim-line shrink (`backdropShrinkRim`): track end inside a held
  end segment 0.960 (ref 0.962), inside the switch knob 0.869 (ref 0.870),
  swollen tab bar end 10 px in (ref 11).
- Lens refraction = UIKit displacement x 2 (18 lifted), dispersion -0.25.
- Content copy under a lens: each item scaled about ITS OWN slot (labels
  stay still under a dragged lens), pre-grown by 1 + (1 / (1 - shrink) - 1)
  x visibility.
- Codename One's 1.16 holds for the tab bar; upstream's fitted 1.1 does not.

## Platters and colors [layer matrices]

- Tab bar resting platter: dark 0.87 x - 0.07 (32 -> 10, 0xAF000000;
  earlier read 0xB5000000), light 1.13 x - 0.2 (0x13000000).
- Tab bar item vibrancy, glows: see tab-bar.md.
- Slider fill / track / thumb colors: see slider.md.
- Native lifted slider thumb in dark: uniform +21 gray wash, no fill in rim
  (ours differs - open).

## Performance (device, gallery)

FROST costs ~1 ms raster per frosted surface per frame (Controls page 13-15
ms vs 2.6); only bars, menus and lifted lenses frost unless "Frost
controls". An OpacityLayer between resting glass broke BackdropGroup
sharing (raster p50 11.8 ms vs 2.3). LiquidGlassCapture drops whole
controls on iOS - not used. Audit p95 raster 2.0 / 2.3 / 2.9 / 3.6 ms
(segmented / tab bar / controls / menu). A lifted lens, knob or thumb
blurs a copy of its own surroundings while its frost animates (glass-renderer.md,
"The lifted lens's frost"): the same measured frost, within 1 - 3 steps.
A resting frost just below Impeller's half resolution blur (the 2 pt bar
and menu frost at 2.625 dpr) is raised to it, by at most 12 percent
(2.17 pt there, unchanged at 3x): about 5 ms less GPU a frame on the
Pixel, 2 - 6 steps on real content, up to 23 on 1 px stripes
(glass-renderer.md "Small blurs").

## References and tools

`references/dark/*.png` (16 states + 9 second-pass shots), `references/light/*.png`
(the same 25 states forced light, 2026-10-03), `references/disabled/` (the
disabled look, see states.md), `*-video/` crops. Audit:
example/integration_test/glass_audit_test.dart (profile, dark, writes
`<app tmp>/glass/`). Static refs recapture: `PROBE_PLAN=refs
PROBE_RESULT=<path>.xcresult ./device.sh`, export attachments with
`xcrun xcresulttool export attachments`; the light set needs no phone
switch: `TEST_RUNNER_PROBE_REF_DARK=0` on ProbeUITests/testReferences and
Widgets2UITests/testW2Refs (xcodebuild test-without-building, see README).
ExtrasUITests.testX3Shots.

## morph

glass.dart (seam: `MorphGlassScope`, `MorphGlassPainter` buildSurface / buildFill
/ buildLayer(spacing:, contentSlots:, outline:) / buildBody / buildGlow,
`MorphGlassSurface`, `MorphGlassKind`, `MorphGlassOptics`), glass_outline.dart
(`MorphGlassOutline`), glass_renderer.dart (`MorphGlassRenderer`,
`liftedOptics`, `MorphGlassTier`, `MorphGlassMaterial`), glass_tier.dart
(`GlassAdaptiveScope`, `MorphGlassDeviceClass`), glass_liquid*.dart,
lib/src/glass/renderer (vendored whynotmake-it renderer, VENDORED + NOTICE).
Tests: glass_renderer_test, lifted_lens_look_test.

## Native face transfer [device, 2026-10-13]

Native `UIGlassEffect` (regular) panels in a `UIVisualEffectView` over 16 gray
stripes, iPhone 16 Pro, iOS 27.0.1, light and dark, read at the panel's center
(lab captures; notes private). Backdrop gray in, glass out (sRGB 8-bit):

| size | light | dark |
|---|---|---|
| 120x44 | 102>173 119>183 136>193 153>203 | 102>117 119>128 136>139 153>148 |
| 160x64 | 102>174 119>183 136>193 153>203 | 102>118 119>128 136>139 153>148 |
| 200x120 | 85>167 119>188 153>208 170>218 | 85>98 119>116 153>129 170>134 |
| 300x260 | 85>170 119>191 153>212 170>221 | 85>96 118>115 152>129 169>133 |
| 362x520 | 68>178 119>194 153>204 187>214 (center blurred) | 68>103 118>117 152>124 186>129 |

- The face is linear in encoded values up to the size where the frost reaches
  the center: slope ~0.6 light. The frost reaches about half the short side, so a
  large panel's center is blurred.
- The display's EDR state changes the isolated face (highlights compress
  when the headroom is 1.0), but the full default material read the same in
  both states.
- The face model `emission + transmittance * Y(1 + lift (1 - Y))` fits every
  curve within 0.2 - 1.3 levels. Clear keyframe, shader and
  `Ios27LiquidGlassColorModel`: light emission 114/255, transmittance 0.582,
  lift 0 up to 64 pt, 0.126 at 120 pt, 0.219 at 260 pt (linear between);
  dark emission 32/255, transmittance 0.600 / 0.415 and lift 0.667 / 1.31
  (controls up to 75 pt / surfaces from 105 pt), chroma gain 1.13 / 1.02
  (light 1.17 kept: measured 1.14 - 1.17). Error against the table: light
  max 0.5 - 2.8 (was 9 - 14), dark max 0.3 - 2.6 (was 7 - 13); the 260 pt
  rows carry the frost reaching the center. Middle and Tinted keyframes
  unchanged. The menu card's transmission gamma refits to 1.14 over the
  new large dark face (57 / 68 native, 55.7 / 68.1).

## Open / gaps

- Light audit (2026-10-03, simulator, liquid tier, glass_audit_test with
  `AUDIT_LIGHT=true AUDIT_OUT=<dir>`): layout matches (tab bar, segmented,
  controls, menu); the simulator shots are Display P3 encoded, so compare
  grays only (sRGB greens/blues read shifted: 0x34C759 -> 101,196,102).
  Plain fills agree (stepper 226, slider track 217 vs 218). The light
  GLASS material is off: a resting glass button body reads 251,251,252
  vs native 245,245,251 (too bright, not blue enough), the menu interior
  246,246,252 vs 249,249,255 (3 under). A renderer light-material fit
  is open; the final look check belongs on the phone.
- Popover arrow is drawn flat.
- `UIGlassEffect.tintColor` / tinted glass and `interactive = false` as a
  consumer API on arbitrary surfaces.
