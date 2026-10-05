import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The Android screenshot path talks to the plugin's channel directly.
// ignore: implementation_imports
import 'package:integration_test/src/channel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// The glass density audit on a device: N standalone [MorphGlassButton]s
/// on one plane over a scrolling page of coloured rows, N in
/// [densities], in two variants each - the buttons at rest while the page
/// scrolls under them (`n<N>-rest`), and every button pressed in a wave
/// while the page rests (`n<N>-wave`).
///
/// Build and run it like the glass audit (tool/ios_reference/perf/audit.sh
/// with `AUDIT_TARGET=integration_test/glass_density_test.dart
/// AUDIT_REPORT=tmp/glass_density`; on Android audit_android.sh with
/// `AUDIT_REPORT=glass_density`, which passes `AUDIT_OUT`). The tier is
/// `--dart-define=GALLERY_GLASS=<liquid|fake|flat>` (liquid by
/// default), `--dart-define=AUDIT_RUNS=5` repeats every timed window. The
/// report keeps every run and the median of the runs' percentiles over
/// ACTIVE frames (build or raster above 0.3 ms), as the glass audit does,
/// plus the backdrop captures and offscreen layers of one resting and one
/// pressed frame per density (the layer tree of the profile build).
///
/// A last untimed phase mounts [stressCount] smaller buttons on one
/// screen, presses all of them and fails the test when any glass layer's
/// geometry render failed over the whole run (`geometry_failures` in the
/// report): every layer must draw however many render in one frame.
const int _runs = int.fromEnvironment('AUDIT_RUNS', defaultValue: 1);

const String _tierName = String.fromEnvironment(
  'GALLERY_GLASS',
  defaultValue: 'liquid',
);

/// Whether the buttons sit in one [MorphGlassContainer]
/// (`--dart-define=DENSITY_CONTAINER=true`).
const bool _container = bool.fromEnvironment('DENSITY_CONTAINER');

/// Whether the run takes a resting and a held screenshot per density
/// (`--dart-define=AUDIT_SHOTS=true`), outside the timed windows.
const bool _shots = bool.fromEnvironment('AUDIT_SHOTS');

/// Whether every timed window also records the framework's BUILD /
/// LAYOUT / PAINT / COMPOSITING time per composited frame
/// (`--dart-define=DENSITY_PHASES=true`, profile builds).
const bool _phases = bool.fromEnvironment('DENSITY_PHASES');

/// The densities to run, comma separated (`--dart-define=DENSITY_NS=1,4`);
/// empty for all of [densities].
const String _only = String.fromEnvironment('DENSITY_NS');

/// The button counts the audit measures.
const List<int> densities = [1, 4, 8, 16, 32];

/// The button count of the stress phase, more geometry renders in one
/// frame than a uniform block holds.
const int stressCount = 96;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('glass density', (WidgetTester tester) async {
    final audit = _Density(binding, tester);
    binding.platformDispatcher.platformBrightnessTestValue = .dark;
    SchedulerBinding.instance.addTimingsCallback(audit.timings.addAll);
    final reportError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if ('${details.exception}'.contains('geometry render failed')) {
        audit.geometryFailures++;
      }
      reportError?.call(details);
    };
    await audit.run();
    FlutterError.onError = reportError;
    File('${_Density.outDir.path}/report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(audit.report()),
    );
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    expect(audit.geometryFailures, 0);
  });
}

/// The page of the density audit: [count] glass buttons in a fixed grid
/// over a list of coloured rows.
class DensityPage extends StatelessWidget {
  /// Creates the page with [count] buttons at [tier].
  const DensityPage({
    required this.count,
    required this.tier,
    this.compact = false,
    this.container = false,
    this.aligned = false,
    super.key,
  });

  /// Whether every button's box lies on whole device pixels.
  final bool aligned;

  /// Whether the buttons sit in one [MorphGlassContainer].
  final bool container;

  /// The number of glass buttons.
  final int count;

  /// Whether the buttons are the stress phase's smaller ones, 8 to a row,
  /// so that [stressCount] fit on one screen.
  final bool compact;

  /// The glass tier the page is drawn at.
  final MorphGlassTier tier;

