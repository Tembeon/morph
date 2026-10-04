import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/glass_glow.dart';

void main() {
  test('A5 glow delayed reactions agree under coarse and fine advances', () {
    final coarse = MorphTouchGlowMotion(washPeak: 1, spotPeak: 1);
    final fine = MorphTouchGlowMotion(washPeak: 1, spotPeak: 1);
    for (final motion in [coarse, fine]) {
      motion.pointerDown(0, Offset.zero);
      motion.pointerMove(0.01, const Offset(60, 0));
      motion.pointerUp(0.02);
    }
    for (var i = 3; i <= 400; i++) {
      fine.advance(i / 1000);
    }
    coarse.advance(0.4);
    expect(coarse.washOpacity(0.4), fine.washOpacity(0.4));
    expect(coarse.spotOpacity(0.4), fine.spotOpacity(0.4));
    expect(coarse.spotScale(0.4), fine.spotScale(0.4));
  });

  test('A5 releasing before the rise delay never reignites the glow', () {
    final motion = MorphTouchGlowMotion(washPeak: 1, spotPeak: 1);
    motion.pointerDown(0, Offset.zero);
    motion.pointerUp(0.01);
    motion.advance(2);
    expect(motion.washOpacity(2), 0);
    expect(motion.spotOpacity(2), 0);
    expect(motion.isSettled(2), isTrue);
  });
}
