import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/date_picker_motion.dart';

void main() {
  test('P3 date motion queries do not apply future scheduled changes', () {
    final motion = MorphDatePickerMotion();
    motion.open(0);
    expect(motion.progress(1), closeTo(1, 0.002));
    expect(motion.progress(0.05), 0);
    expect(motion.time, 0);
    expect(motion.isSettled, isFalse);
    expect(motion.isClosed, isFalse);
    motion.close(0.06);
    expect(motion.progress(0.06), 0);
    motion.advance(1);
    expect(motion.isClosed, isTrue);
  });

  test('P3 another page turn cannot reset the running slide', () {
    final motion = MorphDatePickerMotion();
    motion.turnPage(0, 1);
    final before = motion.page(0.15);
    motion.turnPage(0.15, 1);
    expect(motion.page(0.15), before);
    expect(motion.page(0.3), 1);
  });

  test('P10api reduced motion only suppresses the documented label dim', () {
    final regular = MorphDatePickerMotion();
    final reduced = MorphDatePickerMotion();
    reduced.reducedMotion = true;
    regular.open(0);
    reduced.open(0);
    regular.press(0);
    reduced.press(0);
    expect(regular.highlight(0.2), lessThan(1));
    expect(reduced.highlight(0.2), 1);
    expect(reduced.progress(0.2), regular.progress(0.2));
  });
}
