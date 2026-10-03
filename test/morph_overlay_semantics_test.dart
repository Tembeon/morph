import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

Future<void> settle(WidgetTester tester, {int frames = 400}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

void main() {
  testWidgets('an open overlay blocks semantics of the page behind', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const Text('page-text'),
              MorphTag(
                id: 'btn',
                child: Builder(
                  builder: (BuildContext context) => TextButton(
                    onPressed: () => flight = showMorphDialog(
                      context,
                      from: 'btn',
                      builder: (BuildContext context, MorphFlight f) =>
                          const Text('dialog-content'),
                    ),
                    child: const Text('open-me'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.semantics.byLabel('page-text'), findsOne);
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);

    // The page behind the scrim must be gone from the semantics tree,
    // like behind any modal barrier.
    expect(find.text('page-text'), findsOneWidget);
    expect(find.semantics.byLabel('page-text'), findsNothing);
    expect(find.semantics.byLabel('dialog-content'), findsOne);

    flight!.close();
    await settle(tester);
    expect(find.semantics.byLabel('page-text'), findsOne);
    semantics.dispose();
  });
}
