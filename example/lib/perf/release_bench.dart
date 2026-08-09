import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/widgets.dart';
// The bench measures package INTERNALS by design - it is an instrument
// of the package, living in the example only to get an AOT build.
// ignore: implementation_imports
import 'package:morph/src/benchmark_scenes.dart';
// ignore: implementation_imports
import 'package:morph/src/liquid_field.dart';

/// The AOT half of the performance passport: the SAME tracing scenes as
/// benchmark/liquid_benchmark_test.dart, measured inside a release
/// build, plus real engine FrameTimings collected during a scripted
/// glacial flight. Launched with --dart-define=MORPH_BENCH=true; prints
/// lines prefixed with `BENCH` and exits.
Future<void> runReleaseBench(BuildContext context) async {
  final String mode = kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';
  _report('mode=$mode platform=${Platform.operatingSystem}');

  _tracingOps();
  await _frameTimings(context);

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

/// Real engine frame costs during one glacial open + close of a morph
/// dialog flown from a home card: build (UI thread) and raster (GPU
/// thread) per frame, average / p95 / worst.
Future<void> _frameTimings(BuildContext context) async {
  final List<FrameTiming> timings = <FrameTiming>[];
  void collect(List<FrameTiming> batch) => timings.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(collect);

  final MorphFlight flight = showMorphDialog(
    context,
    from: 'lesson-identity',
    width: 520,
    height: 420,
    motion: .glacial,
    builder: (BuildContext context, MorphFlight flight) =>
        const Center(child: Text('bench')),
  );
  await Future<void>.delayed(const Duration(milliseconds: 3200));
  flight.close();
  await flight.closed;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  SchedulerBinding.instance.removeTimingsCallback(collect);

  if (timings.isEmpty) {
    _report('frames n=0');
    return;
  }
  List<double> ms(Duration Function(FrameTiming) pick) {
    final List<double> values = <double>[
      for (final FrameTiming t in timings) pick(t).inMicroseconds / 1000.0,
    ]..sort();
    return values;
  }

  String stats(List<double> values) {
    final double avg =
        values.reduce((double a, double b) => a + b) / values.length;
    final double p95 =
        values[(values.length * 0.95).floor().clamp(0, values.length - 1)];
    return 'avg=${avg.toStringAsFixed(2)} p95=${p95.toStringAsFixed(2)} '
        'worst=${values.last.toStringAsFixed(2)}';
  }

  final List<double> build = ms((FrameTiming t) => t.buildDuration);
  final List<double> raster = ms((FrameTiming t) => t.rasterDuration);
  _report('frames n=${timings.length} (glacial flight open+close)');
  _report('build  ms: ${stats(build)}');
  _report('raster ms: ${stats(raster)}');
}
