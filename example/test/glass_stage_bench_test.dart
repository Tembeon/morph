import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/perf/glass_stage_bench.dart';

ui.FrameTiming _frame(int index, int buildUs, int rasterUs) {
  final start = index * 16667;
  return ui.FrameTiming(
    vsyncStart: start,
    buildStart: start,
    buildFinish: start + buildUs,
    rasterStart: start + buildUs,
    rasterFinish: start + buildUs + rasterUs,
    rasterFinishWallTime: start + buildUs + rasterUs,
  );
}

void main() {
  test('cheap rendered frames remain in the percentile denominator', () {
    final frames = [
      for (var i = 0; i < 20; i++) _frame(i, 100, 100),
      _frame(20, 20000, 1000),
    ];
    final result = stageBenchStats(frames, 1000 / 60);
    expect(result['n'], 21);
    expect(result['build_p95'], .1);
    expect(result['build_p99'], 20);
    expect(result['over_budget'], 1);
    expect(result['raster_mean'], closeTo(3 / 21, 1e-9));
  });

  test('frame budget counts either pipeline stage, not their sum', () {
    final result = stageBenchStats([
      _frame(0, 10000, 10000),
      _frame(1, 100, 18000),
    ], 1000 / 60);
    expect(result['over_budget'], 1);
    expect(() => stageBenchStats([], 16.67), throwsStateError);
  });

  test(
    'spread and cluster preserve visible area while changing union area',
    () {
      const size = ui.Size(412, 860);
      double area(List<ui.Rect> rects) =>
          rects.fold(0, (total, r) => total + r.width * r.height);
      ui.Rect union(List<ui.Rect> rects) =>
          rects.reduce((a, b) => a.expandToInclude(b));
      final cluster = stageBenchRects('cluster', size);
      final spread = stageBenchRects('spread', size);
      expect(area(cluster), closeTo(area(spread), 1e-6));
      expect(
        union(spread).width * union(spread).height,
        greaterThan(3 * union(cluster).width * union(cluster).height),
      );
      for (final layout in ['single', 'large', 'cluster', 'spread']) {
        final rects = stageBenchRects(layout, size);
        for (final rect in rects) {
          expect((ui.Offset.zero & size).contains(rect.topLeft), isTrue);
          expect((ui.Offset.zero & size).contains(rect.bottomRight), isTrue);
        }
      }
      expect(() => stageBenchRects('unknown', size), throwsArgumentError);
    },
  );
}
