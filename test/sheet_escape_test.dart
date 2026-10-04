import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/sheet.dart';
import 'package:morph/src/widgets/sheet_motion.dart';

void main() {
  for (final dismissible in [true, false]) {
    testWidgets('Escape respects sheet dismissible=$dismissible', (
      tester,
    ) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: nav, home: const SizedBox()),
      );
      nav.currentState!.push<void>(
        MorphSheetRoute<void>(
          dismissible: dismissible,
          detents: const [MorphSheetDetent.medium],
          builder: (_) => const Text('sheet'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('sheet'), dismissible ? findsNothing : findsOneWidget);
    });
  }
}
