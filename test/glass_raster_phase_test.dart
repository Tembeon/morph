import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/raster_phase.dart';

double _sampleOffset(double origin) {
  const pixel = 7;
  const center = pixel + 0.5;
  final texel = (center - origin).floorToDouble();
  return origin + texel + 0.5 - center;
}

void main() {
  test('the phase is where a nearest-sampled matte reads a pixel', () {
    for (var i = 0; i <= 40; i++) {
      final origin = -3 + i * 0.173;
      expect(
        glassRasterPhase(origin),
        moreOrLessEquals(_sampleOffset(origin), epsilon: 1e-9),
      );
      expect(glassRasterPhase(origin), greaterThan(-0.5));
      expect(glassRasterPhase(origin), lessThanOrEqualTo(0.5));
    }
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
    final shift = glassRasterPhaseShift(layer, shape, pass, ratio);
    double expected(double origin, double anchor) =>
        (glassRasterPhase(origin * ratio) -
            glassRasterPhase((origin + anchor) * ratio)) /
        ratio;
    expect(shift.dx, moreOrLessEquals(expected(10.45, 0.3), epsilon: 1e-9));
    expect(shift.dy, moreOrLessEquals(expected(20, 1.6), epsilon: 1e-9));
    expect(shift, isNot(Offset.zero));
    expect(glassRasterPhaseShift(layer, layer, pass, ratio), Offset.zero);
    expect(
      glassRasterPhaseShift(
        layer,
        shape,
        Matrix4.diagonal3Values(2, 2, 1),
        ratio,
      ),
      Offset.zero,
    );
  });
}
