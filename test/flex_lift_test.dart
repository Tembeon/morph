import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/motion/flex_spec.dart';

void main() {
  test('the lift grows the long side by the lift points', () {
    for (final size in const [Size(44, 44), Size(120, 44), Size(44, 120)]) {
      final spec = MorphFlexSpec.forSize(size);
      expect(
        spec.liftScaleFor(size) * size.longestSide,
        closeTo(size.longestSide + spec.liftScalePoints, 1e-9),
      );
    }
  });

  test('a portrait surface lifts like its landscape twin', () {
    const wide = Size(200, 80);
    const tall = Size(80, 200);
    expect(
      MorphFlexSpec.forSize(tall).liftScaleFor(tall),
      MorphFlexSpec.forSize(wide).liftScaleFor(wide),
    );
  });

  test('an empty surface does not lift', () {
    expect(MorphFlexSpec.ultraSmall.liftScaleFor(Size.zero), 1);
  });
}
