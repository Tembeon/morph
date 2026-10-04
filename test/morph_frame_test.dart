import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

const Rect source = .fromLTWH(0, 500, 100, 50);
const Rect target = .fromLTWH(200, 100, 400, 300);

MorphFrame frameAt(
  double value, {
  ShapeBorder targetShape = const RoundedRectangleBorder(
    borderRadius: .all(.circular(28)),
  ),
}) {
  return computeMorphFrame(
    value: value,
    sourceRect: source,
    targetRect: target,
    sourceShape: const StadiumBorder(),
    targetShape: targetShape,
    sourceColor: Colors.black,
    targetColor: Colors.white,
    maxScrimOpacity: 0.45,
  );
}

double radiusOf(MorphFrame f) =>
    ((f.shape as RoundedRectangleBorder).borderRadius as BorderRadius)
        .topLeft
        .x;

double centerProgress(MorphFrame f) =>
    (f.rect.center.dx - source.center.dx) /
    (target.center.dx - source.center.dx);

double sizeProgress(MorphFrame f) =>
    (f.rect.width - source.width) / (target.width - source.width);

void main() {
  test('the endpoints match source and target', () {
    expect(frameAt(0).rect, source);
    expect(frameAt(1).rect, target);
    expect(frameAt(0).sourceOpacity, 1);
    expect(frameAt(0).targetOpacity, 0);
    expect(frameAt(1).sourceOpacity, 0);
    expect(frameAt(1).targetOpacity, 1);
  });

  test('geometry is linear in the spring value: position and size in sync', () {
    final MorphFrame mid = frameAt(0.5);
    expect(centerProgress(mid), moreOrLessEquals(0.5));
    expect(sizeProgress(mid), moreOrLessEquals(0.5));
  });

  test('radius is derived from live geometry, the stadium is the cap', () {
    expect(radiusOf(frameAt(0)), 25, reason: 'a 100x50 capsule = radius 25');
    expect(radiusOf(frameAt(1)), 28);
    final double midRadius = radiusOf(frameAt(0.5));
    expect(midRadius, greaterThan(25));
    expect(midRadius, lessThan(28));
  });

  test('radius structurally cannot lag: capped at half the side', () {
    for (double v = 0; v <= 1.2001; v += 0.02) {
      final MorphFrame f = frameAt(
        v,
        targetShape: const RoundedRectangleBorder(
          borderRadius: .all(.circular(500)),
        ),
      );
      expect(
        radiusOf(f),
        lessThanOrEqualTo(f.rect.shortestSide / 2 + 0.0001),
        reason: 'radius must stay under the cap at value=$v',
      );
    }
  });

  test('crossfade: a short home hold, dissolved before aspects diverge', () {
    // The source holds solid over the spring's settle-dwell zone only,
    // and is GONE by 0.30 - past that the container's aspect no longer
    // matches the button and opaque source content would read as a
    // second surface. The target holds from 0.90.
    expect(frameAt(0.04).sourceOpacity, 1);
    expect(frameAt(0.95).targetOpacity, 1);
    expect(frameAt(0.3).sourceOpacity, moreOrLessEquals(0, epsilon: 0.01));
    expect(frameAt(0.35).targetOpacity, moreOrLessEquals(0, epsilon: 0.02));
    expect(frameAt(0.15).sourceOpacity, greaterThan(0));
    expect(frameAt(0.7).targetOpacity, greaterThan(0.4));
    expect(frameAt(0.7).targetScale, greaterThan(0.95));
  });

  test('above 1 center, size and radius extrapolate on the same value', () {
    final MorphFrame over = frameAt(1.2);
    expect(centerProgress(over), moreOrLessEquals(1.2));
    expect(sizeProgress(over), moreOrLessEquals(1.2));
    expect(over.rect.size, const Size(460, 350));
    expect(radiusOf(over), moreOrLessEquals(28.6));
  });

  test('below 0 the source size and radius hold through close undershoot', () {
    final MorphFrame under = frameAt(-0.2);
    expect(centerProgress(under), lessThan(0));
    expect(under.rect.size, source.size);
    expect(radiusOf(under), 25);
    expect(under.sourceOpacity, 1);
    expect(under.targetOpacity, 0);
  });

  test('appearance properties clamp while geometry overshoots', () {
    final MorphFrame over = frameAt(1.1);
    expect(over.scrimOpacity, moreOrLessEquals(0.45));
    expect(radiusOf(over), moreOrLessEquals(28.3));
    expect(over.targetOpacity, 1);
    expect(over.sourceOpacity, 0);
    expect(over.targetScale, 1);
    expect(over.elevation, 24);
    expect(over.surfaceColor, Colors.white);
  });

  test('the device menu width peak extrapolates beyond its target rect', () {
    const Rect blob = Rect.fromLTWH(159.4, 260, 83.2, 80);
    const Rect menu = Rect.fromLTWH(76, 424.67, 250, 208);
    const double peakWidth = 253.16;
    final double value = (peakWidth - blob.width) / (menu.width - blob.width);
    final MorphFrame frame = computeMorphFrame(
      value: value,
      sourceRect: blob,
      targetRect: menu,
      sourceShape: const StadiumBorder(),
      targetShape: const RoundedRectangleBorder(
        borderRadius: .all(.circular(32)),
      ),
      sourceColor: Colors.black,
      targetColor: Colors.white,
      maxScrimOpacity: 0.2,
    );
    expect(value, closeTo(1.0189448441247, 1e-12));
    expect(
      frame.rect.width,
      closeTo(peakWidth, 1e-9),
      reason: 'context_menu/morph.json ctxd-l-1 at 1.1235 seconds',
    );
    expect(frame.rect.height, closeTo(210.4249400479616, 1e-9));
    expect(frame.cornerRadius, closeTo(31.8484412470024, 1e-9));
    expect(
      (frame.rect.center.dy - blob.center.dy) /
          (menu.center.dy - blob.center.dy),
      closeTo(value, 1e-12),
    );
  });

  test('overshoot respects the radius floor and nonnegative dimensions', () {
    final MorphFrame over = frameAt(
      12,
      targetShape: const RoundedRectangleBorder(),
    );
    expect(over.cornerRadius, 0);
    final MorphFrame shrink = computeMorphFrame(
      value: 2,
      sourceRect: target,
      targetRect: source,
      sourceShape: const StadiumBorder(),
      targetShape: const StadiumBorder(),
      sourceColor: Colors.black,
      targetColor: Colors.white,
      maxScrimOpacity: 0.45,
    );
    expect(shrink.rect.size, Size.zero);
    expect(shrink.cornerRadius, 0);
  });

  testWidgets('a liquid open overshoots size by its spring travel', (
    WidgetTester tester,
  ) async {
    final MorphController controller = MorphController(
      vsync: const TestVSync(),
      motion: MorphMotion.liquid,
    );
    addTearDown(controller.dispose);
    controller.open();
    await tester.pump();
    double peak = 1;
    for (int i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      final MorphFrame frame = frameAt(controller.value);
      expect(centerProgress(frame), closeTo(controller.value, 1e-9));
      expect(sizeProgress(frame), closeTo(controller.value, 1e-9));
      peak = math.max(peak, sizeProgress(frame));
    }
    expect(controller.isAnimating, isFalse);
    expect(peak, closeTo(1.028, 0.001));
    expect(frameAt(peak).rect.width, closeTo(408.4, 0.3));
    expect(frameAt(peak).rect.height, closeTo(307, 0.25));
  });

  test('an unknown shape pair falls back to ShapeBorder.lerp', () {
    final MorphFrame f = frameAt(
      0.5,
      targetShape: const BeveledRectangleBorder(),
    );
    expect(f.shape, isNot(isA<RoundedRectangleBorder>()));
  });

  test('cornerRadius is derived for a stadium source', () {
    expect(frameAt(0).cornerRadius, 25);
  });

  test('the shadow is continuous: starts from the button elevation', () {
    final MorphFrame start = computeMorphFrame(
      value: 0,
      sourceRect: source,
      targetRect: target,
      sourceShape: const CircleBorder(),
      targetShape: const RoundedRectangleBorder(),
      sourceColor: Colors.black,
      targetColor: Colors.white,
      maxScrimOpacity: 0.45,
      sourceElevation: 6,
      targetElevation: 24,
    );
    expect(start.elevation, 6);
    expect(frameAt(1).elevation, 24);
    // The lerp rides p^1.5: sub-linear near home (a nearly-home
    // container must not float on a borrowed dialog shadow) while the
    // middle keeps enough depth to read as a card.
    final MorphFrame mid = computeMorphFrame(
      value: 0.5,
      sourceRect: source,
      targetRect: target,
      sourceShape: const CircleBorder(),
      targetShape: const RoundedRectangleBorder(),
      sourceColor: Colors.black,
      targetColor: Colors.white,
      maxScrimOpacity: 0.45,
      sourceElevation: 6,
      targetElevation: 24,
    );
    expect(mid.elevation, moreOrLessEquals(6 + 18 * 0.5 * math.sqrt(0.5)));
  });

  test('a pure function of the value: one value - one frame', () {
    final MorphFrame a = frameAt(0.37);
    final MorphFrame b = frameAt(0.37);
    expect(a.rect, b.rect);
    expect(a.shape, b.shape);
    expect(a.targetOpacity, b.targetOpacity);
  });

  group('border side', () {
    MorphFrame frameAt(double value) {
      return computeMorphFrame(
        value: value,
        sourceRect: const Rect.fromLTWH(0, 0, 100, 40),
        targetRect: const Rect.fromLTWH(200, 200, 300, 400),
        sourceShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: Colors.green, width: 2),
        ),
        targetShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
        sourceColor: Colors.black,
        targetColor: Colors.white,
        maxScrimOpacity: 0.45,
      );
    }

    BorderSide sideAt(double value) =>
        (frameAt(value).shape as RoundedRectangleBorder).side;

    test('a stroked source keeps its contour through the concentric path', () {
      // The launch frame carries the full side - without the lerp the
      // radius rebuild dropped it and the contour popped off.
      expect(sideAt(0).width, closeTo(2, 1e-9));
      expect(sideAt(0.5).width, closeTo(1, 1e-9));
      expect(sideAt(1).width, closeTo(0, 1e-9));
    });
  });
}
