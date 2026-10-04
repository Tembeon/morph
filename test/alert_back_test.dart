import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/alert.dart';

void main() {
  for (final systemBack in [true, false]) {
    testWidgets(
      'alert cancels after dismissal on ${systemBack ? 'back' : 'pop'}',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        var cancelled = 0;
        final cancel = MorphAlertAction(
          title: 'Cancel',
          style: MorphAlertActionStyle.cancel,
          onPressed: () => cancelled++,
        );
        await tester.pumpWidget(
          MaterialApp(navigatorKey: nav, home: const SizedBox()),
        );
        final route = MorphAlertRoute(title: 'Alert', actions: [cancel]);
        final result = nav.currentState!.push<MorphAlertAction>(route);
        await tester.pumpAndSettle();
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          nav.currentState!.pop();
        }
        expect(cancelled, 0);
        await tester.pumpAndSettle();
        expect(cancelled, 1);
        expect(await result, same(cancel));
        expect(find.text('Alert'), findsNothing);
      },
    );
  }
}