  /// The center of button [i] on a 402 pt wide screen.
  static Offset buttonCenter(int i) =>
      Offset(57 + (i % 4) * 96.0, 120 + (i ~/ 4) * 60.0);

  /// The center of compact button [i].
  static Offset compactCenter(int i) =>
      Offset(28 + (i % 8) * 50.0, 80 + (i ~/ 8) * 44.0);

  /// The center of button [i] on this page.
  Offset centerOf(int i) => compact ? compactCenter(i) : buttonCenter(i);

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
    builder: (BuildContext context, Widget? child) =>
        MorphAdaptiveGlass(tier: tier, child: child!),
    home: Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView.builder(
              key: const ValueKey<String>('rows'),
              itemCount: 400,
              itemBuilder: (BuildContext context, int i) => SizedBox(
                height: 56,
                child: ColoredBox(
                  color: HSVColor.fromAHSV(
                    1,
                    (i * 37) % 360.0,
                    0.6,
                    0.4 + (i % 5) * 0.12,
                  ).toColor(),
                  child: Align(
                    alignment: .centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text('Row $i'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (container)
            Positioned.fill(
              child: MorphGlassContainer(child: Stack(children: _buttons())),
            )
          else
            ..._buttons(),
        ],
      ),
    ),
  );

  Rect _snap(Rect rect) {
    if (!aligned) return rect;
    final ratio = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    double on(double v) => (v * ratio).roundToDouble() / ratio;
    return Rect.fromLTRB(
      on(rect.left),
      on(rect.top),
      on(rect.right),
      on(rect.bottom),
    );
  }

  List<Widget> _buttons() => [
    for (var i = 0; i < count; i++)
      Positioned.fromRect(
        rect: _snap(
          Rect.fromCenter(
            center: centerOf(i),
            width: compact ? 44 : 80,
            height: compact ? 36 : 44,
          ),
        ),
        child: MorphGlassButton(onPressed: () {}, child: Text('$i')),
      ),
  ];
}

class _Density {
  _Density(this.binding, this.tester);

  static final Directory outDir = Directory(
    const String.fromEnvironment('AUDIT_OUT').isEmpty
        ? '${Directory.systemTemp.path}/glass_density'
        : const String.fromEnvironment('AUDIT_OUT'),
  );

  final IntegrationTestWidgetsFlutterBinding binding;
  final WidgetTester tester;
  final List<ui.FrameTiming> timings = [];
  final Map<String, List<(int, int)>> _scenes = {};
  final Map<String, Map<String, int>> _layers = {};
  final Map<String, List<Map<String, double>>> _phaseRuns = {};
  final Stopwatch _clock = Stopwatch();
  int _pointer = 300;

  /// Geometry renders that failed over the run.
  int geometryFailures = 0;

  MorphGlassTier get tier => MorphGlassTier.values.byName(_tierName);

  Future<void> settle([int ms = 900]) =>
      tester.pump(Duration(milliseconds: ms));

  Future<void> measure(String scene, Future<void> Function() body) async {
    for (var run = 0; run < _runs; run++) {
      await settle(300);
      final start = timings.length;
      if (_phases) FlutterTimeline.debugCollectionEnabled = true;
      await body();
      if (_phases) {
        final collected = FlutterTimeline.debugCollect();
        FlutterTimeline.debugCollectionEnabled = false;
        final composited = collected.getAggregated('COMPOSITING').count;
        double per(String phase) {
          var total = 0.0;
          for (final block in collected.aggregatedBlocks) {
            if (block.name.startsWith(phase)) total += block.duration;
          }
          return composited == 0 ? 0 : total / composited / 1000;
        }

        (_phaseRuns[scene] ??= []).add({
          'frames': composited.toDouble(),
          for (final phase in ['BUILD', 'LAYOUT', 'PAINT', 'COMPOSITING'])
            phase: per(phase),
        });
      }
      await settle(300);
      await tester.pump();
      await settle(100);
      (_scenes[scene] ??= []).add((start, timings.length));
    }
  }

