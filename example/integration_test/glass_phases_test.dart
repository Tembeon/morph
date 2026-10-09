import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// Where the UI thread's frame goes on a device: the framework's own
/// BUILD, LAYOUT, PAINT and COMPOSITING blocks (FlutterTimeline, profile
/// builds only) per composited frame while glass controls move, next to
/// the FrameTiming build percentiles.
///
/// Build and run it like the glass audit (tool/ios_reference/perf/audit.sh
/// with `AUDIT_TARGET=integration_test/glass_phases_test.dart
/// AUDIT_REPORT=tmp/glass_phases`); `--dart-define=GALLERY_GLASS=tier`
/// (liquid by default) and `--dart-define=AUDIT_RUNS=n` as there. The
/// collection itself costs a little per block, the same in every build it
/// compares.
const int _runs = int.fromEnvironment('AUDIT_RUNS', defaultValue: 1);

const String _tierName = String.fromEnvironment(
  'GALLERY_GLASS',
  defaultValue: 'liquid',
);

const List<String> _phases = [
  'BUILD',
  'LAYOUT',
  'UPDATING COMPOSITING BITS',
  'PAINT',
  'COMPOSITING',
  'FINALIZE TREE',
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('glass phases', (WidgetTester tester) async {
    final dir = Directory(
      const String.fromEnvironment('AUDIT_OUT').isEmpty
          ? '${Directory.systemTemp.path}/glass_phases'
          : const String.fromEnvironment('AUDIT_OUT'),
    );
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    binding.platformDispatcher.platformBrightnessTestValue = .dark;
    final timings = <ui.FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);
    await MorphGlassRenderer.precache();
    final tier = MorphGlassTier.values.byName(_tierName);
    final report = <String, Object?>{
      'tier': _tierName,
      'liquid_available': MorphGlassRenderer.liquidAvailable,
    };
    var pointer = 400;
    Future<void> drag(Offset from, List<Offset> path) async {
      final gesture = await tester.createGesture(pointer: pointer++);
      await gesture.down(from);
      await tester.pump(const Duration(milliseconds: 120));
      for (final p in path) {
        await gesture.moveTo(p);
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 600));
    }

    List<Offset> line(Offset a, Offset b, int n) => [
      for (var i = 1; i <= n; i++) Offset.lerp(a, b, i / n)!,
    ];

    Future<void> scene(
      String name,
      Widget page,
      Future<void> Function() body,
    ) async {
      const only = String.fromEnvironment('PHASES_ONLY');
      if (only.isNotEmpty && !only.split(',').contains(name)) return;
      runApp(_App(tier: tier, child: page));
      await tester.pump(const Duration(milliseconds: 1500));
      final runs = <Map<String, double>>[];
      for (var run = 0; run < _runs; run++) {
        await tester.pump(const Duration(milliseconds: 300));
        final start = timings.length;
        FlutterTimeline.debugCollectionEnabled = true;
        await body();
        final collected = FlutterTimeline.debugCollect();
        FlutterTimeline.debugCollectionEnabled = false;
        await tester.pump(const Duration(milliseconds: 300));
        final frames = [
          for (final f in timings.sublist(start))
            if (f.buildDuration.inMicroseconds > 300 ||
                f.rasterDuration.inMicroseconds > 300)
              f,
        ];
        final composited = collected.getAggregated('COMPOSITING').count;
        double per(String phase) {
          var total = 0.0;
          for (final block in collected.aggregatedBlocks) {
            if (block.name.startsWith(phase)) total += block.duration;
          }
          return composited == 0 ? 0 : total / composited / 1000;
        }

        final build = [
          for (final f in frames) f.buildDuration.inMicroseconds / 1000,
        ];
        build.sort();
        double pick(double q) => build.isEmpty
            ? 0
            : build[math.min(build.length - 1, (build.length * q).floor())];
        runs.add({
          'frames': composited.toDouble(),
          for (final phase in _phases) phase: per(phase),
          'build_p50': pick(0.5),
          'build_p95': pick(0.95),
        });
      }
      double median(String key) {
        final values = [for (final r in runs) r[key]!];
        values.sort();
        return values[values.length ~/ 2];
      }

      report[name] = {
        'median': {for (final key in runs.first.keys) key: median(key)},
        'runs': runs,
      };
    }

    final a = const Offset(201 - 100, 437);
    final c = const Offset(201 + 100, 437);
    await scene(
      'segmented',
      const _Segmented(),
      () => drag(a, [...line(a, c, 40), ...line(c, a, 40)]),
    );
    const home = Offset(201 - 110, 437);
    const radio = Offset(201 + 110, 437);
    await scene(
      'tab-bar',
      const _Tabs(),
      () => drag(home, [...line(home, radio, 50), ...line(radio, home, 50)]),
    );
    await scene('density16-wave', const _Density(16), () async {
      final gestures = <int, TestGesture>{};
      for (var frame = 0; frame <= 15 * 2 + 25; frame++) {
        for (var i = 0; i < 16; i++) {
          if (frame == i * 2) {
            final gesture = await tester.createGesture(pointer: pointer++);
            await gesture.down(_Density.center(i));
            gestures[i] = gesture;
          } else if (frame == i * 2 + 25) {
            await gestures.remove(i)!.up();
          }
        }
        await tester.pump(const Duration(milliseconds: 8));
      }
      await tester.pump(const Duration(milliseconds: 600));
    });
    const from = Offset(201, 800);
    await scene(
      'density16-rest',
      const _Density(16),
      () => drag(from, line(from, from - const Offset(0, 300), 40)),
    );
    dir.createSync(recursive: true);
    File(
      '${dir.path}/report.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}

class _App extends StatelessWidget {
  const _App({required this.tier, required this.child});

  final MorphGlassTier tier;
  final Widget child;

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
          for (var i = 0; i < 16; i++)
            Positioned(
              left: 0,
              right: 0,
              top: i * 56.0,
              height: 28,
              child: ColoredBox(
                color: HSVColor.fromAHSV(1, i * 37 % 360.0, 0.6, 0.7).toColor(),
              ),
            ),
          Positioned.fill(child: child),
        ],
      ),
    ),
  );
}

class _Segmented extends StatefulWidget {
  const _Segmented();

  @override
  State<_Segmented> createState() => _SegmentedState();
}

class _SegmentedState extends State<_Segmented> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 300,
      child: MorphSegmentedControl(
        segments: const ['A', 'B', 'C'],
        selected: _selected,
        onChanged: (int v) => setState(() => _selected = v),
      ),
    ),
  );
}

class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: MorphTabBar(
      items: const [
        MorphTabItem(icon: Icons.home, label: 'Home'),
        MorphTabItem(icon: Icons.search, label: 'Search'),
        MorphTabItem(icon: Icons.radio, label: 'Radio'),
      ],
      selected: _selected,
      onChanged: (int v) => setState(() => _selected = v),
    ),
  );
}

class _Density extends StatelessWidget {
  const _Density(this.count);

  final int count;

  static Offset center(int i) =>
      Offset(57 + (i % 4) * 96.0, 120 + (i ~/ 4) * 60.0);

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: ListView.builder(
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
              child: Text('Row $i'),
            ),
          ),
        ),
      ),
      for (var i = 0; i < count; i++)
        Positioned.fromRect(
          rect: Rect.fromCenter(center: center(i), width: 80, height: 44),
          child: MorphGlassButton(onPressed: () {}, child: Text('$i')),
        ),
    ],
  );
}
