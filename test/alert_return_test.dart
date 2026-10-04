import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/alert.dart';

void main() {
  for (final enabled in [true, false]) {
    testWidgets(
      'Return in an alert field respects preferred enabled=$enabled',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        var chosen = 0;
        final accept = MorphAlertAction(
          title: 'Accept',
          isPreferred: true,
          enabled: enabled,
          onPressed: () => chosen++,
        );
        await tester.pumpWidget(
          MaterialApp(navigatorKey: nav, home: const SizedBox()),
        );
        final route = MorphAlertRoute(
          title: 'Alert',
          actions: [accept],
          textFields: const [MorphAlertTextField(placeholder: 'Name')],
        );
        nav.currentState!.push<MorphAlertAction>(route);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText), 'Ada');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(chosen, enabled ? 1 : 0);
        expect(route.isActive, !enabled);
      },
    );
  }

  testWidgets('physical Return in a focused alert field chooses preferred', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    var chosen = 0;
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const SizedBox()),
    );
    nav.currentState!.push<MorphAlertAction>(
      MorphAlertRoute(
        actions: [
          MorphAlertAction(
            title: 'Accept',
            isPreferred: true,
            onPressed: () => chosen++,
          ),
        ],
        textFields: const [MorphAlertTextField()],
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(chosen, 1);
  });
}
