import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/rendering/consolidated_fake_glass_layer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

void main() {
  setUpAll(() async {
    isLocalTest = true;
    await MultiShaderBuilder.precacheShaders([ShaderKeys.fakeGlassSurface]);
  });
  tearDownAll(() => isLocalTest = false);

  for (final initiallyHidden in [false, true]) {
    testWidgets(
      'hidden glass settles while frames continue: $initiallyHidden',
      (tester) async {
        final visibility = ValueNotifier<double>(initiallyHidden ? 0 : 1);
        addTearDown(visibility.dispose);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: LiquidGlassLayer(
              fake: true,
              child: ValueListenableBuilder<double>(
                valueListenable: visibility,
                builder: (_, value, child) => Center(
                  child: LiquidGlassVisibility(
                    visibility: value,
                    child: child!,
                  ),
                ),
                child: const LiquidGlass(
                  shape: LiquidOval(),
                  child: SizedBox.square(dimension: 80),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        if (!initiallyHidden) {
          visibility.value = 0;
          await tester.pump();
          await tester.pump();
        }
        final layer = tester.allRenderObjects
            .whereType<RenderConsolidatedFakeGlassLayer>()
            .last;
        final paints = layer.debugPaintCount;
        for (var i = 0; i < 8; i++) {
          tester.binding.scheduleFrame();
          await tester.pump();
        }
        expect(layer.debugPaintCount, paints);
        visibility.value = 1;
        await tester.pump();
        expect(layer.debugPaintCount, greaterThan(paints));
      },
    );
  }

  testWidgets(
    'fake appearance overrides share the input but have their own transfer',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: LiquidGlassLayer(
            fake: true,
            useBackdropGroup: false,
            settings: LiquidGlassSettings(frost: 8),
            defaultAppearance: LiquidGlassAppearance(saturation: 1),
            child: Stack(
              children: [
                Positioned(
                  left: 20,
                  top: 20,
                  child: LiquidGlass(
                    shape: LiquidOval(),
                    child: SizedBox.square(dimension: 80),
                  ),
                ),
                Positioned(
                  left: 110,
                  top: 20,
                  child: LiquidGlass(
                    appearance: LiquidGlassAppearance(
                      saturation: 2,
                      transmissionGamma: 1.8,
                    ),
                    shape: LiquidOval(),
                    child: SizedBox.square(dimension: 80),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final layer = tester.allRenderObjects
          .whereType<RenderConsolidatedFakeGlassLayer>()
          .last;
      final shared = layer.debugBackdropFilterLayer!;
      final separate = layer.debugSeparateBackdropLayers.single;
      expect(shared.backdropKey, isNotNull);
      expect(separate.backdropKey, same(shared.backdropKey));
      expect(layer.debugClipPath!.contains(const Offset(60, 60)), isTrue);
      expect(layer.debugClipPath!.contains(const Offset(150, 60)), isFalse);
      final outline = Path();
      outline.addRect(const Rect.fromLTWH(10, 10, 190, 100));
      layer.outline = outline;
      await tester.pump();
      expect(layer.debugClipPath!.contains(const Offset(60, 60)), isTrue);
      expect(layer.debugClipPath, same(outline));
      final clips = <ClipPathLayer>[];
      Layer? ancestor = shared.parent;
      while (ancestor != null) {
        if (ancestor is ClipPathLayer) clips.add(ancestor);
        ancestor = ancestor.parent;
      }
      expect(clips.length, greaterThanOrEqualTo(2));
      expect(
        clips.every((clip) => clip.clipPath!.contains(const Offset(60, 60))),
        isTrue,
      );
      expect(
        clips.every((clip) => clip.clipPath!.contains(const Offset(150, 60))),
        isFalse,
      );
      expect(
        layer.debugSeparateBackdropLayers.single.backdropKey,
        same(shared.backdropKey),
      );
    },
  );
  testWidgets('an override draws even when the shared transfer is identity', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: LiquidGlassLayer(
          fake: true,
          settings: LiquidGlassSettings(frost: 0),
          defaultAppearance: LiquidGlassAppearance(saturation: 1),
          child: Center(
            child: LiquidGlass(
              appearance: LiquidGlassAppearance(saturation: 2),
              shape: LiquidOval(),
              child: SizedBox.square(dimension: 80),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final layer = tester.allRenderObjects
        .whereType<RenderConsolidatedFakeGlassLayer>()
        .last;
    expect(layer.debugBackdropFilterLayer, isNull);
    expect(layer.debugSeparateBackdropLayers, hasLength(1));
  });
}
