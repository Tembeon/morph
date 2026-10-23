---
name: use-morph
description: This skill should be used when building Flutter UI with the morph package (Tembeon/morph), or when the user asks for iOS 27 / Liquid Glass controls in Flutter - "liquid glass tab bar", "iOS 26/27 glass buttons", "UIKit-like menu from a button", "context menu with preview", "iOS sheet with detents", "sheet that grows out of a card", "zoom transition to a page", "UIAlertController alert or action sheet", "glass search toolbar", "navigation bar with large titles", "inset grouped list", "segmented control / switch / slider / stepper like iOS", "flat vs liquid glass" - or mentions MorphTheme, MorphThemeData, MorphGlassRenderer, MorphTabBar, MorphGlassButton, MorphGlassContainer, MorphGlassEffect, MorphMenuButton, MorphMenuSource, MorphMenuItem, MorphContextMenuRegion, MorphBarButton, MorphToolbar, MorphNavigationStack, MorphNavigationScaffold, MorphNavigationRoute, MorphSource, MorphSourceLink, showMorphSheet, showMorphAlert, showMorphActionSheet, MorphSegmentedControl, MorphSwitch, MorphSlider, MorphStepper, MorphListSection, MorphListRow, MorphSearchToolbar, MorphDatePicker, MorphPageControl. Also for migrating old morph code (Tug, CoopTug, SpringButton, MorphTag, MorphSkin, showMorphMenu, showMorphDialog, package:morph/widgets.dart). Not for plain Material or Cupertino widgets.
version: 2.0.0
---

# morph: iOS 27 Liquid Glass widgets for Flutter

morph draws UIKit's iOS 27 controls in Flutter: the tab bar and its lens,
glass buttons, menus and context menus, navigation bars and stacks,
sheets, alerts and action sheets, search, the date picker, lists,
segmented control, switch, slider, stepper, page control and more.
Springs, delays and thresholds are read from UIKit and replayed against
device recordings, so use the controls as they are instead of rebuilding
their motion. Every control draws liquid glass or a flat look; the app
or its user picks.

Answer from this skill and its references before reading package
sources:

- `references/api.md`: every public type and function with its
  constructors and first dartdoc sentence (generated from the reviewed
  API, so it is current).
- `references/recipes.md`: copyable call sites for each control and
  presentation.
- `references/glass.md`: how the glass is chosen and composed, and the
  rules that keep it fast.
- `references/migration.md`: what replaced the old API (Tug, MorphTag,
  `widgets.dart`, ...).

## Install and import

```yaml
dependencies:
  morph:
    git:
      url: https://github.com/Tembeon/morph.git
      ref: v0.8.2 # pin a tag; there is no pub.dev release
```

One import: `import 'package:morph/morph.dart';`.
`package:morph/glass_painter.dart` is only for a custom glass painter.

## Set up (do this first)

```dart
void main() {
  runApp(
    WidgetsApp(
      color: const Color(0xFF007AFF),
      builder: (context, child) => MorphTheme(
        data: const MorphThemeData(glass: MorphGlassRenderer.adaptive()),
        child: child!,
      ),
      home: const HomePage(),
    ),
  );
}
```

- `MorphTheme` goes above the navigator (in `WidgetsApp.builder` or
  `MaterialApp.builder`). On `MaterialApp` pass
  `brightness: Theme.of(context).brightness` in `MorphThemeData`.
- The first `MorphTheme` loads the glass shaders and holds the app's
  first frame until they are ready (at most a second). No precache call
  is needed; `MorphTheme.precacheGlass()` only starts the load earlier.
- Liquid glass needs Impeller with Flutter GPU. iOS / macOS
  `Info.plist`: `FLTEnableFlutterGPU` = `true`. Android manifest inside
  `<application>`: `<meta-data
  android:name="io.flutter.embedding.android.EnableFlutterGPU"
  android:value="true" />`.
- Strings default to English (`DefaultMorphLocalizations`); to
  translate the back, close, search and dismiss labels, register a
  `LocalizationsDelegate<MorphLocalizations>` of your own.

## Controls, at a glance

