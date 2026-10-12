import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// The A/B toggles the renderer's own composition.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/internal/backdrop_cache.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// The floating sheet's glass over a cached copy of the page against the
/// backdrop filter, on the host's Impeller with the liquid tier:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/backdrop_cache_host_test.dart
///
/// The gallery's Sheets page opens its medium sheet; both variants are shot
/// in the middle of the opening and at rest. Prints the largest channel
/// difference and the pixels over 2 and 8 at each moment. Without Impeller
/// the test does nothing.
void main() => _main();

/// `--dart-define=AUDIT_OUT=<dir>` keeps the shots as PNGs.
const String _out = String.fromEnvironment('AUDIT_OUT');

void _main() {
  testWidgets('the sheet over its cached page', (WidgetTester tester) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => debugMorphBackdropCache = false);
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

    Future<List<ui.Image>> render({required bool cache}) async {
      debugMorphBackdropCache = cache;
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
      await tester.tap(find.text('Sheets'));
      await frames(60);
      await tester.tap(find.text('Medium and large'));
      Future<ui.Image> shoot() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        return (await tester.runAsync(
          () => render.toImage(pixelRatio: 2.625),
        ))!;
      }

      await frames(8);
      final mid = await shoot();
      await frames(80);
      final rest = await shoot();
      await tester.pumpWidget(const SizedBox());
      return [mid, rest];
    }

    final off = await render(cache: false);
    final on = await render(cache: true);
    for (final (i, moment) in ['mid-open', 'rest'].indexed) {
      final a = (await tester.runAsync(
        off[i].toByteData,
      ))!.buffer.asUint8List();
      final b = (await tester.runAsync(on[i].toByteData))!.buffer.asUint8List();
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
      print('$moment: max $max, over 2: $over2, over 8: $over8');
      if (_out.isNotEmpty) {
        for (final (name, image) in [('off', off[i]), ('on', on[i])]) {
          final png = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.png),
          );
          File(
            '$_out/$moment-$name.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        }
      }
    }
  });
}
