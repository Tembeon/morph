// The test drives the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';
// The test reads the renderer's own layer below the widget layer.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;

import '../integration_test/support/shader_harness.dart';

/// A frosted glass layer copies the backdrop around it into a pass of its
/// own and blurs that copy, on the host's Impeller:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/frost_seed_host_test.dart
///
/// Without Impeller there is no liquid tier and the test does nothing.
void main() {
  List<BackdropFilterLayer> filters(Layer root) {
    final out = <BackdropFilterLayer>[];
    void walk(Layer layer) {
      if (layer.runtimeType == BackdropFilterLayer) {
        out.add(layer as BackdropFilterLayer);
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

  testWidgets('a frosted layer blurs a copy of its own surroundings', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => RenderLiquidGlassLayer.debugSeedsBlur = true);
    await tester.runAsync(MorphGlassRenderer.precache);
    if (!MorphGlassRenderer.liquidAvailable) return;
    final harness = ShaderHarness(tester);

    Future<(HarnessShot, List<BackdropFilterLayer>)> render(
      String name, {
      required bool seed,
    }) async {
      RenderLiquidGlassLayer.debugSeedsBlur = seed;
      await harness.show(
        harnessCasesNamed(name).single,
        ShaderVariant.candidate,
      );
      final layers = filters(harness.boundary.debugLayer!);
      return (await harness.shoot(), layers);
    }

    for (final name in [
      'lens-frost-rise',
      'lens-frost-quarter',
      'lens-frost-half',
      'lens-frost-late',
    ]) {
      final (seeded, seededLayers) = await render(name, seed: true);
      final (whole, wholeLayers) = await render(name, seed: false);
      expect(wholeLayers, hasLength(1), reason: name);
      expect(seededLayers, hasLength(2), reason: name);
      expect(seededLayers.first.filter, isA<ColorFilter>(), reason: name);
      final diff = HarnessDiff.of(seeded, whole);
      expect(diff.max, lessThanOrEqualTo(3), reason: '$name ${diff.toJson()}');
    }

    final (_, menu) = await render('menu-frosted', seed: true);
    expect(menu, hasLength(1));
    final (_, unfrosted) = await render('lens-lifted', seed: true);
    expect(unfrosted, hasLength(1));
  });
}