| Want (UIKit) | Use |
|---|---|
| UITabBar, floating, with lens | `MorphTabBar(items: [MorphTabItem(...)], selected:, onChanged:)` |
| UIButton glass / prominent / clear | `MorphGlassButton`, `.prominent`, `.clear` |
| Joined glass buttons (GlassEffectContainer) | `MorphGlassContainer(child: Row(...))` |
| Any widget on glass | `MorphGlassEffect(child:, shape:, style:)` |
| UIMenu from a button | `MorphMenuButton(menu: [...])`, `MorphGlassButton(menu:)`, `MorphBarButton(menu:)` |
| Menu from any widget (`showsMenuAsPrimaryAction`, SwiftUI `Menu(label:)`) | `MorphMenuSource(menu:, child:)`; `trigger: MorphMenuTrigger.hold` with `onTap:` for tap-acts, hold-opens; `MorphMenuSource.open(context)` / `.close(context)` |
| Context menu with preview (`UIContextMenuInteraction`, any widget) | `MorphContextMenuRegion(menu:, preview:, child:)` |
| UINavigationController | `MorphNavigationStack(home:)` + `MorphNavigationScaffold` per page |
| Bar buttons / toolbar | `MorphBarButtonGroup([MorphBarButton(...)])`, `MorphToolbar` |
| Sheet with detents | `showMorphSheet(context, detents:, builder:)` |
| Zoom transition from a cell | `MorphSource(link:)` + `MorphNavigationRoute(from: link)` |
| UIAlertController | `showMorphAlert`, `showMorphActionSheet` |
| Search | `MorphSearchToolbar`, `MorphSearchField`, `MorphNavigationSearch` |
| Inset grouped list | `MorphListSection(children: [MorphListRow(...)])` |
| UISegmentedControl / UISwitch / UISlider / UIStepper | `MorphSegmentedControl`, `MorphSwitch`, `MorphSlider`, `MorphStepper` |
| UIDatePicker | `MorphDatePicker(value:, onChanged:, mode:, style:)` |
| UIPageControl / UIProgressView / spinner | `MorphPageControl`, `MorphProgressView`, `MorphActivityIndicator` |

Call sites for each: `references/recipes.md`. Exact parameters:
`references/api.md`.

## Rules that matter

1. Let morph draw the glass. Do not paint your own blur behind a morph
   control, and do not wrap glass in `Opacity`, `ClipRRect` or
   `ImageFiltered` between it and its parent: the control composes its
   glass with its neighbours and needs to see what lies under it.
2. Group neighbouring glass in a `MorphGlassContainer`: their resting
   glass is shaded in one layer instead of one per button. A
   `MorphListSection`, a resting `MorphSearchToolbar` and the bars group
   their own glass.
3. Presentations grow out of their source only through a
   `MorphSourceLink` on a `MorphSource`; without `from:` they present
   from the screen edge as UIKit does.
4. Set `MorphThemeData.fontFamily` for built-in app-font text; explicit
   appearance families win and native role sizes/weights remain. Style through `MorphThemeData.appearances` (one `Morph*Appearance`
   per control type) or each widget's `appearance:`; tint through
   `MorphThemeData.tint`. Do not fork a control to restyle it.
5. Pick the tier with `MorphGlassRenderer.adaptive()` (liquid on capable
   GPUs, flat elsewhere) or `MorphGlassRenderer.tier(MorphGlassTier.flat)`
   for a user setting. Shapes and motion are the same on both tiers.
6. `showMorphSheet`, `showMorphAlert` and `showMorphActionSheet` complete
   when the route is popped, as `Navigator.push` does; back, the barrier
   and Escape go through `PopScope`.

Custom content uses `MorphSegment.custom` (preview, cancel and re-tap
activation), `MorphTabItem.custom` (one primary glyph plus independent
visual replicas), and `MorphTouchTarget` with a passive `MorphTouchFeedback`.
`MorphMenuPresentationController.closed` observes completed dismissal;
`menuBuilder` resolves current actions when preparing an opening. A custom
chrome-over-navigator shell uses `MorphPresentationBoundary`. See recipes
and migration for the ownership contracts.

## When something looks wrong

- Glass is flat on a device that should draw liquid: read
  `MorphTheme.liquidGlassUnavailableReason`; check the Flutter GPU flag
  and that a `MorphTheme` with `glass:` sits above the controls.
- Glass shows black or the wrong content: something between the glass
  and its source paints with a layer (Opacity, clip, filter); move it
  outside, or give the glass its own `BackdropGroup` when it must show
  other glass through it (see `references/glass.md`).
- An old symbol does not exist: see `references/migration.md`.
