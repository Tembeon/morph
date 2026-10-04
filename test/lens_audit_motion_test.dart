import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/lens_motion.dart';
import 'package:morph/src/widgets/slider_motion.dart';
import 'package:morph/src/widgets/small_lens.dart';

MorphSmallLens _small() => MorphSmallLens(
  restSize: const Size(37, 24),
  liftedSize: const Size(58, 38.33),
);

MorphLensMotion _lens({double distance = 120}) => MorphLensMotion(
  tuning: MorphLensTuning.segmented,
  slots: [(center: 60, width: 116), (center: 60 + distance, width: 116)],
  selected: 0,
  height: 28,
);

void main() {
  test('C1 re-lift carries progress and size landing velocity', () {
    final lens = _small();
    lens.lift(0);
    lens.unlift(0.3);
    lens.advance(0.4);
    const dt = 1e-6;
    final value = lens.progress(0.4);
    final velocity = (value - lens.progress(0.4 - dt)) / dt;
    final at = 0.4 + lens.sizeLag;
    final width = lens.size(at).width;
    final sizeVelocity = (width - lens.size(at - dt).width) / dt;
    lens.lift(0.4);
    expect(lens.progress(0.4), value);
    expect((lens.progress(0.4 + dt) - value) / dt, closeTo(velocity, 0.01));
    expect(lens.size(at).width, width);
    expect((lens.size(at + dt).width - width) / dt, closeTo(sizeVelocity, 0.1));
  });

  test('C2 programmatic slider jumps do not accelerate the flex loop', () {
    final motion = MorphSliderMotion(width: 300, value: 0.3);
    motion.advance(0);
    motion.advance(0.1);
    motion.setValue(0.1, 0.4);
    for (var i = 1; i <= 40; i++) {
      motion.advance(0.1 + i / 120);
      expect(motion.lens.scaleX(motion.time), closeTo(1, 1e-10));
      expect(motion.lens.scaleY(motion.time), closeTo(1, 1e-10));
    }
  });

  test('C2 slider relayout does not accelerate the flex loop', () {
    final motion = MorphSliderMotion(width: 300, value: 0.3);
    motion.advance(0);
    motion.advance(0.1);
    motion.width = 600;
    for (var i = 1; i <= 40; i++) {
      motion.advance(0.1 + i / 120);
      expect(motion.lens.scaleX(motion.time), closeTo(1, 1e-10));
      expect(motion.lens.scaleY(motion.time), closeTo(1, 1e-10));
    }
  });

  test('C2 extreme physical samples never invert the small lens', () {
    final lens = _small();
    lens.advance(0, (_) => 0);
    for (var i = 1; i <= 60; i++) {
      lens.advance(i / 120, (t) => t < 0.1 ? 0 : 1000000);
      expect(lens.scaleY(i / 120), greaterThan(0));
    }
  });

  test('C3 lifted slot relayout does not fabricate acceleration', () {
    final motion = _lens();
    motion.pointerDown(0, 60);
    motion.advance(0.4);
    motion.slots = const [(center: 260, width: 116), (center: 380, width: 116)];
    for (var i = 1; i <= 60; i++) {
      motion.advance(0.4 + i / 120);
      expect(motion.center, closeTo(260, 1e-10));
      expect(motion.scaleX, closeTo(1, 1e-10));
      expect(motion.scaleY, closeTo(1, 1e-10));
    }
  });

  test('C3 pending travel uses the new slot geometry', () {
    final motion = _lens();
    motion.pointerDown(0, 180);
    motion.pointerUp(0.01, 180);
    motion.slots = const [(center: 260, width: 116), (center: 380, width: 116)];
    motion.advance(2);
    expect(motion.center, closeTo(380, 0.01));
    expect(motion.isSettled, isTrue);
  });

  test('C3 extreme travel saturates flex without NaN', () {
    for (final distance in [1e8, -1e8]) {
      final motion = _lens(distance: distance);
      motion.pointerDown(0, 60 + distance);
      motion.pointerUp(0.05, 60 + distance);
      for (var i = 1; i <= 120; i++) {
        motion.advance(0.05 + i / 120);
        expect(motion.center.isFinite, isTrue);
        expect(motion.scaleX.isFinite, isTrue);
        expect(motion.scaleY.isFinite, isTrue);
      }
    }
  });

  test('C8 empty slots and invalid selections are safe', () {
    final motion = MorphLensMotion(
      tuning: MorphLensTuning.segmented,
      slots: const [],
      selected: 30,
      height: 28,
    );
    motion.pointerDown(0, 50);
    motion.pointerMove(0.1, 100);
    motion.pointerUp(0.2, 100);
    motion.pointerCancel(0.3);
    motion.select(0.4, -5);
    motion.advance(1);
    expect(motion.selected, -1);
    expect(motion.slotAt(0), -1);
    motion.slots = const [(center: 60, width: 116)];
    motion.select(1, 30);
    expect(motion.selected, 0);
    motion.slots = const [];
    motion.advance(2);
    expect(motion.selected, -1);
  });
}
