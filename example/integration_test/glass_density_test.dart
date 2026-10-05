import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
/// AUDIT_REPORT=tmp/glass_density`). The tier is
/// `--dart-define=GALLERY_GLASS=<liquid|frosted|flat>` (liquid by
/// default), `--dart-define=AUDIT_RUNS=5` repeats every timed window. The
/// report keeps every run and the median of the runs' percentiles over
/// ACTIVE frames (build or raster above 0.3 ms), as the glass audit does,
/// plus the backdrop captures and offscreen layers of one resting and one
/// pressed frame per density (the layer tree of the profile build).
const int _runs = int.fromEnvironment('AUDIT_RUNS', defaultValue: 1);

const String _tierName = String.fromEnvironment(
  'GALLERY_GLASS',
  defaultValue: 'liquid',
);

/// The button counts the audit measures.
const List<int> densities = [1, 4, 8, 16, 32];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('glass density', (WidgetTester tester) async {
    final audit = _Density(binding, tester);
    binding.platformDispatcher.platformBrightnessTestValue = .dark;
    SchedulerBinding.instance.addTimingsCallback(audit.timings.addAll);
    await audit.run();
    File('${_Density.outDir.path}/report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(audit.report()),
    );
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}

/// The page of the density audit: [count] glass buttons in a fixed grid
/// over a list of coloured rows.
class DensityPage extends StatelessWidget {
  /// Creates the page with [count] buttons at [tier].
  const DensityPage({required this.count, required this.tier, super.key});

  /// The number of glass buttons.
  final int count;

  /// The glass tier the page is drawn at.
  final MorphGlassTier tier;

  /// The center of button [i] on a 402 pt wide screen.
  static Offset buttonCenter(int i) =>
      Offset(57 + (i % 4) * 96.0, 120 + (i ~/ 4) * 60.0);

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
          for (var i = 0; i < count; i++)
            Positioned.fromRect(
              rect: Rect.fromCenter(
                center: buttonCenter(i),
                width: 80,
                height: 44,
              ),
              child: MorphGlassButton(onPressed: () {}, child: Text('$i')),
            ),
        ],
      ),
    ),
  );
}

class _Density {
  _Density(this.binding, this.tester);

  static final Directory outDir = Directory(
    '${Directory.systemTemp.path}/glass_density',
  );

  final IntegrationTestWidgetsFlutterBinding binding;
  final WidgetTester tester;
  final List<ui.FrameTiming> timings = [];
  final Map<String, List<(int, int)>> _scenes = {};
  final Map<String, Map<String, int>> _layers = {};
  final Stopwatch _clock = Stopwatch();
  int _pointer = 300;

  MorphGlassTier get tier => MorphGlassTier.values.byName(_tierName);

  Future<void> settle([int ms = 900]) =>
      tester.pump(Duration(milliseconds: ms));

  Future<void> measure(String scene, Future<void> Function() body) async {
    for (var run = 0; run < _runs; run++) {
      await settle(300);
      final start = timings.length;
      await body();
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
    for (final n in densities) {
      runApp(DensityPage(key: ValueKey<int>(n), count: n, tier: tier));
      await settle(1500);
      _layers['n$n-rest'] = _countLayers();
      await measure('n$n-rest', _scroll);
      await measure('n$n-wave', () => _wave(n, sample: 'n$n-pressed'));
    }
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

  /// Presses every button in a wave: finger i lands two frames after
  /// finger i - 1 and lifts 25 frames after it landed.
  Future<void> _wave(int n, {required String sample}) async {
    const down = 25;
    final gestures = <int, TestGesture>{};
    final last = (n - 1) * 2 + down;
    for (var frame = 0; frame <= last; frame++) {
      for (var i = 0; i < n; i++) {
        if (frame == i * 2) {
          final gesture = await tester.createGesture(pointer: _pointer++);
          await gesture.down(
            DensityPage.buttonCenter(i),
            timeStamp: _clock.elapsed,
          );
          gestures[i] = gesture;
        } else if (frame == i * 2 + down) {
          await gestures.remove(i)!.up(timeStamp: _clock.elapsed);
        }
      }
      await tester.pump(const Duration(milliseconds: 8));
      if (frame == math.min(last, (n - 1) * 2 + 4) &&
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
      };
    }

    return {
      'tier': _tierName,
      'liquid_available': MorphGlassRenderer.liquidAvailable,
      'runs': _runs,
      'layers': _layers,
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
