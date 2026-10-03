import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

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
    test('narrow surfaces are ultra small whatever their height', () {
      for (final size in const [Size(30, 30), Size(100, 54), Size(116, 90)]) {
        final spec = MorphFlexSpec.forSize(size);
        expect(spec.liftScalePoints, 16, reason: '$size');
        expect(spec.scaleDistanceThreshold, 2000, reason: '$size');
        expect(spec.scaleSpring, const MorphSpring(0.4, 0.375));
      }
    });

    test('springs follow the width and sizes follow the height', () {
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

  group('MorphFlexSpec.loupeForSize matches UIKit', () {
    test('blends by height between 37 and 70', () {
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
