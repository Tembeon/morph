import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';
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
                    openBuilder: (BuildContext context, MorphFlight flight) =>
                        const Text('sheet'),
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

  Widget fellowshipHost({required Rect neighbor, MorphPieceChannel? channel}) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Scaffold(
        body: MorphSkin(
          blend: 24,
          color: const Color(0xFF2A2440),
          pieces: <MorphPiece>[
            MorphPiece(id: 'bystander', rect: neighbor),
            MorphPiece.morphable(
              id: 'hero',
              rect: const .fromLTWH(170, 310, 110, 50),
              channel: channel,
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () {
                    showMorphDialog(
                      context,
                      from: 'hero',
                      width: 500,
                      height: 420,
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
    );
  }

  Future<int> maxBlobsDuringFlight(WidgetTester tester) async {
    final RenderMorphSkin skin = tester.renderObject(find.byType(MorphSkin));
    int maxBlobs = 0;
    await tester.tap(find.text('fly'));
    for (int i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (skin.lastFlightBlobCount > maxBlobs) {
        maxBlobs = skin.lastFlightBlobCount;
      }
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    return maxBlobs;
  }

  testWidgets('flight blob ignores pieces outside the launch fellowship', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The bystander is far from the hero at launch (gap >> k), but the
    // opening dialog grows right past it - and must not goo onto it.
    await tester.pumpWidget(
      fellowshipHost(neighbor: const Rect.fromLTWH(200, 100, 120, 70)),
    );
    expect(await maxBlobsDuringFlight(tester), 0);
  });

  testWidgets('flight blob keeps the neck to a fused launch fellowship', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Fused at rest (gap 10 <= k 24): the neighbor is part of the body
    // the hero launches out of, so the blob necks to it.
    await tester.pumpWidget(
      fellowshipHost(neighbor: const Rect.fromLTWH(40, 300, 120, 70)),
    );
    expect(await maxBlobsDuringFlight(tester), greaterThan(0));
  });

  testWidgets('a stray flight of a disposed tag is ignored by a new skin', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget stage({required bool withSkin}) {
      return MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: !withSkin
              ? const SizedBox()
              : MorphSkin(
                  blend: 24,
                  color: const Color(0xFF2A2440),
                  pieces: <MorphPiece>[
                    MorphPiece.morphable(
                      id: 'hero',
                      rect: const .fromLTWH(170, 310, 110, 50),
                      child: Builder(
                        builder: (BuildContext context) => TextButton(
                          onPressed: () {
                            showMorphDialog(
                              context,
                              from: 'hero',
                              builder:
                                  (BuildContext context, MorphFlight flight) =>
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
      );
    }

    await tester.pumpWidget(stage(withSkin: true));
    await tester.tap(find.text('fly'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // The screen is torn down mid-flight: the tag disposes, the flight
    // lives on (the scope owns it)...
    await tester.pumpWidget(stage(withSkin: false));
    await tester.pump(const Duration(milliseconds: 16));

    // ...and a fresh skin mounts with the same piece id. It must treat
    // the stray flight as none at all: no defunct-tag access in the
    // debug assert, no companion blob, no exceptions.
    await tester.pumpWidget(stage(withSkin: true));
    // Both doors: observers still see the stray, engine consumers
    // (the skin, a retarget in MorphFlight.launch) see nothing.
    final MorphScopeState scope = tester.state(find.byType(MorphScope));
    expect(scope.flightOf('hero'), isNotNull);
    expect(scope.liveFlightOf('hero'), isNull);
    final RenderMorphSkin skin = tester.renderObject(find.byType(MorphSkin));
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      expect(skin.lastFlightBlobCount, 0);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
  });

  testWidgets('channel: a write re-traces its own cluster, no rebuild, '
      'no relayout, hit test follows', (WidgetTester tester) async {
    final MorphPieceChannel channel = MorphPieceChannel();
    addTearDown(channel.dispose);
    int builds = 0;
    int layouts = 0;
    int taps = 0;
    await tester.pumpWidget(
      host(
        MorphSkin(
          blend: 20,
          color: const Color(0xFF2A2440),
          pieces: <MorphPiece>[
            MorphPiece(
              id: 'a',
              rect: const .fromLTWH(20, 20, 100, 60),
              channel: channel,
              child: Builder(
                builder: (BuildContext context) {
                  builds++;
                  return TextButton(
                    onPressed: () => taps++,
                    child: const Text('tap'),
                  );
                },
              ),
            ),
            MorphPiece(
              id: 'b',
              rect: const .fromLTWH(220, 120, 100, 60),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  layouts++;
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );
    final RenderMorphSkin skin = tester.renderObject<RenderMorphSkin>(
      find.byType(MorphSkin),
    );
    expect(skin.tracer.lastClusterCount, 2);
    final int buildsBefore = builds;
    final int layoutsBefore = layouts;
    final Offset origin = tester.getTopLeft(find.byType(MorphSkin));

    channel.update(offset: const Offset(0, 80));
    await tester.pump();

    // The tick stayed on the paint path: nothing rebuilt, nothing
    // relaid out, and only the moved piece's cluster re-traced.
    expect(builds, buildsBefore);
    expect(layouts, layoutsBefore);
    expect(skin.tracer.lastClusterCount, 2);
    expect(skin.tracer.lastMissCount, 1);

    // Hit testing follows the displaced content: the base center
    // misses, the displaced center hits.
    await tester.tapAt(origin + const Offset(70, 50));
    expect(taps, 0);
    await tester.tapAt(origin + const Offset(70, 130));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel: the flight launches from the displaced rect and '
      'the landing composes with the delta', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final MorphPieceChannel channel = MorphPieceChannel();
    addTearDown(channel.dispose);
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
              .morphable(
                id: 'hero',
                rect: const .fromLTWH(170, 310, 110, 50),
                channel: channel,
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

    channel.update(offset: const Offset(60, 30));
    await tester.pump();

    // localToGlobal sees the channel transform (applyPaintTransform):
    // the tap lands on the displaced pill and the flight measures its
    // source there.
    await tester.tap(find.text('fly'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final RenderBox skinBox = tester.renderObject<RenderMorphSkin>(
      find.byType(MorphSkin),
    );
    final Rect expected =
        skinBox.localToGlobal(const Offset(170 + 60, 310 + 30)) &
        const Size(110, 50);
    expect(flight!.sourceRect.left, moreOrLessEquals(expected.left));
    expect(flight!.sourceRect.top, moreOrLessEquals(expected.top));
    expect(flight!.sourceRect.width, moreOrLessEquals(expected.width));
    expect(flight!.sourceRect.height, moreOrLessEquals(expected.height));

    // The close plays the landing bump on top of the still-displaced
    // channel - the composed content transform must stay exception
    // free all the way to settle.
    for (int i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    flight!.close();
    for (int i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(flight!.isFinished, isTrue);
  });

  testWidgets('channel: fellowship is captured from the displaced geometry', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The same far-neighbor scene that yields ZERO blobs undisplaced
    // (pinned above): dragged into contact through the channel before
    // launch, the bystander joins the launch fellowship and the blob
    // necks to it.
    final MorphPieceChannel channel = MorphPieceChannel();
    addTearDown(channel.dispose);
    await tester.pumpWidget(
      fellowshipHost(
        neighbor: const Rect.fromLTWH(200, 100, 120, 70),
        channel: channel,
      ),
    );
    channel.update(offset: const Offset(30, -135));
    await tester.pump();
    expect(await maxBlobsDuringFlight(tester), greaterThan(0));
  });

  testWidgets('channel: swapping the channel object resubscribes', (
    WidgetTester tester,
  ) async {
    final MorphPieceChannel first = MorphPieceChannel();
    final MorphPieceChannel second = MorphPieceChannel();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget build(MorphPieceChannel channel) {
      return host(
        MorphSkin(
          blend: 20,
          color: const Color(0xFF2A2440),
          pieces: <MorphPiece>[
            MorphPiece(
              id: 'p',
              rect: const .fromLTWH(40, 60, 200, 100),
              channel: channel,
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(build(first));
    first.update(offset: const Offset(10, 0));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();

    await tester.pumpWidget(build(second));
    first.update(offset: const Offset(20, 0));
    expect(tester.binding.hasScheduledFrame, isFalse);
    second.update(offset: const Offset(10, 0));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('channel rejects negative scales; zero deflates to empty mass', () {
    final MorphPieceChannel channel = MorphPieceChannel();
    expect(() => channel.update(scaleX: -1), throwsAssertionError);
    expect(() => channel.update(scaleY: -0.1), throwsAssertionError);
    channel.update(scaleX: 0, scaleY: 0);
    expect(channel.apply(const Rect.fromLTWH(10, 10, 100, 50)).isEmpty, isTrue);
    channel.dispose();
  });

  testWidgets('a link into a channel-deflated piece paints, not asserts', (
    WidgetTester tester,
  ) async {
    final MorphPieceChannel channel = MorphPieceChannel();
    addTearDown(channel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MorphSkin(
            color: const Color(0xFF2A2440),
            links: const <MorphLink>[MorphLink(from: 'a', to: 'b')],
            pieces: <MorphPiece>[
              const MorphPiece(id: 'a', rect: Rect.fromLTWH(40, 40, 100, 50)),
              MorphPiece(
                id: 'b',
                rect: const Rect.fromLTWH(240, 40, 100, 50),
                channel: channel,
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Deflate: the default bridge width derives from the collapsed
    // height - the pipe must vanish with the mass, not trip the
    // bridge's radius assert on every paint.
    channel.update(scaleX: 0, scaleY: 0);
    await tester.pump();
    expect(tester.takeException(), isNull);
    channel.update(scaleX: 1, scaleY: 1);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the flight blob lands in group space under a nested overlay', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The nearest Overlay is offset from the window origin - the
    // embedded-device-frame case. The flight's rects live in overlay
    // coordinates; the blob must translate them into group space
    // through the overlay, not assume the two origins coincide.
    const Rect heroRect = Rect.fromLTWH(170, 310, 110, 50);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(left: 60, top: 90),
            child: Overlay(
              initialEntries: <OverlayEntry>[
                OverlayEntry(
                  builder: (BuildContext context) => MorphSkin(
                    blend: 24,
                    color: const Color(0xFF2A2440),
                    pieces: <MorphPiece>[
                      const MorphPiece(
                        id: 'bystander',
                        rect: Rect.fromLTWH(170, 380, 110, 50),
                      ),
                      MorphPiece.morphable(
                        id: 'hero',
                        rect: heroRect,
                        child: Builder(
                          builder: (BuildContext context) => TextButton(
                            onPressed: () => showMorphDialog(
                              context,
                              from: 'hero',
                              builder:
                                  (BuildContext context, MorphFlight flight) =>
                                      const Text('dialog'),
                            ),
                            child: const Text('fly'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final RenderMorphSkin skin = tester.renderObject(find.byType(MorphSkin));
    await tester.tap(find.text('fly'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 8));
    expect(skin.lastFlightBlobCount, 1);
    // Early in the flight the blob still hugs the launch rect. A
    // coordinate-space mixup would displace it by the overlay offset.
    final Rect blob = skin.lastFlightBlobRects.single;
    expect(
      (blob.center - heroRect.center).distance,
      lessThan(30),
      reason:
          'the blob must sit at the hero piece, not shifted by the '
          'nested overlay origin',
    );
    for (int i = 0; i < 600; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
  });

  testWidgets('tint-only update is paint-only: no relayout, no resync', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        const MorphSkin(
          blend: 10,
          color: Color(0xFF000000),
          pieces: <MorphPiece>[
            MorphPiece(id: 'a', rect: .fromLTWH(20, 20, 100, 60)),
            MorphPiece(id: 'b', rect: .fromLTWH(160, 20, 100, 60)),
          ],
        ),
      ),
    );
    final RenderMorphSkin skin = tester.renderObject(find.byType(MorphSkin));
    expect(skin.debugNeedsPaint, isFalse);

    skin.pieces = const <MorphPiece>[
      MorphPiece(
        id: 'a',
        rect: .fromLTWH(20, 20, 100, 60),
        tint: Color(0x80FF0000),
      ),
      MorphPiece(id: 'b', rect: .fromLTWH(160, 20, 100, 60)),
    ];
    expect(skin.debugNeedsPaint, isTrue);
    expect(skin.debugNeedsLayout, isFalse);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tint inks only its own body: piece blended, sibling clean', (
    WidgetTester tester,
  ) async {
    const Color base = Color(0xFF000000);
    const Color tint = Color(0x80FF0000);
    final GlobalKey boundaryKey = GlobalKey();
    await tester.pumpWidget(
      host(
        RepaintBoundary(
          key: boundaryKey,
          child: const MorphSkin(
            // Well under the 40px gap: the pieces stay separate blobs.
            blend: 8,
            color: base,
            pieces: <MorphPiece>[
              MorphPiece(
                id: 'lit',
                rect: .fromLTWH(20, 20, 100, 60),
                radius: 12,
                tint: tint,
              ),
              MorphPiece(
                id: 'calm',
                rect: .fromLTWH(160, 20, 100, 60),
                radius: 12,
              ),
            ],
          ),
        ),
      ),
    );
    final RenderRepaintBoundary boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    late final ui.Image image;
    await tester.runAsync(() async {
      image = await boundary.toImage();
    });
    ByteData? raw;
    await tester.runAsync(() async {
      raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    final ByteData bytes = raw!;
    Color pixel(int x, int y) {
      final int i = (y * image.width + x) * 4;
      return Color.fromARGB(
        bytes.getUint8(i + 3),
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    }

    // Center of the tinted piece: tint srcOver base = half red on black.
    final Color lit = pixel(70, 50);
    expect(lit.a, 1.0);
    expect((lit.r * 255).round(), closeTo(128, 3));
    expect((lit.g * 255).round(), closeTo(0, 3));
    // The untinted sibling stays pure base.
    expect(pixel(210, 50), base);
    image.dispose();
  });

  testWidgets('stroke: inner contour over the tint, nothing outside', (
    WidgetTester tester,
  ) async {
    const Color base = Color(0xFF000000);
    const Color tint = Color(0xFFFF0000);
    const Color line = Color(0xFF00FF00);
    final GlobalKey boundaryKey = GlobalKey();
    await tester.pumpWidget(
      host(
        RepaintBoundary(
          key: boundaryKey,
          child: const ColoredBox(
            color: Color(0xFFFFFFFF),
            child: MorphSkin(
              blend: 8,
              color: base,
              stroke: MorphStroke(color: line, width: 6),
              pieces: <MorphPiece>[
                MorphPiece(
                  id: 'lit',
                  rect: .fromLTWH(20, 20, 100, 60),
                  radius: 12,
                  tint: tint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final RenderRepaintBoundary boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    late final ui.Image image;
    await tester.runAsync(() async {
      image = await boundary.toImage();
    });
    ByteData? raw;
    await tester.runAsync(() async {
      raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    final ByteData bytes = raw!;
    Color pixel(int x, int y) {
      final int i = (y * image.width + x) * 4;
      return Color.fromARGB(
        bytes.getUint8(i + 3),
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    }

    // Just inside the left edge at mid-height: the stroke, NOT the tint
    // eating it - the paint order is fill, tints, stroke.
    expect(pixel(23, 50), line);
    // Well inside: the tint over the fill, untouched by the stroke.
    expect(pixel(70, 50), tint);
    // Outside the silhouette: the ground shows through - the stroke is
    // inner and cannot grow the mass.
    expect(pixel(12, 50), const Color(0xFFFFFFFF));
    image.dispose();
  });

  testWidgets('stroke update is paint-only: no relayout, no re-trace', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        const MorphSkin(
          blend: 10,
          color: Color(0xFF000000),
          pieces: <MorphPiece>[
            MorphPiece(id: 'a', rect: .fromLTWH(20, 20, 100, 60)),
            MorphPiece(id: 'b', rect: .fromLTWH(160, 20, 100, 60)),
          ],
        ),
      ),
    );
    final RenderMorphSkin skin = tester.renderObject(find.byType(MorphSkin));
    final int misses = skin.tracer.lastMissCount;
    final int clusters = skin.tracer.lastClusterCount;
    expect(skin.debugNeedsPaint, isFalse);

    skin.stroke = const MorphStroke(color: Color(0xFFFFFFFF), width: 2);
    expect(skin.debugNeedsPaint, isTrue);
    expect(skin.debugNeedsLayout, isFalse);
    await tester.pump();
    expect(tester.takeException(), isNull);
    // The stroke is not part of the trace signature: the cached contour
    // survives and the tracer never runs again.
    expect(skin.tracer.lastMissCount, misses);
    expect(skin.tracer.lastClusterCount, clusters);
  });
}
