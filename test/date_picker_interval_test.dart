import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/date_picker.dart';
import 'package:morph/widgets.dart';

void main() {
  testWidgets('the minute wheel steps by the minute interval', (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 956));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final picked = <DateTime>[];
    var current = DateTime(2026, 10, 3, 9, 41);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => Align(
            alignment: const Alignment(0, -0.4),
            child: MorphDatePicker(
              value: current,
              mode: MorphDatePickerMode.time,
              use24HourFormat: true,
              minuteInterval: 15,
              onChanged: (DateTime v) {
                picked.add(v);
                setState(() => current = v);
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('09:41'), findsNothing);
    await tester.tap(find.text('09:30'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    final minutes = find.byType(ListWheelScrollView).last;
    expect(
      find.descendant(of: minutes, matching: find.text('45')),
      findsWidgets,
    );
    expect(
      find.descendant(of: minutes, matching: find.text('41')),
      findsNothing,
    );
    await tester.timedDrag(
      minutes,
      const Offset(0, -64),
      const Duration(milliseconds: 375),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(picked, isNotEmpty);
    expect(picked.last.minute % 15, 0);
  });

  test('a minute interval rounds down and drops the seconds', () {
    expect(morphFloorMinute(44, 15), 30);
    expect(morphFloorMinute(58, 5), 55);
    expect(morphFloorMinute(58, 1), 58);
    expect(
      morphFloorToMinuteInterval(DateTime(2026, 10, 3, 9, 59, 42), 15),
      DateTime(2026, 10, 3, 9, 45),
    );
  });

  test('the variant enum reserves UIKit styles', () {
    expect(MorphDatePickerStyle.values.map((s) => s.name), [
      'compact',
      'inline',
      'wheels',
    ]);
  });
}
