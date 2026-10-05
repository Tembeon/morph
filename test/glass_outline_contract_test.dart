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

  test('shapes moved together reuse their fused outline, moved', () {
    const shapes = [
      RRect.fromLTRBXY(16, 60, 160, 104, 22, 22),
      RRect.fromLTRBXY(166, 60, 210, 104, 22, 22),
    ];
    const offset = Offset(0.75, -37.5);
    final first = morphGlassContainerOutline(shapes, 12);
    final moved = morphGlassContainerOutline([
      for (final shape in shapes) shape.shift(offset),
    ], 12);
    for (var i = 0.0; i < 4; i++) {
      morphGlassContainerOutline([
        RRect.fromLTRBXY(0, 0, 40 + i, 40, 20, 20),
        RRect.fromLTRBXY(44 + i, 0, 84 + i, 40, 20, 20),
      ], 9);
    }
    final fresh = morphGlassContainerOutline([
      for (final shape in shapes) shape.shift(offset),
    ], 12);
    expect(fresh, isNot(same(moved)));
    final a = morphGlassOutlineField(moved)!;
    final b = morphGlassOutlineField(fresh)!;
    expect(a.cols, b.cols);
    expect(a.rows, b.rows);
    expect(a.origin.dx, closeTo(b.origin.dx, 1e-9));
    expect(a.origin.dy, closeTo(b.origin.dy, 1e-9));
    expect(
      identical(a.samples, morphGlassOutlineField(first)!.samples),
      isTrue,
    );
    var worst = 0.0;
    for (var i = 0; i < a.samples.length; i++) {
      final d = (a.samples[i] - b.samples[i]).abs();
      if (d > worst) worst = d;
    }
    expect(worst, lessThan(1e-4));
    final pa = moved.path.getBounds();
    final pb = fresh.path.getBounds();
    expect(pa.left, closeTo(pb.left, 1e-4));
    expect(pa.top, closeTo(pb.top, 1e-4));
    expect(pa.right, closeTo(pb.right, 1e-4));
    expect(pa.bottom, closeTo(pb.bottom, 1e-4));
  });
}
