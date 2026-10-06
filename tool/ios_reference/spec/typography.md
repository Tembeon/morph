# Typography passport

Status: measured device == simulator (to 0.001 pt); ported
(typography_test, device parity test).

## Native

UIKit labels of each control, system font (SF Pro) through CoreText:
optical size axis `opsz` = point size (17..28 effective), size-dependent
tracking from the `trak` table, wght medium 510 / semibold 590.

## Spec

- Flutter's iOS default font (null family == '.AppleSystemUIFont' ==
  'CupertinoSystemText') is SF Pro at opsz 17 with NO tracking at every
  size. `FontVariation('opsz'/'wght')` on the null family works on iOS;
  letterSpacing = tracking(size) then matches CoreText to 0.01 pt.
- Tracking measured 6 - 96 pt, e.g. 13 pt -0.076, 17 pt -0.431, 34 pt
  +0.382 (`MorphTypography.tracking`).
- Medium/semibold are wght 510/590, not 500/600 (0.3 pt over 15 chars).
- Roles (size + weight): segments 13 regular, selected 13 medium (+ GRAD
  466/448, not reproduced); tab titles 10 medium, selected semibold; glass
  button and menu rows 17 regular; bar buttons 17 medium (prominent
  semibold); nav title 17 semibold; large title 34 bold; alert title 17
  semibold, message 15 regular, actions 17 medium; search 17 medium; date
  picker title / weekday / day / compact roles.
- Width parity: 25 labels within 0.01 pt ("Unread messages" segment 108.58
  pt; large title "Settings" 132.96).
- Apple platforms only (macOS CoreText path inferred, not measured);
  elsewhere `resolve` adds no axes or tracking. Caller `letterSpacing` /
  `fontVariations` win; custom families untouched.
- Every resolved style is COMPLETE (`inherit: false`) on every platform:
  a label never merges with the ambient DefaultTextStyle. Labels mounted
  in an overlay with no Material above it (the nav bar back menu's
  vessel in the root overlay, 2026-10-03 owner report) used to pick up
  MaterialApp's missing-style fallback (yellow double underline,
  monospace), and a TextPainter measuring the style saw something else
  than what was painted. Pinned by test/overlay_text_style_test.dart
  (every overlay of the widget layer in a bare WidgetsApp whose ambient
  style is that fallback).

- Text under an ANIMATING scale (2026-10-06, glass-renderer.md "Glyph
  atlas"): at rest every label is drawn exactly as above (resolve,
  layout, raster). While a lens copy lifts or sets down, its labels'
  screen scale snaps to a 64-steps-per-octave grid through the device
  pixel ratio (`MorphGlyphScale`, at most 0.54 percent of the distance
  from the slot center, crisp glyphs); while the menu's content blur is
  >= 0.5 pt its root rows draw from one raster at the device pixel
  ratio (`MorphGlyphRaster`, mipmapped). Neither touches opsz / wght /
  tracking: the style and its layout are the rest style throughout.

## Fixtures / recordings

`tool/ios_reference/recordings/fonts-{sim,device}` (gitignored dumps).

## Recapture

Scene `fonts` (Sources/Typography.swift). morph parity on device:
example/integration_test/typography_parity_test.dart as a profile app,
pull `<app tmp>/typography_parity.txt`.

## morph

typography.dart (`MorphTypography.resolve`, role constants).

## Open / gaps

- Dynamic Type (letterSpacing does not scale with the TextScaler).
- Date wheel 22 pt resolved like any label, not measured.
- GRAD axis.
