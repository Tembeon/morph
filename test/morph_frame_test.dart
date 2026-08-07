import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

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
    for (double v = 0; v <= 1.0001; v += 0.02) {
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

  test('crossfade: a fast early sub-range, no double exposure', () {
    expect(frameAt(0.3).sourceOpacity, moreOrLessEquals(0, epsilon: 0.01));
    expect(frameAt(0.3).targetOpacity, moreOrLessEquals(0, epsilon: 0.01));
    expect(frameAt(0.15).sourceOpacity, greaterThan(0));
    expect(frameAt(0.6).targetOpacity, greaterThan(0.4));
    expect(frameAt(0.6).targetScale, greaterThan(0.95));
  });

  test('beyond the travel range the morph shifts but does not stretch', () {
    final MorphFrame over = frameAt(1.2);
    expect(centerProgress(over), greaterThan(1));
    expect(over.rect.size, target.size, reason: 'size is frozen at the edge');

    final MorphFrame under = frameAt(-0.2);
    expect(centerProgress(under), lessThan(0));
    expect(
      under.rect.size,
      source.size,
      reason: 'pulling past the button does not degenerate the rect',
    );
  });

  test('surface properties clamp on overshoot', () {
    final MorphFrame over = frameAt(1.1);
    expect(over.scrimOpacity, moreOrLessEquals(0.45));
    expect(radiusOf(over), 28);
    expect(over.targetOpacity, 1);
    expect(over.sourceOpacity, 0);
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
  });

  test('a pure function of the value: one value - one frame', () {
    final MorphFrame a = frameAt(0.37);
    final MorphFrame b = frameAt(0.37);
    expect(a.rect, b.rect);
    expect(a.shape, b.shape);
    expect(a.targetOpacity, b.targetOpacity);
  });

  group('morphBumpedRect / morphLandingBump', () {
    test('rest returns the original rect', () {
      const Rect r = .fromLTWH(10, 20, 100, 60);
      expect(
        morphBumpedRect(
          r,
          value: 0,
          impactAxis: const Offset(0, 100),
          bumpScale: 0.6,
          bumpRecoil: 140,
        ),
        r,
      );
    });

    test('undershoot squashes along the axis and kicks away', () {
      const Rect r = .fromLTWH(0, 0, 100, 100);
      final Rect bumped = morphBumpedRect(
        r,
        value: -0.2,
        impactAxis: const Offset(0, 100),
        bumpScale: 0.5,
        bumpRecoil: 100,
      );
      expect(bumped.height, closeTo(100 * (1 - 0.2 * 0.5), 1e-9));
      expect(bumped.width, closeTo(100 * (1 + 0.2 * 0.5 * 0.45), 1e-9));
      expect(bumped.center.dy, closeTo(50 + 20, 1e-9));
      expect(bumped.center.dx, closeTo(50, 1e-9));
    });

    test('a degenerate axis falls back to vertical', () {
      const Rect r = .fromLTWH(0, 0, 100, 60);
      final Rect bumped = morphBumpedRect(
        r,
        value: -0.3,
        impactAxis: .zero,
        bumpScale: 0.5,
        bumpRecoil: 0,
      );
      expect(bumped.height, lessThan(60));
      expect(bumped.width, greaterThan(100));
    });

    test('a horizontal axis flips the squash orientation', () {
      final ({double scaleX, double scaleY, Offset kick}) b = morphLandingBump(
        value: -0.2,
        impactAxis: const Offset(100, 0),
        bumpScale: 0.5,
        bumpRecoil: 100,
      );
      expect(b.scaleX, closeTo(0.9, 1e-9));
      expect(b.scaleY, closeTo(1.045, 1e-9));
      expect(b.kick, const Offset(20, 0));
    });
  });
}
