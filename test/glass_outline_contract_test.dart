import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/widgets.dart';

void main() {
  test(
    'flat fusion keeps the exact contour without sharing optical caches',
    () {
      final random = math.Random(20261008);
      for (var trial = 0; trial < 120; trial++) {
        final shapes = [
          for (var i = 0; i < 2 + trial % 3; i++)
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                i * 43 + random.nextDouble() * 8,
                random.nextDouble() * 12,
                38 + random.nextDouble() * 36,
                30 + random.nextDouble() * 20,
              ),
              Radius.circular(8 + random.nextDouble() * 6),
            ),
        ];
        final spacing = 8 + random.nextDouble() * 16;
        final flat = morphGlassContainerOutline(
          shapes,
          spacing,
          withField: false,
        );
        final optical = morphGlassContainerOutline(shapes, spacing);
        expect(morphGlassOutlineField(flat), isNull);
        expect(morphGlassOutlineField(optical), isNotNull);
        expect(morphGlassContainerOutline(shapes, spacing), same(optical));
        expect(
          morphGlassContainerOutline(shapes, spacing, withField: false),
          same(flat),
        );
        void equalPaths(Path a, Path b) {
          expect(a.getBounds(), b.getBounds());
          final first = a.computeMetrics().toList();
          final second = b.computeMetrics().toList();
          expect(first.length, second.length);
          for (var i = 0; i < first.length; i++) {
            expect(first[i].length, second[i].length);
            for (var t = 0.0; t < first[i].length; t += 0.75) {
              expect(
                first[i].getTangentForOffset(t)!.position,
                second[i].getTangentForOffset(t)!.position,
              );
            }
          }
        }

        equalPaths(flat.path, optical.path);
        const shift = Offset(0.75, -37.5);
        final moved = [for (final shape in shapes) shape.shift(shift)];
        equalPaths(
          morphGlassContainerOutline(moved, spacing, withField: false).path,
          flat.shift(shift).path,
        );
        final frame = MorphGlassFrame([
          for (final shape in shapes)
            MorphGlassSurface(
              kind: MorphGlassKind.bar,
              shape: shape,
              color: const Color(0xFFFFFFFF),
              brightness: Brightness.dark,
            ),
        ], spacing: spacing);
        for (final (_, outline) in frame.partsFor(MorphGlassTier.flat).fused) {
          expect(morphGlassOutlineField(outline), isNull);
        }
        for (final (_, outline) in frame.partsFor(MorphGlassTier.fake).fused) {
          expect(morphGlassOutlineField(outline), isNotNull);
        }
        expect(frame.partsFor(MorphGlassTier.liquid), same(frame.parts));
      }
    },
  );

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

  test('a plain union at spacing 0 is the exact union of its boxes', () {
    for (final (shapes, parts) in [
      (
        [
          const RRect.fromLTRBXY(0, 0, 60, 40, 12, 12),
          const RRect.fromLTRBXY(40, 0, 100, 40, 12, 12),
        ],
        1,
      ),
      (
        [
          const RRect.fromLTRBXY(0, 0, 60, 40, 12, 12),
          const RRect.fromLTRBXY(70, 0, 130, 40, 12, 12),
          const RRect.fromLTRBXY(0, 50, 130, 90, 20, 20),
        ],
        3,
      ),
      (
        [
          const RRect.fromLTRBXY(0, 0, 260, 440, 34, 34),
          const RRect.fromLTRBXY(20, 20, 44, 44, 12, 12),
        ],
        1,
      ),
      (
        [
          const RRect.fromLTRBXY(0, 0, 60, 40, 12, 12),
          const RRect.fromLTRBXY(0, 0, 60, 40, 12, 12),
        ],
        1,
      ),
      (
        [
          const RRect.fromLTRBXY(0, 0, 60, 40, 20, 20),
          const RRect.fromLTRBXY(40, 0, 100, 40, 20, 20),
        ],
        1,
      ),
    ]) {
      final outline = morphGlassContainerOutline(shapes, 0);
      expect(morphGlassOutlineField(outline), isNull);
      expect(morphGlassOutlineShapes(outline), shapes);
      expect(identical(morphGlassContainerOutline(shapes, 0), outline), isTrue);
      final boxes = MorphOutlineBoxes(shapes);
      final area = outline.bounds.inflate(3);
      for (var y = area.top; y <= area.bottom; y += 0.75) {
        for (var x = area.left; x <= area.right; x += 0.75) {
          var d = boxes.distance(0, x, y);
          for (var i = 1; i < shapes.length; i++) {
            d = math.min(d, boxes.distance(i, x, y));
          }
          if (d.abs() < 0.05) continue;
          expect(outline.path.contains(Offset(x, y)), d < 0, reason: '$x $y');
        }
      }
      final rim = [
        for (final metric in outline.path.computeMetrics()) metric.length,
      ];
      expect(rim, hasLength(parts));
    }
    final moved = morphGlassContainerOutline([
      const RRect.fromLTRBXY(0, 0, 60, 40, 12, 12),
    ], 0).shift(const Offset(5, 7));
    expect(morphGlassOutlineShapes(moved), [
      const RRect.fromLTRBXY(5, 7, 65, 47, 12, 12),
    ]);
    expect(moved.bounds, const Rect.fromLTRB(5, 7, 65, 47));
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
