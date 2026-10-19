# Testing, example app and documentation rules

## Verification

```bash
dart format lib test example/lib example/test && flutter analyze
flutter test && (cd example && flutter test)
cd example && flutter build macos --release
cd example && flutter run -d macos --dart-define=MORPH_AUTODEMO=true
cd example && flutter build web --wasm   # the liquid tier compiles to stubs there
```

Scope the run to the change:

- `lib/` change: format, analyze, both test suites; add the macOS release build and the
  autodemo when a widget, flight or route changed.
- Shader or `tool/` change: the offline gate (`tool/audit/shader/offline.py`), the
  relevant host tests, and a device parity run (`tool/audit/shader/run_pixel.sh`).
- Docs only: format and analyze are enough.

`flutter analyze` from the package root also covers `example`; it stays at zero. Use
`nice -n 10 flutter test -j 2` when the Mac is shared. `dart doc --dry-run` reports zero
warnings.

Autodemo (`--dart-define=MORPH_AUTODEMO=true`): every gallery page in turn - push, center
tap, horizontal drag, upward scroll, pop home - then the app exits. Green means no
EXCEPTION in the log and `AUTODEMO done` at the end.

Motion fidelity is judged by the replay tests against the recordings; the eye judges on
glacial / slow-mo and, for widgets, on the iPhone next to the native controls.

## Example app

The example is the measured gallery (`example/lib/gallery/`): one `MorphNavigationStack`
whose pages are `GalleryPage` scaffolds and list sections (no Material Scaffold, AppBar
or ListTile). `example/lib/main.dart` runs `GalleryApp`, so a plain `flutter run` opens
it.

- One page per measured widget family, plus the Glass renderer page (tier, material,
  dark, RTL, disabled, inspector toggle) and Size to physics (`spec_inspector`).
- A SLOW-MO toggle cycles `timeDilation` 1x/5x/10x. Motion runs on ticker time, the flex
  filters step on the sub-clock in the same time and touches are stamped on it, so the
  widgets slow down as a whole; only the finger keeps real time.
- The gallery root installs `GlassAdaptiveScope` with the session's
  `MorphGlassRenderer` (`glass_settings.dart`); `liquid_glass.dart` keeps only
  `precacheLiquidGlass()`.
- A morph must TRANSFORM IDENTITY (the thing you touch becomes the surface you use);
  spring-skinning ordinary controls is animation, not morph.
- Entry points: `--dart-define=MORPH_AUTODEMO=true` (`lib/autodemo.dart`),
  `--dart-define=MORPH_BENCH=true` (`ReleaseBenchApp`, `lib/perf/release_bench.dart`).
  Device harnesses (profile builds launched with devicectl or adb) live in
  `example/integration_test/` and `example/lib/perf/`; the passports list them.
- `example/ios/` (bundle `dev.tembeon.morphExample`, team 83S63575XD) runs the gallery on
  the owner's iPhone next to the native controls.
- Layout: `gallery/` (one file per page plus glass settings and painters), `perf/`,
  `autodemo.dart`, `main.dart`. Tests that replay fixtures live in the PACKAGE (`test/`),
  fixtures under `test/fixtures/`.

## Test traps

- `tester.getSize` reads the LAYOUT size and ignores paint transforms; a press lift or any
  Transform shows only in `tester.getRect`.
- The first tick after a ticker (re)start evaluates at t = 0, so a sample right after a
  start or retarget needs one more pump. A size change reported post-frame starts its
  spring on the NEXT pump, whose first tick is at t = 0, so a mid-value sample needs
  `pump()` + `pump(16ms)` + `pump(N)`.
- A tag dropped by a build is only DEACTIVATED that frame and unmounts at the frame's
  end, so `MorphFlight.isSourceLost` reads true one frame later.
- A broadcast-stream subscription made after an `await` misses what was queued before it.
- `find.byKey(heroKey).last` in a context-menu test is the shuttle's GHOST replica; the
  slot copy is the one under the menu's Column.
- `FlightSprings.instant` is a 281 ms critically damped spring, not a cut.
- A live widget that replaces a stock one subclasses it; tests find it with
  `find.bySubtype`, or by the live type when it is a new widget (for example
  `MorphLiveTransform`). A test that looks for `Transform` or `AnimatedBuilder` breaks
  when a build-per-tick widget becomes a live render object.
- Widget-layer hosts pick their sub-clock rate from the test display's refresh rate (60 in
  flutter_test), while device replays pass 120 explicitly to the pure motion; a widget
  test and a 120 Hz replay of the same gesture differ in deformation by design.
- Replays must step every frame the recorder missed. A replay feeds the recorded touches
  into the PURE motion class at their recorded times and compares geometry per frame
  within per-quantity tolerances: a red replay is a fidelity regression, never a flaky
  test, and tolerances are not knobs.
- A plain `flutter test` has no Impeller: the liquid tier builds its real tree but its
  layers paint their content without glass, so those tests cannot judge shader output or
  count glass backdrop filters (count the layers that hold shapes instead).
- The example's `*_host_test.dart` files render real liquid glass on the host's Impeller
  (the same runtime-effect SPIR-V the Pixel runs, on a software rasterizer) and return
  at once without it, so a plain run passes them silently. Any change under
  `lib/src/glass`, to a shader, or to how a control composes its glass runs them:

  ```bash
  cd example && flutter test --enable-impeller --enable-flutter-gpu test/*_host_test.dart
  ```

  flutter test caches compiled shaders in `example/build/unit_test_assets` and misses an
  edit to an included `.glsl`: delete that folder after editing a shader include. The
  shader parity oracle compares the live final pass with
  `example/shader_audit/baseline`; after a deliberate change of the pass's output or
  uniforms, verified by the other oracles, freeze it again with
  `tool/audit/shader/freeze_baseline.py` and name the change in the commit. Device pixel
  identity is `tool/audit/shader/parity.py`.
- Tracing-pipeline changes also run `flutter test benchmark/liquid_benchmark_test.dart`
  (JIT numbers, relative before/after only).

## Lints and documentation

- One strict `analysis_options.yaml` at the package root (strict-casts, strict-inference,
  strict-raw-types, `always_use_package_imports`, `prefer_final_locals`,
  `no_default_cases`, `avoid_catches_without_on_clauses`, ...); the example includes it.
- `public_member_api_docs` is on: every public member of the package carries a dartdoc,
  including unexported `src/` machinery. The lint is the coverage gate.
- No cascades (`..`) in new code: the parser glues a `..` section onto a preceding
  expression-bodied lambda. Existing cascades may stay where a receiver is configured at
  construction; actions a test asserts on are plain statements.
- Dot shorthands (`.center`, `motion: .liquid`) and pattern matching (switch expressions,
  if-case) are the house style where the context type is known. There is no built-in lint
  for shorthands; for a sweep, temporarily add the `prefer_shorthands` analyzer plugin
  (known false positive: `Object.hashAll` in an int context).
- Dartdoc speaks to the consumer in the present tense: behavior, contract, the constraint
  the code cannot show, and in the widget layer the measurement a value comes from. Design
  history and bug archaeology live in commit messages. Effective Dart style: one-sentence
  summary first, noun phrases for properties, square brackets only for resolvable
  identifiers (ranges like `[0, 1]` are backticked), no caps-shouting.
- CHANGELOG entries: `## X.Y.Z - DATE`, a prose lead saying what the release IS, then
  bullets; BREAKING inline in the bullet it belongs to. READ the file before writing to it.
- When a measurement changes, update the passport AND the tuning class dartdoc in the same
  change.
