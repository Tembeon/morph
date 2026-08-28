import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

double _tanh(double x) {
  final double e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

Widget host(Widget child) {
  return MaterialApp(
    theme: ThemeData(brightness: .dark),
    home: Scaffold(
      body: Center(child: SizedBox(width: 300, child: child)),
    ),
  );
}

Future<void> settle(WidgetTester tester, {int frames = 400}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

void main() {
  testWidgets('Tug: follows the finger, springs home, taps pass through', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      host(
        Tug(
          child: SpringButton(
            onPressed: () => taps++,
            child: const Padding(padding: .all(20), child: Text('pill')),
          ),
        ),
      ),
    );
    final Offset home = tester.getCenter(find.text('pill'));
    final State<StatefulWidget> mounted = tester.state(
      find.byType(SpringButton),
    );
    // Drag past the touch slop: the surface must follow, rubber-banded.
    // Two moves on purpose - the first one wins the gesture arena
    // (dragStartBehavior.start swallows it), the second one pulls.
    final TestGesture gesture = await tester.startGesture(home);
    await gesture.moveBy(const Offset(20, 5));
    await tester.pump();
    await gesture.moveBy(const Offset(140, 40));
    // The offset chases the finger on a follow spring - give it a few
    // frames to arrive before measuring.
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    final Offset pulled = tester.getCenter(find.text('pill'));
    // The travel budget is deliberately tiny: the transmission is a few
    // percent (heavier still here - the 300px-wide host is past the 2:1
    // aspect and calms itself), and the pull mostly feeds the shape.
    expect((pulled - home).distance, greaterThan(2));
    expect((pulled - home).distance, lessThan(63));
    // Release: it springs back to exactly home.
    await gesture.up();
    await settle(tester);
    expect((tester.getCenter(find.text('pill')) - home).distance, lessThan(1));
    // The wrapper chain must stay structurally stable across the zero
    // crossing: a remounted subtree here is the "ghost button" bug - a
    // MorphTag inside would forget it belongs to a live flight.
    expect(identical(tester.state(find.byType(SpringButton)), mounted), isTrue);
    // A clean tap still reaches the button through the leash.
    await tester.tap(find.text('pill'));
    await tester.pump();
    expect(taps, 1);
    await settle(tester);
  });

  testWidgets('Tug: high-frequency pointer events keep the chase alive', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Tug(
          child: SizedBox(
            width: 132,
            height: 44,
            child: Center(child: Text('pill')),
          ),
        ),
      ),
    );
    final Offset home = tester.getCenter(find.text('pill'));
    final TestGesture gesture = await tester.startGesture(home);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 16));
    // Several move events per frame, like a high-frequency mouse: a
    // per-event controller retarget starves the simulation (it
    // restarts before it ever ticks) and the surface freezes while
    // the pointer moves. The chase ticker must keep integrating.
    for (int frame = 0; frame < 12; frame++) {
      for (int sub = 0; sub < 4; sub++) {
        await gesture.moveBy(const Offset(3, 1));
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      (tester.getCenter(find.text('pill')) - home).distance,
      greaterThan(2),
    );
    await gesture.up();
    await settle(tester);
    expect((tester.getCenter(find.text('pill')) - home).distance, lessThan(1));
  });

  testWidgets('showMorphMenu: the control becomes its own menu', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: .dark),
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Center(
            child: MorphTag(
              id: 'menu-button',
              shape: const StadiumBorder(),
              surfaceColor: const Color(0xFF2A2440),
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () {
                    showMorphMenu(
                      context,
                      items: <MorphMenuItem>[
                        MorphMenuItem(
                          icon: Icons.push_pin_outlined,
                          label: 'Pin',
                          onSelected: () => selected = 'pin',
                        ),
                        MorphMenuItem(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete',
                          tint: const Color(0xFFFF7A83),
                          onSelected: () => selected = 'delete',
                        ),
                      ],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    // The rows cascaded in with the flight's own spring.
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    // Selecting fires the action first, then the menu closes home.
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(selected, 'delete');
    await settle(tester);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  test('ChaseSpring converges at a 30 fps step', () {
    final ChaseSpring spring = ChaseSpring()
      ..grab(Offset.zero)
      ..target = const Offset(10, 0);
    // At one whole-frame Euler step this stiffness diverges (10, 0,
    // 20, -10, 40, -40...). Sliced integration must converge instead.
    double maxAbs = 0;
    for (int i = 0; i < 60; i++) {
      spring.tick(1 / 30);
      maxAbs = spring.value.dx.abs() > maxAbs ? spring.value.dx.abs() : maxAbs;
    }
    expect(maxAbs, lessThan(15), reason: 'no growing oscillation');
    expect((spring.value - const Offset(10, 0)).distance, lessThan(0.5));
  });

  Widget menuHost({
    required int itemCount,
    ValueChanged<String>? onSelected,
    double textScale = 1,
  }) {
    return MaterialApp(
      theme: ThemeData(brightness: .dark),
      builder: (BuildContext context, Widget? child) => MorphScope(
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Center(
          child: MorphTag(
            id: 'menu-button',
            shape: const StadiumBorder(),
            child: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () {
                  showMorphMenu(
                    context,
                    items: <MorphMenuItem>[
                      for (int i = 0; i < itemCount; i++)
                        MorphMenuItem(
                          icon: Icons.circle_outlined,
                          label: 'Item with a fairly long label $i',
                          onSelected: () => onSelected?.call('item-$i'),
                        ),
                    ],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('showMorphMenu: seven items cascade inside the contract', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(menuHost(itemCount: 7));
    await tester.tap(find.text('open'));
    // settle() asserts no exception per frame: the fixed-step cascade
    // used to walk row seven past to = 1 and trip MorphReveal's range
    // assert while the shuttle builds.
    await settle(tester);
    expect(find.text('Item with a fairly long label 6'), findsOneWidget);
  });

  testWidgets('showMorphMenu: accessibility text scale does not overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(menuHost(itemCount: 4, textScale: 2));
    await tester.tap(find.text('open'));
    // settle() asserts no exception per frame: fixed 48 px rows used
    // to overflow the popover at doubled text sizes.
    await settle(tester);
    expect(find.textContaining('label 3'), findsOneWidget);
  });

  testWidgets('SpringButton: focusable, Enter activates, announces button', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    int presses = 0;
    await tester.pumpWidget(
      host(SpringButton(onPressed: () => presses++, child: const Text('go'))),
    );
    expect(
      tester.getSemantics(find.text('go')),
      matchesSemantics(
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        label: 'go',
      ),
    );

    Focus.of(tester.element(find.text('go'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
    await settle(tester);
    semantics.dispose();
  });

  testWidgets('an open overlay blocks semantics of the page behind', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const Text('page-text'),
              MorphTag(
                id: 'btn',
                child: Builder(
                  builder: (BuildContext context) => TextButton(
                    onPressed: () => flight = showMorphDialog(
                      context,
                      from: 'btn',
                      builder: (BuildContext context, MorphFlight f) =>
                          const Text('dialog-content'),
                    ),
                    child: const Text('open-me'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.semantics.byLabel('page-text'), findsOne);
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);

    // The page behind the scrim must be gone from the semantics tree,
    // like behind any modal barrier.
    expect(find.text('page-text'), findsOneWidget);
    expect(find.semantics.byLabel('page-text'), findsNothing);
    expect(find.semantics.byLabel('dialog-content'), findsOne);

    flight!.close();
    await settle(tester);
    expect(find.semantics.byLabel('page-text'), findsOne);
    semantics.dispose();
  });

  testWidgets('Tug parity: the settled model matches the reference math', (
    WidgetTester tester,
  ) async {
    // The oracle is the liquid-glass reference (Kyant0's LiquidButton
    // ported): travel = capM * tanh(give * d / capM) on the RAW pull,
    // shape at [stretch] gain saturated on 0.35 * M, volume-corrected
    // scales, the travel riding inside the scale. Written here
    // independently so a regression in the widget cannot hide in a
    // shared implementation.
    final MorphPieceChannel channel = MorphPieceChannel();
    addTearDown(channel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: Tug(
              channel: channel,
              pressGrow: 0,
              child: const Center(child: Text('pill')),
            ),
          ),
        ),
      ),
    );
    final Offset home = tester.getCenter(find.text('pill'));
    final TestGesture gesture = await tester.startGesture(home);
    await gesture.moveBy(const Offset(20, 5));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 20));
    // Hold until the chase snaps exactly onto the target (the rest
    // guard) - the model is then a pure function of the resting pull.
    for (int i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    const Offset pull = Offset(80, 25);
    const double m = 100;
    final double len = pull.distance;
    final double travelLen = m * _tanh(0.05 * len / m);
    final Offset travel = pull * (travelLen / len);
    Offset shape = pull * 0.08;
    final double ceiling = 0.35 * m;
    final double shapeLen = shape.distance;
    shape = shape * (ceiling * _tanh(shapeLen / ceiling) / shapeLen);
    final double relX = shape.dx.abs() / m;
    final double relY = shape.dy.abs() / m;
    final double baseX = 1 + relX;
    final double baseY = 1 + relY;
    final double mag = math.sqrt(relX * relX + relY * relY);
    final double correction = math.sqrt((1 + mag * 0.5) / (baseX * baseY));
    final double scaleX = baseX * correction;
    final double scaleY = baseY * correction;

    expect(channel.scaleX, closeTo(scaleX, 0.002));
    expect(channel.scaleY, closeTo(scaleY, 0.002));
    expect(channel.offset.dx, closeTo(travel.dx * scaleX, 0.05));
    expect(channel.offset.dy, closeTo(travel.dy * scaleY, 0.05));
    await gesture.up();
    await settle(tester);
    expect(channel.offset.distance, lessThan(0.5));
  });

  testWidgets('Tug: pointer-down lifts the glass and release settles it', (
    WidgetTester tester,
  ) async {
    final MorphPieceChannel channel = MorphPieceChannel();
    addTearDown(channel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: Tug(
              channel: channel,
              child: const Center(child: Text('pill')),
            ),
          ),
        ),
      ),
    );
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('pill')),
    );
    // Two pumps: the first tick of a freshly started ticker evaluates
    // at t = 0 (Ticker.elapsed restarts on start), only the second one
    // advances the press spring.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    // The finger LIFTS glass: the surface grows, it does not sink.
    expect(channel.scaleX, greaterThan(1.02));
    expect(channel.scaleY, greaterThan(1.02));
    await gesture.up();
    await settle(tester);
    expect(channel.scaleX, closeTo(1, 0.005));
    expect(channel.scaleY, closeTo(1, 0.005));
  });

  testWidgets('Tug: vertical 0 pins the height and the vertical travel', (
    WidgetTester tester,
  ) async {
    final MorphPieceChannel channel = MorphPieceChannel();
    addTearDown(channel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: Tug(
              channel: channel,
              vertical: 0,
              child: const Center(child: Text('pill')),
            ),
          ),
        ),
      ),
    );
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('pill')),
    );
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    expect(channel.offset.dx, greaterThan(0.5));
    expect(channel.offset.dy, 0);
    expect(channel.scaleY, 1);
    await gesture.up();
    await settle(tester);
  });

  testWidgets('Tug: a non-primary button neither presses nor pulls', (
    WidgetTester tester,
  ) async {
    final MorphPieceChannel channel = MorphPieceChannel();
    addTearDown(channel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: Tug(
              channel: channel,
              child: const Center(child: Text('pill')),
            ),
          ),
        ),
      ),
    );
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('pill')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.moveBy(const Offset(40, 10));
    await tester.pump(const Duration(milliseconds: 120));
    expect(channel.isIdentity, isTrue);
    await gesture.up();
    await settle(tester);
  });

  testWidgets('Tug in channel mode: repeated drags never walk the home away', (
    WidgetTester tester,
  ) async {
    // The regression: _grab recovers the home center as
    // `center - channel.offset`. Anything folded into the written
    // offset is read back as real displacement on the NEXT grab, so the
    // error compounds and the surface migrates across the screen.
    final MorphPieceChannel channel = MorphPieceChannel();
    addTearDown(channel.dispose);

    const Rect home = Rect.fromLTWH(40, 40, 120, 44);
    await tester.pumpWidget(
      host(
        SizedBox(
          height: 200,
          child: MorphScope(
            child: MorphSkin(
              color: const Color(0xFF203040),
              pieces: <MorphPiece>[
                MorphPiece(
                  id: 'pill',
                  rect: home,
                  radius: 22,
                  channel: channel,
                  child: Tug(
                    channel: channel,
                    child: const Center(child: Text('pill')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    final Offset start = tester.getCenter(find.text('pill'));

    for (int round = 0; round < 4; round++) {
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('pill')),
      );
      await gesture.moveBy(const Offset(24, 8));
      await tester.pump();
      await gesture.moveBy(const Offset(90, 40));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
      // Re-grab MID-RETURN on purpose: at full rest the channel offset
      // is zero and a mis-scaled write cannot be told apart from a
      // correct one. The error only shows when home is recovered from a
      // surface that is still displaced.
      await tester.pump(const Duration(milliseconds: 24));
    }
    await settle(tester);
    expect(
      (tester.getCenter(find.text('pill')) - start).distance,
      lessThan(1),
      reason: 'the surface drifted across interrupted drags',
    );
    expect(channel.offset.distance, lessThan(1));
  });

  testWidgets('Tug: a flick never throws the surface off its leash', (
    WidgetTester tester,
  ) async {
    // The landing bump reads the remaining displacement as a spring
    // value, but it is normalised by the pull that produced it - so a
    // short drag released fast overshoots past -1 and bumpRecoil, which
    // is in PIXELS, multiplies that. Unclamped it launched the surface
    // clean off the screen.
    await tester.pumpWidget(
      host(
        const Tug(
          cap: 1.4,
          child: Padding(padding: .all(20), child: Text('pill')),
        ),
      ),
    );
    final Offset home = tester.getCenter(find.text('pill'));
    final TestGesture gesture = await tester.startGesture(home);
    await gesture.moveBy(const Offset(18, 4));
    await tester.pump();
    await gesture.moveBy(const Offset(26, 6));
    await tester.pump(const Duration(milliseconds: 8));
    await gesture.up();
    double worst = 0;
    for (int i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      final double d = (tester.getCenter(find.text('pill')) - home).distance;
      worst = math.max(worst, d);
      if (!tester.binding.hasScheduledFrame) break;
    }
    expect(worst, lessThan(200), reason: 'the flick threw it $worst px');
    expect((tester.getCenter(find.text('pill')) - home).distance, lessThan(1));
  });
}
