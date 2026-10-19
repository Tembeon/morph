import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/src/glass/renderer/internal/render_liquid_glass_geometry.dart';
import 'package:morph/src/glass/renderer/internal/rounded_superellipse_parameters.dart';
import 'package:morph/src/glass/renderer/liquid_glass.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// A glass shape whose two top corners share one radius and two bottom
/// corners another - a floating sheet's 38 and 54 - is Flutter's own
/// rounded superellipse of those corners, the outline its clip draws: two
/// symmetric halves on the split line Impeller's MakeBoundsRadii puts at
/// the radii's ratio of the height. The shaders read the halves' rows.
void main() {
  group('pair parameters', () {
    const size = Size(402, 469.67);

    test('the split divides the height in the radii\'s ratio', () {
      expect(
        roundedSuperellipseSplit(size.height, 38, 54),
        closeTo(469.67 * 38 / 92, 1e-9),
      );
      expect(roundedSuperellipseSplit(100, 0, 0), 50);
      expect(roundedSuperellipseSplit(100, 38, 0), 100);
    });

    test('each half is the symmetric rounded superellipse of its quadrant', () {
      const scale = 3.0;
      final pair = roundedSuperellipsePairParameters(
        size,
        38,
        54,
        scale: scale,
      );
      expect(pair, hasLength(24));
      final upper = roundedSuperellipseSplit(size.height, 38, 54);
      final lower = size.height - upper;
      final top = roundedSuperellipseParameters(
        Size(size.width, 2 * upper),
        38,
        scale: scale,
      );
      final bottom = roundedSuperellipseParameters(
        Size(size.width, 2 * lower),
        54,
        scale: scale,
      );
      expect(pair.sublist(0, 12), top);
      // The bottom rows' half width slot carries the bottom radius.
      expect(pair[12 + 8], 54 * scale);
      expect(pair.sublist(13 + 8), bottom.sublist(9));
      expect(pair.sublist(12, 12 + 8), bottom.sublist(0, 8));
      // Both halves span the shape's width: they meet the sides on the
      // split line.
      expect(top[8], size.width * scale / 2);
      expect(bottom[8], size.width * scale / 2);
      expect(top[9] + bottom[9], closeTo(size.height * scale, 1e-9));
    });
  });

  group('shape', () {
    test('a pair compares by both radii', () {
      const pair = LiquidRoundedSuperellipse(
        borderRadius: 38,
        bottomRadius: 54,
      );
      expect(
        pair,
        const LiquidRoundedSuperellipse(borderRadius: 38, bottomRadius: 54),
      );
      expect(
        pair,
        isNot(
          const LiquidRoundedSuperellipse(borderRadius: 38, bottomRadius: 62),
        ),
      );
      expect(pair.isUniform, isFalse);
      expect(
        const LiquidRoundedSuperellipse(borderRadius: 20),
        const LiquidRoundedSuperellipse(borderRadius: 20, bottomRadius: 20),
      );
      expect(
        pair.radii,
        const BorderRadius.vertical(
          top: Radius.circular(38),
          bottom: Radius.circular(54),
        ),
      );
      expect(
        pair.scale(0.5),
        const LiquidRoundedSuperellipse(borderRadius: 19, bottomRadius: 27),
      );
    });

    test('a pair packs as the pair type, a uniform squircle as before', () {
      expect(
        RawShapeType.fromLiquidGlassShape(
          const LiquidRoundedSuperellipse(borderRadius: 38, bottomRadius: 54),
        ),
        RawShapeType.squirclePair,
      );
      expect(RawShapeType.squirclePair.shaderIndex, 4);
      expect(
        RawShapeType.fromLiquidGlassShape(
          const LiquidRoundedSuperellipse(borderRadius: 38),
        ),
        RawShapeType.squircle,
      );
    });
  });

  group('liquid tier', () {
    setUpAll(() => isLocalTest = true);
    tearDownAll(() => isLocalTest = false);

    Future<LiquidShape> shapeOf(WidgetTester tester, RRect shape) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: shape.outerRect.size,
              child: MorphGlassHost(
                painter: const GlassBuiltInPainter(),
                mode: MorphGlassMode.surface,
                frame: () => MorphGlassFrame([
                  MorphGlassSurface(
                    kind: MorphGlassKind.menu,
                    shape: shape,
                    color: const Color(0xF2F9F9F9),
                    brightness: Brightness.light,
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
      final glass = tester.renderObject<RenderLiquidGlass>(
        find.descendant(
          of: find.byType(LiquidGlass),
          matching: find.byWidgetPredicate(
            (Widget w) => w.runtimeType.toString() == '_RawLiquidGlass',
          ),
        ),
      );
      return glass.shape;
    }

    testWidgets('a sheet\'s outline reaches the glass with both radii', (
      tester,
    ) async {
      final shape = await shapeOf(
        tester,
        RRect.fromLTRBAndCorners(
          0,
          0,
          402,
          469.67,
          topLeft: const Radius.circular(38),
          topRight: const Radius.circular(38),
          bottomLeft: const Radius.circular(54),
          bottomRight: const Radius.circular(54),
        ),
      );
      expect(
        shape,
        const LiquidRoundedSuperellipse(borderRadius: 38, bottomRadius: 54),
      );
    });

    testWidgets('radii that do not fit scale down together', (tester) async {
      // 60 + 80 is more than the 70 point height: both scale by 0.5, as
      // Flutter scales a rounded superellipse's radii.
      final shape = await shapeOf(
        tester,
        RRect.fromLTRBAndCorners(
          0,
          0,
          300,
          70,
          topLeft: const Radius.circular(60),
          topRight: const Radius.circular(60),
          bottomLeft: const Radius.circular(80),
          bottomRight: const Radius.circular(80),
        ),
      );
      expect(
        shape,
        const LiquidRoundedSuperellipse(borderRadius: 30, bottomRadius: 40),
      );
    });
  });
}
