// The oracle toggles a debug switch of the widget layer.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
// The oracle pins the widget layer's container switch.
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_container.dart'
    show debugMorphGlassContainersAnalyticUnderGate;
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// A floating sheet's glass container under the sheet's scale: its members
/// shaded analytically in the container's one layer against each member in
/// a layer of its own, frame by frame while the sheet opens and closes.
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/container_gate_host_test.dart
void main() {
  for (final dark in [false, true]) {
    testWidgets('sheet container under its scale, dark $dark', (
      WidgetTester tester,
    ) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      tester.view.physicalSize = const ui.Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      addTearDown(() => debugMorphGlassContainersAnalyticUnderGate = true);
      await tester.runAsync(MorphGlassRenderer.precache);
      if (!MorphGlassRenderer.liquidAvailable) return;

      Future<void> frames(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      Future<List<ByteData>> run({required bool analytic}) async {
        debugMorphGlassContainersAnalyticUnderGate = analytic;
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
        settings.appearance = dark ? ThemeMode.dark : ThemeMode.light;
        await frames(30);
        await tester.ensureVisible(find.text('Sheets'));
        await frames(10);
        await tester.tap(find.text('Sheets'));
        await frames(60);
        await tester.ensureVisible(find.text('Medium and large'));
        await frames(20);
        final shots = <ByteData>[];
        Future<void> shoot() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = (await tester.runAsync(
            () => render.toImage(pixelRatio: 2.625),
          ))!;
          final bytes = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          shots.add(bytes!);
          image.dispose();
        }

        await tester.tap(find.text('Medium and large'));
        for (var i = 0; i < 6; i++) {
          await frames(3);
          await shoot();
        }
        await frames(60);
        await shoot();
        await tester.tapAt(const Offset(200, 80));
        for (var i = 0; i < 6; i++) {
          await frames(3);
          await shoot();
        }
        await tester.pumpWidget(const SizedBox());
        return shots;
      }

      final own = await run(analytic: false);
      final joined = await run(analytic: true);
      expect(joined.length, own.length);
      var worst = 0;
      for (var f = 0; f < own.length; f++) {
        final a = own[f].buffer.asUint8List();
        final b = joined[f].buffer.asUint8List();
        var max = 0, over2 = 0, over8 = 0;
        for (var i = 0; i < a.length; i++) {
          final d = (a[i] - b[i]).abs();
          if (d > max) max = d;
          if (d > 2) over2++;
          if (d > 8) over8++;
        }
        if (max > worst) worst = max;
        // The report is the test's output.
        // ignore: avoid_print
        print('frame $f: max $max, over 2: $over2, over 8: $over8');
      }
      // ignore: avoid_print
      print('worst $worst');
      // At rest the container is exact; moving, the rims of its members sit
      // a fraction of a pixel from where their own layers rasterize them.
      expect(worst, lessThanOrEqualTo(80));
    });
  }
}
