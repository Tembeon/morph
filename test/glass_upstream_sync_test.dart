import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/liquid_glass.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

void main() {
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);

  testWidgets('a shape without content carries no clip or fade', (
    tester,
  ) async {
    Future<List<RenderObject>> wrappersUnder(Widget? child) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LiquidGlassLayer(
            child: Center(
              child: SizedBox.square(
                dimension: 80,
                child: LiquidGlass(
                  shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final shapes = tester.allRenderObjects.whereType<RenderLiquidGlass>();
      expect(shapes, isNotEmpty);
      final found = <RenderObject>[];
      void visit(RenderObject node) {
        if (node is RenderOpacity || node is RenderClipRSuperellipse) {
          found.add(node);
        }
        node.visitChildren(visit);
      }

      for (final glass in shapes) {
        expect(glass.size, const Size.square(80));
        glass.visitChildren(visit);
      }
      return found;
    }

    expect(await wrappersUnder(null), isEmpty);
    expect(await wrappersUnder(const SizedBox.expand()), isNotEmpty);
  });
}
