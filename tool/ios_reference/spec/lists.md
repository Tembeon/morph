# Lists passport (inset grouped sections and rows)

Status: measured simulator (layout + colors, light and dark); ported
(`MorphListSection`, `MorphListRow`, `MorphListStyle`, `MorphListMetrics`);
pinned by test/list_test.dart; rows' glass in one layer per section
(test/list_glass_stage_test.dart). Motion (highlight timing) not measured.

## Native

`UITableView(style: .insetGrouped)` (and SwiftUI `List` with the inset
grouped style), cells configured with `UIListContentConfiguration`
(`cell()`, `subtitleCell()`, `valueCell()`, `header()`, `footer()`),
`UIBackgroundConfiguration.listGroupedCell()`, accessories
`.disclosureIndicator`, `.checkmark`, `accessoryView` (UISwitch).

## Spec - geometry [layout, sim 402 pt]

- Card: 20 pt from the screen edges (table layout margin), corner radius 26
  (fitted to the screenshot outline within 0.3 pt; the layer reports
  continuous corners).
- Row: 53 pt single line; content margins 15 / 16 / 15 / 8 (top, leading,
  bottom, trailing); a 17 pt title over a 15 pt subtitle is 69.33 pt
  (content + 2 x 15.5). Title text starts 16 pt into the card.
- Value cell: detail 17 pt at the trailing edge, 16 pt from the card edge
  without an accessory; title-to-detail 8 (`textToSecondaryTextHorizontalPadding`).
- Accessories end 20 pt from the card edge (chevron 10.33 x 14 glyph box,
  UISwitch 63 x 28); the text stops 8 pt before them.
- Leading symbol: 22 pt glyph in a 28.67 pt image view centered 28 pt from
  the card edge, text and separator from 56 pt (`imageToTextPadding` 16).
- Separator: 1 pt (3 px at 3x), from the text leading edge to 16 pt before
  the trailing edge; the last row of a section has none.
- Header: 17 pt semibold, label 11.67 below the header's top, 6 above the
  card, 16 pt in. Footer: 13 pt regular, 7.67 below the card, 6.67 below the
  label. A card without a header starts 17.67 below the previous block, one
  without a footer ends 17.33 above the next (35 between two plain cards).

## Spec - colors [layout, sim, light / dark]

| role | light | dark |
|------|-------|------|
| page (systemGroupedBackground) | F2F2F7 | 000000 |
| card (secondarySystemGroupedBackground) | FFFFFF | 1C1C1E |
| highlighted / selected (systemGray4) | D1D1D6 | 3A3A3C |
| separator | 3C3C43 @ 0.12 | 545458 @ 0.5 |
| title (label) | 000000 | FFFFFF |
| subtitle, detail, header, footer (secondaryLabel) | 3C3C43 @ 0.6 | EBEBF5 @ 0.6 |
| chevron (rendered as tertiaryLabel: 197 over white, 90 over 1C1C1E) | 3C3C43 @ 0.3 | EBEBF5 @ 0.3 |
| leading symbol (tint) | 0088FF | 0091FF |

## Fixtures

`test/fixtures/ios27/list/list-tree-{light,dark}.txt` (manifest.txt),
screenshots `references/list/native-list-{light,dark}.png`.

## Recapture

Scene `list` (Sources/Lists.swift): `SIMCTL_CHILD_PROBE_SCENE=list
SIMCTL_CHILD_PROBE_DARK=0|1 xcrun simctl launch --terminate-running-process
booted dev.tembeon.morph.probe`, then pull Documents/list-tree-*.txt;
`PROBE_LISTSTYLE=plain` dumps a plain table instead.

## morph

lib/src/widgets/list.dart; typography roles `MorphTypography.body`,
`listSubtitle`, `listHeader`, `listFooter`. `MorphNavigationScaffold` gives
its content the body style.

## Glass in rows (package stage, 2026-10-06)

Not a UIKit measurement: how morph draws glass accessories (glass buttons
in a row's leading or trailing slot) on a section's card. The card fill
sits under a `MorphGlassStage`, so the resting glass of all its rows is
shaded in one layer, as UIKit's glass container would. Proof that nothing
the section paints between the stage and a member is read by it: resting
unfrosted glass samples only inside its own outline (refraction reaches
inward, frost 0, on the liquid and the fake tier), and the only thing a
row paints inside an accessory's outline is its highlight - a highlighted
row keeps its accessories out (`MorphGlassContainerBarrier`) until the
highlight goes. Text, separators (the row's own after its child, the
previous row's 15.5 pt above an accessory) and the header lie outside
every accessory. With `frostControls` the blur would read them, so the
stage closes. A row's own `child` content painted under its glass is
app content: option C applies (glass-renderer.md). Evidence:
test/list_glass_stage_test.dart, the gallery's Lists page and the audit's
`list` scene (glass-renderer.md "List sections").

## Not reproduced / open

- Highlight timing (UIKit delays the highlight inside a scroll view and
  fades the deselection): morph highlights on Flutter's tap-down, removes on
  release, no fade. Keyboard focus shows the highlight (unmeasured).
- Disabled cell look (no change drawn).
- A value cell whose title and detail do not fit side by side stacks them
  (`prefersSideBySideTextAndSecondaryText`); morph keeps them side by side
  and wraps the detail within half the row.
- Chevron glyph: a stroked polyline fitted to the 3x screenshot (2 pt
  stroke), not the SF Symbol.
- Card inset on other screen widths (only 402 pt read), Dynamic Type.

## API gaps

- Plain and grouped (non-inset) styles, swipe actions, reordering,
  checkmark accessory, section index, sliver form for long sections.
