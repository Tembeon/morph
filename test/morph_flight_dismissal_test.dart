import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

void main() {
  testWidgets('declining dismissal keeps back above the open overlay', (
    WidgetTester tester,
  ) async {
    int requests = 0;
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    );
    final MaterialPageRoute<void> page = MaterialPageRoute<void>(
      builder: (BuildContext context) => Scaffold(
        body: MorphAnchor(
          tagId: 'anchor',
          isOpen: true,
          onDismiss: () => requests++,
          target: MorphTargetSpec.dialog(),
          closedBuilder: (BuildContext context) => const Text('source'),
          openBuilder: (BuildContext context, MorphFlight flight) =>
              const Text('overlay'),
        ),
      ),
    );
    unawaited(navigatorKey.currentState!.push(page));
    await tester.pumpAndSettle();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('anchor')!;

    for (int i = 0; i < 3; i++) {
      expect(await navigatorKey.currentState!.maybePop(), isTrue);
      await tester.pump();
      expect(requests, i + 1);
      expect(page.isCurrent, isTrue);
      expect(page.willHandlePopInternally, isTrue);
      expect(flight.isOpenOrOpening, isTrue);
      expect(find.text('overlay'), findsOneWidget);
    }

    flight.close();
    await tester.pumpAndSettle();
    expect(page.willHandlePopInternally, isFalse);
    expect(await navigatorKey.currentState!.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(page.isActive, isFalse);
    expect(find.text('home'), findsOneWidget);
  });
}
