import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/date_picker.dart';
import 'package:morph/src/widgets/search_field.dart';

void main() {
  testWidgets('C6 date label yields a scrolling touch without opening', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          children: [
            const SizedBox(height: 100),
            Center(
              child: MorphDatePicker(
                value: DateTime(2026, 10, 3),
                onChanged: (_) {},
              ),
            ),
            const SizedBox(height: 1500),
          ],
        ),
      ),
    );
    final label = find.byType(MorphDatePicker);
    final gesture = await tester.startGesture(
      tester.getBottomLeft(label) + const Offset(30, -4),
    );
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, -5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
    expect(find.text('October 2026'), findsNothing);
    expect(find.byType(ListWheelScrollView), findsNothing);
  });

  testWidgets('C6 search capsule stays at rest during a scrolling touch', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          children: [
            const SizedBox(height: 100),
            MorphSearchField(focusNode: focus),
            const SizedBox(height: 1500),
          ],
        ),
      ),
    );
    final field = find.byType(MorphSearchField);
    final gesture = await tester.startGesture(tester.getCenter(field));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 100));
    final transform = tester.widget<Transform>(
      find.descendant(of: field, matching: find.byType(Transform)).first,
    );
    expect(transform.transform.getMaxScaleOnAxis(), 1);
    expect(focus.hasFocus, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
  });
}
