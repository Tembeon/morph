import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/ui/goo_selector.dart';
import 'package:morph_example/ui/lab_chrome.dart';
import 'package:morph_example/ui/spring_switcher.dart';
import 'package:morph_example/ui/spring_toggle.dart';

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

  testWidgets('GooSelector: the blob re-anchors after a width change', (
    WidgetTester tester,
  ) async {
    double width = 300;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: .dark),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                rebuild = setState;
                return SizedBox(
                  width: width,
                  child: GooSelector(
                    labels: const <String>['one', 'two', 'three'],
                    index: 2,
                    onSelect: (int _) {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    // Emphasis is a pure function of the blob position: the selected
    // label sits under the blob and reads brightest.
    double alphaOf(String label) {
      final Text text = tester.widget<Text>(find.text(label));
      return (text.style!.color!.a);
    }

    expect(alphaOf('three'), greaterThan(alphaOf('one')));

    // Shrink the track: every slot center moves left. A blob stuck at
    // its old absolute position would drift off slot 2 and dim its
    // label; re-anchoring keeps 'three' the brightest.
    rebuild(() => width = 150);
    await tester.pump();
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      alphaOf('three'),
      greaterThan(alphaOf('one')),
      reason: 'the blob re-anchored to slot 2 at the new width',
    );
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
}
