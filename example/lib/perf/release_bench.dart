import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// The bench measures package INTERNALS by design - it is an instrument
// of the package, living in the example only to get an AOT build.
// ignore: implementation_imports
import 'package:morph/src/benchmark_scenes.dart';
// ignore: implementation_imports
import 'package:morph/src/liquid_field.dart';
// ignore: implementation_imports
import 'package:morph/src/scope.dart';

const Object _benchSourceId = 'bench-card';

/// The AOT half of the performance passport as an app: one card to fly a
/// dialog from, and [runReleaseBench] started once the card is laid out.
///
/// The example's entrypoint runs it under `--dart-define=MORPH_BENCH=true`.
class ReleaseBenchApp extends StatelessWidget {
  /// Creates the bench app.
  const ReleaseBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: const Color(0xFF2A2440),
      debugShowCheckedModeBanner: false,
      textStyle: const TextStyle(color: Color(0xFFFFFFFF)),
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
            settings: settings,
            pageBuilder: (BuildContext context, _, _) => builder(context),
          ),
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: const _BenchHome(),
    );
  }
}

class _BenchHome extends StatefulWidget {
  const _BenchHome();

  @override
  State<_BenchHome> createState() => _BenchHomeState();
}

class _BenchHomeState extends State<_BenchHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        await runReleaseBench(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Center(
        child: MorphTag(
          id: _benchSourceId,
          shape: RoundedRectangleBorder(borderRadius: .circular(20)),
          surfaceColor: const Color(0xFF2A2440),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF2A2440),
              borderRadius: .circular(20),
            ),
            child: const SizedBox(
              width: 220,
              height: 120,
              child: Center(child: Text('bench')),
            ),
          ),
        ),
      ),
    );
  }
}

/// The AOT half of the performance passport: the SAME tracing scenes as
/// benchmark/liquid_benchmark_test.dart, measured inside a release
/// build, plus real engine FrameTimings collected during a scripted
/// glacial flight. Prints lines prefixed with `BENCH` and exits.
Future<void> runReleaseBench(BuildContext context) async {
  final String mode = kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';
  _report('mode=$mode platform=${Platform.operatingSystem}');

  try {
    _tracingOps();
  } on Object catch (error) {
    // A passport that half-prints and hangs is worse than one that
    // says why: never let a launch failure skip the exit below (the
    // process is grepped for BENCH and must terminate).
    _report('error $error');
  }

  _report('done');
  exit(0);
}

void _report(String line) {
  // ignore: avoid_print
  print('BENCH $line');
}

/// Median us/op over five ~200ms batches, after warmup - the release
/// counterpart of benchmark_harness.measure().
double _measureUs(void Function() run) {
  for (int i = 0; i < 20; i++) {
    run();
  }
  final List<double> samples = <double>[];
  for (int s = 0; s < 5; s++) {
    int iterations = 0;
    final Stopwatch watch = Stopwatch()..start();
    while (watch.elapsedMicroseconds < 200000) {
      run();
      iterations++;
    }
    watch.stop();
    samples.add(watch.elapsedMicroseconds / iterations);
  }
  samples.sort();
  return samples[2];
}

void _tracingOps() {
  final Map<String, void Function()> scenarios = <String, void Function()>{
    'fusedPair': () => liquidPath(benchFusedPair),
    'sandboxSpread': () => liquidPath(benchSandboxSpread),
    'flightFar': () => liquidPath(benchFlightFar),
    'manyPieces': () => liquidPath(benchManyPieces),
    'megaCluster64': () => liquidPath(benchMegaCluster64),
    'megaCluster64/unbounded': () =>
        liquidPath(benchMegaCluster64, evalBudget: null),
  };
  for (final MapEntry<String, void Function()>(
        key: String name,
        value: void Function() run,
      )
      in scenarios.entries) {
    _report('${name.padRight(24)} ${_measureUs(run).toStringAsFixed(1)} us/op');
  }

  int frame = 0;
  _report(
    '${'oneMoving/pure'.padRight(24)} '
    '${_measureUs(() => liquidPath(benchOneMovingFrame(frame++))).toStringAsFixed(1)} us/op',
  );
  final LiquidTracer tracer = LiquidTracer();
  frame = 0;
  _report(
    '${'oneMoving/cached'.padRight(24)} '
    '${_measureUs(() => tracer.trace(benchOneMovingFrame(frame++))).toStringAsFixed(1)} us/op',
  );
}
