import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_body_shadow.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu_fusion.dart';
import 'package:morph/widgets.dart';

void main() {
  testWidgets('a fused menu has one exterior shadow and no button shadow', (
    WidgetTester tester,
  ) async {
    isLocalTest = true;
    addTearDown(() => isLocalTest = false);
    const menu = RRect.fromLTRBXY(30, 70, 270, 280, 80, 80);
    const button = RRect.fromLTRBXY(128, 40, 172, 84, 22, 22);
    final outline = morphMenuSilhouette(menu, button, 20);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.square(
            dimension: 320,
            child: Builder(
              builder: (BuildContext context) =>
                  const MorphGlassRenderer().buildLayer(context, [
                    const MorphGlassSurface(
                      kind: MorphGlassKind.button,
                      shape: button,
                      color: Color(0xF2FFFFFF),
                      brightness: Brightness.light,
                    ),
                    const MorphGlassSurface(
                      kind: MorphGlassKind.menu,
                      shape: menu,
                      color: Color(0xF2FFFFFF),
                      brightness: Brightness.light,
                    ),
                  ], outline: outline),
            ),
          ),
        ),
      ),
    );
    final shapes = tester.widgetList<LiquidGlass>(find.byType(LiquidGlass));
    expect(shapes.length, 2);
    for (final shape in shapes) {
      expect(shape.shadows, isEmpty);
    }
    final shadows = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    final body = shadows
        .map((CustomPaint paint) => paint.painter)
        .whereType<MorphGlassBodyShadow>()
        .single;
    expect(body.outline, same(outline.path));
    expect(body.shadows.length, 1);
    expect(tester.takeException(), isNull);
  });

  test('zero blur keeps the menu and button in one distance field', () {
    final motion = MorphMenuMotion(
      button: const Rect.fromLTWH(177, 126, 48, 48),
      itemCount: 4,
      bounds: const Size(402, 874),
      padding: EdgeInsets.zero,
    );
    motion.open(0);
    motion.advance(2);
    expect(motion.fusionRadius, 0);
    final outline = motion.silhouette!;
    expect(morphGlassOutlineField(outline), isNotNull);
    expect(outline.path.computeMetrics().length, 1);
    expect(outline.path.contains(motion.buttonBlob.rect.center), isTrue);
    motion.close(2);
    for (var frame = 0; frame < 50; frame++) {
      motion.advance(2 + frame / 120);
      if (!motion.isPresented) break;
      expect(morphGlassOutlineField(motion.silhouette!), isNotNull);
    }
  });
}
