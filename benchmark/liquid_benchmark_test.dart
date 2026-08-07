import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/benchmark_scenes.dart';
import 'package:morph/src/liquid_field.dart';

/// Microbenchmarks for the liquid tracing pipeline (field sampling +
/// marching squares + stitching + Chaikin + Path build).
///
/// Not part of the regular test suite - run explicitly:
///
/// ```bash
/// flutter test benchmark/liquid_benchmark_test.dart
/// ```
///
/// Numbers come from the JIT test VM, so treat them as RELATIVE (for
/// before/after comparisons on one machine). For AOT numbers run the
/// example app's release benchmark over the SAME scenes:
///
/// ```bash
/// cd example && flutter run -d macos --release --dart-define=MORPH_BENCH=true
/// ```
class _LiquidBench extends BenchmarkBase {
  _LiquidBench(
    super.name,
    this.field, {
    this.evalBudget = liquidDefaultEvalBudget,
  });

  final LiquidField field;
  final int? evalBudget;

  @override
  void run() {
    liquidPath(field, evalBudget: evalBudget);
  }
}

class _OneMovingBench extends BenchmarkBase {
  _OneMovingBench(super.name, {required this.cached});

  final bool cached;
  final LiquidTracer _tracer = LiquidTracer();
  int _frame = 0;

  @override
  void run() {
    _frame++;
    final LiquidField field = benchOneMovingFrame(_frame);
    if (cached) {
      _tracer.trace(field);
    } else {
      liquidPath(field);
    }
  }
}

void main() {
  test('liquid tracing microbenchmarks', () {
    final List<BenchmarkBase> benches = <BenchmarkBase>[
      _LiquidBench('fusedPair', benchFusedPair),
      _LiquidBench('sandboxSpread', benchSandboxSpread),
      _LiquidBench('flightFar', benchFlightFar),
      _LiquidBench('manyPieces', benchManyPieces),
      _LiquidBench('megaCluster64', benchMegaCluster64),
      _LiquidBench(
        'megaCluster64/unbounded',
        benchMegaCluster64,
        evalBudget: null,
      ),
      _OneMovingBench('oneMoving/pure', cached: false),
      _OneMovingBench('oneMoving/cached', cached: true),
    ];
    // benchmark_harness reports microseconds per run() call.
    for (final BenchmarkBase bench in benches) {
      final double us = bench.measure();
      // ignore: avoid_print
      print(
        '${bench.name.padRight(14)} '
        '${us.toStringAsFixed(1).padLeft(9)} us/op',
      );
    }
  });
}
