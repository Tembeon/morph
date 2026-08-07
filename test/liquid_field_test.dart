import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/liquid_field.dart';

void main() {
  group('liquidSmin', () {
    test('k = 0 degenerates to a plain min', () {
      expect(liquidSmin(3, 7, 0), 3);
      expect(liquidSmin(-2, 5, 0), -2);
    });

    test('symmetric and never greater than min', () {
      const double k = 10;
      for (final (double a, double b) in <(double, double)>[
        (4, 6),
        (-3, 2),
        (0, 0),
        (12, -12),
      ]) {
        expect(liquidSmin(a, b, k), closeTo(liquidSmin(b, a, k), 1e-9));
        expect(liquidSmin(a, b, k), lessThanOrEqualTo(math.min(a, b) + 1e-9));
      }
    });

    test('matches min far away from the junction', () {
      expect(liquidSmin(1, 100, 5), closeTo(1, 1e-9));
    });
  });

  group('liquidBoxDistance', () {
    const Rect rect = .fromLTWH(0, 0, 100, 60);

    test('signs: negative inside, zero on the edge, positive outside', () {
      expect(liquidBoxDistance(rect.center, rect, 10), lessThan(0));
      expect(
        liquidBoxDistance(const Offset(50, 0), rect, 10),
        closeTo(0, 1e-9),
      );
      expect(
        liquidBoxDistance(const Offset(50, -20), rect, 10),
        closeTo(20, 1e-9),
      );
    });

    test('distance at the center is minus half of the shorter side', () {
      expect(liquidBoxDistance(rect.center, rect, 10), closeTo(-30, 1e-9));
    });

    test('radius is clamped: a huge radius yields a stadium', () {
      final double atCorner = liquidBoxDistance(.zero, rect, 1000);
      // Stadium with half-height 30: the left cap circle is centered at (30, 30).
      final double expected =
          (Offset.zero - const Offset(30, 30)).distance - 30;
      expect(atCorner, closeTo(expected, 1e-9));
    });
  });

  group('liquidCapsuleDistance', () {
    test('a point on the axis is inside, past the end cap is outside', () {
      const Offset a = .zero;
      const Offset b = Offset(100, 0);
      expect(
        liquidCapsuleDistance(const Offset(50, 0), a, b, 10),
        closeTo(-10, 1e-9),
      );
      expect(
        liquidCapsuleDistance(const Offset(120, 0), a, b, 10),
        closeTo(10, 1e-9),
      );
    });

    test('a degenerate segment behaves like a circle', () {
      const Offset c = Offset(5, 5);
      expect(
        liquidCapsuleDistance(const Offset(5, 20), c, c, 10),
        closeTo(5, 1e-9),
      );
    });
  });

  group('liquidRectGap', () {
    test('overlap yields zero, separation yields the distance', () {
      const Rect a = .fromLTWH(0, 0, 100, 60);
      expect(liquidRectGap(a, const .fromLTWH(50, 30, 100, 60)), 0);
      expect(liquidRectGap(a, const .fromLTWH(140, 0, 50, 60)), 40);
      expect(liquidRectGap(a, const .fromLTWH(0, 100, 100, 60)), 40);
      expect(
        liquidRectGap(a, const .fromLTWH(130, 100, 50, 50)),
        closeTo(50, 1e-9),
      );
    });
  });

  group('LiquidField', () {
    test('bounds expands by k + pad: headroom for the fusion bulge', () {
      const LiquidField field = LiquidField(<LiquidShape>[
        LiquidBox(.fromLTWH(0, 0, 100, 60)),
      ], k: 20);
      expect(field.bounds(), const Rect.fromLTRB(-20, -20, 120, 80));
      expect(field.bounds(pad: 5), const Rect.fromLTRB(-25, -25, 125, 85));
    });

    test('empty field: infinity and a zero rect', () {
      const LiquidField field = LiquidField(<LiquidShape>[]);
      expect(field.eval(.zero), double.infinity);
      expect(field.bounds(), Rect.zero);
    });
  });

  group('liquidContours / liquidPath', () {
    test('a single box is traced by one loop close to its rect', () {
      const Rect rect = .fromLTWH(20, 20, 120, 80);
      const LiquidField field = LiquidField(<LiquidShape>[
        LiquidBox(rect, radius: 16),
      ], k: 8);
      final List<List<Offset>> loops = liquidContours(field, cell: 4);
      expect(loops, hasLength(1));
      final Path path = liquidPath(field, cell: 4);
      expect(path.contains(rect.center), isTrue);
      expect(path.contains(const Offset(300, 300)), isFalse);
      final Rect traced = path.getBounds();
      // Marching squares is discrete and Chaikin shrinks a little - the
      // contour bounds match the shape up to the grid step.
      expect((traced.left - rect.left).abs(), lessThan(5));
      expect((traced.top - rect.top).abs(), lessThan(5));
      expect((traced.right - rect.right).abs(), lessThan(5));
      expect((traced.bottom - rect.bottom).abs(), lessThan(5));
    });

    test('small k: distant boxes stay separate islands', () {
      const LiquidField field = LiquidField(<LiquidShape>[
        LiquidBox(.fromLTWH(0, 0, 60, 40), radius: 10),
        LiquidBox(.fromLTWH(100, 0, 60, 40), radius: 10),
      ], k: 5);
      expect(liquidContours(field, cell: 4), hasLength(2));
    });

    test('large k fuses the same boxes into a single loop', () {
      // Blend depth at the middle of a gap is ~k/4: closing a gap of 40
      // (20 from each side) needs k well above 80.
      const LiquidField field = LiquidField(<LiquidShape>[
        LiquidBox(.fromLTWH(0, 0, 60, 40), radius: 10),
        LiquidBox(.fromLTWH(100, 0, 60, 40), radius: 10),
      ], k: 90);
      final List<List<Offset>> loops = liquidContours(field, cell: 4);
      expect(loops, hasLength(1));
      // A point in the gap between the boxes is now inside the shared skin.
      final Path path = liquidPath(field, cell: 4);
      expect(path.contains(const Offset(80, 20)), isTrue);
    });

    test('a bridge connects the islands even at small k', () {
      const LiquidField field = LiquidField(<LiquidShape>[
        LiquidBox(.fromLTWH(0, 0, 60, 40), radius: 10),
        LiquidBox(.fromLTWH(140, 0, 60, 40), radius: 10),
        LiquidBridge(Offset(30, 20), Offset(170, 20), radius: 8),
      ], k: 5);
      expect(liquidContours(field, cell: 4), hasLength(1));
    });

    test('smoothing does not inflate the contour bounds', () {
      const Rect rect = .fromLTWH(0, 0, 100, 60);
      const LiquidField field = LiquidField(<LiquidShape>[
        LiquidBox(rect, radius: 12),
      ], k: 6);
      final Rect raw = liquidPath(field, cell: 4, smoothPasses: 0).getBounds();
      final Rect smoothed = liquidPath(field, cell: 4).getBounds();
      expect(smoothed.left, greaterThanOrEqualTo(raw.left - 1e-6));
      expect(smoothed.top, greaterThanOrEqualTo(raw.top - 1e-6));
      expect(smoothed.right, lessThanOrEqualTo(raw.right + 1e-6));
      expect(smoothed.bottom, lessThanOrEqualTo(raw.bottom + 1e-6));
    });
  });
}
