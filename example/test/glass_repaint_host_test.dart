// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// The test drives and reads the renderer's own layers.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// Glass that comes back after a transition is painted by the time the app
/// goes idle, on the host's Impeller with the liquid tier:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/glass_repaint_host_test.dart
///
/// A shape that joins a layer in a frame the layer does not paint (a menu
/// source landing, bar buttons coming back after a push, a toolbar group
/// splitting or merging) is found by the layer's compositing poll, which
/// asks for a paint after the frame painted; the app must not go idle with
/// that paint pending. Without Impeller the test does nothing.
void main() {
  Future<void> frames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // Pumps until no frame is scheduled; a loop that never rests fails.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; tester.binding.hasScheduledFrame; i++) {
      expect(i, lessThan(300), reason: 'the app never went idle');
      await frames(tester, 1);
    }
  }

  void expectGlassPainted(WidgetTester tester, String moment) {
    final layers = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet();
    expect(layers, isNotEmpty);
    for (final layer in layers) {
      expect(
        layer.debugNeedsPaint,
        isFalse,
        reason: '$moment: a layer went idle with its paint pending',
      );
      expect(
        layer.shapesWithGeometry.length,
        layer.link.shapes.length,
        reason: '$moment: a layer went idle without its registered shapes',
      );
    }
  }

  Future<NavigatorState?> openGallery(WidgetTester tester, String page) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return null;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => RenderLiquidGlassLayer.debugAnalyticGeometry = null);
    await tester.runAsync(MorphGlassRenderer.precache);
    if (!MorphGlassRenderer.liquidAvailable) return null;
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(GalleryApp(navigatorKey: navigator));
    await frames(tester, 10);
    final settings = GalleryGlassScope.of(navigator.currentContext!);
    settings.tier = MorphGlassTier.liquid;
    settings.appearance = ThemeMode.dark;
    await frames(tester, 10);
    final entry = galleryEntries.firstWhere((e) => e.title == page);
    unawaited(
      navigator.currentState!.push(
        MorphNavigationRoute<void>(builder: entry.builder),
      ),
    );
    await settle(tester);
    expectGlassPainted(tester, 'at rest');
    return navigator.currentState;
  }

  testWidgets('a shape that joins or leaves under a repaint boundary', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(600, 600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(MorphGlassRenderer.precache);
    if (!MorphGlassRenderer.liquidAvailable) return;
    final second = ValueNotifier(false);
    addTearDown(second.dispose);
    Widget glass(double left) => Positioned(
      left: left,
      top: 40,
      width: 96,
      height: 44,
      child: const LiquidGlass(
        shape: LiquidRoundedSuperellipse(borderRadius: 22),
        appearance: LiquidGlassAppearance.ios27RegularDark(),
        child: SizedBox.expand(),
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF406080),
          child: LiquidGlassLayer(
            settings: const LiquidGlassSettings(frost: 0),
            child: Stack(
              children: [
                glass(20),
                // Only this boundary repaints when its shape comes or goes;
                // the layer above it does not.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: second,
                      builder: (context, shown, _) =>
                          Stack(children: [if (shown) glass(160)]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expectGlassPainted(tester, 'one shape');
    final layer = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    expect(layer.shapesWithGeometry, hasLength(1));

    second.value = true;
    await settle(tester);
    expectGlassPainted(tester, 'joined');
    expect(layer.shapesWithGeometry, hasLength(2));

    second.value = false;
    await settle(tester);
    expectGlassPainted(tester, 'left');
    expect(layer.shapesWithGeometry, hasLength(1));
  });

  testWidgets('a menu source shows its glass after the menu closes', (
    WidgetTester tester,
  ) async {
    if (await openGallery(tester, 'Menu') == null) return;
    final source = find.byType(MorphMenuButton).at(1);
    await tester.tapAt(tester.getCenter(source));
    await settle(tester);
    expectGlassPainted(tester, 'menu open');
    await tester.tapAt(const Offset(200, 900));
    await settle(tester);
    expectGlassPainted(tester, 'menu closed');
  });

  testWidgets('bar buttons show their glass after a push and a pop', (
    WidgetTester tester,
  ) async {
    if (await openGallery(tester, 'Navigation') == null) return;
    await tester.tap(find.text('Message 0'));
    await settle(tester);
    expectGlassPainted(tester, 'pushed');
    await tester.tap(find.text('Done'));
    await settle(tester);
    expectGlassPainted(tester, 'popped');
  });

  testWidgets('toolbar groups show their glass after they split and merge', (
    WidgetTester tester,
  ) async {
    if (await openGallery(tester, 'Navigation') == null) return;
    await tester.tap(find.text('Filter'));
    await settle(tester);
    expectGlassPainted(tester, 'two buttons per group');
    await tester.tap(find.bySemanticsLabel('trash'));
    await settle(tester);
    expectGlassPainted(tester, 'split');
    await tester.tap(find.bySemanticsLabel('trash'));
    await settle(tester);
    expectGlassPainted(tester, 'merged');
  });
}
