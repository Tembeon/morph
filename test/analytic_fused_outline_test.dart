// The test reads the renderer's and the widget layer's internals.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

RRect _capsule(double left, double top, double width) => RRect.fromLTRBR(
  left,
  top,
  left + width,
  top + 44,
  const Radius.circular(22),
);

MorphGlassSurface _bar(RRect shape) => MorphGlassSurface(
  kind: MorphGlassKind.bar,
  shape: shape,
  color: const Color(0x00000000),
  brightness: Brightness.dark,
);

/// A frame of [shapes] in a glass container with spacing 12.
MorphGlassFrame _frame(List<RRect> shapes) =>
    MorphGlassFrame([for (final shape in shapes) _bar(shape)], spacing: 12);

void main() {
  final pair = [_capsule(16, 0, 44), _capsule(66, 0, 44)];
  final five = [for (var i = 0; i < 5; i++) _capsule(16 + i * 50.0, 0, 44)];

  setUp(debugClearMorphGlassOutlines);
  tearDown(() => RenderLiquidGlassLayer.debugAnalyticGeometry = null);

  test('the liquid tier with analytic geometry merges boxes without '
      'fusing them on the CPU', () {
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    final traces = morphGlassOutlineDebugTraces;
    final (members, outline) = _frame(
      pair,
    ).partsFor(MorphGlassTier.liquid).fused.single;
    expect(members, hasLength(2));
    final field = morphGlassOutlineField(outline);
    expect(field, isA<GlassBoxField>());
    final boxes = field! as GlassBoxField;
    expect(boxes.boxes, pair);
    expect(boxes.spacing, 12);
    expect(morphGlassOutlineDebugTraces, traces);
    // The path is the plain union, for the body's shadow.
    expect(
      outline.bounds,
      pair.first.outerRect.expandToInclude(pair.last.outerRect),
    );
    // Reading the samples fuses the field the package would have fused.
    final expected = morphGlassOutlineField(
      morphGlassContainerOutline(pair, 12),
    )!;
    expect(boxes.samples, same(expected.samples));
    expect(boxes.origin, expected.origin);
    expect(boxes.step, expected.step);
  });

  test('a body of more than four boxes keeps its fused field', () {
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    final (_, outline) = _frame(
      five,
    ).partsFor(MorphGlassTier.liquid).fused.single;
    final field = morphGlassOutlineField(outline);
    expect(field, isNotNull);
    expect(field, isNot(isA<GlassBoxField>()));
  });

  for (final analytic in [false, true]) {
    test(
      'fake and flat outlines are the package fusion, analytic $analytic',
      () {
        RenderLiquidGlassLayer.debugAnalyticGeometry = analytic;
        final frame = _frame(pair);
        final fake = frame.partsFor(MorphGlassTier.fake).fused.single.$2;
        final flat = frame.partsFor(MorphGlassTier.flat).fused.single.$2;
        expect(fake, same(morphGlassContainerOutline(pair, 12)));
        expect(
          flat,
          same(morphGlassContainerOutline(pair, 12, withField: false)),
        );
        expect(morphGlassOutlineField(fake), isNot(isA<GlassBoxField>()));
        expect(morphGlassOutlineField(flat), isNull);
        final liquid = frame.partsFor(MorphGlassTier.liquid).fused.single.$2;
        expect(morphGlassOutlineField(liquid) is GlassBoxField, analytic);
        if (!analytic) expect(liquid, same(fake));
      },
    );
  }

  test('a merged-box outline moves with its boxes', () {
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    final first = morphGlassContainerBoxOutline(pair, 12);
    const offset = Offset(7, 3);
    final moved = morphGlassContainerBoxOutline([
      for (final shape in pair) shape.shift(offset),
    ], 12);
    final field = morphGlassOutlineField(moved)! as GlassBoxField;
    expect(field.boxes, [for (final shape in pair) shape.shift(offset)]);
    expect(moved.bounds, first.bounds.shift(offset));
    final base = morphGlassOutlineField(first)! as GlassBoxField;
    expect(field.origin, base.origin + offset);
    expect(field.samples, same(base.samples));
  });

  test('moves of a merged-box field share one fusion, moved once', () {
    final first =
        morphGlassOutlineField(morphGlassContainerBoxOutline(pair, 12))!
            as GlassBoxField;
    var moved = first;
    var total = Offset.zero;
    for (var i = 0; i < 200; i++) {
      const step = Offset(0.25, -0.5);
      moved = moved.shift(step);
      total += step;
    }
    expect(moved.debugRoot, same(first.debugRoot));
    final once = first.shift(total);
    expect(once.debugRoot, same(first.debugRoot));
    expect(moved.samples, same(once.samples));
    expect(moved.samples, same(first.samples));
    expect(moved.origin, once.origin);
    expect(moved.origin, first.origin + total);
    expect(
      moved.boxes.first.outerRect.topLeft,
      pair.first.outerRect.topLeft + total,
    );
  });

  test('the shadow of merged boxes stays out of their necks', () {
    // 6 apart, spacing 12: the merge closes the gap.
    final outline = morphGlassContainerBoxOutline(pair, 12);
    final cover = morphGlassOutlineShadowCover(outline)!;
    const neck = Offset(63, 22);
    expect(pair.any((box) => box.contains(neck)), isFalse);
    expect(outline.path.contains(neck), isFalse);
    expect(cover.contains(neck), isTrue);
    expect(cover.contains(const Offset(63, 1)), isTrue);
    for (final box in pair) {
      expect(cover.contains(box.center), isTrue);
    }
    expect(cover.contains(const Offset(63, -8)), isFalse);
    expect(cover.contains(const Offset(200, 22)), isFalse);
    // Moved with the outline.
    const offset = Offset(10, 20);
    final moved = morphGlassContainerBoxOutline([
      for (final box in pair) box.shift(offset),
    ], 12);
    expect(
      morphGlassOutlineShadowCover(moved)!.contains(neck + offset),
      isTrue,
    );
    // Boxes farther apart than the spacing have no bridge.
    final apart = morphGlassContainerBoxOutline([
      _capsule(16, 0, 44),
      _capsule(80, 0, 44),
    ], 12);
    expect(
      morphGlassOutlineShadowCover(apart)!.contains(const Offset(70, 22)),
      isFalse,
    );
    // A fused outline's own edge covers its neck: no separate cover.
    expect(
      morphGlassOutlineShadowCover(morphGlassContainerOutline(pair, 12)),
      isNull,
    );
  });
}
