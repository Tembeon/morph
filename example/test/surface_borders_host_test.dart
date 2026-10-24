import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:morph/morph.dart';

void main() {
  for (final tier in MorphGlassTier.values) {
    for (final glassWithoutInk in [false, true]) {
      testWidgets(
        '${tier.name} contours survive a menu round trip on Impeller (liquid without ink: $glassWithoutInk)',
        (tester) async {
          if (!ui.ImageFilter.isShaderFilterSupported) return;
          await tester.runAsync(MorphTheme.precacheGlass);
          expect(MorphTheme.liquidGlassAvailable, isTrue);
          final controller = MorphMenuPresentationController();
          addTearDown(controller.dispose);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                builder: (context, child) => MorphTheme(
                  data: MorphThemeData(
                    glass: MorphGlassRenderer.tier(tier),
                    liquidBorders: glassWithoutInk
                        ? const MorphSurfaceBorders()
                        : null,
                    borders: const MorphSurfaceBorders.all(
                      BorderSide(color: Color(0xFFFF0000), width: 2),
                    ),
                  ),
                  child: child!,
                ),
                home: ColoredBox(
                  color: const Color(0xFFEEEEEE),
                  child: Center(
                    child: MorphMenuButton(
                      controller: controller,
                      menu: [MorphMenuItem(title: 'Action', onSelected: () {})],
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

          Future<int> contourPixels() async {
            await frames(5);
            final box =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = (await tester.runAsync(box.toImage))!;
            final bytes = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
            ))!;
            var red = 0;
            for (var i = 0; i < bytes.lengthInBytes; i += 4) {
              if (bytes.getUint8(i) > 180 &&
                  bytes.getUint8(i + 1) < 80 &&
                  bytes.getUint8(i + 2) < 80) {
                red++;
              }
            }
            image.dispose();
            return red;
          }

          await frames(20);
          final resting = await contourPixels();
          final noInk = glassWithoutInk && tier == MorphGlassTier.liquid;
          expect(resting, noInk ? 0 : greaterThan(30));
          controller.open();
          await frames(90);
          expect(find.text('Action'), findsOneWidget);
          expect(await contourPixels(), noInk ? 0 : greaterThan(resting * 2));
          controller.close();
          await frames(120);
          expect(controller.isOpen, isFalse);
          expect(await contourPixels(), resting);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
