import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// The A/B toggles the renderer's own composition.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/internal/backdrop_region.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// The navigation bar's edge effect and glass in one backdrop region against
/// each taking its own read, on the host's Impeller with the liquid tier:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/backdrop_region_host_test.dart
///
/// The gallery home is scrolled under its navigation bar so the edge effect
/// shows. With the region the bar's glass reads the region's pass instead of
/// the screen, the edge effect drops its own copy, and every pixel stays the
/// same. Prints the largest channel difference and the backdrop filters of
/// both frames. Without Impeller the test does nothing.
void main() {
  // Each backdrop filter in the scene, and whether it paints inside another
  // backdrop filter's pass.
  List<(BackdropFilterLayer, bool)> filters(Layer root) {
    final out = <(BackdropFilterLayer, bool)>[];
    bool nested(Layer layer) {
      for (var parent = layer.parent; parent != null; parent = parent.parent) {
        // The glass's own opacity seed wraps it unseeded, outside the scene.
        if (parent is BackdropFilterLayer && parent.engineLayer != null) {
          return true;
        }
      }
      return false;
    }

    void walk(Layer layer) {
      if (layer is BackdropFilterLayer && layer.engineLayer != null) {
        out.add((layer, nested(layer)));
      }
      if (layer is ContainerLayer) {
        for (
          var child = layer.firstChild;
          child != null;
          child = child.nextSibling
        ) {
          walk(child);
        }
      }
    }

    walk(root);
    return out;
  }

  testWidgets('the bar and its edge effect read one copy of the band', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => debugMorphBackdropRegions = false);
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

    Future<(ui.Image, List<(BackdropFilterLayer, bool)>)> render({
      required bool regions,
    }) async {
      debugMorphBackdropRegions = regions;
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
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -260),
        warnIfMissed: false,
      );
      await frames(120);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => render.toImage(pixelRatio: 2.625),
      ))!;
      final layers = filters(
        // ignore: invalid_use_of_protected_member
        RendererBinding.instance.renderViews.first.layer!,
      );
      await tester.pumpWidget(const SizedBox());
      return (image, layers);
    }

    final (off, offFilters) = await render(regions: false);
    final (on, onFilters) = await render(regions: true);
    final a = (await tester.runAsync(off.toByteData))!.buffer.asUint8List();
    final b = (await tester.runAsync(on.toByteData))!.buffer.asUint8List();
    var max = 0;
    var over2 = 0;
    for (var p = 0; p < a.length ~/ 4; p++) {
      var pixel = 0;
      for (var c = 0; c < 4; c++) {
        final d = (a[p * 4 + c] - b[p * 4 + c]).abs();
        if (d > pixel) pixel = d;
      }
      if (pixel > max) max = pixel;
      if (pixel > 2) over2++;
    }
    String describe(List<(BackdropFilterLayer, bool)> layers) => [
      for (final (layer, nested) in layers)
        [
          '${layer.filter.runtimeType}',
          if (layer.backdropKey != null) 'keyed',
          if (nested) 'nested',
        ].join(' '),
    ].join(', ');
    // The report is the test's output.
    // ignore: avoid_print
    print(
      'max channel difference $max, pixels over 2: $over2\n'
      'own reads: ${describe(offFilters)}\n'
      'region: ${describe(onFilters)}',
    );
    expect(
      onFilters.length,
      offFilters.length,
      reason: 'the region seed replaces the edge effect seed',
    );
    expect(max, lessThanOrEqualTo(2));
    final glass = onFilters.where(
      (entry) => entry.$1.filter is! ui.ColorFilter,
    );
    expect(glass, isNotEmpty);
    expect(glass.every((entry) => entry.$2), isTrue);
    expect(
      offFilters.where((entry) => entry.$2),
      hasLength(1),
      reason: 'the edge blur in its own seed',
    );
  });
}
