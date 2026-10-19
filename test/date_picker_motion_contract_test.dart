import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/date_picker_motion.dart';
import 'support/motion_at.dart';

void main() {
  test('P3 date motion reads stay at the motion time', () {
    final motion = MorphDatePickerMotion();
    motion.open(0);
    expect(motion.progress, 0);
    expect(motion.time, 0);
    expect(motion.isSettled, isFalse);
    expect(motion.isClosed, isFalse);
    expect(motion.at(0.05).progress, 0);
    motion.close(0.06);
    expect(motion.progress, 0);
    motion.advance(1);
    expect(motion.isClosed, isTrue);
  });

  test('P3 another page turn cannot reset the running slide', () {
    final motion = MorphDatePickerMotion();
    motion.turnPage(0, 1);
    final before = motion.at(0.15).page;
    motion.turnPage(0.15, 1);
    expect(motion.at(0.15).page, before);
    expect(motion.at(0.3).page, 1);
  });

  test('P10api reduced motion drops the label dim and fades the overlay', () {
    final regular = MorphDatePickerMotion();
    final reduced = MorphDatePickerMotion();
    reduced.reducedMotion = true;
    regular.open(0);
    reduced.open(0);
    regular.press(0);
    reduced.press(0);
    expect(regular.at(0.2).highlight, lessThan(1));
    expect(reduced.at(0.2).highlight, 1);
    const start = MorphDatePickerTuning.openDelay;
    const fade = MorphDatePickerTuning.reducedMotionDuration;
    reduced.advance(start + fade / 2);
    expect(reduced.at(start + fade / 2).opacity, closeTo(0.5, 1e-9));
    expect(reduced.at(start + fade / 2).scale, 1);
    expect(reduced.at(start + fade / 2).height(300), 300);
    expect(regular.at(start + fade / 2).scale, lessThan(1));
    reduced.advance(start + fade);
    expect(reduced.at(start + fade).opacity, 1);
    reduced.close(1);
    reduced.advance(1 + MorphDatePickerTuning.closeDelay + fade);
    expect(reduced.isClosed, isTrue);
  });
}
