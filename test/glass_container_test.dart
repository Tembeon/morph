import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/widgets.dart';

Offset _center(int i) => Offset(40 + (i % 8) * 50.0, 60 + (i ~/ 8) * 44.0);

Widget _page(
  int count, {
  required bool container,
  MorphGlassTier tier = MorphGlassTier.liquid,
}) {
  final buttons = Stack(
    children: [
      for (var i = 0; i < count; i++)
        Positioned.fromRect(
          rect: Rect.fromCenter(center: _center(i), width: 44, height: 36),
          child: MorphGlassButton(
            key: ValueKey<int>(i),
            onPressed: () {},
            child: Text('$i'),
          ),
        ),
    ],
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
    home: MorphAdaptiveGlass(
      tier: tier,
      child: ColoredBox(
        color: const Color(0xFF203040),
        child: container ? MorphGlassContainer(child: buttons) : buttons,
      ),
    ),
  );
}

int _filters() {
  var count = 0;
  void walk(Layer layer) {
    if (layer.runtimeType == BackdropFilterLayer) count++;
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

  for (final view in RendererBinding.instance.renderViews) {
    final root = view.debugLayer;
    if (root != null) walk(root);
  }
  return count;
}

void main() {
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);

  for (final tier in [MorphGlassTier.liquid, MorphGlassTier.fake]) {
    testWidgets('resting buttons in a container share one layer '
        '(${tier.name})', (WidgetTester tester) async {
      await tester.pumpWidget(_page(8, container: true, tier: tier));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
      expect(find.byType(LiquidGlass), findsNWidgets(8));
      await tester.pumpWidget(_page(8, container: false, tier: tier));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LiquidGlassLayer), findsNWidgets(8));
    });
  }

  testWidgets('a pressed button leaves the container and comes back', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_page(4, container: true));
    await tester.pump(const Duration(milliseconds: 100));
    final gesture = await tester.startGesture(_center(1));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(find.byType(LiquidGlass), findsNWidgets(4));
  });

  testWidgets('a resting search field joins the container, a pressed one '
      'leaves it', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
        home: MorphAdaptiveGlass(
          tier: MorphGlassTier.liquid,
          child: ColoredBox(
            color: const Color(0xFF203040),
            child: MorphGlassContainer(
              child: Column(
                children: [
                  const SizedBox(height: 100),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: MorphSearchField(),
                  ),
                  SizedBox(
                    width: 80,
                    height: 44,
                    child: MorphGlassButton(
                      onPressed: () {},
                      child: const Text('B'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphSearchField)),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
  });

  testWidgets('a resting search toolbar shades its field and buttons in '
      'one layer, a searching one in their own', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
        home: MorphAdaptiveGlass(
          tier: MorphGlassTier.liquid,
          child: ColoredBox(
            color: const Color(0xFF203040),
            child: MorphSearchToolbar(
              leading: [
                MorphBarButton(
                  id: 'a',
                  icon: const SizedBox.square(dimension: 20),
                  semanticLabel: 'A',
                  onPressed: () {},
                ),
              ],
              trailing: [
                MorphBarButton(
                  id: 'b',
                  icon: const SizedBox.square(dimension: 20),
                  semanticLabel: 'B',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlass), findsNWidgets(3));
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    await tester.tap(find.byType(MorphSearchField));
    var most = 0;
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final layers = find.byType(LiquidGlassLayer).evaluate().length;
      if (layers > most) most = layers;
    }
    expect(most, greaterThanOrEqualTo(3));
  });

  testWidgets('a toolbar in a container keeps its own layer: it floats '
      'in a backdrop group of its own', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
        home: MorphAdaptiveGlass(
          tier: MorphGlassTier.liquid,
          child: ColoredBox(
            color: const Color(0xFF203040),
            child: MorphGlassContainer(
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MorphToolbar(
                      leading: [
                        MorphBarButtonGroup([
                          MorphBarButton(id: 'a', label: 'A', onPressed: () {}),
                        ], id: 'a'),
                      ],
                      trailing: [
                        MorphBarButtonGroup([
                          MorphBarButton(id: 'b', label: 'B', onPressed: () {}),
                        ], id: 'b'),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 20,
                    top: 100,
                    width: 80,
                    height: 44,
                    child: MorphGlassButton(
                      onPressed: () {},
                      child: const Text('B'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlass), findsNWidgets(3));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
  });

  testWidgets('a container shades at most its capacity, the rest draw '
      'their own layer', (WidgetTester tester) async {
    await tester.pumpWidget(_page(40, container: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LiquidGlass), findsNWidgets(40));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(1 + 40 - 32));
  });

  testWidgets('on the flat tier a container adds nothing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _page(4, container: true, tier: MorphGlassTier.flat),
    );
    expect(find.byType(LiquidGlassLayer), findsNothing);
  });

  testWidgets('a container paints one backdrop filter for its buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _page(8, container: true, tier: MorphGlassTier.fake),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final shared = _filters();
    await tester.pumpWidget(
      _page(8, container: false, tier: MorphGlassTier.fake),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(shared, lessThan(_filters()));
  });

  for (final (name, wrap) in <(String, Widget Function(Widget child))>[
    ('hidden', (child) => Opacity(opacity: 0, child: child)),
    ('half faded', (child) => Opacity(opacity: 0.5, child: child)),
    ('clipped', (child) => ClipRect(child: child)),
  ]) {
    testWidgets('a $name button keeps its own layer and its own pixels', (
      WidgetTester tester,
    ) async {
      final key = GlobalKey();
      Future<Uint8List> shot({required bool container}) async {
        final buttons = Stack(
          children: [
            Positioned(
              left: 20,
              top: 20,
              width: 80,
              height: 44,
              child: wrap(
                MorphGlassButton(onPressed: () {}, child: const Text('a')),
              ),
            ),
            Positioned(
              left: 120,
              top: 20,
              width: 80,
              height: 44,
              child: MorphGlassButton(onPressed: () {}, child: const Text('b')),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
            home: MorphAdaptiveGlass(
              tier: MorphGlassTier.fake,
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: const Color(0xFF406080),
                  child: container
                      ? MorphGlassContainer(child: buttons)
                      : buttons,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await tester.runAsync(boundary.toImage);
        final data = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        image!.dispose();
        return data!.buffer.asUint8List();
      }

      final own = await shot(container: false);
      final shared = await shot(container: true);
      expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
      expect(shared, own);
    });
  }
}
