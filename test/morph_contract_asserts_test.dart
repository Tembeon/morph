import 'package:material_ui/material_ui.dart';
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
}
