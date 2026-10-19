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
  picker title / weekday / day / compact roles. List roles (`body` 17
  regular, `listSubtitle` 15 regular, `listHeader` 17 semibold,
  `listFooter` 13 regular) come from lists.md [sim], not from this scene.
- Width parity: 25 labels within 0.01 pt ("Unread messages" segment 108.58
  pt; large title "Settings" 132.96). The device test gates at 1 pt per
  label; list roles and `datePickerDay` are not in its table.
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

- Text under an ANIMATING transform (glass-renderer.md "One glyph
  policy", 2026-10-12): at rest every label is drawn exactly as above
  (resolve, layout, raster). While its screen scale moves, one policy
  (`MorphGlyphPolicy`, carried out by `MorphGlyphs`) draws it from what
  it observes each frame: snapped to a grid of scales through the device
  pixel ratio while slow (64 steps per octave, 32 or 16 when the content
  is re-recorded every frame and the scale moves faster: at most 0.54 /
  1.1 / 2.2 percent off about the label's center, crisp glyphs; NEAR);
  from one raster of itself while it moves fast or under a blur >= 0.5
  pt (mipmapped, taken at the device pixel ratio up to 1.09x magnified;
  NEAR); blurred and faded through the pyramid shader on Android
  (`morphVeiledGlyphs`). None touches opsz / wght / tracking: the style
  and its layout are the rest style throughout.

## Fixtures / recordings

`tool/ios_reference/recordings/fonts-{sim,device}` (gitignored dumps).

## Recapture

Scene `fonts` (Sources/Typography.swift). morph parity on device:
example/integration_test/typography_parity_test.dart as a profile app,
pull `<app tmp>/typography_parity.txt`.

## morph

`lib/src/widgets/typography.dart` (`MorphTypography.resolve`, role
constants); host test `test/typography_test.dart` (table, axes, resolve);
device test `example/integration_test/typography_parity_test.dart`.

## Open / gaps

- Dynamic Type: Flutter's `TextStyle.getTextStyle` scales `fontSize` only,
  so under a text scale `opsz` and tracking stay those of the unscaled
  size; one linear factor for every role, no per-style curve
  (`UIFontMetrics`). Per-control scale caps have no native source
  (api/cross-cutting.md).
- Bold Text: `MediaQuery.boldText` is not read; the explicit `wght` axis
  likely masks the bold weight `Text` merges in (inferred, not run).
- Text styles beyond the control roles (title1-3, headline, callout,
  subheadline, footnote, caption1-2) are not measured.
- Date wheel 22 pt resolved like any label, not measured.
- GRAD axis.
