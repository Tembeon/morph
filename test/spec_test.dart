import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';
import 'package:morph/motion.dart';

void main() {
  group('MorphSpring', () {
    test('maps response and damping ratio to a unit-mass spring', () {
      const spring = MorphSpring(0.27, 0.625);
      expect(spring.stiffness, moreOrLessEquals(541.54208, epsilon: 1e-4));
      expect(spring.damping, moreOrLessEquals(29.088821, epsilon: 1e-5));
      expect(spring.description.mass, 1);
    });
  });

  group('MorphFlexSpec.forSize matches UIKit', () {
    test('surfaces with a long side under 120 are ultra small', () {
      for (final size in const [Size(30, 30), Size(100, 54), Size(116, 90)]) {
        final spec = MorphFlexSpec.forSize(size);
        expect(spec.liftScalePoints, 16, reason: '$size');
        expect(spec.scaleDistanceThreshold, 2000, reason: '$size');
        expect(spec.scaleSpring, const MorphSpring(0.4, 0.375));
      }
    });

    test('springs follow the long side and sizes the short side', () {
      final spec = MorphFlexSpec.forSize(const Size(120, 54));
      expect(spec.liftScalePoints, moreOrLessEquals(14.96551724137931));
      expect(
        spec.scaleDistanceThreshold,
        moreOrLessEquals(7551.724137931034, epsilon: 1e-9),
      );
      expect(spec.scaleSpring.response, moreOrLessEquals(0.3737931034482759));
      expect(
        spec.scaleSpring.dampingRatio,
        moreOrLessEquals(0.5224137931034483),
      );
      expect(
        spec.trackingSpring.response,
        moreOrLessEquals(0.2960689655172414),
      );
      expect(spec.trackingSpring.dampingRatio, moreOrLessEquals(0.625));
      expect(spec.littleGlowOpacity, moreOrLessEquals(0.2913793103448276));
      expect(spec.bigGlowOpacity, moreOrLessEquals(0.9137931034482758));
      expect(spec.movementScalePoints, 10);
    });

    test('heights from 120 shrink the lift toward 4', () {
      expect(
        MorphFlexSpec.forSize(const Size(120, 120)).liftScalePoints,
        moreOrLessEquals(8.137931034482758, epsilon: 1e-3),
      );
      final big = MorphFlexSpec.forSize(const Size(300, 300));
      expect(big.liftScalePoints, 4);
      expect(big.scaleDistanceThreshold, 24000);
      expect(big.scaleSpring, const MorphSpring(0.36, 0.6));
      expect(big.littleGlowOpacity, moreOrLessEquals(0.2));
      expect(big.bigGlowOpacity, 0);
    });
  });

  group('MorphFlexSpec selects by the short and long sides', () {
    test('a portrait surface gets the spec of its landscape twin', () {
      for (final size in const [Size(80, 200), Size(200, 80)]) {
        final spec = MorphFlexSpec.forSize(size);
        expect(spec.liftScalePoints, moreOrLessEquals(12.275862068965518));
        expect(
          spec.scaleDistanceThreshold,
          moreOrLessEquals(11586.206896551725, epsilon: 1e-9),
        );
        expect(spec.scaleSpring, const MorphSpring(0.36, 0.6));
        expect(spec.trackingSpring, const MorphSpring(0.314, 0.625));
      }
    });

    test('the long side decides the ultra small class', () {
      for (final size in const [Size(119.9, 40), Size(40, 119.9)]) {
        final spec = MorphFlexSpec.forSize(size);
        expect(spec.scaleDistanceThreshold, 2000, reason: '$size');
        expect(spec.littleGlowOpacity, 1, reason: '$size');
      }
      for (final size in const [Size(120, 40), Size(40, 120)]) {
        final spec = MorphFlexSpec.forSize(size);
        expect(spec.scaleDistanceThreshold, 6000, reason: '$size');
        expect(spec.littleGlowOpacity, moreOrLessEquals(0.3), reason: '$size');
        expect(
          spec.scaleSpring.response,
          moreOrLessEquals(0.3737931034482759),
          reason: '$size',
        );
      }
      final above = MorphFlexSpec.forSize(const Size(60, 121));
      expect(above.liftScalePoints, moreOrLessEquals(14.344827586206897));
    });

    test('the short side drives the lift from 44 to 160', () {
      for (final (short, lift) in const [
        (44.0, 16.0),
        (102.0, 10.0),
        (160.0, 4.0),
      ]) {
        expect(
          MorphFlexSpec.forSize(Size(300, short)).liftScalePoints,
          moreOrLessEquals(lift),
          reason: 'landscape $short',
        );
        expect(
          MorphFlexSpec.forSize(Size(short, 300)).liftScalePoints,
          moreOrLessEquals(lift),
          reason: 'portrait $short',
        );
      }
    });

    test('a 274 by 62 bar reads the native glow and lift', () {
      final spec = MorphFlexSpec.forSize(const Size(274, 62));
      expect(spec.liftScalePoints, moreOrLessEquals(14.137931, epsilon: 1e-6));
      expect(spec.littleGlowOpacity, moreOrLessEquals(0.284483, epsilon: 1e-6));
      expect(spec.bigGlowOpacity, moreOrLessEquals(0.844828, epsilon: 1e-6));
    });

    test('a loupe blends by its short side', () {
      for (final size in const [Size(37, 70), Size(70, 37)]) {
        final spec = MorphFlexSpec.loupeForSize(size);
        expect(spec.scaleSpring, const MorphSpring(0.444, 0.56));
        expect(spec.movementScalePoints, 10);
        expect(spec.scaleDistanceThreshold, 0);
        expect(spec.liftScalePoints, 0);
      }
      final full = MorphFlexSpec.loupeForSize(const Size(70, 300));
      expect(full.scaleSpring, const MorphSpring(0.5, 1));
      expect(full.movementScalePoints, 100);
      expect(full.scaleDistanceThreshold, 0);
    });
  });

  group('MorphFlexSpec.loupeForSize matches UIKit', () {
    test('blends by the short side between 37 and 70', () {
      final spec = MorphFlexSpec.loupeForSize(const Size(80, 54));
      expect(spec.movementScalePoints, moreOrLessEquals(56.36363636363637));
      expect(spec.movementMinScale, moreOrLessEquals(0.8227272727272728));
      expect(spec.movementMaxScale, moreOrLessEquals(1.125757575757576));
      expect(
        spec.movementNormalizationFactor,
        moreOrLessEquals(2257.575757575758, epsilon: 1e-9),
      );
      expect(spec.scaleSpring.response, moreOrLessEquals(0.4728484848484849));
      expect(
        spec.scaleSpring.dampingRatio,
        moreOrLessEquals(0.7866666666666666),
      );
      expect(
        spec.trackingSpring.dampingRatio,
        moreOrLessEquals(0.7351515151515151),
      );
    });

    test('clamps outside the range', () {
      expect(
        MorphFlexSpec.loupeForSize(const Size(30, 30)).scaleSpring,
        const MorphSpring(0.444, 0.56),
      );
      expect(
        MorphFlexSpec.loupeForSize(const Size(300, 300)).scaleSpring,
        const MorphSpring(0.5, 1),
      );
    });
  });
}
