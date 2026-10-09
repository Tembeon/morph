// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// The test reads the renderer's own layers.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/glass_field.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// Flipping `RenderLiquidGlassLayer.debugAnalyticGeometry` while the
/// gallery rests on a message page, whose leading bar group the glass
/// container fuses: the layer takes merged boxes or the sampled field with
/// each flip, and draws what a fresh mount in that mode draws.
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/analytic_toggle_host_test.dart
///
/// Without Impeller the test does nothing.
void main() {
  testWidgets('flipping analytic geometry at rest follows in one mount', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => RenderLiquidGlassLayer.debugAnalyticGeometry = null);
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);

    Future<void> frames(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    final boundary = GlobalKey();
    // A fresh gallery on a message's page.
    Future<void> open() async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(const SizedBox.shrink());
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
      final entry = galleryEntries.firstWhere((e) => e.title == 'Navigation');
      unawaited(
        navigator.currentState!.push(
          MorphNavigationRoute<void>(builder: entry.builder),
        ),
      );
      await frames(90);
      await tester.tap(find.text('Message 0'));
      await frames(150);
    }

    // The layer of the fused leading group.
    RenderLiquidGlassLayer fusedLayer() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .singleWhere((layer) => layer.field != null);

    // The top of the screen, where the bars are, RGBA.
    Future<List<int>> bars() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => render.toImage(pixelRatio: 2.625),
      ))!;
      final data = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final rowBytes = image.width * 4;
      image.dispose();
      return data.buffer.asUint8List().sublist(0, rowBytes * 160);
    }

    int maxDiff(List<int> a, List<int> b) {
      var max = 0;
      for (var i = 0; i < a.length; i++) {
        final d = (a[i] - b[i]).abs();
        if (d > max) max = d;
      }
      return max;
    }

    void expectLayer({required bool analytic}) {
      final layer = fusedLayer();
      expect(layer.field is GlassBoxField, analytic);
      expect(layer.debugAnalytic, analytic);
      expect(
        layer.debugAnalyticIneligibility,
        analytic ? isNull : anyOf('disabled', 'fused field'),
      );
    }

    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    await open();
    expectLayer(analytic: true);
    final freshOn = await bars();
    RenderLiquidGlassLayer.debugAnalyticGeometry = false;
    await frames(5);
    expectLayer(analytic: false);
    final flippedOff = await bars();
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    await frames(5);
    expectLayer(analytic: true);
    final flippedOn = await bars();
    RenderLiquidGlassLayer.debugAnalyticGeometry = false;
    await open();
    expectLayer(analytic: false);
    final freshOff = await bars();
    // The comparison is the test's output.
    // ignore: avoid_print
    print(
      'flip off vs fresh off ${maxDiff(flippedOff, freshOff)}, '
      'flip on vs fresh on ${maxDiff(flippedOn, freshOn)}, '
      'on vs off ${maxDiff(freshOn, freshOff)}',
    );
    expect(maxDiff(flippedOff, freshOff), lessThanOrEqualTo(1));
    expect(maxDiff(flippedOn, freshOn), lessThanOrEqualTo(1));
  });
}
