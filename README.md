# morph

Flutter widgets that behave and look like iOS 27 Liquid Glass: the tab
bar and its lens, segmented control, switch, slider, stepper, glass
buttons, menus and context menus, navigation bars and stacks, sheets,
alerts, search, the date picker, lists and more. Springs, delays and
thresholds are read from UIKit on the device and checked against
recordings of the real controls. Every control works with liquid glass
or with a flat look, chosen by the app or by the end user.

> I build this for apps of mine, and the API follows what they need.
> There is no pub.dev release; versions are git tags following semver.
> If you build on it, pin a tag.

## Start with the example

The gallery has one page per control, a slow-motion toggle and a glass
page that switches the tier, appearance and text direction for the whole
app. Live build: <https://tembeon.github.io/morph/> (wasm, so flat glass;
a native build shows liquid glass). API docs:
<https://tembeon.github.io/morph/docs/>.

```bash
cd example
flutter run -d macos
```

## Install

```yaml
dependencies:
  morph:
    git:
      url: https://github.com/Tembeon/morph.git
      ref: v0.8.0 # a tag
```

Everything is one import:

```dart
import 'package:morph/morph.dart';
```

`package:morph/glass_painter.dart` is the seam for a custom glass
painter; an app on the built-in glass never needs it.

## Set up

Put a `MorphTheme` above the app's navigator and load the glass shaders
before the first frame:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MorphTheme.precacheGlass();
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

`MorphThemeData` carries the brightness (null follows the platform), the
tint, haptics, the glass and per-control `appearances`. Menus, sheets and
alerts carry the theme of the subtree they open from into their routes.
On `MaterialApp`, put the theme in `MaterialApp.builder` and pass it
`Theme.of(context).brightness`; morph itself does not depend on Material.

Liquid glass needs Impeller with Flutter GPU. Turn Flutter GPU on in the
app:

- iOS and macOS `Info.plist`: `FLTEnableFlutterGPU` set to `true`.
- Android `AndroidManifest.xml`, inside `<application>`:
  `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true" />`.

The package's build hook compiles the glass shaders into
`build/shaderbundles/`; nothing else to configure.

## Which glass is drawn

- `MorphGlassRenderer.adaptive()` picks once per session from the GPU:
  liquid glass on a capable GPU, flat on the OpenGL ES fallback, on Skia
  and on Apple GPUs older than the A13, where sampling the backdrop
  misses the frame budget.
- `MorphGlassRenderer.tier(MorphGlassTier.flat)` (or `liquid`) fixes the
  tier, for example from a user setting.
- Where the liquid tier cannot load (the web, a build without Flutter
  GPU, a shader failure), liquid draws flat glass.
  `MorphTheme.liquidGlassUnavailableReason` says why; the failure is also
  reported once through `FlutterError.reportError`. Until the shaders
  have loaded liquid is drawn flat too and turns liquid when they are
  ready: await `MorphTheme.precacheGlass()` before `runApp` so the first
  frame is liquid already.
- Without a theme that chooses glass, the controls draw flat.

The shapes, motion and fusion of every control are the same on every
tier.

## Presentations

A sheet, a zoomed page or a popover can grow out of the widget that
opened it. Name that widget with a `MorphSourceLink`:

```dart
final link = MorphSourceLink();

MorphSource(
  link: link,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  ),
  child: AlbumCard(album),
);

showMorphSheet<void>(
  context,
  from: link,
  detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
  builder: (context) => AlbumDetails(album),
);

Navigator.of(context).push(
  MorphNavigationRoute<void>(from: link, builder: (_) => AlbumPage(album)),
);
```

`showMorphSheet`, `showMorphAlert` and `showMorphActionSheet` return when
the presentation is popped, as `Navigator.push` does; the visual close
continues after that. Back, the barrier and Escape go through `PopScope`.
A presentation whose source leaves the tree dissolves instead of landing.

Menus need no wiring: `MorphMenuButton(menu: [...])`,
`MorphBarButton(menu: [...])` and `MorphContextMenuRegion(menu: [...])`
grow their menu out of themselves, with `MorphMenuItem`,
`MorphMenuSection`, `MorphSubmenu` and `MorphMenuDeferred` as entries.

## Performance: group neighbouring glass

Every separate glass layer is a backdrop filter: the engine reads the
backdrop under it, filters it and composites it, whatever its size,
about 0.3 to 0.75 ms of raster time per layer and frame on a Pixel 6a.
As Apple advises for Liquid Glass, group neighbouring glass: wrap a row
or cluster of glass buttons in a `MorphGlassContainer` and their resting
glass is shaded in one layer (four resting buttons over a scrolling
page: Pixel 6a raster -18 percent). Everything inside the container is
content above its glass, so put what the glass must show through under
the container. A `MorphListSection` and a resting `MorphSearchToolbar`
group their own glass.

Resting glass in one `BackdropGroup` shares one copy of the screen; a
card of glass buttons drawn over other glass needs a `BackdropGroup` of
its own to show that glass through it. See the `MorphTheme` docs.

## Claude skill

This repository is a Claude Code plugin marketplace. Its `use-morph`
skill (`plugins/morph`) teaches coding agents the current API, with a
reference generated from the reviewed public API:

```
/plugin marketplace add Tembeon/morph
/plugin install morph@morph
```

## License

[MIT](LICENSE), except the vendored glass renderer, derived from
[liquid_glass_renderer](https://github.com/whynotmake-it/flutter_liquid_glass)
by Tim Lehmann for whynotmake.it under [Apache-2.0](lib/src/glass/renderer/LICENSE).
Its [NOTICE](lib/src/glass/renderer/NOTICE) and
[VENDORED](lib/src/glass/renderer/VENDORED) record attribution and local
changes; adapted shaders retain Flutter's BSD and Inigo Quilez's MIT notices.
