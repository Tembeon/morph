import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:morph/morph.dart';

void main() {
  for (final tier in MorphGlassTier.values) {
    testWidgets(
      '${tier.name}: a menu paints and receives taps above its fitted preview',
      (tester) async {
        if (!ui.ImageFilter.isShaderFilterSupported) return;
        await tester.runAsync(MorphTheme.precacheGlass);
        expect(MorphTheme.liquidGlassAvailable, isTrue);
        tester.view.physicalSize = const Size(402, 874);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
        addTearDown(tester.view.reset);
        final capture = GlobalKey();
        final controller = MorphMenuPresentationController();
        addTearDown(controller.dispose);
        var selected = 0;
        var previewed = 0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              builder: (context, child) => MorphTheme(
                data: MorphThemeData(glass: MorphGlassRenderer.tier(tier)),
                child: child!,
              ),
              home: Stack(
                children: [
                  Positioned(
                    left: 51,
                    top: -80,
                    width: 300,
                    height: 1000,
                    child: MorphContextMenuRegion(
                      controller: controller,
                      onPreviewTap: () => previewed++,
                      menu: [
                        MorphMenuItem(
                          title: 'Copy',
                          onSelected: () => selected++,
                        ),
                        MorphMenuItem(title: 'Share', onSelected: () {}),
                      ],
                      child: const ColoredBox(color: Color(0xFF0088FF)),
                    ),
                  ),
                ],
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

        await frames(10);
        controller.open();
        await frames(100);
        final title = tester.getRect(find.text('Copy'));
        expect(title.top, greaterThan(720));
        expect(
          title.bottom,
          lessThan(824),
          reason: 'the title overlaps the solid blue preview',
        );
        final box =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = (await tester.runAsync(box.toImage))!;
        final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        var ink = 0;
        for (var y = title.top.ceil(); y < title.bottom.floor(); y++) {
          for (var x = title.left.ceil(); x < title.right.floor(); x++) {
            final at = (y * image.width + x) * 4;
            if (bytes.getUint8(at) < 70 &&
                bytes.getUint8(at + 1) < 70 &&
                bytes.getUint8(at + 2) < 70) {
              ink++;
            }
          }
        }
        image.dispose();
        expect(
          ink,
          greaterThan(10),
          reason:
              'menu ink is visible above the preview in the actual renderer',
        );
        await tester.tap(find.text('Copy'));
        await frames(100);
        expect(selected, 1);
        expect(previewed, 0);
        expect(controller.isOpen, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
