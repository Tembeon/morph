import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';

/// A control held still under a finger rests: no frame is scheduled once
/// its press motion settles, and the next move wakes it and is followed
/// (lifecycle.md, touch rows).
void main() {
  Widget app(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: Center(child: child)),
  );

  Future<void> holdStill(WidgetTester tester) async {
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('a held slider thumb rests and follows the next move', (
    tester,
  ) async {
    var value = 0.3;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => SizedBox(
            width: 300,
            child: MorphSlider(
              value: value,
              onChanged: (double v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(MorphSlider));
    final gesture = await tester.startGesture(
      Offset(box.left + box.width * 0.3, box.center.dy),
    );
    await holdStill(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(value, greaterThan(0.4));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a held switch knob rests and follows the next move', (
    tester,
  ) async {
    var on = false;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => MorphSwitch(
            value: on,
            onChanged: (bool v) => setState(() => on = v),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(MorphSwitch));
    final gesture = await tester.startGesture(
      Offset(box.left + box.width * 0.3, box.center.dy),
    );
    await holdStill(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(on, isTrue);
  });

  testWidgets('a held tab bar rests and its lens follows the next move', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => MorphTabBar(
            items: const [
              MorphTabItem(icon: Icons.home, label: 'Home'),
              MorphTabItem(icon: Icons.search, label: 'Browse'),
              MorphTabItem(icon: Icons.person, label: 'Profile'),
            ],
            selected: selected,
            onChanged: (int i) => setState(() => selected = i),
          ),
        ),
      ),
    );
    final home = tester.getCenter(find.text('Home'));
    final profile = tester.getCenter(find.text('Profile'));
    final gesture = await tester.startGesture(home);
    await holdStill(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(Offset((profile.dx - home.dx) / 20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, 2);
  });
}
