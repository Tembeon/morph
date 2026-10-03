import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/ui/lab_chrome.dart';
import 'package:morph_example/ui/spring_switcher.dart';

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
  testWidgets('LabSegmented: taps select, mid-flight retarget, no match', (
    WidgetTester tester,
  ) async {
    int? selected = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return LabSegmented(
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
    // Retarget mid-flight: the lens carries its velocity.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('one'));
    await tester.pump();
    expect(selected, 0);
    await settle(tester);
    // No matching option dims the control and keeps the last lens.
    rebuild(() => selected = null);
    await settle(tester);
    expect(
      tester.widget<Opacity>(find.byType(Opacity).first).opacity,
      lessThan(1),
    );
  });

  testWidgets('LabSegmented: the lens follows a width change', (
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
                  child: LabSegmented(
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
    FontWeight? weightOf(String label) =>
        tester.widget<Text>(find.text(label)).style!.fontWeight;
    expect(weightOf('three'), FontWeight.w600);
    expect(weightOf('one'), FontWeight.w500);

    rebuild(() => width = 150);
    await tester.pump();
    await settle(tester);
    expect(tester.getSize(find.byType(MorphSegmentedControl)).width, 150);
    expect(weightOf('three'), FontWeight.w600);
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

  testWidgets('LabActionButton fires and plays the glass press', (
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

  testWidgets('LabSwitchTile flips on tap and settles', (
    WidgetTester tester,
  ) async {
    bool value = false;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) =>
              LabSwitchTile(
                label: 'toggle',
                value: value,
                onChanged: (bool v) => setState(() => value = v),
              ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphSwitch));
    await tester.pump();
    expect(value, isTrue);
    // Flip back mid-flight: retarget with velocity carry-over.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(MorphSwitch));
    await tester.pump();
    expect(value, isFalse);
    await settle(tester);
  });
}
