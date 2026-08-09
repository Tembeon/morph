import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

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
    await gesture.moveBy(const Offset(60, 20));
    // The offset chases the finger on a follow spring - give it a few
    // frames to arrive before measuring.
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    final Offset pulled = tester.getCenter(find.text('pill'));
    expect((pulled - home).distance, greaterThan(10));
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
      greaterThan(5),
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
}
