import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// The A/B toggles the renderer's own frost.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show debugMorphShaderFrost;
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// Frosted glass blurring its backdrop in the final pass against the blur
/// pass, on the host's Impeller with the liquid tier:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/shader_frost_host_test.dart
///
/// The gallery home scrolled under its navigation bar, and the tab bar page.
/// Prints the largest channel difference and the pixels over 2 and 8.
/// Without Impeller the test does nothing.
void main() => _main();

/// `--dart-define=AUDIT_OUT=<dir>` keeps the shots as PNGs.
const String _out = String.fromEnvironment('AUDIT_OUT');

void _main() {
  for (final page in [null, 'Tab bar']) {
    final name = page ?? 'home';
    testWidgets('$name frost in the final pass', (WidgetTester tester) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      tester.view.physicalSize = const ui.Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      addTearDown(() => debugMorphShaderFrost = false);
      await tester.runAsync(MorphGlassRenderer.precache);
      if (!MorphGlassRenderer.liquidAvailable) return;

      Future<void> frames(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      Future<ui.Image> render({required bool shader}) async {
        debugMorphShaderFrost = shader;
        final boundary = GlobalKey();
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: GalleryApp(navigatorKey: navigator),
          ),
        );
        await frames(10);
        final settings = GalleryGlassScope.of(navigator.currentContext!);
        settings.tier = MorphGlassTier.liquid;
        settings.appearance = ThemeMode.dark;
        await frames(10);
        if (page != null) {
          await tester.ensureVisible(find.text(page));
          await frames(20);
          await tester.tap(find.text(page));
          await frames(60);
        }
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -260),
          warnIfMissed: false,
        );
        await frames(120);
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = (await tester.runAsync(
          () => render.toImage(pixelRatio: 2.625),
        ))!;
        await tester.pumpWidget(const SizedBox());
        return image;
      }

      final off = await render(shader: false);
      final on = await render(shader: true);
      final a = (await tester.runAsync(off.toByteData))!.buffer.asUint8List();
      final b = (await tester.runAsync(on.toByteData))!.buffer.asUint8List();
      var max = 0;
      var over2 = 0;
      var over8 = 0;
      for (var p = 0; p < a.length ~/ 4; p++) {
        var pixel = 0;
        for (var c = 0; c < 4; c++) {
          final d = (a[p * 4 + c] - b[p * 4 + c]).abs();
          if (d > pixel) pixel = d;
        }
        if (pixel > max) max = pixel;
        if (pixel > 2) over2++;
        if (pixel > 8) over8++;
      }
      // The report is the test's output.
      // ignore: avoid_print
      print('$name: max $max, over 2: $over2, over 8: $over8');
      if (_out.isNotEmpty) {
        for (final (variant, image) in [('off', off), ('on', on)]) {
          final png = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.png),
          );
          File(
            '$_out/frost-$name-$variant.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        }
      }
    });
  }
}
