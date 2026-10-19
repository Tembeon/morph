import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:morph/morph.dart';

Widget _scene(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 300, child: child)),
  ),
);

void main() {
  testWidgets('a ranged slider reports in its range, start to end', (
    tester,
  ) async {
    var value = 50.0;
    final events = <String>[];
    late StateSetter update;
    await tester.pumpWidget(
      _scene(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MorphSlider(
              value: value,
              min: 0,
              max: 200,
              onChangeStart: (v) => events.add('start $v'),
              onChanged: (v) {
                events.add('change');
                setState(() => value = v);
              },
              onChangeEnd: (v) => events.add('end $v'),
            );
          },
        ),
      ),
    );
    final box = tester.getRect(find.byType(MorphSlider));
    final thumb = Offset(box.left + box.width * 0.25, box.center.dy);
    final gesture = await tester.startGesture(thumb);
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(events.first, 'start 50.0');
    expect(events, contains('change'));
    expect(events.last, startsWith('end '));
    final end = double.parse(events.last.substring(4));
    expect(value, end);
    expect(value, greaterThan(50));
    expect(value, lessThanOrEqualTo(200));
    update(() => value = 150);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard steps move within the range', (tester) async {
    final changes = <double>[];
    final starts = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: MorphSlider(
              value: 10,
              min: 10,
              max: 20,
              onChangeStart: starts.add,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(starts, [10]);
    expect(changes.single, closeTo(11, 1e-9));
  });
}
