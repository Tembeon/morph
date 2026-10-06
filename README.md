# morph

Identity-based, spring-driven, interruptible widget-to-overlay morphs
for Flutter, plus a liquid skin that fuses nearby surfaces into one
organic shape. No Navigator coupling.

<!-- hero.gif: the Card to page scene - a library card morphs into
     the full player and back, artwork travelling as a shared
     element. -->
<img src="doc/media/hero.gif" alt="morph hero" width="300">

> I build this for an app of mine, and the API develops in whatever
> direction that app needs. There is no pub.dev release; versions are
> GitHub tags following semver. If you build on it, pin a tag.

## Start with the example

A gallery of the widgets layer, one page per control: the segmented
control and tab bar lens, switch, slider, stepper, the menu button, glass
sheets, alerts, navigation bars, search and the date picker, each
checked against recordings of the real UIKit controls, with a slow-motion
toggle and a glass page that switches the renderer, appearance and
direction for the whole app. Live build:
<https://tembeon.github.io/morph/> (wasm, fake glass - the liquid
glass renderer needs Impeller and Flutter GPU, so a native build shows
the real one). API docs live next to it:
<https://tembeon.github.io/morph/docs/>.

```bash
cd example
flutter run -d macos   # or any device
```

Recipes and applied patterns live there, not in this README.

## Two layers, Flutter-style

- `package:morph/foundation.dart` - the engine: identity, flights,
  retargeting, the liquid skin. No opinions.
- `package:morph/widgets.dart` - widgets built on it that move like
  iOS Liquid Glass, measured from UIKit and checked against recordings
  of the real controls: `MorphSegmentedControl` and `MorphTabBar`
  (the liquid selection lens: tap, press, scrub), `MorphSwitch`,
  `MorphSlider`, `MorphStepper`, `MorphGlassButton`, `MorphMenuButton`
  (a button becomes its own menu), the bars - `MorphNavigationBar`,
  `MorphToolbar`, `MorphScrollEdgeEffect`, `MorphNavigationStack` (glass
  button groups that morph into each other as items change and screens
  push, large titles, the scroll edge effect); sheets with detents
  (`presentMorphSheet`: a floating glass sheet that docks edge to edge
  at the large detent, dragged between detents, flicked away, handing
  scroll drags to the sheet); alerts and action sheets
  (`showMorphAlert`, `showMorphActionSheet`: a glass popover growing out
  of its source); the search field (`MorphSearchField`, the bottom
  `MorphSearchToolbar` that rises above the keyboard, and
  `MorphSearchTabBar`, whose search tab turns into the field); the
  compact `MorphDatePicker`; `MorphPageControl`, `MorphProgressView`
  and `MorphActivityIndicator`; plus `MorphContextMenuRegion` (a held
  surface becomes its own context menu, satellites around it).
  Their motion objects
  (`MorphLensMotion`, `MorphSwitchMotion`, `MorphMenuMotion`, ...) are
  pure functions of explicit time and work without the widgets.

The engine never depends on the widget layer. The package ships
`MorphGlassRenderer` with flat, fake and liquid tiers;
`MorphAdaptiveGlass` installs it at one tier per session, chosen by the
device's GPU class, or uses an explicit tier. Liquid glass needs Impeller and Flutter GPU;
unsupported builds fall back to fake glass (the same layers without
refraction). Controls draw flat fills
without a painter. Custom painters still use `MorphGlass(painter:)`.
Every tier shades the outlines computed by the package. Looks resolve
from each control's `style`, then the `MorphWidgetsTheme` extension, then light and dark
tables from the iOS system colors.

## Performance: group neighbouring glass

Every separate glass layer is a backdrop filter: the engine reads the
backdrop under it, filters it and composites it, whatever its size -
about 0.3 - 0.75 ms of raster time per layer and frame on a Pixel 6a.
Apple's advice for Liquid Glass applies here too: group neighbouring
glass in one container. Wrap a row or cluster of glass buttons in a
`MorphGlassContainer` and their resting glass is shaded in one layer
(four resting buttons over a scrolling page: Pixel 6a raster -18
percent). Everything inside the container is content above its glass,
so put what the glass must show through under the container, not in
it; a pressed, faded or clipped button keeps its own layer.

The package groups glass on its own only where it owns everything
painted between the members: a `MorphListSection` shades the resting
glass buttons in its rows in one layer (a pressed row's button leaves
while its highlight shows), a resting `MorphSearchToolbar` its field
and side buttons. A container around a scroll view joins nothing in
it - wrap the content inside the scroll view instead.

