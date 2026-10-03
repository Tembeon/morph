import 'dart:ui';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu_fusion.dart';

/// Microbenchmarks for the fused glass outlines: the menu's blurred
/// silhouette (a ten-row menu over its button, the shapes the device
/// audit in example/integration_test/glass_audit_test.dart times) and a
/// bar's fused capsules.
///
/// Not part of the regular test suite - run explicitly:
///
/// ```bash
/// flutter test benchmark/glass_outline_benchmark_test.dart
/// ```
///
/// The shapes move a little every call, so no outline is reused. JIT
/// numbers: relative only; the audit gives the device's.
class _MenuBench extends BenchmarkBase {
  _MenuBench(this.radius) : super('menu10-r${radius.round()}');

  final double radius;
  int _frame = 0;

  @override
  void run() {
    _frame++;
    morphMenuSilhouette(
      RRect.fromLTRBXY(70, 200 + (_frame % 100) * 0.01, 330, 640, 32, 32),
      const RRect.fromLTRBXY(177, 652, 225, 700, 24, 24),
      radius,
    );
  }
}

class _BarBench extends BenchmarkBase {
  _BarBench() : super('bar-capsules');

  int _frame = 0;

  @override
  void run() {
    _frame++;
    morphGlassContainerOutline([
      RRect.fromLTRBXY(16 + (_frame % 1000) * 0.001, 60, 160, 104, 22, 22),
      const RRect.fromLTRBXY(166, 60, 210, 104, 22, 22),
    ], 12);
  }
}

void main() {
  test('glass outline microbenchmarks', () {
    final benches = <BenchmarkBase>[
      _MenuBench(4),
      _MenuBench(10),
      _MenuBench(20),
      _BarBench(),
    ];
    for (final bench in benches) {
      final us = bench.measure();
      // ignore: avoid_print
      print(
        '${bench.name.padRight(14)} ${us.toStringAsFixed(1).padLeft(9)} us/op',
      );
    }
  });
}
