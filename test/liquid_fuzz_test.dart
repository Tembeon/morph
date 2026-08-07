import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/liquid_field.dart';

/// Seeded fuzz over the tracing pipeline: random (but reproducible)
/// scenes pushed through the sign-consistency invariant and the
/// tracer/pure equivalence. Orders of magnitude more coverage than
/// hand-written cases; a failure prints the seed for exact replay.
void main() {
  const int sceneCount = 30;

  for (int seed = 0; seed < sceneCount; seed++) {
    test('fuzz scene #$seed stays sign-consistent and cache-exact', () {
      final math.Random random = math.Random(seed);
      final LiquidField field = _randomField(random);

      // Sign consistency: contour agrees with the field away from the
      // surface.
      final Path path = liquidPath(field, cell: 4);
      final Rect b = field.bounds(pad: 8);
      int checked = 0;
      for (double y = b.top; y <= b.bottom; y += 9) {
        for (double x = b.left; x <= b.right; x += 9) {
          final double d = field.eval(Offset(x, y));
          if (d.abs() < 6) {
            continue;
          }
          checked++;
          expect(
            path.contains(Offset(x, y)),
            d < 0,
            reason: 'seed $seed: sign mismatch at ($x, $y), distance $d',
          );
        }
      }
      expect(checked, greaterThan(20), reason: 'seed $seed: net too sparse');

      // Cache exactness: a tracer fed the scene twice (second time with
      // one shape nudged) must match the pure function bit for bit.
      final LiquidTracer tracer = LiquidTracer();
      expect(
        tracer.trace(field, cell: 4).getBounds(),
        path.getBounds(),
        reason: 'seed $seed: tracer diverged from pure liquidPath',
      );
      final LiquidField nudged = _nudgeFirstShape(field);
      expect(
        tracer.trace(nudged, cell: 4).getBounds(),
        liquidPath(nudged, cell: 4).getBounds(),
        reason: 'seed $seed: cached composite diverged after a nudge',
      );
    });
  }
}

LiquidField _randomField(math.Random random) {
  final int shapeCount = 2 + random.nextInt(5);
  final double k = 6 + random.nextDouble() * 40;
  final List<LiquidShape> shapes = <LiquidShape>[];
  for (int i = 0; i < shapeCount; i++) {
    if (random.nextDouble() < 0.8) {
      shapes.add(
        LiquidBox(
          .fromLTWH(
            random.nextDouble() * 400,
            random.nextDouble() * 300,
            30 + random.nextDouble() * 140,
            24 + random.nextDouble() * 100,
          ),
          radius: random.nextDouble() * 40,
        ),
      );
    } else {
      final Offset a = Offset(
        random.nextDouble() * 400,
        random.nextDouble() * 300,
      );
      shapes.add(
        LiquidBridge(
          a,
          a +
              Offset(
                random.nextDouble() * 200 - 100,
                random.nextDouble() * 160 - 80,
              ),
          radius: 4 + random.nextDouble() * 14,
        ),
      );
    }
  }
  return LiquidField(shapes, k: k);
}

LiquidField _nudgeFirstShape(LiquidField field) {
  final List<LiquidShape> shapes = .of(field.shapes);
  final LiquidShape first = shapes.first;
  shapes[0] = switch (first) {
    LiquidBox(:final Rect rect, :final double radius) => LiquidBox(
      rect.shift(const Offset(3, 2)),
      radius: radius,
    ),
    LiquidBridge(:final Offset a, :final Offset b, :final double radius) =>
      LiquidBridge(
        a + const Offset(3, 2),
        b + const Offset(3, 2),
        radius: radius,
      ),
  };
  return LiquidField(shapes, k: field.k);
}