`MorphGlassInspector` shows, in debug and profile builds, how many
glass layers each frame draws, who draws them, and which neighbouring
resting glass one container could shade together (or what keeps glass
out of the container it sits in); in release it is removed:

```dart
MaterialApp(
  builder: (context, child) => MorphGlassInspector(
    child: MorphScope(child: child!),
  ),
);
```

## Install

```yaml
dependencies:
  morph:
    git:
      url: https://github.com/Tembeon/morph.git
      ref: wip/measured-liquid-glass # unreleased; pin a semver tag for releases
```

One-time wiring - the scope goes above your app's Navigator:

```dart
MaterialApp(
  builder: (context, child) => MorphScope(child: child!),
);
```

Physics comes from [motor](https://pub.dev/packages/motor); its
minimal motion vocabulary is re-exported. The widgets are one import
away: `package:morph/widgets.dart`.

morph speaks the standalone
[material_ui](https://pub.dev/packages/material_ui) package, not the
in-SDK `package:flutter/material.dart`. The two are separate copies of
Material - their `Theme`, `ThemeData` and `ThemeExtension` are
different types - so an app on the in-SDK library either migrates with
`dart fix --apply --code=migrate_design_widgets` or wraps the morph
subtree in `MaterialUiCompatibilityBridge`.

## The API is a ladder

Each level is a complete integration on its own; climb only when a
screen needs more. Every public member is dartdoc'd - this is just the
map.

**1. A tag and a call** - wrap what you tap in `MorphTag`, call
`showMorphDialog` or `showMorphSheet`:

```dart
MorphTag(
  id: 'compose',
  shape: const StadiumBorder(),
  surfaceColor: Theme.of(context).colorScheme.primaryContainer,
  child: ComposeButton(),
);

// Anywhere inside the tag's subtree - the source is inferred:
showMorphDialog(context, builder: (context, flight) {
  return ComposeForm(onDone: flight.close);
});
```

Motion, scrim and shape come with defaults; scrim tap, Esc and the
Android back gesture close it. Most screens stop here. Pass
`modal: false` when the surface is a tool rather than a dialog: no
scrim at all, the page underneath stays live (a search field expanding
over the list it filters).

**2. State instead of calls** - `MorphAnchor(isOpen: ..., onDismiss:
...)`: the same morph, driven by your state instead of a call.

**3. Your own targets** - `MorphTargetSpec` places the destination
anywhere: popovers, docked panels, fullscreen - fixed boxes or sized by
their content, always clear of the keyboard. `MorphMotion` sets the
spring profile - `MorphMotion.liquid`, UIKit's measured morph spring,
is the default, `glacial` the same five times slower for the eye,
`instant` the reduced-motion one, `MorphMotion.springs` your own -
`MorphTheme` the app-wide defaults, `overlay:` picks
the overlay a flight renders in when chrome floats over a nested
navigator, and `flight.events` marks the moments for haptics.
([menu](example/lib/gallery/menu_page.dart),
[alerts](example/lib/gallery/alert_page.dart))

**4. Real pages and gestures** - `showMorphRoute` morphs into a real
route: back button, predictive back and pop results work, state
survives. `MorphSharedElement` flies content between the two sides,
and `flight.beginDrag`/`dragBy`/`endDrag` is a ready drag-to-dismiss.

**5. Raw parts** - `MorphController` is a standalone retargetable
spring, `MorphSkin` fuses widgets into one liquid mass, and the
gesture math is public.

At every level the same contract holds: re-showing retargets the
running animation instead of restarting it, and closing mid-open just
works.

## Claude skill

The API reference and the recipes, distilled for coding agents, ship
as the `use-morph` skill in my
[tem_tools](https://github.com/Tembeon/tem_tools) plugin marketplace:

```
/plugin marketplace add Tembeon/tem_tools
/plugin install morph@tem-tools
```

## License

[MIT](LICENSE), except the vendored glass renderer, derived from
[liquid_glass_renderer](https://github.com/whynotmake-it/flutter_liquid_glass)
by Tim Lehmann for whynotmake.it under [Apache-2.0](lib/src/glass/renderer/LICENSE).
Its [NOTICE](lib/src/glass/renderer/NOTICE) and
[VENDORED](lib/src/glass/renderer/VENDORED) record attribution and local
changes; adapted shaders retain Flutter's BSD and Inigo Quilez's MIT notices.
