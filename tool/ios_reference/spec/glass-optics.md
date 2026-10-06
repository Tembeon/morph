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

glass.dart (seam: `MorphGlass`, `MorphGlassPainter` buildSurface / buildFill
/ buildLayer(spacing:, contentSlots:, outline:) / buildBody / buildGlow,
`MorphGlassSurface`, `MorphGlassKind`, `MorphGlassOptics`), glass_outline.dart
(`MorphGlassOutline`), glass_renderer.dart (`MorphGlassRenderer`,
`liftedOptics`, `MorphGlassTier`, `MorphGlassMaterial`), glass_tier.dart
(`MorphAdaptiveGlass`, `MorphGlassDeviceClass`), glass_liquid*.dart,
lib/src/glass/renderer (vendored whynotmake-it renderer, VENDORED + NOTICE).
Tests: glass_renderer_test, lifted_lens_look_test.

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
