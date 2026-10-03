# Skin merge law passport (liquid fusion)

Status: measured on device (UIKit and SwiftUI agree); ported; replayed
(liquid_apple_merge_test 0.17 - 0.32 pt rms = screenshot noise floor).

## Native

`UIGlassContainerEffect` (`spacing`), SwiftUI
`GlassEffectContainer(spacing:)`, `glassEffectID`, `glassEffectUnion`;
rendered by `CASDFLayer` + `CASDFElementLayer` (smoothness == spacing).

## Spec

- Mix-form polynomial smooth-min with a PER-SAMPLE width
  k' = k (1 - dot(na, nb)) / 2 = k sin^2(theta/2), na/nb unit normals of the
  two operands: facing surfaces blend over the full k, side-by-side edges
  not at all (aligned tops stay STRAIGHT). Necks: m = 4(a - 0.40)/spacing ==
  sin^2(theta/2) within 1 percent.
- k (blend) == container spacing, 1:1 in logical px: facing surfaces lean
  toward each other below a gap of k and touch at k / 2; blend depth at the
  middle of a facing gap ~k/4.
- Compare at the field's 0.40 level (Apple's tint fill sits ~0.4 pt outside
  the SDF zero).
- SwiftUI default spacing 8 (`MorphSkinStyle.subtle`). Bars use 12 (see
  bars.md). Menu container: smoothness 0 + Gaussian-blurred field (see
  menu-button.md).
- Births (`glassEffectID` per-frame rects): born at 0.2 of size at the final
  center, `birthSpring` 0.492/0.711 (peak ~3 percent over at 0.38 s,
  settled by 0.7 s); leaves the same way, parked inside the survivor.
- Rejected: plain smin (lifts aligned edges by k/4, rms 9 pt at spacing 80);
  the renderer's sin(theta/2) chord (necks +0.5..+8 pt too fat).

## Fixtures

`ios27-device/merge/` (profiles-uikit.json, profiles-swiftui.json,
necks.json, sdf-layers.json, dynamic.json, fit-per-pair.json,
merge-params.json). References `references/merge/*.png`.

## Recapture

Scenes `merge`, `mergeDyn`, `mergeID` (Merge.swift): `PROBE_API=uikit|
swiftui`, `PROBE_BG=grey|stripes`, `PROBE_TINT=1`, `PROBE_SPACING`,
`PROBE_SPACINGS` (device.sh default 0,10,20,40,80), `PROBE_GAPS`. Device
plans `merge`, `mergedyn`. Scene: capsules 60x44 at x 110, circles 44x44 at
x 300, rows y = 150 + 80 i for gaps [40,30,20,15,10,6,3,0,-5].

## morph

lib/src/liquid_field.dart (`liquidMergeWidth`, `_FieldSampler`,
clustering), lib/src/skin.dart (`MorphSkin`, `MorphPiece`,
`MorphPieceChannel.birthScale/birthSpring`). Tests: liquid_apple_merge_test,
liquid_regression_test, liquid_geometry_golden_test, liquid_fuzz_test.

## Open

- 3+ masses: normals mixed by the smin weight (natural fold, unmeasured).
- Dynamic necks during drags vs the static law: see dynamic.json.
