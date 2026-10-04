import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/date_picker.dart';
import 'package:morph/src/widgets/page_control.dart';
import 'package:morph/src/widgets/stepper.dart';

void main() {
  testWidgets('P7api page and stepper expose caller-formatted values', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            MorphPageControl(
              count: 3,
              page: 1,
              onChanged: (_) {},
              semanticValueFormatter: (page, count) => '$page / $count',
            ),
            MorphStepper(value: 0.1 + 0.2, onChanged: (_) {}),
            MorphStepper(
              value: 4,
              onChanged: (_) {},
              semanticValueFormatter: (value) => 'count=$value',
            ),
          ],
        ),
      ),
    );
    final values = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((s) => s.properties.value)
        .toList();
    expect(values, containsAll(['2 / 3', '0.3', 'count=4.0']));
    expect(values, isNot(contains('0.30000000000000004')));
  });

  testWidgets(
    'P7api calendar header, weekdays and day semantics are localizable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: MorphDatePicker(
              value: DateTime(2026, 10, 3),
              onChanged: (_) {},
              localize: (text) => 'L:$text',
              calendarTitleFormatter: (date) => 'title:${date.month}',
              daySemanticFormatter: (date) => 'day:${date.day}',
              numberFormatter: (number) => 'n:$number',
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MorphDatePicker));
      await tester.pumpAndSettle();
      expect(find.text('title:10'), findsOneWidget);
      expect(find.text('L:SUN'), findsOneWidget);
      expect(find.text('n:3'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'day:3',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('title:10'));
      await tester.pumpAndSettle();
      expect(find.text('L:October'), findsWidgets);
      expect(find.text('n:2026'), findsWidgets);
    },
  );
}
