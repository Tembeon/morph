import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/skin.dart';

Widget host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 340, height: 220, child: child)),
    ),
  );
}

void main() {
  testWidgets('MorphSkin builds: skin behind, content stays tappable', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      host(
        MorphSkin(
          blend: 20,
          color: const Color(0xFF2A2440),
          pieces: <MorphPiece>[
            MorphPiece(
              id: 'main',
              rect: const .fromLTWH(40, 60, 200, 100),
              radius: 20,
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('tap'),
              ),
            ),
            const MorphPiece(
              id: 'tab',
              rect: .fromLTWH(220, 40, 70, 40),
              radius: 14,
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('tap'));
    expect(taps, 1);
  });

  // The recompute-only-on-change guarantee itself lives in LiquidTracer
  // and is unit-tested there; at the widget level we pin the render
  // object contract: one persistent RenderMorphSkin (its tracer cache
  // survives rebuilds), its own repaint boundary, and knob updates that
  // do not recreate it.
  testWidgets('render object persists across rebuilds and owns its layer', (
    WidgetTester tester,
  ) async {
    Widget build(double k) {
      return host(
        MorphSkin(
          blend: k,
          color: const Color(0xFF2A2440),
          pieces: const <MorphPiece>[
            MorphPiece(id: 'a', rect: .fromLTWH(20, 20, 100, 60)),
            MorphPiece(id: 'b', rect: .fromLTWH(140, 20, 100, 60)),
          ],
        ),
      );
    }

    await tester.pumpWidget(build(10));
    final RenderMorphSkin before = tester.renderObject<RenderMorphSkin>(
      find.byType(MorphSkin),
    );
    expect(before.isRepaintBoundary, isTrue);
    await tester.pumpWidget(build(10));
    await tester.pumpWidget(build(40));
    final RenderMorphSkin after = tester.renderObject<RenderMorphSkin>(
      find.byType(MorphSkin),
    );
    expect(identical(before, after), isTrue);
    expect(after.k, 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a piece from the middle keeps MorphTag identity', (
    WidgetTester tester,
  ) async {
    Widget build(List<String> ids) {
      return MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: MorphSkin(
            blend: 10,
            color: const Color(0xFF2A2440),
            pieces: <MorphPiece>[
              for (int i = 0; i < ids.length; i++)
                MorphPiece(
                  id: ids[i],
                  rect: .fromLTWH(20 + i * 90.0, 20, 80, 50),
                  child: MorphTag(id: ids[i], child: Text(ids[i])),
                ),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(build(<String>['a', 'b', 'c']));
    expect(find.byKey(const ValueKey<Object>('b')), findsOneWidget);
    await tester.pumpWidget(build(<String>['a', 'c']));
    // Without keys on Positioned, the element of piece 'b' would be
    // reused for 'c' and MorphTag would trip the duplicate-id assert.
    expect(tester.takeException(), isNull);
    expect(find.text('c'), findsOneWidget);
    await tester.pumpWidget(build(<String>['a', 'b', 'c']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('solid: false removes the mass but the content stays alive', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        const MorphSkin(
          blend: 20,
          color: Color(0xFF2A2440),
          pieces: <MorphPiece>[
            MorphPiece(id: 'a', rect: .fromLTWH(20, 20, 100, 60)),
            MorphPiece(
              id: 'b',
              rect: .fromLTWH(140, 20, 100, 60),
              solid: false,
              child: Text('ghost'),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('ghost'), findsOneWidget);
  });

  testWidgets('morphable: a scope flight is picked up, opens, and lands', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: MorphSkin(
            blend: 24,
            color: const Color(0xFF2A2440),
            pieces: <MorphPiece>[
              const MorphPiece(
                id: 'neighbor',
                rect: .fromLTWH(40, 300, 120, 70),
              ),
              // All the layer-1 sugar: no MorphTag, no flight in state.
              .morphable(
                id: 'hero',
                rect: const .fromLTWH(170, 310, 110, 50),
                child: Builder(
                  builder: (BuildContext context) => TextButton(
                    onPressed: () {
                      flight = showMorphDialog(
                        context,
                        from: 'hero',
                        width: 400,
                        height: 300,
                        builder: (BuildContext context, MorphFlight flight) =>
                            const Text('dialog'),
                      );
                    },
                    child: const Text('fly'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('fly'));
    for (int i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(flight!.isOpenOrOpening, isTrue);

    flight!.close();
    for (int i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(flight!.isFinished, isTrue);
    expect(find.text('fly'), findsOneWidget);
  });

  testWidgets(
    'MorphAnchor(tagId): the flight is visible in the scope by name',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      bool open = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) =>
              MorphScope(child: child!),
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  rebuild = setState;
                  return MorphAnchor(
                    isOpen: open,
                    tagId: 'pill',
                    onDismiss: () => rebuild(() => open = false),
                    target: MorphTargetSpec.sheet(),
                    closedBuilder: (BuildContext context) => const Text('pill'),
                    openBuilder: (BuildContext context) => const Text('sheet'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final MorphScopeState scope = tester.state<MorphScopeState>(
        find.byType(MorphScope),
      );
      expect(scope.flightOf('pill'), isNull);
      rebuild(() => open = true);
      await tester.pump();
      await tester.pump();
      expect(scope.flightOf('pill'), isNotNull);
      for (int i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        expect(tester.takeException(), isNull);
        if (!tester.binding.hasScheduledFrame) {
          break;
        }
      }
      expect(find.text('sheet'), findsOneWidget);
    },
  );

  testWidgets('MorphSkinStyle: presets apply, an explicit k takes precedence', (
    WidgetTester tester,
  ) async {
    expect(MorphSkinStyle.geometric.blend, lessThan(MorphSkinStyle.goo.blend));
    expect(
      MorphSkinStyle.subtle.blend,
      lessThan(MorphSkinStyle.geometric.blend),
    );
    await tester.pumpWidget(
      host(
        const MorphSkin(
          style: .goo,
          blend: 5,
          color: Color(0xFF2A2440),
          pieces: <MorphPiece>[
            MorphPiece(id: 'a', rect: .fromLTWH(20, 20, 100, 60)),
            MorphPiece(id: 'b', rect: .fromLTWH(160, 20, 100, 60)),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('MorphLink fuses distant pieces with a bridge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        const MorphSkin(
          blend: 5,
          links: <MorphLink>[MorphLink(from: 'a', to: 'b')],
          color: Color(0xFF2A2440),
          pieces: <MorphPiece>[
            MorphPiece(id: 'a', rect: .fromLTWH(10, 80, 80, 50)),
            MorphPiece(id: 'b', rect: .fromLTWH(240, 80, 80, 50)),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
