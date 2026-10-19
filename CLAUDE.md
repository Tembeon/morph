# morph

Flutter widgets that behave and look like iOS 27 Liquid Glass, plus the engine under them:
spring-driven, interruptible morphs from an inline widget to an overlay (dialog, sheet,
page, menu), a "liquid" skin that fuses nearby surfaces into one shape, and a measured
widget layer (tab bar, segmented control, switch, slider, stepper, buttons, menus, bars,
sheets, alerts, search, date picker, lists, ...). No Navigator coupling. Physics is Flutter's
spring simulation with UIKit's own measured tuning.

Not on pub.dev (`publish_to: none`); releases are git tags following semver, and the API
follows the owner's app. Owner-local context lives in `CLAUDE.local.md` (untracked).

## Goal

The package is meant for MASS use by app developers, who should not have to optimize
anything themselves.

- Every widget works with either renderer, chosen by the app or the end user: the glass
  renderer (liquid glass) or the flat one. Some users want iOS physics without glass,
  others want everything iOS. Both stay supported.
- Performance target: on the Pixel 6a (Mali-G78, Vulkan, 60 Hz, 16.67 ms budget) the app
  holds 60+ fps everywhere, ideally with headroom toward 120 fps, because weaker devices
  exist.
- Fidelity is traded for performance wherever the eye does not notice. Every such trade is
  declared (identical / near / approximation) in the dartdoc and the passport and is
  approved by eye on the iPhone. Frame time comes first; energy is measured and modest
  increases are acceptable for a real frame-time win.
- There is no layer purity to protect. Physics (engine), widgets and the glass renderer may
  know each other when that makes a surface right or fast. Prefer one general Flutter
  mechanism over a special case; prefer fewer moving parts over fragmentation.

## Spec and evidence

- The measured iOS behaviour is the spec: springs, delays, gains and thresholds in `lib/`
  are read from UIKit tuning on the device or fitted to recordings, and tests replay those
  recordings. A number carries its source in its dartdoc. Nothing is hand-tuned to look
  native without a measurement; a deviation for performance follows the rule above.
- `tool/ios_reference/spec/README.md` holds the protocol; one passport per control or
  family sits beside it. Read the passport of the control you touch. When a measurement
  changes, update the passport AND the tuning class dartdoc in the same change.
- References for ideas and optimizations: `tool/audit/` (research and experiment
  reports), `docs/research/`, the experiment branches in `docs/performance.md`, the
  native lab in `tool/ios_reference/lab`. Old reports are evidence, not instructions.

## Devices

- iPhone 16 Pro (iOS 27): measuring native behaviour, visual parity of ported widgets.
  `example/ios` runs the gallery. Lock: `/tmp/morph-native/device.lock`.
- Pixel 6a (adb serial 26221JEGR12737): the weak-Android performance device. Lock:
  `/tmp/morph-native/pixel.lock` (a directory made with `mkdir`, with an `owner` file).
  Never run two device scripts at once; one timing run owns the phone.
- macOS: desktop correctness. Windows and Linux use Impeller too, so macOS stands in for
  them.
- Never touch a phone without its lock. The Mac belongs to the owner: no GUI apps or
  simulators that steal focus without asking.

## Where things are

- `lib/morph.dart` - the one public library: controls, presentations, theme and glass
  choice. `lib/glass_painter.dart` - the custom painter seam. Public names are `Morph*`.
  Tests and the example's dev tools import `lib/src/` directly. `test/api/public_api.txt`
  is the reviewed API; its test also rejects internal types in public signatures, so
  tunings, metrics and test hooks on public widgets are `@internal` parameters.
- `lib/src/` engine (flights, targets, routes, liquid skin, scope), `lib/src/widgets/`
  measured controls (pure motion class + thin host + appearance tables),
  `lib/src/glass/renderer/` the one vendored glass renderer (tiers flat / fake / liquid).
- `example/` is the measured gallery (also the device benches under `example/lib/perf/`).

Read only the doc you need:

| doc | for |
|---|---|
| `docs/engine.md` | flights, targets, routes, skin, scope: contracts of the engine |
| `docs/engine-rules.md` | invariants, API and structural conventions, rejected approaches |
| `docs/widgets.md` | the control pattern and widget-layer machinery |
| `docs/glass.md` | glass seam, surfaces channel, backdrop groups, renderer contract |
| `docs/performance.md` | targets, harnesses, shipped optimizations, lessons, rejected experiments |
| `docs/testing.md` | verification, example app, test traps, lints and doc rules |

## Rules for every session

- Dart style: no cascades (`..`) in new code; dot shorthands and pattern matching where the
  context type is known; `Object?` not `dynamic`; comments only for the why, never the what;
  dartdoc speaks to the consumer in the present tense (history goes in commit messages).
- `flutter analyze` stays at zero; `public_member_api_docs` is on.
- `lib/` imports no Material, Cupertino or motor (architecture_test). Tests
  and the example use `package:material_ui/material_ui.dart`, never
  `package:flutter/material.dart` (separate copies of Material).
- Packaging: the pubspec asset entry for `build/shaderbundles/` must stay; verify on a
  native device.
- SDKs: normal commands use Flutter 3.47.2 stable; `flutter-beta` / `dart-beta` select the
  3.49 pre-release used for current optimization work.
- A performance change is admitted on evidence: device frame time AND energy, native pixels
  checked (host tests cannot run shaders; use the device parity run), and sustained use. Do
  not merge a path only because CPU or raster timing improved. Use `/usr/bin/grep` whenever
  a negative result is a conclusion.
- READ a file before writing to it (CHANGELOG.md has been overwritten by mistake once).

## Verification

```bash
dart format lib test example/lib example/test && flutter analyze
flutter test && (cd example && flutter test)
```

Glass, shader or composition changes also run the host Impeller tests, which pass
silently without these flags (`docs/testing.md`):

```bash
cd example && flutter test --enable-impeller --enable-flutter-gpu test/*_host_test.dart
```

Scope the rest (macOS release build, autodemo, web build, device runs) to the change; see
`docs/testing.md`.