  Future<void> run() async {
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    outDir.createSync(recursive: true);
    _clock.start();
    await MorphGlassRenderer.precache();
    for (final n in [
      for (final n in densities)
        if (_only.isEmpty || _only.split(',').contains('$n')) n,
    ]) {
      runApp(
        DensityPage(
          key: ValueKey<int>(n),
          count: n,
          tier: tier,
          container: _container,
        ),
      );
      await settle(1500);
      await shot('n$n-rest');
      _layers['n$n-rest'] = _countLayers();
      await measure('n$n-rest', _scroll);
      await measure('n$n-wave', () => _wave(n, sample: 'n$n-pressed'));
      await _held(n);
    }
    runApp(
      DensityPage(
        key: const ValueKey<String>('aligned'),
        count: 8,
        tier: tier,
        container: _container,
        aligned: true,
      ),
    );
    await settle(1500);
    await shot('n8-aligned');
    runApp(
      DensityPage(
        key: const ValueKey<String>('stress'),
        count: stressCount,
        tier: tier,
        compact: true,
        container: _container,
      ),
    );
    await settle(1500);
    _layers['stress-rest'] = _countLayers();
    await _wave(
      stressCount,
      sample: 'stress-pressed',
      at: DensityPage.compactCenter,
      step: 0,
    );
  }

  /// Holds button 0 for half a second and shoots the held frame.
  Future<void> _held(int n) async {
    if (!_shots) return;
    final gesture = await tester.createGesture(pointer: _pointer++);
    await gesture.down(DensityPage.buttonCenter(0), timeStamp: _clock.elapsed);
    await settle(500);
    await shot('n$n-held');
    await gesture.up(timeStamp: _clock.elapsed);
    await settle(900);
  }

