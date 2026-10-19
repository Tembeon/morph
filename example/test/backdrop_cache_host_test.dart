import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// The A/B toggles the renderer's own composition.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/internal/backdrop_cache.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// Glass over a page - the floating sheet, an alert, an action sheet
/// popover, the date picker overlay - over a cached copy of the
/// page against the backdrop filter, on the host's Impeller with the liquid
/// tier:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/backdrop_cache_host_test.dart
///
/// Each gallery page opens its surface; both variants are shot in the
/// middle of the opening and at rest (and, for the sheet, one frame after
/// the page scrolls under it). Prints the largest channel difference and
/// the pixels over 2 and 8 at each moment, and how many copies the cache
/// took. Without Impeller the test does nothing.
void main() => _main();

/// `--dart-define=AUDIT_OUT=<dir>` keeps the shots as PNGs.
const String _out = String.fromEnvironment('AUDIT_OUT');

typedef _Case = (
  String name,
  String page,
  Finder Function() opener,
  bool scroll,
);

final List<_Case> _cases = [
  ('sheet', 'Sheets', () => find.text('Medium and large'), true),
  ('alert', 'Alerts', () => find.text('Two buttons in a row'), false),
  (
    'popover',
    'Alerts',
    () => find.text('Action sheet from this button'),
    false,
  ),
  ('date', 'Date picker', () => find.byType(MorphDatePicker).first, false),
];

void _main() {
  for (final (name, page, opener, scroll) in _cases) {
    testWidgets('$name over its cached page', (WidgetTester tester) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      tester.view.physicalSize = const ui.Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final cacheBefore = debugMorphBackdropCache;
      addTearDown(() => debugMorphBackdropCache = cacheBefore);
      await tester.runAsync(GlassBuiltInPainter.precache);
      if (!MorphTheme.liquidGlassAvailable) return;

      Future<void> frames(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
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
        final settings = GalleryGlassScope.read(navigator.currentContext!);
        settings.tier = MorphGlassTier.liquid;
        settings.appearance = Brightness.dark;
        await frames(30);
        await tester.ensureVisible(find.text(page));
        await frames(20);
        await tester.tap(find.text(page));
        await frames(60);
        await tester.ensureVisible(opener());
        await frames(30);
        await tester.tap(opener());
        Future<ui.Image> shoot() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          return (await tester.runAsync(
            () => render.toImage(pixelRatio: 2.625),
          ))!;
        }

        await frames(8);
        final shots = [await shoot()];
        await frames(80);
        shots.add(await shoot());
        if (scroll) {
          // The page under the sheet moves for one frame: a copy from the
          // frame before would show the old page through the glass.
          final list = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          list.position.jumpTo(list.position.pixels + 120);
          await tester.pump(const Duration(milliseconds: 16));
          shots.add(await shoot());
        }
        await tester.pumpWidget(const SizedBox());
        return shots;
      }

      final off = await render(cache: false);
      debugMorphBackdropCacheCaptures = 0;
      debugMorphBackdropCacheHits = 0;
      debugMorphBackdropCacheMisses.clear();
      final on = await render(cache: true);
      // The report is the test's output.
      // ignore: avoid_print
      print(
        '$name copies taken: $debugMorphBackdropCacheCaptures, frames over '
        'a copy $debugMorphBackdropCacheHits, misses '
        '$debugMorphBackdropCacheMisses',
      );
      final moments = ['mid-open', 'rest', 'page-moved'];
      for (var i = 0; i < off.length; i++) {
        final a = (await tester.runAsync(
          off[i].toByteData,
        ))!.buffer.asUint8List();
        final b = (await tester.runAsync(
          on[i].toByteData,
        ))!.buffer.asUint8List();
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
        // ignore: avoid_print
        print('$name ${moments[i]}: max $max, over 2: $over2, over 8: $over8');
        if (_out.isNotEmpty) {
          for (final (variant, image) in [('off', off[i]), ('on', on[i])]) {
            final png = await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png),
            );
            File(
              '$_out/$name-${moments[i]}-$variant.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
          }
        }
      }
    });
  }
}
