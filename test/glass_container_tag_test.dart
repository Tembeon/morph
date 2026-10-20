import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/glass_tier.dart';

import 'support/glass_backdrop_keys.dart';

const MorphGlassTier _tier = MorphGlassTier.liquid;

void main() {
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);

  final boundary = GlobalKey();
  final containerKey = GlobalKey();

  Widget page({required bool container, bool tagged = true}) {
    Widget button(String label) =>
        MorphGlassButton(onPressed: () {}, child: Text(label));
    final buttons = Stack(
      children: [
        Positioned(
          left: 20,
          top: 20,
          width: 80,
          height: 44,
          child: tagged ? MorphTag(id: 'tag', child: button('a')) : button('a'),
        ),
        Positioned(
          left: 120,
          top: 20,
          width: 80,
          height: 44,
          child: button('b'),
        ),
      ],
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
      home: GlassAdaptiveScope(
        tier: _tier,
        child: MorphScope(
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: const Color(0xFF406080),
              child: container
                  ? MorphGlassContainer(key: containerKey, child: buttons)
                  : buttons,
            ),
          ),
        ),
      ),
    );
  }

  Future<Uint8List> shot(WidgetTester tester) async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(render.toImage);
    final data = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    image!.dispose();
    return data!.buffer.asUint8List();
  }

  int layers() => glassLayersWithShapes(within: find.byKey(containerKey));

  testWidgets('a glass button inside a showing tag joins the container with '
      'its own pixels', (WidgetTester tester) async {
    await tester.pumpWidget(page(container: false));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final own = await shot(tester);
    await tester.pumpWidget(page(container: true));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(glassLayersWithShapes(), 1);
    expect(await shot(tester), own);
  });

  testWidgets('resting menu buttons share the container; an open one leaves '
      'it and comes back after it lands', (WidgetTester tester) async {
    final items = [MorphMenuItem(title: 'One', onSelected: () {})];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
        home: GlassAdaptiveScope(
          tier: _tier,
          child: MorphScope(
            child: ColoredBox(
              color: const Color(0xFF406080),
              child: MorphGlassContainer(
                key: containerKey,
                child: Stack(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Positioned(
                        left: 20 + i * 80.0,
                        top: 200,
                        child: MorphMenuButton(
                          key: ValueKey<int>(i),
                          menu: items,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(layers(), 1);
    await tester.tap(find.byKey(const ValueKey<int>(1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(layers(), 2);
    await tester.tapAt(const Offset(700, 550));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    expect(layers(), 1);
  });

  testWidgets('resting menu buttons draw the same pixels in a container', (
    WidgetTester tester,
  ) async {
    final items = [MorphMenuItem(title: 'One', onSelected: () {})];
    Future<Uint8List> menuShot({required bool container}) async {
      final buttons = Stack(
        children: [
          for (var i = 0; i < 3; i++)
            Positioned(
              left: 20 + i * 80.0,
              top: 200,
              child: MorphMenuButton(menu: items),
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
          home: GlassAdaptiveScope(
            tier: _tier,
            child: MorphScope(
              child: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: const Color(0xFF406080),
                  child: container
                      ? MorphGlassContainer(child: buttons)
                      : buttons,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      return shot(tester);
    }

    final own = await menuShot(container: false);
    expect(glassLayersWithShapes(), 3);
    final shared = await menuShot(container: true);
    expect(glassLayersWithShapes(), 1);
    var worst = 0;
    for (var i = 0; i < own.length; i++) {
      final d = (own[i] - shared[i]).abs();
      if (d > worst) worst = d;
    }
    expect(
      worst,
      lessThanOrEqualTo(4),
      reason:
          'one layer draws round shapes up to 4 steps off on the rim, '
          'as for any circular glass button',
    );
  });
}