  Future<void> shot(String name) async {
    if (!_shots) return;
    await tester.pump();
    if (Platform.isAndroid) {
      integrationTestChannel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'scheduleFrame') {
          ui.PlatformDispatcher.instance.scheduleFrame();
        }
        return null;
      });
      await integrationTestChannel.invokeMethod<void>(
        'convertFlutterSurfaceToImage',
      );
      await tester.pump();
      final bytes = await integrationTestChannel.invokeMethod<List<int>>(
        'captureScreenshot',
        <String, Object?>{'name': name},
      );
      await integrationTestChannel.invokeMethod<void>('revertFlutterImage');
      await tester.pump();
      if (bytes != null) {
        File('${outDir.path}/$name.png').writeAsBytesSync(bytes);
      }
      return;
    }
    final data = await binding.callbackManager.takeScreenshot(name);
    final bytes = (data['bytes']! as List<Object?>).cast<int>();
    File('${outDir.path}/$name.png').writeAsBytesSync(bytes);
  }

  Future<void> _scroll() async {
    const from = Offset(201, 800);
    for (var i = 0; i < 2; i++) {
      await _finger(from, _line(from, from - const Offset(0, 300), 40));
      await settle(700);
      await _finger(
        from - const Offset(0, 300),
        _line(from - const Offset(0, 300), from, 40),
      );
      await settle(700);
    }
  }

  /// Presses every button in a wave: finger i lands [step] frames after
  /// finger i - 1 and lifts 25 frames after it landed.
  Future<void> _wave(
    int n, {
    required String sample,
    Offset Function(int i) at = DensityPage.buttonCenter,
    int step = 2,
  }) async {
    const down = 25;
    final gestures = <int, TestGesture>{};
    final last = (n - 1) * step + down;
    for (var frame = 0; frame <= last; frame++) {
      for (var i = 0; i < n; i++) {
        if (frame == i * step) {
          final gesture = await tester.createGesture(pointer: _pointer++);
          await gesture.down(at(i), timeStamp: _clock.elapsed);
          gestures[i] = gesture;
        } else if (frame == i * step + down) {
          await gestures.remove(i)!.up(timeStamp: _clock.elapsed);
        }
      }
      await tester.pump(const Duration(milliseconds: 8));
      if (frame == math.min(last, (n - 1) * step + 4) &&
          !_layers.containsKey(sample)) {
        _layers[sample] = _countLayers();
      }
    }
    await settle(600);
  }

  Future<void> _finger(Offset from, List<Offset> path) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    await gesture.down(from, timeStamp: _clock.elapsed);
    await tester.pump(const Duration(milliseconds: 16));
    for (final p in path) {
      await gesture.moveTo(p, timeStamp: _clock.elapsed);
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up(timeStamp: _clock.elapsed);
    await tester.pump();
  }

  static List<Offset> _line(Offset a, Offset b, int n) => [
    for (var i = 1; i <= n; i++) Offset.lerp(a, b, i / n)!,
  ];

  /// The independent backdrop captures (a null key is its own capture, a
  /// shared key one for all its members), the backdrop filters and the
  /// offscreen layers the current layer tree adds to the scene.
  Map<String, int> _countLayers() {
    // The profile build keeps no debug layer; the root layer is the view's.
    // ignore: invalid_use_of_protected_member
    final root = binding.renderViews.first.layer;
    var independent = 0;
    var filters = 0;
    var offscreen = 0;
    final keys = <BackdropKey>{};
    void walk(Layer layer) {
      switch (layer) {
        // A glass layer's seed pass for an enclosing fractional opacity
        // leaves the scene unless it seeds (no engine layer).
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        case BackdropFilterLayer(:final backdropKey)
            when layer.engineLayer != null:
          filters++;
          offscreen++;
          if (backdropKey == null) {
            independent++;
          } else {
            keys.add(backdropKey);
          }
        case OpacityLayer(:final alpha?) when alpha < 255:
          offscreen++;
        case ImageFilterLayer() || ColorFilterLayer() || ShaderMaskLayer():
          offscreen++;
        case _:
          break;
      }
      if (layer is ContainerLayer) {
        for (
          var child = layer.firstChild;
          child != null;
          child = child.nextSibling
        ) {
          walk(child);
        }
      }
    }

    if (root != null) walk(root);
    return {
      'captures': independent + keys.length,
      'filters': filters,
      'offscreen': offscreen,
    };
  }

  Map<String, Object?> report() {
    double ms(Duration d) => d.inMicroseconds / 1000;
    double pick(List<double> v, double q) =>
        v[math.min(v.length - 1, (v.length * q).floor())];
    double median(List<double> v) {
      final sorted = [...v];
      sorted.sort();
      return sorted[sorted.length ~/ 2];
    }

    final budget =
        1000 / ui.PlatformDispatcher.instance.views.first.display.refreshRate;
    Map<String, double>? stats(List<ui.FrameTiming> all) {
      final frames = [
        for (final f in all)
          if (ms(f.buildDuration) > 0.3 || ms(f.rasterDuration) > 0.3) f,
      ];
      if (frames.isEmpty) return null;
      List<double> sorted(double Function(ui.FrameTiming f) of) {
        final values = [for (final f in frames) of(f)];
        values.sort();
        return values;
      }

      final build = sorted((f) => ms(f.buildDuration));
      final raster = sorted((f) => ms(f.rasterDuration));
      final span = sorted((f) => ms(f.totalSpan));
      return {
        'n': frames.length.toDouble(),
        'build_p50': pick(build, 0.5),
        'build_p95': pick(build, 0.95),
        'build_worst': build.last,
        'raster_p50': pick(raster, 0.5),
        'raster_p95': pick(raster, 0.95),
        'raster_worst': raster.last,
        'span_p95': pick(span, 0.95),
        'over_budget': frames
            .where(
              (f) =>
                  ms(f.buildDuration) > budget || ms(f.rasterDuration) > budget,
            )
            .length
            .toDouble(),
      };
    }

    return {
      'tier': _tierName,
      'liquid_available': MorphGlassRenderer.liquidAvailable,
      'runs': _runs,
      'geometry_failures': geometryFailures,
      'container': _container,
      'layers': _layers,
      'phases': _phaseRuns,
      for (final MapEntry(key: scene, value: windows) in _scenes.entries)
        scene: () {
          final runs = [
            for (final (start, end) in windows)
              ?stats(timings.sublist(start, end)),
          ];
          if (runs.isEmpty) return 'no frames';
          return {
            'median': {
              for (final key in runs.first.keys)
                key: median([for (final r in runs) r[key]!]),
            },
            'runs': runs,
          };
        }(),
    };
  }
}
