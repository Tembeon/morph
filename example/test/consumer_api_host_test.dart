import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

/// Checks custom selected-mask artwork and shaped feedback on real Impeller.
void main() {
  testWidgets(
    'custom content keeps the native lens and touch feedback paints',
    (tester) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      await tester.runAsync(MorphTheme.precacheGlass);
      expect(MorphTheme.liquidGlassAvailable, isTrue);
      final boundary = GlobalKey();
      final primary = GlobalKey();
      var builders = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: .ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: MorphTheme(
              data: const MorphThemeData(
                glass: MorphGlassRenderer.tier(.liquid),
              ),
              child: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: const Color(0xFFEEEEEE),
                  child: Center(
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        MorphTabBar(
                          items: [
                            MorphTabItem.custom(
                              label: 'Custom',
                              glyph: SizedBox(
                                key: primary,
                                width: 24,
                                height: 24,
                                child: const ColoredBox(
                                  color: Color(0xFF00FF00),
                                ),
                              ),
                              replicaBuilder:
                                  (_, {required selected, required minimized}) {
                                    builders++;
                                    return const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: ColoredBox(
                                        color: Color(0xFFFF0000),
                                      ),
                                    );
                                  },
                            ),
                            const MorphTabItem(
                              icon: IconData(0xe318),
                              label: 'Other',
                            ),
                          ],
                          selected: 0,
                          onChanged: (_) {},
                        ),
                        const SizedBox(height: 60),
                        MorphTouchTarget(
                          onTap: () {},
                          child: const MorphTouchFeedback(
                            shape: BeveledRectangleBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                            child: SizedBox(
                              width: 80,
                              height: 40,
                              child: ColoredBox(color: Color(0xFF555577)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> frames(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      Future<List<int>> pixels() async {
        final box =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = (await tester.runAsync(box.toImage))!;
        final bytes = (await tester.runAsync(image.toByteData))!;
        image.dispose();
        return bytes.buffer.asUint8List();
      }

      await frames(10);
      final rest = await pixels();
      var red = 0;
      for (var i = 0; i < rest.length; i += 4) {
        if (rest[i] > 200 && rest[i + 1] < 30 && rest[i + 2] < 30) red++;
      }
      expect(
        red,
        greaterThan(100),
        reason: 'The selected-mask replica passes through the native lens.',
      );
      final before = builders;
      final press = await tester.startGesture(
        tester.getCenter(find.byType(MorphTouchTarget)),
      );
      await frames(20);
      final held = await pixels();
      expect(held, isNot(rest));
      expect(builders, before);
      expect(find.byKey(primary), findsOneWidget);
      await press.up();
      await frames(90);
      expect(tester.takeException(), isNull);
    },
  );
}
