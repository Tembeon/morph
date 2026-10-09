import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/glass_outline.dart';

/// Points along every contour of [path], at fixed fractions of each
/// contour's length.
List<Offset> _walk(Path path) => [
  for (final metric in path.computeMetrics())
    for (var i = 0; i <= 64; i++)
      metric.getTangentForOffset(metric.length * i / 64)!.position,
];

void main() {
  tearDown(() {
    debugMorphFusionFullSampling = false;
    debugClearMorphGlassOutlines();
  });

  for (final withField in [false, true]) {
    test('a container fusion reads one box where one box decides the merge, '
        'and traces the outline and field the full merge law gives '
        '(${withField ? 'optical field' : 'silhouette'})', () {
      final random = math.Random(withField ? 7 : 20261009);
      debugMorphFusionDecidedBlocks = 0;
      var fused = 0;
      for (var round = 0; round < 200; round++) {
        final count = 2 + random.nextInt(4);
        final shapes = <RRect>[];
        var x = random.nextDouble() * 40;
        var y = 0.0;
        for (var i = 0; i < count; i++) {
          final w = 30 + random.nextDouble() * 120;
          final h = 30 + random.nextDouble() * 40;
          final r = math.min(w, h) / 2 * (0.3 + 0.7 * random.nextDouble());
          shapes.add(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, w, h),
              Radius.circular(r),
            ),
          );
          // Mostly rows, sometimes a step down: necks at corners too.
          if (random.nextInt(4) == 0) {
            y += h + random.nextDouble() * 20 - 6;
          } else {
            x += w + random.nextDouble() * 30 - 8;
            y += random.nextDouble() * 12 - 6;
          }
        }
        final spacing = 2 + random.nextDouble() * 22;
        if (morphGlassContainerGroups(shapes, spacing).length == count) {
          continue;
        }
        fused++;
        debugClearMorphGlassOutlines();
        debugMorphFusionFullSampling = true;
        final full = morphGlassContainerOutline(
          shapes,
          spacing,
          withField: withField,
        );
        debugClearMorphGlassOutlines();
        debugMorphFusionFullSampling = false;
        final fast = morphGlassContainerOutline(
          shapes,
          spacing,
          withField: withField,
        );
        expect(
          _walk(fast.path),
          _walk(full.path),
          reason: 'round $round: $shapes spacing $spacing',
        );
        if (withField) {
          // The optical field's blends weigh the other boxes by exactly 0
          // or 1 where one box decides; the samples agree to float
          // rounding (they are uploaded as 32-bit floats).
          final a = morphGlassOutlineField(fast)!.samples;
          final b = morphGlassOutlineField(full)!.samples;
          expect(a.length, b.length);
          for (var i = 0; i < a.length; i++) {
            expect(
              (a[i] - b[i]).abs(),
              lessThanOrEqualTo(1e-5 * (1 + b[i].abs())),
              reason: 'round $round sample $i',
            );
          }
        }
      }
      expect(fused, greaterThan(100));
      expect(debugMorphFusionDecidedBlocks, greaterThan(fused * 10));
    });
  }
}
