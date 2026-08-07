import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

void main() {
  Widget host() {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const .all(24),
            child: MorphTag(
              id: 'player',
              shape: const RoundedRectangleBorder(
                borderRadius: .all(.circular(16)),
              ),
              surfaceColor: const Color(0xFF222222),
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphDialog(
                    context,
                    from: 'player',
                    width: 400,
                    height: 400,
                    motion: .glacial,
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Padding(
                          padding: .all(40),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: MorphSharedElement(
                              id: 'cover',
                              child: SizedBox(
                                width: 200,
                                height: 200,
                                child: ColoredBox(
                                  color: Color(0xFF7C5CFF),
                                  child: Text('art'),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                  child: const Row(
                    mainAxisSize: .min,
                    children: <Widget>[
                      MorphSharedElement(
                        id: 'cover',
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: ColoredBox(
                            color: Color(0xFF7C5CFF),
                            child: Text('art'),
                          ),
                        ),
                      ),
                      Text('mini'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the cover flies between its endpoint rects', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    final Rect sourceCover = tester.getRect(
      find.byType(MorphSharedElement).first,
    );

    await tester.tap(find.text('mini'));
    await tester.pump();
    // Two glacial-flight frames in: the flying layer must exist and sit
    // between the endpoints, larger than the source and smaller than
    // the target.
    await tester.pump(const Duration(milliseconds: 300));
    final Finder flying = find.byKey(
      const ValueKey<String>('morph-shared-fly-cover'),
    );
    expect(flying, findsOneWidget);
    final Rect mid = tester.getRect(flying);
    expect(mid.width, greaterThan(sourceCover.width));
    expect(mid.width, lessThan(200));
    expect(tester.takeException(), isNull);

    // Settle fully: the flying layer hands back to the real target
    // element.
    for (int i = 0; i < 600; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(flying, findsNothing);
    expect(tester.takeException(), isNull);

    // Close through to the latch and the end: no exceptions, the live
    // button is back with its marker rendered normally.
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    scope.flightOf('player')!.close();
    for (int i = 0; i < 900; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(tester.takeException(), isNull);
    expect(find.text('mini'), findsOneWidget);
  });

  testWidgets('an unpaired id degrades to plain rendering', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Center(
            child: MorphTag(
              id: 'solo',
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphDialog(
                    context,
                    from: 'solo',
                    builder: (BuildContext context, MorphFlight flight) =>
                        const MorphSharedElement(
                          id: 'orphan',
                          child: Text('alone'),
                        ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(
      find.byKey(const ValueKey<String>('morph-shared-fly-orphan')),
      findsNothing,
    );
    expect(find.text('alone'), findsOneWidget);
  });
}
