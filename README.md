# morph

iOS 27 Liquid Glass for Flutter: a tab bar with its lens, glass buttons,
menus that grow out of their button, context menus, sheets, alerts,
navigation bars, search, a date picker, lists and more.

Every spring, delay and threshold is measured on an iPhone and checked
against recordings of the native controls. Each control draws either
liquid glass or a flat look, and the app or its user picks which.

<table>
  <tr>
    <td align="center"><img src="doc/media/tab-bar-lens.gif" width="320" alt="The tab bar's lens lifts, slides across the tabs and refracts the badges under it"><br>Tab bar lens</td>
    <td align="center"><img src="doc/media/glass-button-menu.gif" width="320" alt="A glass button grows into its menu over clear glass and shrinks back"><br>Menu from a glass button</td>
  </tr>
  <tr>
    <td align="center"><img src="doc/media/context-menu.gif" width="320" alt="A held row lifts, shows reactions and opens its actions"><br>Context menu</td>
    <td align="center"><img src="doc/media/sheet-zoom.gif" width="320" alt="A sheet zooms out of its button, goes to its large detent and returns"><br>Sheet zoomed from its button</td>
  </tr>
</table>

Filmed on an iPhone 16 Pro running the example gallery in release mode.

> morph is built for my own apps, and its API follows what they need.
> It is not on pub.dev. Versions are git tags that follow semver, so pin
> one.

## Try the gallery

The example app has a page per control, a slow-motion switch and a glass
page that changes the tier, the appearance and the text direction for the
whole app.

- In the browser: <https://tembeon.github.io/morph/>. The web build draws
  flat glass; liquid glass needs a native build.
- API docs: <https://tembeon.github.io/morph/docs/>.
- On your machine:

  ```bash
  cd example
  flutter run
  ```

## Install

morph needs Flutter 3.47 or newer.

```yaml
dependencies:
  morph:
    git:
      url: https://github.com/Tembeon/morph.git
      ref: v0.8.0
```

One import covers the whole library:

```dart
import 'package:morph/morph.dart';
```

`package:morph/glass_painter.dart` is only for apps that paint their own
glass.

## Set up

Put a `MorphTheme` above your navigator and load the glass shaders before
the first frame:

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

`MorphThemeData` holds the brightness (null follows the platform), the
tint, haptics, the glass and per-control `appearances`. Menus, sheets and
alerts take the theme of the widget they open from. On `MaterialApp`, put
the theme in `MaterialApp.builder` and pass it
`Theme.of(context).brightness`. morph itself does not depend on Material.

Liquid glass runs on Impeller with Flutter GPU. Turn Flutter GPU on:

- iOS and macOS `Info.plist`: `FLTEnableFlutterGPU` set to `true`.
- Android `AndroidManifest.xml`, inside `<application>`:
  `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true" />`.

The package's build hook compiles the shaders. There is nothing else to
configure.

## Choose the glass

- `MorphGlassRenderer.adaptive()` picks once per session from the GPU.
  You get liquid glass on a capable GPU and flat glass on the OpenGL ES
  fallback, on Skia and on Apple GPUs older than the A13.
- `MorphGlassRenderer.tier(MorphGlassTier.flat)` or `.liquid` fixes the
  tier, for example from a user setting.
- Where liquid glass cannot load (the web, a build without Flutter GPU, a
  shader error), the controls draw flat. `MorphTheme.liquidGlassUnavailableReason`
  says why.

Shapes, motion and fusion are the same on both tiers. Only the shading
differs.

## Build with it

A tab bar with a badge, over a page that scrolls under its glass:

```dart
Stack(
  children: [
    Positioned.fill(child: pages[tab]),
    Align(
      alignment: Alignment.bottomCenter,
      child: MorphTabBar(
        items: const [
          MorphTabItem(icon: IconData(0xe318), label: 'Home'),
          MorphTabItem(
            icon: IconData(0xe567),
            label: 'Inbox',
            badge: MorphBadge.count(3),
          ),
        ],
        selected: tab,
        onChanged: (int index) => setState(() => tab = index),
      ),
    ),
  ],
);
```

A menu from any widget, on a tap, as `showsMenuAsPrimaryAction` does in
UIKit. A glass button takes the same `menu:` directly.

```dart
MorphMenuSource(
  menu: [
    MorphMenuItem(title: 'Copy', onSelected: copy),
    MorphMenuItem(title: 'Delete', destructive: true, onSelected: delete),
  ],
  child: const Text('Options'),
);
```

A context menu on a long press, as `UIContextMenuInteraction`:

```dart
MorphContextMenuRegion(
  menu: [MorphMenuItem(title: 'Reply', onSelected: reply)],
  child: MessageRow(message),
);
```

A sheet or a page that grows out of the widget that opened it. Name that
widget with a `MorphSourceLink`:

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
the presentation is popped, like `Navigator.push`. Back, the barrier and
Escape go through `PopScope`. If the source leaves the tree, the
presentation fades out instead of landing on it.

## Keep it fast

Each separate liquid glass layer reads and filters what lies under it. On
a Pixel 6a that costs about 0.3 to 0.75 ms of raster time per layer and
frame, whatever its size. Apple's advice for Liquid Glass applies here:
group neighbouring glass.

- Wrap a row or cluster of glass buttons in `MorphGlassContainer`. Their
  resting glass is then shaded as one layer (four resting buttons over a
  scrolling page: 18 percent less raster time on a Pixel 6a). Everything
  inside the container is content on top of its glass, so keep what the
  glass should show through below the container.
- `MorphGlassContainer(solidBackdrop: color)` says the glass sits on one
  opaque color, such as a card. The glass is then painted over that color
  and reads no backdrop at all.
- `MorphListSection`, a resting `MorphSearchToolbar`, the navigation bar
  and the tab bar group their own glass.

Resting glass in one `BackdropGroup` shares one copy of the screen. A card
of glass buttons drawn over other glass needs a `BackdropGroup` of its own
to show that glass through it.

## For coding agents

This repository is also a Claude Code plugin. Its `use-morph` skill
teaches agents the current API, from a reference generated from the
reviewed public API:

```
/plugin marketplace add Tembeon/morph
/plugin install morph@morph
```

## Working on morph

`CLAUDE.md` and `docs/` describe how the library is built and tested:
the engine, the widget pattern, the glass renderer, performance and the
test setup. Measurements of the native controls live in
`tool/ios_reference/spec/`.

## License

[MIT](LICENSE), except the vendored glass renderer, which is derived from
[liquid_glass_renderer](https://github.com/whynotmake-it/flutter_liquid_glass)
by Tim Lehmann for whynotmake.it under [Apache-2.0](lib/src/glass/renderer/LICENSE).
Its [NOTICE](lib/src/glass/renderer/NOTICE) and
[VENDORED](lib/src/glass/renderer/VENDORED) record the attribution and the
local changes. Adapted shaders keep Flutter's BSD and Inigo Quilez's MIT
notices.
