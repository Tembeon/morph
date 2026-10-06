import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_container.dart';
import 'package:morph/widgets.dart';

final GlobalKey _shot = GlobalKey();

Widget _list({
  MorphGlassTier tier = MorphGlassTier.fake,
  MorphGlassRenderer renderer = const MorphGlassRenderer(),
  int rows = 4,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
  home: MorphAdaptiveGlass(
    renderer: renderer,
    tier: tier,
    child: RepaintBoundary(
      key: _shot,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Align(
          alignment: .topCenter,
          child: MorphListSection(
            header: 'Accessories',
            children: [
              for (var i = 0; i < rows; i++)
                MorphListRow(
                  title: Text('Row $i'),
                  onTap: () {},
                  trailing: SizedBox(
                    width: 72,
                    height: 34,
                    child: MorphGlassButton(
                      onPressed: () {},
                      child: Text('Go $i'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

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

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary =
      _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(boundary.toImage);
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  image!.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);
  tearDown(() => debugMorphGlassStagesOpen = true);

  for (final tier in [MorphGlassTier.liquid, MorphGlassTier.fake]) {
    testWidgets('a section shades its rows\' resting glass accessories in '
        'one layer (${tier.name})', (WidgetTester tester) async {
      await tester.pumpWidget(_list(tier: tier));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LiquidGlass), findsNWidgets(4));
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
    });
  }

  testWidgets('a section paints one backdrop filter for its accessories', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_list());
    await tester.pump(const Duration(milliseconds: 100));
    final shared = _filters();
    debugMorphGlassStagesOpen = false;
    await tester.pumpWidget(_list(rows: 3));
    await tester.pumpWidget(_list());
    await tester.pump(const Duration(milliseconds: 100));
    expect(shared, 1);
    expect(_filters(), 4);
  });

  testWidgets('a highlighted row\'s accessory leaves the section\'s layer '
      'while its highlight shows, the others stay', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_list(tier: MorphGlassTier.liquid));
    await tester.pump(const Duration(milliseconds: 100));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Row 1')),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    expect(find.byType(LiquidGlass), findsNWidgets(4));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
  });

  testWidgets('frosted controls keep their own layers in a section: their '
      'blur reads the rows around them', (WidgetTester tester) async {
    await tester.pumpWidget(
      _list(
        tier: MorphGlassTier.liquid,
        renderer: const MorphGlassRenderer(frostControls: true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(5));
  });

  testWidgets('a section\'s shared layer draws the pixels of the '
      'accessories\' own layers, resting and with a row highlighted', (
    WidgetTester tester,
  ) async {
    Future<(Uint8List, Uint8List)> shots({required bool stage}) async {
      debugMorphGlassStagesOpen = stage;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_list());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      final resting = await _pixels(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Row 2')),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final held = await _pixels(tester);
      await gesture.cancel();
      await tester.pumpAndSettle();
      return (resting, held);
    }

    final own = await shots(stage: false);
    final shared = await shots(stage: true);
    expect(shared.$1, own.$1);
    expect(shared.$2, own.$2);
    expect(shared.$1, isNot(shared.$2));
  });
}
