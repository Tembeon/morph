// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// The report reads the renderer's own layers.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/glass_field.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show AnalyticGeometryMode, RenderLiquidGlassLayer;
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// Which liquid glass layers of the gallery's Navigation page evaluate
/// their shapes analytically, at rest and in the middle of the nested push
/// to a message, on the host's Impeller with the liquid tier.
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/analytic_gallery_host_test.dart
///
/// Prints one line per layer: its owner, its shapes, whether it is
/// analytic and why not. An open menu of the Menu page draws the same
/// analytically as from its matte. Without Impeller the test does nothing.
void main() {
  testWidgets('analytic layers of the gallery navigation page', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    // These tests pin analytic shading on every frame it can; the
    // `changes` mode has its own test (analytic_mode_host_test.dart).
    RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.always;
    addTearDown(() {
      RenderLiquidGlassLayer.debugAnalyticGeometry = null;
      RenderLiquidGlassLayer.debugAnalyticMode = null;
    });
    await tester.runAsync(GlassBuiltInPainter.precache);
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
    final settings = GalleryGlassScope.read(navigator.currentContext!);
    settings.tier = MorphGlassTier.liquid;
    settings.appearance = Brightness.dark;
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
            'analytic ${layer.debugAnalytic} resting ${layer.debugResting} '
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

  testWidgets('an open menu draws the same analytically as from its matte', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.always;
    addTearDown(() {
      RenderLiquidGlassLayer.debugAnalyticGeometry = null;
      RenderLiquidGlassLayer.debugAnalyticMode = null;
    });
    await tester.runAsync(GlassBuiltInPainter.precache);
    if (!MorphTheme.liquidGlassAvailable) return;
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

    Future<void> settle() async {
      for (var i = 0; tester.binding.hasScheduledFrame; i++) {
        expect(i, lessThan(300), reason: 'the app never went idle');
        await frames(1);
      }
    }

    Future<Uint8List> shot() async {
      final image = await tester.runAsync(
        () => captureImage(tester.binding.rootElement!),
      );
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      return bytes!.buffer.asUint8List();
    }

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(GalleryApp(navigatorKey: navigator));
    await frames(10);
    final settings = GalleryGlassScope.read(navigator.currentContext!);
    settings.tier = MorphGlassTier.liquid;
    settings.appearance = Brightness.dark;
    await frames(10);
    final entry = galleryEntries.firstWhere((e) => e.title == 'Menu');
    unawaited(
      navigator.currentState!.push(
        MorphNavigationRoute<void>(builder: entry.builder),
      ),
    );
    await settle();
    // The menus whose rows leave the shrunk source (12 pt, inside the
    // open menu) uncovered: the middle one and a corner one.
    for (final index in [0, 4]) {
      RenderLiquidGlassLayer.debugAnalyticGeometry = true;
      await tester.tapAt(
        tester.getCenter(find.byType(MorphMenuButton).at(index)),
      );
      await settle();
      // The menu's layer holds the menu and its shrunk source; the
      // smaller of the two is the source.
      final menuLayer = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .where(
            (layer) =>
                layer.debugAnalytic &&
                layer.shapesWithGeometry.fold<int>(
                      0,
                      (sum, entry) => sum + entry.$2.shapes.length,
                    ) ==
                    2,
          );
      expect(
        menuLayer,
        isNotEmpty,
        reason: 'menu $index: the menu and its source shade analytically',
      );
      final rects = [
        for (final (_, geometry, _) in menuLayer.first.shapesWithGeometry)
          for (final shape in geometry.shapes)
            MatrixUtils.transformRect(
              shape.renderObject.getTransformTo(null),
              Offset.zero & shape.renderObject.size,
            ),
      ];
      rects.sort((a, b) => a.width.compareTo(b.width));
      final source = rects.first;
      expect(source.width, lessThan(20), reason: 'menu $index');
      final dpr = tester.view.devicePixelRatio;
      final width = tester.view.physicalSize.width.round();
      final region = source.inflate(2);
      final analytic = await shot();
      RenderLiquidGlassLayer.debugAnalyticGeometry = false;
      await frames(2);
      final matte = await shot();
      var over = 0;
      for (var i = 0; i < analytic.length; i++) {
        final pixel = i ~/ 4;
        final at = Offset(
          (pixel % width + 0.5) / dpr,
          (pixel ~/ width + 0.5) / dpr,
        );
        if (!region.contains(at)) continue;
        if ((analytic[i] - matte[i]).abs() > 12) over++;
      }
      expect(
        over,
        0,
        reason: 'menu $index: channels over the source off by more than 12',
      );
      await tester.tapAt(const Offset(5, 5));
      await settle();
    }
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
