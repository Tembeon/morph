import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

import 'support/material_bridge.dart';

/// The census of every glass layer below an owned plane, in tree order.
List<GlassMemberCensus> _census(WidgetTester tester) => [
  for (final member
      in tester.allRenderObjects.whereType<RenderGlassMember>().toSet())
    if (member.plane != null) member.census,
];

Widget _app(Widget child) => MaterialApp(
  builder: morphFromMaterial,
  debugShowCheckedModeBanner: false,
  theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
  home: MorphTheme(
    data: const MorphThemeData(glass: .tier(MorphGlassTier.liquid)),
    child: ColoredBox(color: const Color(0xFF406080), child: child),
  ),
);

Widget _buttons({Widget Function(Widget child)? wrapFirst}) => Stack(
  children: [
    Positioned(
      left: 20,
      top: 20,
      width: 80,
      height: 44,
      child: (wrapFirst ?? (Widget child) => child)(
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

void main() {
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);

  for (final (name, wrap, blocker) in <(String, Widget Function(Widget), Type)>[
    ('hidden', (child) => Opacity(opacity: 0, child: child), RenderOpacity),
    (
      'half faded',
      (child) => Opacity(opacity: 0.5, child: child),
      RenderOpacity,
    ),
    ('clipped', (child) => ClipRect(child: child), RenderClipRect),
  ]) {
    testWidgets('a $name button is kept out by what lies between', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(MorphGlassContainer(child: _buttons(wrapFirst: wrap))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final census = _census(tester).single;
      expect(census.strategy, GlassStrategy.split);
      expect(census.split, GlassSplit.blocked);
      expect(census.blocker.runtimeType, blocker);
    });
  }

  testWidgets('an opaque fade is no break', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(
        MorphGlassContainer(
          child: _buttons(
            wrapFirst: (child) =>
                ClipRect(child: Opacity(opacity: 1, child: child)),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_census(tester).single.blocker, isA<RenderClipRect>());
  });

  testWidgets('a pressed button glows on its own', (WidgetTester tester) async {
    await tester.pumpWidget(_app(MorphGlassContainer(child: _buttons())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_census(tester), isEmpty);
    final gesture = await tester.startGesture(const Offset(60, 42));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_census(tester).single.split, GlassSplit.glow);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a container in a floating sheet is drawn scaled', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () => showMorphSheet<void>(
                context,
                detents: const [MorphSheetDetent.medium],
                builder: (BuildContext context) => MorphGlassContainer(
                  child: Column(
                    children: [
                      for (var i = 0; i < 3; i++)
                        SizedBox(
                          width: 200,
                          height: 44,
                          child: MorphGlassButton(
                            onPressed: () {},
                            child: Text('$i'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              child: const Text('present'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await tester.pumpAndSettle();
    expect([
      for (final census in _census(tester)) census.split,
    ], List.filled(3, GlassSplit.scaled));
  });

  testWidgets('a highlighted list row breaks its glass out of the section', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MorphListSection(
          children: [
            for (var i = 0; i < 2; i++)
              MorphListRow(
                title: Text('Row $i'),
                onTap: () {},
                trailing: SizedBox(
                  width: 72,
                  height: 34,
                  child: MorphGlassButton(onPressed: () {}, child: Text('$i')),
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_census(tester), isEmpty);
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.text('Row 0')) + const Offset(4, 4),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      _census(tester).single.blocker,
      isA<RenderObject>().having(
        (RenderObject o) => o.runtimeType.toString(),
        'type',
        'RenderGlassPlaneBreak',
      ),
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
