# Migrating from older morph

morph 0.8 took UIKit's vocabulary and dropped the old engine. Code written
for 0.7 or earlier, or for the old use-morph skill, needs these changes.
The full list, with every renamed parameter, is CHANGELOG.md "0.8.0".

## Imports

| Old | New |
|---|---|
| `package:morph/widgets.dart`, `package:morph/foundation.dart`, `package:morph/motion.dart` | `package:morph/morph.dart` (one library) |
| custom glass painter types (`MorphGlassSurface`, `MorphGlassKind`, `MorphGlassOutline`, ...) | `package:morph/glass_painter.dart` |
| `motor` re-exports (`Motion`, `CupertinoMotion`, ...) | gone; morph has no `motor` dependency |

## The old engine and its widgets are gone

`MorphTag`, `MorphFlight`, `MorphController`, `MorphScope`, `showMorph`,
`showMorphRoute`, `showMorphDialog`, `MorphPageRoute`, `MorphTargetSpec`,
`morphAnchorRect`, `MorphAnchor`, `MorphSkin` and its pieces,
`MorphPiece`, `MorphPieceChannel`, `MorphSkinStyle`, `MorphMass`,
`MorphReveal`, `MorphSharedElement`, `MorphSharedFade`, the drag and
scrub APIs, `Tug`, `CoopTug`, `ChaseSpring`, `SpringButton`,
`MorphSurface` and `MorphTapTarget` no longer exist. Replace the
pattern, not the call:

| Old pattern | New |
|---|---|
| a tagged widget that morphs into a dialog or sheet (`MorphTag` + `showMorphDialog` / old `showMorphSheet`) | `MorphSource(link: link, child: ...)` + `showMorphSheet(context, from: link, builder: ...)` |
| a tagged card that morphs into a page (`showMorphRoute`, `MorphPageRoute`) | `Navigator.push(MorphNavigationRoute(from: link, builder: ...))`, or `MorphNavigationPage(from: link)` in a declarative stack |
| a control that becomes its own menu (`showMorphMenu`) | `MorphMenuButton(menu: [...])`, `MorphGlassButton(menu: [...])`, `MorphBarButton(menu: [...])` |
| long-press preview menus | `MorphContextMenuRegion(menu: [...], preview: ...)` |
| a liquid tab dock built from `MorphSkin` pieces | `MorphTabBar(items: [MorphTabItem(...)], ...)` |
| toolbar buttons merging on scroll (`MorphSkin`) | `MorphToolbar` / `MorphNavigationScaffold(toolbarLeading:, toolbarTrailing:)`; the bars fuse their capsules themselves |
| glass buttons on a rubber tether (`Tug`, `CoopTug`), `SpringButton`, `MorphSurface`, `MorphTapTarget` | `MorphGlassButton` (and `.prominent` / `.clear`); group neighbours in `MorphGlassContainer`; arbitrary content on glass with `MorphGlassEffect` |
| `MorphMotion` / spring tuning on widgets | internal: each control carries UIKit's measured springs |

## Theme and glass

| Old | New |
|---|---|
| `MorphWidgetsTheme`, `MorphWidgetsThemeScope`, the engine's `MorphTheme` extension | `MorphTheme(data: MorphThemeData(...))` above the navigator |
| `MorphAdaptiveGlass`, the renderer's statics | `MorphThemeData(glass: MorphGlassRenderer.adaptive())`, `MorphTheme.precacheGlass()`, `liquidGlassAvailable`, `liquidGlassUnavailableReason` |
| `MorphGlassTier.fake` | gone: the tiers are `flat` and `liquid` |
| per-control style objects | `Morph*Appearance` in `MorphThemeData.appearances` or a widget's `appearance:` |
| Material dependency | none: morph needs only `package:flutter/widgets.dart` |

## Common renames

| Old | New |
|---|---|
| `MorphSegmentedControl(segments: ['A'], selected:, sizeByContent:)` | `MorphSegmentedControl(segments: [MorphSegment('A')], selectedIndex:, proportionalWidth:)` |
| `MorphStepper.semanticValueFormatter` | `semanticFormatterCallback` |
| `MorphDatePicker.firstDate`, `lastDate` | `minimumDate`, `maximumDate` |
| `MorphDatePicker` formatter callbacks | `localizations: MorphDatePickerLocalizations(...)` |
| `MorphListSection(header: 'A', footer: 'B')` | `header: Text('A'), footer: Text('B')` |
| `MorphListRow(chevron: true)` | `accessory: MorphListAccessory.disclosureIndicator` |
| `MorphNavigationScaffold.largeTitle: true / false` | `largeTitleDisplayMode: MorphLargeTitleDisplayMode.always / .never` |
| `backTitle`, `backLabel` | `backButtonTitle`, `backButtonSemanticLabel` |
| `leading: MorphBarButtonGroup(...)` | `leading: [MorphBarButtonGroup(...)]` |
| `MorphBarButtonGroup(..., prominent: true)` | `style: MorphBarButtonStyle.prominent` |
| `MorphNavigationRoute(zoomSource:)`, `MorphSheetRoute(source:)`, `pushMorphZoom` | `from:` on `MorphNavigationRoute` / `MorphSheetRoute` |
| `MorphSearchTabBar(searching:, onSearchingChanged:)` | `active:`, `onActiveChanged:` |
| `MorphMenuButton(items:)`, `MorphMenuSource(items:)` | `menu:` |
| `MorphMenuItem(icon: Icons.x)` | `icon: Icon(Icons.x)` |
| `MorphContextMenuRegion(below: MorphSatellite(...))`, `above:` | `menu: [...]` (free-form rows as `MorphMenuWidget`), `accessory:` |
| `presentMorphSheet` | `showMorphSheet` |

When a symbol is missing, search `api.md` (generated from the current
public API) before guessing; anything not there is internal or gone.
