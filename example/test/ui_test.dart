import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/ui/goo_selector.dart';
import 'package:morph_example/ui/spring_button.dart';
import 'package:morph_example/ui/spring_switcher.dart';
import 'package:morph_example/ui/spring_toggle.dart';
import 'package:morph_example/ui/tug.dart';

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
  testWidgets('GooSelector: taps select, mid-flight retarget, deselect', (
    WidgetTester tester,
  ) async {
    int? selected = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return GooSelector(
              labels: const <String>['one', 'two', 'three'],
              index: selected,
              onSelect: (int i) => setState(() => selected = i),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('three'));
    await tester.pump();
    expect(selected, 2);
    // Retarget mid-flight: the blob must carry its velocity.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('one'));
    await tester.pump();
    expect(selected, 0);
    await settle(tester);
    // A null selection deflates the blob without exceptions.
    rebuild(() => selected = null);
    await settle(tester);
  });

  testWidgets('SpringSwitcher: swap mid-flight stays continuous', (
    WidgetTester tester,
  ) async {
    Widget page(String label) =>
        SpringSwitcher(child: Text(label, key: ValueKey<String>(label)));
    await tester.pumpWidget(host(page('first')));
    await settle(tester);
    await tester.pumpWidget(host(page('second')));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    // Interrupt the transition with a third child.
    await tester.pumpWidget(host(page('third')));
    await settle(tester);
    expect(find.text('third'), findsOneWidget);
    expect(find.text('second'), findsNothing);
    expect(find.text('first'), findsNothing);
  });

  testWidgets('SpringToggle flips on tap and settles', (
    WidgetTester tester,
  ) async {
    bool value = false;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) =>
              SpringToggleTile(
                label: 'toggle',
                value: value,
                onChanged: (bool v) => setState(() => value = v),
              ),
        ),
      ),
    );
    await tester.tap(find.byType(SpringToggle));
    await tester.pump();
    expect(value, isTrue);
    // Flip back mid-flight: retarget with velocity carry-over.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(SpringToggle));
    await tester.pump();
    expect(value, isFalse);
    await settle(tester);
  });

  testWidgets('SpringButton fires and plays the press spring', (
    WidgetTester tester,
  ) async {
    int presses = 0;
    await tester.pumpWidget(
      host(LabActionButton(label: 'press me', onPressed: () => presses++)),
    );
    await tester.tap(find.text('press me'));
    await tester.pump();
    expect(presses, 1);
    await settle(tester);
  });

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
}
