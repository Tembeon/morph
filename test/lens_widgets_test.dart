import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: SizedBox(width: 360, child: child)),
);

void main() {
  testWidgets('a segmented control selects on release and settles', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => MorphSegmentedControl(
            segments: const ['A', 'B', 'C'],
            selected: selected,
            onChanged: (i) => setState(() => selected = i),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(find.text('C')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(selected, 0, reason: 'a segmented control waits for the release');
    await gesture.up();
    await tester.pump();
    expect(selected, 2);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a tab bar selects on contact and settles after release', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: StatefulBuilder(
            builder: (context, setState) => MorphTabBar(
              items: const [
                MorphTabItem(icon: IconData(0xe318), label: 'One'),
                MorphTabItem(icon: IconData(0xe318), label: 'Two'),
                MorphTabItem(icon: IconData(0xe318), label: 'Three'),
              ],
              selected: selected,
              onChanged: (i) => setState(() => selected = i),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Three')),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(selected, 2, reason: 'a tab bar selects on contact');
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  test('a pressed selected segment can be dragged to another one', () {
    final motion = MorphLensMotion(
      tuning: MorphLensTuning.segmented,
      slots: const [
        (center: 60, width: 116),
        (center: 180, width: 116),
        (center: 300, width: 116),
      ],
      selected: 0,
      height: 28,
    );
    final picked = <int>[];
    motion.onSelect = picked.add;
    motion.advance(0);
    motion.pointerDown(0.1, 60);
    for (var i = 1; i <= 30; i++) {
      motion.pointerMove(0.1 + i / 60, 60 + i * 8);
    }
    motion.advance(0.7);
    expect(motion.center, greaterThan(250));
    expect(motion.lift, closeTo(1, 0.01));
    motion.pointerUp(0.7, 300);
    expect(picked, [2]);
    motion.advance(2.5);
    expect(motion.center, closeTo(300, 0.05));
    expect(motion.isSettled, isTrue);
  });

  test('a drag past the last segment rubber-bands within 12 px', () {
    final motion = MorphLensMotion(
      tuning: MorphLensTuning.segmented,
      slots: const [(center: 60, width: 116), (center: 180, width: 116)],
      selected: 1,
      height: 28,
    );
    motion.advance(0);
    motion.pointerDown(0.1, 180);
    for (var i = 1; i <= 60; i++) {
      motion.pointerMove(0.1 + i / 60, 180 + i * 4);
    }
    motion.advance(2);
    expect(motion.center - 180, inInclusiveRange(9, 12));
  });
}
