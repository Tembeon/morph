import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';
import 'package:morph/src/liquid_field.dart' show LiquidField;

void main() {
  testWidgets('a snapToEnd close spring is rejected at controller creation', (
    WidgetTester tester,
  ) async {
    const MorphMotion broken = MorphMotion(
      name: 'broken',
      openMotion: CupertinoMotion.smooth(),
      closeMotion: CupertinoMotion(snapToEnd: true),
    );
    expect(
      () => MorphController(vsync: const TestVSync(), motion: broken),
      throwsAssertionError,
    );

    final MorphController c = MorphController(vsync: const TestVSync());
    addTearDown(c.dispose);
    expect(() => c.motion = broken, throwsAssertionError);
  });

  test('a reveal range outside 0 <= from < to <= 1 is rejected', () {
    expect(
      () => MorphReveal(from: 0.9, to: 0.4, child: const SizedBox()),
      throwsAssertionError,
    );
    expect(
      () => MorphReveal(from: -0.1, to: 0.5, child: const SizedBox()),
      throwsAssertionError,
    );
  });

  test('liquid knobs reject nonsense distances', () {
    expect(() => LiquidField(const <MorphMass>[], k: -1), throwsAssertionError);
    expect(
      () => MorphMass.box(const Rect.fromLTWH(0, 0, 10, 10), radius: -1),
      throwsAssertionError,
    );
    expect(
      () => MorphMass.bridge(Offset.zero, const Offset(10, 0), radius: 0),
      throwsAssertionError,
    );
  });

  testWidgets('a manual MorphTag inside a skin piece must zero its own bump', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: const Scaffold(
          body: MorphSkin(
            color: Color(0xFF444444),
            pieces: <MorphPiece>[
              MorphPiece(
                id: 'p',
                rect: Rect.fromLTWH(20, 20, 120, 48),
                // The trap: a manual tag keeps the DEFAULT bump, so the
                // tag and the skin would both squash on landing.
                child: MorphTag(
                  id: 'p',
                  child: Text('piece', textDirection: TextDirection.ltr),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final BuildContext context = tester.element(find.text('piece'));
    showMorph(
      context,
      from: 'p',
      target: MorphTargetSpec.dialog(),
      builder: (BuildContext context, MorphFlight flight) => const SizedBox(),
    );
    await tester.pump();
    expect(tester.takeException(), isFlutterError);
    // Drain the broken flight so no tickers leak into other tests.
    await tester.pumpWidget(const SizedBox());
  });
}
