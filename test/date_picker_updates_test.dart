import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/date_picker.dart';

Semantics _wheel(WidgetTester tester, String label) => tester.widget<Semantics>(
  find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label),
);

void main() {
  testWidgets(
    'P3 time wheels follow parent updates and time bounds while open',
    (tester) async {
      var value = DateTime(2026, 10, 3, 7, 41);
      DateTime? first;
      DateTime? last;
      late StateSetter update;
      final changes = <DateTime>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: MorphDatePicker(
                  value: value,
                  firstDate: first,
                  lastDate: last,
                  mode: MorphDatePickerMode.time,
                  use24HourFormat: true,
                  onChanged: (next) {
                    changes.add(next);
                    setState(() => value = next);
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byType(MorphDatePicker));
      await tester.pumpAndSettle();
      update(() => value = DateTime(2026, 10, 3, 16, 12));
      await tester.pumpAndSettle();
      expect(_wheel(tester, 'Hour').properties.value, '16');
      expect(_wheel(tester, 'Minute').properties.value, '12');
      expect(changes, isEmpty);
      update(() {
        first = DateTime(2026, 10, 3, 17, 30);
        last = DateTime(2026, 10, 3, 17, 35);
      });
      await tester.pumpAndSettle();
      expect(_wheel(tester, 'Hour').properties.value, '17');
      expect(_wheel(tester, 'Minute').properties.value, '30');
      final minute = _wheel(tester, 'Minute');
      minute.properties.onDecrease!();
      await tester.pumpAndSettle();
      expect(changes.last, DateTime(2026, 10, 3, 17, 30));
      expect(_wheel(tester, 'Minute').properties.value, '30');
    },
  );

  testWidgets('C4 rejected time wheel returns to the parent value', (
    tester,
  ) async {
    final changes = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MorphDatePicker(
            value: DateTime(2026, 10, 3, 7, 41),
            mode: MorphDatePickerMode.time,
            use24HourFormat: true,
            onChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphDatePicker));
    await tester.pumpAndSettle();
    _wheel(tester, 'Hour').properties.onIncrease!();
    await tester.pumpAndSettle();
    expect(changes, [DateTime(2026, 10, 3, 8, 41)]);
    expect(_wheel(tester, 'Hour').properties.value, '07');
    _wheel(tester, 'Minute').properties.onIncrease!();
    await tester.pumpAndSettle();
    expect(changes.last, DateTime(2026, 10, 3, 7, 42));
    expect(_wheel(tester, 'Minute').properties.value, '41');
  });

  testWidgets('C4 rejected month wheel restores month and header', (
    tester,
  ) async {
    final changes = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MorphDatePicker(
            value: DateTime(2026, 10, 3),
            onChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphDatePicker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('October 2026'));
    await tester.pumpAndSettle();
    _wheel(tester, 'Month').properties.onIncrease!();
    await tester.pumpAndSettle();
    expect(changes, [DateTime(2026, 11, 3)]);
    expect(_wheel(tester, 'Month').properties.value, 'October');
    expect(find.text('October 2026'), findsOneWidget);
  });

  testWidgets('P3 quick month taps complete both slides without restarting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MorphDatePicker(
            value: DateTime(2026, 10, 3),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphDatePicker));
    await tester.pumpAndSettle();
    final next = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Next month',
    );
    await tester.tap(next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('December 2026'), findsOneWidget);
  });
}
