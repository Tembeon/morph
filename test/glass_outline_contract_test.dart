import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/widgets.dart';

void main() {
  test('K2 rejects nonuniform and elliptical distance-field corners', () {
    final nonuniform = RRect.fromRectAndCorners(
      const Rect.fromLTWH(0, 0, 80, 40),
      topLeft: const Radius.circular(10),
      topRight: const Radius.circular(20),
    );
    expect(() => MorphOutlineBoxes([nonuniform]), throwsAssertionError);
    expect(
      () => MorphOutlineBoxes([
        RRect.fromRectXY(const Rect.fromLTWH(0, 0, 80, 40), 10, 15),
      ]),
      throwsAssertionError,
    );
  });

  testWidgets('K1 a fused body survives gaining a separate surface', (
    tester,
  ) async {
    isLocalTest = true;
    addTearDown(() => isLocalTest = false);
    const a = RRect.fromLTRBXY(0, 0, 50, 44, 22, 22);
    const b = RRect.fromLTRBXY(55, 0, 105, 44, 22, 22);
    const c = RRect.fromLTRBXY(180, 0, 230, 44, 22, 22);
    MorphGlassSurface surface(RRect shape) => MorphGlassSurface(
      kind: MorphGlassKind.button,
      shape: shape,
      color: const Color(0xFFFFFFFF),
      brightness: Brightness.light,
    );
    Widget host({required bool separate}) => Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 300,
        height: 80,
        child: Builder(
          builder: (context) => const MorphGlassRenderer().buildLayer(context, [
            surface(a),
            surface(b),
            if (separate) surface(c),
          ], spacing: 12),
        ),
      ),
    );
    final body = find.descendant(
      of: find.byKey(const ValueKey<String>('body')),
      matching: find.byType(LiquidGlassLayer),
    );
    await tester.pumpWidget(host(separate: false));
    final element = body.evaluate().single;
    await tester.pumpWidget(host(separate: true));
    expect(body.evaluate().single, same(element));
    await tester.pumpWidget(host(separate: false));
    expect(body.evaluate().single, same(element));
  });

  test('a plain union at spacing 0 carries a finite field', () {
    for (final shapes in [
      [
        const RRect.fromLTRBXY(0, 0, 60, 40, 12, 12),
        const RRect.fromLTRBXY(40, 0, 100, 40, 12, 12),
      ],
      [
        const RRect.fromLTRBXY(0, 0, 60, 40, 12, 12),
        const RRect.fromLTRBXY(70, 0, 130, 40, 12, 12),
        const RRect.fromLTRBXY(0, 50, 130, 90, 20, 20),
      ],
    ]) {
      final field = morphGlassOutlineField(
        morphGlassContainerOutline(shapes, 0),
      )!;
      expect(field.samples.where((value) => value.isNaN), isEmpty);
    }
  });
}
