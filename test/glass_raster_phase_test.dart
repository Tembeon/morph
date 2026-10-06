import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/raster_phase.dart';

double _sampleOffset(double origin) {
  const pixel = 7;
  const center = pixel + 0.5;
  final texel = (center - origin).ceilToDouble() - 1;
  return origin + texel + 0.5 - center;
}

void main() {
  test('the phase is where a nearest-sampled matte reads a pixel', () {
    for (var i = 0; i <= 40; i++) {
      final origin = -3 + i * 0.173;
      expect(
        glassRasterPhase(origin),
        moreOrLessEquals(_sampleOffset(origin), epsilon: 1e-6),
      );
      expect(glassRasterPhase(origin), greaterThanOrEqualTo(-0.5));
      expect(glassRasterPhase(origin), lessThan(0.5));
    }
  });

  test('a pixel center on a texel edge reads the texel before it, at the '
      'origin the final pass receives', () {
    expect(glassRasterPhase(60.5), -0.5);
    expect(glassRasterPhase(60.5 + 1e-9), -0.5);
    expect(glassRasterPhase(60.5 - 1e-9), -0.5);
    expect(glassRasterPhase(60.497), moreOrLessEquals(0.497, epsilon: 1e-5));
  });

  test('a grid within the tie band moves onto the pixel centers', () {
    final near = GlassRasterGrid(const Offset(60.5, 30.2));
    expect(near.bias.dx, 0.5);
    expect(near.bias.dy, 0);
    expect(near.sample.dx, moreOrLessEquals(0, epsilon: 1e-6));
    expect(near.shiftFor(near.origin).dx, moreOrLessEquals(0.5, epsilon: 1e-6));
    expect(near.shiftFor(near.origin).dy, 0);
    final clear = GlassRasterGrid(
      const Offset(60.5 - 2 * glassRasterTieBand, 0),
    );
    expect(clear.biased, isFalse);
    expect(clear.shiftFor(clear.origin), Offset.zero);
    final fixed = GlassRasterGrid(const Offset(60.5, 0), movable: false);
    expect(fixed.biased, isFalse);
  });

  testWidgets('a shape under an anchor shifts onto its own grid', (
    WidgetTester tester,
  ) async {
    final layerKey = GlobalKey();
    final anchorKey = GlobalKey();
    final shapeKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned(
              left: 10,
              top: 20,
              width: 200,
              height: 200,
              child: SizedBox(
                key: layerKey,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0.3,
                      top: 1.6,
                      width: 50,
                      height: 30,
                      child: GlassRasterAnchor(
                        key: anchorKey,
                        child: SizedBox(key: shapeKey),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final layer = layerKey.currentContext!.findRenderObject()!;
    final shape = shapeKey.currentContext!.findRenderObject()!;
    final pass = Matrix4.translationValues(10.45, 20, 0);
    const ratio = 2.625;
    final grid = glassRasterGrid(pass, ratio)!;
    final shift = glassRasterPhaseShift(layer, shape, grid, ratio);
    double expected(double sample, double origin, double anchor) =>
        (sample - glassRasterPhase((origin + anchor) * ratio)) / ratio;
    expect(grid.bias.dx, 0);
    expect(grid.sample.dx, glassRasterPhase(10.45 * ratio));
    expect(grid.bias.dy, 0.5, reason: '20 * 2.625 is an exact tie');
    expect(
      shift.dx,
      moreOrLessEquals(expected(grid.sample.dx, 10.45, 0.3), epsilon: 1e-9),
    );
    expect(
      shift.dy,
      moreOrLessEquals(expected(grid.sample.dy, 20, 1.6), epsilon: 1e-9),
    );
    expect(shift, isNot(Offset.zero));
    expect(
      glassRasterPhaseShift(layer, layer, grid, ratio),
      grid.shiftFor(grid.origin) / ratio,
    );
    expect(glassRasterGrid(Matrix4.diagonal3Values(2, 2, 1), ratio), isNull);
  });
}
