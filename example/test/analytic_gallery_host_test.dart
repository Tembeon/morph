// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// The report reads the renderer's own layers.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/glass_field.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// Which liquid glass layers of the gallery's Navigation page evaluate
/// their shapes analytically, at rest and in the middle of the nested push
/// to a message, on the host's Impeller with the liquid tier.
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/analytic_gallery_host_test.dart
///
/// Prints one line per layer: its owner, its shapes, whether it is
/// analytic and why not. Without Impeller the test does nothing.
void main() {
  testWidgets('analytic layers of the gallery navigation page', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => RenderLiquidGlassLayer.debugAnalyticGeometry = null);
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;

    Future<void> frames(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(GalleryApp(navigatorKey: navigator));
    await frames(10);
    final settings = GalleryGlassScope.of(navigator.currentContext!);
    settings.tier = MorphGlassTier.liquid;
    settings.appearance = ThemeMode.dark;
    await frames(10);
    final traces = morphGlassOutlineDebugTraces;
    final entry = galleryEntries.firstWhere((e) => e.title == 'Navigation');
    unawaited(
      navigator.currentState!.push(
        MorphNavigationRoute<void>(builder: entry.builder),
      ),
    );
    await frames(90);

    final report = <String, List<String>>{};
    var mergedAnalytic = 0;
    void record(String moment) {
      final lines = <String>[];
      for (final layer
          in tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .toSet()) {
        if (layer.shapesWithGeometry.isEmpty) continue;
        final shapes = layer.shapesWithGeometry.fold<int>(
          0,
          (sum, entry) => sum + entry.$2.shapes.length,
        );
        final blends = {
          for (final (_, geometry, _) in layer.shapesWithGeometry)
            geometry.blend,
        };
        var bounds = Rect.zero;
        for (final (geometry, _, _) in layer.shapesWithGeometry) {
          final box = MatrixUtils.transformRect(
            geometry.getTransformTo(null),
            geometry.paintBounds,
          );
          bounds = bounds.isEmpty ? box : bounds.expandToInclude(box);
        }
        final line =
            '$moment ${_owner(layer)} at ${_rect(bounds)} '
            'shapes $shapes blends $blends '
            'field ${switch (layer.field) {
              null => 'none',
              GlassBoxField(:final boxes) => '${boxes.length} merged boxes',
              _ => 'sampled',
            }} '
            'analytic ${layer.debugAnalytic} '
            'reason ${layer.debugAnalyticIneligibility}';
        lines.add(line);
        if (layer.field is GlassBoxField && layer.debugAnalytic) {
          mergedAnalytic++;
        }
        expect(layer.debugAnalytic, isTrue, reason: line);
        // The report is the test's output.
        // ignore: avoid_print
        print(line);
      }
      report[moment] = lines;
    }

    record('rest');
    expect(report['rest'], isNotEmpty);
    await tester.tap(find.text('Message 0'));
    await frames(9);
    record('mid-push');
    await frames(90);
    record('pushed');
    await frames(300);
    record('settled');
    // A bar group the container fuses goes analytic as merged boxes, and
    // the CPU never fuses its field.
    expect(mergedAnalytic, greaterThan(0));
    // ignore: avoid_print
    print('fields fused on the CPU ${morphGlassOutlineDebugTraces - traces}');
    expect(morphGlassOutlineDebugTraces - traces, 0);
  });
}

String _rect(Rect r) =>
    '(${r.left.round()},${r.top.round()} ${r.width.round()}x${r.height.round()})';

/// The bars, pages and scaffolds above [layer], innermost first.
String _owner(RenderObject layer) {
  final creator = layer.debugCreator;
  if (creator is! DebugCreator) return '?';
  // Walks to the root: the page and bar names above the layer.
  final names = <String>[];
  creator.element.visitAncestorElements((element) {
    final name = element.widget.runtimeType.toString();
    final interesting =
        name == 'MorphNavigationBar' ||
        name == 'MorphToolbar' ||
        name == 'MorphNavigationScaffold' ||
        name == 'MorphBarItems' ||
        name.startsWith('_Inbox') ||
        name.startsWith('_Detail') ||
        name == 'NavigationDemoPage';
    if (interesting && !names.contains(name)) names.add(name);
    return true;
  });
  return names.join('<');
}
